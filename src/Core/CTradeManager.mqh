//+------------------------------------------------------------------+
//| CTradeManager.mqh  - XAUUSD Scalper EA Phase 1                  |
//| Thin CTrade wrapper: entry execution, no trail/modify in Phase 1 |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

class CTradeManager
{
private:
   CTrade  m_trade;
   string  m_symbol;
   double  m_lotSize;
   int     m_slPips;
   int     m_tpPips;

public:
   void Init(string symbol, ulong magic);
   bool HasOpenPosition();
   bool OpenBuy();
   bool OpenSell();
};

//--- Configure CTrade; set lot/pip defaults
void CTradeManager::Init(string symbol, ulong magic)
{
   m_symbol  = symbol;
   m_lotSize = 0.01;
   m_slPips  = 25;
   m_tpPips  = 50;

   m_trade.SetExpertMagicNumber(magic);
   m_trade.SetDeviationInPoints(10);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   m_trade.SetAsyncMode(false);
}

//--- Check if there is an open position for this symbol
bool CTradeManager::HasOpenPosition()
{
   return PositionSelect(m_symbol);
}

//--- Open BUY at Ask; SL/TP calculated in points (m_slPips * _Point)
bool CTradeManager::OpenBuy()
{
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   double sl  = ask - m_slPips * _Point;
   double tp  = ask + m_tpPips * _Point;

   if(!m_trade.Buy(m_lotSize, m_symbol, ask, sl, tp, "XAUUSD Scalper"))
   {
      PrintFormat("CTradeManager::OpenBuy failed, retcode=%u", m_trade.ResultRetcode());
      return false;
   }
   PrintFormat("CTradeManager::OpenBuy OK, ask=%.5f sl=%.5f tp=%.5f", ask, sl, tp);
   return true;
}

//--- Open SELL at Bid; SL/TP calculated in points (m_slPips * _Point)
bool CTradeManager::OpenSell()
{
   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double sl  = bid + m_slPips * _Point;
   double tp  = bid - m_tpPips * _Point;

   if(!m_trade.Sell(m_lotSize, m_symbol, bid, sl, tp, "XAUUSD Scalper"))
   {
      PrintFormat("CTradeManager::OpenSell failed, retcode=%u", m_trade.ResultRetcode());
      return false;
   }
   PrintFormat("CTradeManager::OpenSell OK, bid=%.5f sl=%.5f tp=%.5f", bid, sl, tp);
   return true;
}
//+------------------------------------------------------------------+
