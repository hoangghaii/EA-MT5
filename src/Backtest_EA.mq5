//+------------------------------------------------------------------+
//| Backtest_EA.mq5  - XAUUSD Scalper EA                            |
//| Bar-replay backtest entry point for Strategy Tester              |
//| Runs CBacktester in OnInit(), exposes OnTester() criterion       |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Scalper EA"
#property version   "1.00"
#property strict

#include "Backtest/CMetricsEngine.mqh"  // includes CBacktester.mqh transitively

input int    InpBarsBack  = 20000;                    // Bars to replay
input double InpLotSize   = 0.01;                     // Lot size per trade
input double InpRR        = 3.0;                      // Risk-Reward ratio (TP = SL × RR)
input bool   InpBEStop    = true;                     // Break-even stop at 1:1 level
input int    InpPyramid   = 1;                        // Max pyramid positions (1=off, 2-4)
input int    InpPyrDelta  = 5;                        // Points between pyramid entries
input string InpCsvFile   = "xauusd_backtest.csv";   // CSV output filename

CBacktester   g_bt;
CMetricsEngine g_me;

//--- Run full backtest at EA load; all results ready before OnTester()
int OnInit()
{
   if(!g_bt.Init(_Symbol, InpBarsBack))
   {
      Print("Backtest_EA: CBacktester init failed");
      return INIT_FAILED;
   }

   g_bt.SetLot(InpLotSize);
   g_bt.SetRR(InpRR);
   g_bt.SetBEStop(InpBEStop);
   g_bt.SetPyramid(InpPyramid, InpPyrDelta);
   int n = g_bt.Run();
   if(n == 0)
   {
      Print("Backtest_EA: no trades generated");
      g_bt.Deinit();
      return INIT_SUCCEEDED; // non-fatal: metrics will be zero
   }

   // Build trade array for metrics
   VirtualTrade trades[];
   ArrayResize(trades, n);
   for(int i = 0; i < n; i++) g_bt.GetTrade(i, trades[i]);

   g_me.Process(trades, n);
   g_me.ExportCSV(InpCsvFile, trades, n);
   g_me.PrintSummary();

   return INIT_SUCCEEDED;
}

//--- Empty — backtest logic runs entirely in OnInit()
void OnTick() { /* no live trading */ }

//--- Returns profit factor as custom Strategy Tester optimization criterion
double OnTester()
{
   return g_me.GetProfitFactor();
}

//--- Release indicator handles
void OnDeinit(const int reason)
{
   g_bt.Deinit();
}
//+------------------------------------------------------------------+
