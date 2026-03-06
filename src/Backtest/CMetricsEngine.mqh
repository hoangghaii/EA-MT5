//+------------------------------------------------------------------+
//| CMetricsEngine.mqh  - XAUUSD Scalper EA                         |
//| Consumes VirtualTrade[], computes perf stats, exports CSV        |
//+------------------------------------------------------------------+
#property strict
#include "CBacktester.mqh"

class CMetricsEngine
{
private:
   double   m_winRate;
   double   m_profitFactor;
   double   m_maxDD;
   double   m_sharpe;
   int      m_maxConsecLosses;
   double   m_totalPnL;
   int      m_tradeCount;

   //--- Daily PnL bucketing for Sharpe
   string   m_dayKeys[];
   double   m_dayPnl[];
   int      m_dayCount;

   int      _findDay(string key);
   void     _addDayPnl(datetime t, double pnl);
   double   _computeSharpe();

public:
   void  Process(VirtualTrade &trades[], int count);
   double GetWinRate()         { return m_winRate; }
   double GetProfitFactor()    { return m_profitFactor; }
   double GetMaxDD()           { return m_maxDD; }
   double GetSharpe()          { return m_sharpe; }
   int    GetMaxConsecLosses() { return m_maxConsecLosses; }
   double GetTotalPnL()        { return m_totalPnL; }
   void  ExportCSV(string filename, VirtualTrade &trades[], int count);
   void  PrintSummary();
};

//--- Find index of existing day key; returns -1 if not found
int CMetricsEngine::_findDay(string key)
{
   for(int i = 0; i < m_dayCount; i++)
      if(m_dayKeys[i] == key) return i;
   return -1;
}

//--- Add trade PnL to its date bucket
void CMetricsEngine::_addDayPnl(datetime t, double pnl)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   string key = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
   int idx = _findDay(key);
   if(idx < 0)
   {
      if(m_dayCount >= ArraySize(m_dayKeys))
      {
         ArrayResize(m_dayKeys, m_dayCount + 32);
         ArrayResize(m_dayPnl,  m_dayCount + 32);
      }
      idx = m_dayCount++;
      m_dayKeys[idx] = key;
      m_dayPnl[idx]  = 0.0;
   }
   m_dayPnl[idx] += pnl;
}

//--- Sharpe = mean_daily / stdev_daily * sqrt(252)
double CMetricsEngine::_computeSharpe()
{
   if(m_dayCount < 2) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < m_dayCount; i++) sum += m_dayPnl[i];
   double mean = sum / m_dayCount;
   double var  = 0.0;
   for(int i = 0; i < m_dayCount; i++) { double d = m_dayPnl[i] - mean; var += d * d; }
   double stdev = MathSqrt(var / (m_dayCount - 1)); // sample stdev (N-1)
   if(stdev == 0.0) return 0.0;
   return (mean / stdev) * MathSqrt(252.0);
}

//--- Single-pass metrics computation
void CMetricsEngine::Process(VirtualTrade &trades[], int count)
{
   m_winRate = 0.0; m_profitFactor = 0.0; m_maxDD = 0.0;
   m_sharpe = 0.0;  m_maxConsecLosses = 0; m_totalPnL = 0.0;
   m_tradeCount = 0; m_dayCount = 0;
   ArrayResize(m_dayKeys, 64); ArrayResize(m_dayPnl, 64);

   if(count <= 0) return;

   int    wins = 0, consec = 0, maxConsec = 0;
   double grossWin = 0.0, grossLoss = 0.0;
   double equity = 0.0, peak = 0.0; // peak=0: DD% only computed once equity first turns positive

   for(int i = 0; i < count; i++)
   {
      if(trades[i].exit_reason == "OPEN") continue; // skip unclosed
      double pnl = trades[i].pnl;
      m_totalPnL += pnl;
      equity     += pnl;
      m_tradeCount++;
      if(pnl > 0.0) { wins++; grossWin  += pnl; consec = 0; }
      else          { grossLoss += MathAbs(pnl); consec++;
                      if(consec > maxConsec) maxConsec = consec; }
      if(equity > peak) peak = equity;
      if(peak > 0.0)
      {
         double dd = (peak - equity) / peak * 100.0;
         if(dd > m_maxDD) m_maxDD = dd;
      }
      _addDayPnl(trades[i].entry_time, pnl);
   }

   m_winRate         = (m_tradeCount > 0) ? (wins * 100.0 / m_tradeCount) : 0.0;
   m_profitFactor    = (grossLoss > 0.0)  ? (grossWin / grossLoss)         : 0.0;
   m_maxConsecLosses = maxConsec;
   m_sharpe          = _computeSharpe();
}

//--- Export closed trades to CSV in Terminal\Common\Files\
void CMetricsEngine::ExportCSV(string filename, VirtualTrade &trades[], int count)
{
   int fh = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) { Print("CMetricsEngine::ExportCSV - FileOpen failed"); return; }

   FileWrite(fh, "DateTime", "Direction", "EntryPrice", "SL", "TP", "ExitPrice", "PnL", "Result");

   for(int i = 0; i < count; i++)
   {
      if(trades[i].exit_reason == "OPEN") continue;
      string dir = (trades[i].direction == +1) ? "BUY" : "SELL";
      string dt  = TimeToString(trades[i].entry_time, TIME_DATE | TIME_MINUTES);
      FileWrite(fh, dt, dir,
                DoubleToString(trades[i].entry_price, _Digits),
                DoubleToString(trades[i].sl,          _Digits),
                DoubleToString(trades[i].tp,          _Digits),
                DoubleToString(trades[i].exit_price,  _Digits),
                DoubleToString(trades[i].pnl,         2),
                trades[i].exit_reason);
   }
   FileClose(fh);
   PrintFormat("CMetricsEngine::ExportCSV — saved %s", filename);
}

//--- Print all metrics to Experts log
void CMetricsEngine::PrintSummary()
{
   PrintFormat("=== Backtest Results ===");
   PrintFormat("Trades       : %d",    m_tradeCount);
   PrintFormat("Win Rate     : %.1f%%", m_winRate);
   PrintFormat("Profit Factor: %.2f",  m_profitFactor);
   PrintFormat("Total PnL    : %.2f",  m_totalPnL);
   PrintFormat("Max Drawdown : %.2f%%", m_maxDD);
   PrintFormat("Max Cons.Loss: %d",    m_maxConsecLosses);
   PrintFormat("Sharpe Ratio : %.2f",  m_sharpe);
   PrintFormat("========================");
}
//+------------------------------------------------------------------+
