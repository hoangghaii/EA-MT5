//+------------------------------------------------------------------+
//| CNotificationBase.mqh  - XAUUSD Scalper EA Phase 3              |
//| Abstract notification interface — one pure virtual method only   |
//+------------------------------------------------------------------+
#property strict

class CNotificationBase
{
public:
   virtual bool Send(string event, string detail) = 0;
   virtual void ~CNotificationBase() {}
};
//+------------------------------------------------------------------+
