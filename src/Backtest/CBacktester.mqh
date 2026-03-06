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

   // Implementations in CBacktester-signal-filters.mqh
   bool   _isDowBlocked(datetime t);
   int    _getSession(datetime t);
   bool   _drawdownAllowed(datetime t);
   bool   _isSignal(int i, int &dir);
   double _calcPnL(int dir, double entry, double ex);
   bool   _detectExit(VirtualTrade &t, int idx);

public:
   bool Init(string symbol, int barsBack);
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

   int copied = CopyRates(m_symbol, PERIOD_M3, 0, barsBack, m_ratesM3);
   if(copied <= 0) { Print("CBacktester::Init - CopyRates failed"); return false; }
   ArraySetAsSeries(m_ratesM3, true);

   // Create handles AFTER history loaded to avoid stale buffers (Phase 1 risk mitigation)
   m_macdH = iMACD(m_symbol, PERIOD_M3,  12, 26, 9, PRICE_CLOSE);
   m_rsiH  = iRSI(m_symbol,  PERIOD_M3,  14, PRICE_CLOSE);
   m_emaH  = iMA(m_symbol,   PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(m_macdH == INVALID_HANDLE || m_rsiH == INVALID_HANDLE || m_emaH == INVALID_HANDLE)
   { Print("CBacktester::Init - indicator handle failed"); return false; }

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

   bool         hasOpen = false;
   VirtualTrade cur;

   for(int i = total - 1; i >= 1; i--)
   {
      datetime barTime = m_ratesM3[i].time;

      // Step 1: check exit on any open trade
      if(hasOpen)
      {
         if(_detectExit(cur, i))
         {
            cur.exit_time = barTime;
            cur.pnl       = _calcPnL(cur.direction, cur.entry_price, cur.exit_price);
            if(m_tradeCount >= ArraySize(m_trades)) ArrayResize(m_trades, m_tradeCount + 50);
            m_trades[m_tradeCount++] = cur;
            if(cur.pnl < 0.0) m_consecLosses++; else m_consecLosses = 0;
            hasOpen = false;
         }
         continue; // 1 trade at a time — skip signal check while in trade
      }

      if(i > total - BT_WARMUP)     continue; // warm-up guard
      if(_isDowBlocked(barTime))     continue; // Mon/Fri filter
      if(!_drawdownAllowed(barTime)) continue; // 4-loss drawdown filter

      // Step 2: evaluate signal; enter at next bar open (no lookahead)
      int sigDir = 0;
      if(!_isSignal(i, sigDir)) continue;

      cur.entry_time  = m_ratesM3[i - 1].time;
      cur.direction   = sigDir;
      cur.entry_price = m_ratesM3[i - 1].open;
      cur.sl          = cur.entry_price - sigDir * BT_SL_PTS * _Point;
      cur.tp          = cur.entry_price + sigDir * BT_SL_PTS * _Point * 2; // RR 1:2
      cur.exit_price  = 0;
      cur.exit_time   = 0;
      cur.pnl         = 0;
      cur.exit_reason = "OPEN";
      hasOpen         = true;
   }

   // Preserve any trade still open at end of history
   if(hasOpen)
   {
      if(m_tradeCount >= ArraySize(m_trades)) ArrayResize(m_trades, m_tradeCount + 1);
      m_trades[m_tradeCount++] = cur;
   }

   PrintFormat("CBacktester::Run done: %d trades from %d bars", m_tradeCount, total);
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
