//+------------------------------------------------------------------+
//| EA_Main.mq5  - XAUUSD Scalper EA                                |
//| Orchestrator: enabled gate → bar guard → filters → signal       |
//| Symbol: XAUUSD | Chart TF: M3 | HTF: M15                        |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Scalper EA"
#property version   "3.00"
#property strict

#include "Core/CSignalEngine.mqh"
#include "Core/CTradeManager.mqh"
#include "Filters/CTimeFilter.mqh"
#include "Filters/CNewsFilter.mqh"
#include "Filters/CDrawdownFilter.mqh"  // includes CRiskManager.mqh transitively
#include "UI/CControlPanel.mqh"
#include "Notifications/CTelegramNotifier.mqh"

#define MAGIC_NUMBER    20260304
#define PANEL_X         10
#define PANEL_Y         20

//--- Global instances
CSignalEngine    g_signalEngine;
CTradeManager    g_tradeManager;
CRiskManager     g_riskManager;
CTimeFilter      g_timeFilter;
CNewsFilter      g_newsFilter;
CDrawdownFilter  g_drawdownFilter;
CControlPanel    g_panel;
CTelegramNotifier g_notifier;
datetime         g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_signalEngine.Init())
   {
      Print("EA_Main::OnInit - CSignalEngine init failed");
      return INIT_FAILED;
   }

   g_tradeManager.Init(_Symbol, MAGIC_NUMBER);
   g_riskManager.Init(MAGIC_NUMBER);
   g_timeFilter.Init();
   g_newsFilter.Init();
   g_drawdownFilter.Init(GetPointer(g_riskManager));
   g_panel.Init(PANEL_X, PANEL_Y, MAGIC_NUMBER);
   g_notifier.Init("", ""); // tokens empty; wire in EA inputs when Telegram is enabled

   g_lastBarTime = 0;
   PrintFormat("XAUUSD Scalper EA v3 initialized | symbol=%s magic=%d", _Symbol, MAGIC_NUMBER);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_panel.Deinit();
   g_signalEngine.Deinit();
   g_timeFilter.Deinit();
   g_newsFilter.Deinit();
   g_drawdownFilter.Deinit();
   g_riskManager.Deinit();
   PrintFormat("XAUUSD Scalper EA deinitialized, reason=%d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick handler                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // First gate: manual on/off toggle
   if(!g_panel.IsEnabled())
   {
      g_panel.UpdateStatus("EA: DISABLED");
      return;
   }

   // Bar-open guard: evaluate signal once per new M3 bar only
   datetime currentBarTime = iTime(_Symbol, PERIOD_M3, 0);
   if(currentBarTime == g_lastBarTime)
      return;
   g_lastBarTime = currentBarTime;

   // Filter gates (cheap → expensive)
   if(!g_timeFilter.IsAllowed())
   {
      g_panel.UpdateStatus("BLOCKED: weekday");
      return;
   }
   if(!g_drawdownFilter.IsAllowed())
   {
      g_panel.UpdateStatus(StringFormat("PAUSED: %d losses", g_riskManager.GetConsecutiveLosses()));
      return;
   }
   if(!g_newsFilter.IsAllowed())
   {
      g_panel.UpdateStatus("BLOCKED: news");
      return;
   }

   // Signal evaluation and execution
   int signal = g_signalEngine.CheckSignal();
   g_panel.UpdateStatus(StringFormat("ACTIVE | losses:%d", g_riskManager.GetConsecutiveLosses()));

   if(signal == +1)
   {
      if(g_tradeManager.OpenBuy())
         g_notifier.Send("TRADE_OPEN", "BUY 0.01 " + _Symbol);
   }
   else if(signal == -1)
   {
      if(g_tradeManager.OpenSell())
         g_notifier.Send("TRADE_OPEN", "SELL 0.01 " + _Symbol);
   }
}

//+------------------------------------------------------------------+
//| Chart event handler — route clicks to panel                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool wasEnabled = g_panel.IsEnabled();
      g_panel.OnClick(sparam);
      // Notify on manual toggle
      if(wasEnabled != g_panel.IsEnabled())
         g_notifier.Send("EA_TOGGLE", g_panel.IsEnabled() ? "ON" : "OFF");
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler — update loss counter on deal close    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!HistoryDealSelect(trans.deal))
   {
      PrintFormat("OnTradeTransaction: HistoryDealSelect(%llu) failed", trans.deal);
      return;
   }

   // Only process deals from this EA
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MAGIC_NUMBER)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   g_riskManager.OnDeal(profit);
   g_notifier.Send("TRADE_CLOSE", StringFormat("P&L: %.2f", profit));

   // Notify if drawdown pause was just triggered
   if(g_riskManager.GetConsecutiveLosses() >= 4)
      g_notifier.Send("DRAWDOWN_PAUSE", "4 consecutive losses — pausing until next session");
}
//+------------------------------------------------------------------+
