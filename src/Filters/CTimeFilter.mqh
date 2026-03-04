//+------------------------------------------------------------------+
//| CTimeFilter.mqh  - XAUUSD Scalper EA Phase 2                    |
//| Day-of-week gate: block Monday (DOW=1) and Friday (DOW=5)       |
//+------------------------------------------------------------------+
#property strict

class CTimeFilter
{
public:
   bool Init()      { return true; }
   void Deinit()    {}
   bool IsAllowed();
};

//--- Return false on Monday (1) and Friday (5); use TimeGMT() for broker-TZ safety
bool CTimeFilter::IsAllowed()
{
   int dow = TimeDayOfWeek(TimeGMT());
   if(dow == 1 || dow == 5)
   {
      // Uncomment for debug: Print("CTimeFilter: blocked day=", dow);
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
