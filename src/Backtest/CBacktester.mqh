//+------------------------------------------------------------------+
//| CBacktester.mqh  - XAUUSD Scalper EA                            |
//| Historical bar-replay + virtual trade simulation engine          |
//| Private helpers: see CBacktester-signal-filters.mqh             |
//+------------------------------------------------------------------+
#property strict

#define BT_SL_PTS  25    // Stop loss points (matches CTradeManager)
#define BT_LOT     0.01  // Fixed lot size
#define BT_WARMUP  55    // Bars before signal eval: EMA50+MACD(26)+RSI(14)

struct VirtualTrade
{
   datetime entry_time, exit_time;
   int      direction;    // +1=BUY, -1=SELL
   double   entry_price, sl, tp, exit_price, pnl;
   string   exit_reason;  // "TP", "SL", "OPEN"
};

class CBacktester
{
private:
   string       m_symbol;
   int          m_barsBack;
   MqlRates     m_ratesM3[];
   int          m_macdH, m_rsiH, m_emaH;
   VirtualTrade m_trades[];
   int          m_tradeCount;
   int          m_consecLosses;
   int          m_pausedSession; // -1 = not paused
   double       m_rr;           // Risk-Reward ratio (TP = SL × m_rr)
   double       m_lot;          // Lot size per trade
   bool         m_beStop;       // Break-even stop: move SL to entry at 1:1
   int          m_pyramid;      // Max positions per signal (1=no pyramid)
   int          m_pyrDelta;     // Points between pyramid entries

   // Signal diagnostic counters (reset each Run())
   int          m_dBuf;   // CopyBuffer failed
   int          m_dM15;   // iBarShift M15 failed
   int          m_dMacd;  // MACD flip absent
   int          m_dRsi;   // RSI not in range
   int          m_dSlope; // EMA slope insufficient

   // Implementations in CBacktester-signal-filters.mqh
   bool   _isDowBlocked(datetime t);
   int    _getSession(datetime t);
   bool   _drawdownAllowed(datetime t);
   bool   _isSignal(int i, int &dir);
   double _calcPnL(int dir, double entry, double ex);
   bool   _detectExit(VirtualTrade &t, int idx);
   int    _openPyramid(VirtualTrade &open[], int sigDir, int i);

public:
   bool Init(string symbol, int barsBack);
   void SetRR(double rr)     { m_rr      = (rr  > 0.1)  ? rr  : 2.0;  }
   void SetLot(double lot)   { m_lot     = (lot > 0.001) ? lot : 0.01; }
   void SetBEStop(bool b)    { m_beStop  = b; }
   void SetPyramid(int n, int deltaPts=5) { m_pyramid=MathMax(1,MathMin(n,4)); m_pyrDelta=MathMax(1,deltaPts); }
   void Deinit();
   int  Run();
   bool GetTrade(int idx, VirtualTrade &t);
   int  GetTradeCount() { return m_tradeCount; }
};

//--- Init: load M3 history then create indicator handles
bool CBacktester::Init(string symbol, int barsBack)
{
   if(barsBack > 50000) barsBack = 50000;
   m_symbol        = symbol;
   m_barsBack      = barsBack;
   m_tradeCount    = 0;
   m_consecLosses  = 0;
   m_pausedSession = -1;
   m_rr            = 2.0;   // default RR
   m_lot           = 0.01;  // default lot
   m_beStop        = false; // default: no break-even stop
   m_pyramid       = 1;     // default: single position
   m_pyrDelta      = 5;     // default: 5 pts between pyramid entries

   // Wait for M3 history to be available from broker (up to 10s)
   int copied = 0;
   for(int attempt = 0; attempt < 100 && copied < BT_WARMUP + 2; attempt++)
   {
      copied = CopyRates(m_symbol, PERIOD_M3, 0, barsBack, m_ratesM3);
      if(copied >= BT_WARMUP + 2) break;
      Sleep(100);
   }
   if(copied < BT_WARMUP + 2)
   {
      PrintFormat("CBacktester::Init - only %d M3 bars available (need %d). Open M3 chart first.", copied, BT_WARMUP + 2);
      return false;
   }
   ArraySetAsSeries(m_ratesM3, true);

   // Create indicator handles
   m_macdH = iMACD(m_symbol, PERIOD_M3,  12, 26, 9, PRICE_CLOSE);
   m_rsiH  = iRSI(m_symbol,  PERIOD_M3,  14, PRICE_CLOSE);
   m_emaH  = iMA(m_symbol,   PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(m_macdH == INVALID_HANDLE || m_rsiH == INVALID_HANDLE || m_emaH == INVALID_HANDLE)
   { Print("CBacktester::Init - indicator handle failed"); return false; }

   // Wait for indicator buffers to compute enough history (up to 10s)
   for(int attempt = 0; attempt < 100; attempt++)
   {
      if(BarsCalculated(m_macdH) >= copied &&
         BarsCalculated(m_rsiH)  >= copied &&
         BarsCalculated(m_emaH)  >= copied) break;
      Sleep(100);
   }
   PrintFormat("CBacktester::Init - BarsCalc: MACD=%d RSI=%d EMA=%d",
               BarsCalculated(m_macdH), BarsCalculated(m_rsiH), BarsCalculated(m_emaH));

   ArrayResize(m_trades, barsBack / 10);
   PrintFormat("CBacktester::Init OK: %d M3 bars | symbol=%s", copied, symbol);
   return true;
}

//--- Deinit: release all indicator handles
void CBacktester::Deinit()
{
   if(m_macdH != INVALID_HANDLE) IndicatorRelease(m_macdH);
   if(m_rsiH  != INVALID_HANDLE) IndicatorRelease(m_rsiH);
   if(m_emaH  != INVALID_HANDLE) IndicatorRelease(m_emaH);
}

//--- Main replay loop: oldest bar first (i = total-1 down to 1)
int CBacktester::Run()
{
   int total = ArraySize(m_ratesM3);
   if(total < BT_WARMUP + 2) { Print("CBacktester::Run - insufficient bars"); return 0; }

   VirtualTrade openList[];
   int openCount = 0;
   int diagDow = 0, diagDD = 0, diagSig = 0;
   m_dBuf = 0; m_dM15 = 0; m_dMacd = 0; m_dRsi = 0; m_dSlope = 0;

   for(int i = total - 1; i >= 1; i--)
   {
      datetime barTime = m_ratesM3[i].time;

      // Step 1: check exits on all open positions (reverse order for safe removal)
      for(int k = openCount - 1; k >= 0; k--)
      {
         if(_detectExit(openList[k], i))
         {
            openList[k].exit_time = barTime;
            openList[k].pnl = _calcPnL(openList[k].direction, openList[k].entry_price, openList[k].exit_price);
            if(m_tradeCount >= ArraySize(m_trades)) ArrayResize(m_trades, m_tradeCount + 50);
            m_trades[m_tradeCount++] = openList[k];
            if(openList[k].pnl < 0.0) m_consecLosses++; else m_consecLosses = 0;
            for(int j = k; j < openCount - 1; j++) openList[j] = openList[j + 1];
            openCount--;
         }
      }
      if(openCount > 0) continue; // still in trade — skip signal

      if(i > total - BT_WARMUP)     continue; // warm-up guard
      if(_isDowBlocked(barTime))     { diagDow++; continue; }
      if(!_drawdownAllowed(barTime)) { diagDD++;  continue; }

      int sigDir = 0;
      if(!_isSignal(i, sigDir)) { diagSig++; continue; }
      openCount = _openPyramid(openList, sigDir, i);
   }

   // Preserve any positions still open at end of history
   for(int k = 0; k < openCount; k++)
   {
      if(m_tradeCount >= ArraySize(m_trades)) ArrayResize(m_trades, m_tradeCount + 1);
      m_trades[m_tradeCount++] = openList[k];
   }

   PrintFormat("CBacktester::Run done: %d trades | bars=%d skip_dow=%d skip_dd=%d skip_signal=%d",
               m_tradeCount, total, diagDow, diagDD, diagSig);
   PrintFormat("  signal_diag: buf_fail=%d m15_fail=%d macd_noflip=%d rsi_fail=%d slope_fail=%d",
               m_dBuf, m_dM15, m_dMacd, m_dRsi, m_dSlope);
   return m_tradeCount;
}

//--- GetTrade: bounds-checked access to trade array
bool CBacktester::GetTrade(int idx, VirtualTrade &t)
{
   if(idx < 0 || idx >= m_tradeCount) return false;
   t = m_trades[idx];
   return true;
}

// Include private helper method implementations
#include "CBacktester-signal-filters.mqh"
//+------------------------------------------------------------------+
