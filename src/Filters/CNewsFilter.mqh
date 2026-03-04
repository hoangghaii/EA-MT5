//+------------------------------------------------------------------+
//| CNewsFilter.mqh  - XAUUSD Scalper EA Phase 2                    |
//| Block trades 30 min before/after HIGH/MEDIUM USD or XAU events  |
//+------------------------------------------------------------------+
#property strict

#define NEWS_BUFFER_SECS 1800 // 30 minutes in seconds

class CNewsFilter
{
private:
   bool _hasHighMediumEvent(MqlCalendarValue &values[], datetime now);
   bool _checkCurrency(string currency, datetime serverNow);

public:
   bool Init()   { return true; }
   void Deinit() {}
   bool IsAllowed();
};

//--- Scan values array for HIGH or MEDIUM importance events within ±30 min
bool CNewsFilter::_hasHighMediumEvent(MqlCalendarValue &values[], datetime now)
{
   for(int i = 0; i < ArraySize(values); i++)
   {
      // Resolve event importance via CalendarEventById
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      // Filter: MEDIUM or HIGH impact only
      if(event.importance < CALENDAR_IMPORTANCE_MODERATE)
         continue;

      // Filter: within NEWS_BUFFER_SECS of current server time
      long diff = MathAbs((long)values[i].time - (long)now);
      if(diff <= NEWS_BUFFER_SECS)
         return true;
   }
   return false;
}

//--- Query calendar for one currency; return false on API failure (fail-safe)
bool CNewsFilter::_checkCurrency(string currency, datetime serverNow)
{
   MqlCalendarValue values[];
   datetime         from = serverNow - NEWS_BUFFER_SECS;
   datetime         to   = serverNow + NEWS_BUFFER_SECS;

   if(!CalendarValueHistory(values, from, to, "", currency))
   {
      Print("NEWS_API_FAIL: CalendarValueHistory failed for ", currency);
      return true; // fail-safe: treat as news active
   }

   return _hasHighMediumEvent(values, serverNow);
}

//--- Check USD and XAU; block if any HIGH/MEDIUM event within buffer
bool CNewsFilter::IsAllowed()
{
   datetime serverNow = TimeTradeServer();

   if(_checkCurrency("USD", serverNow)) return false;
   if(_checkCurrency("XAU", serverNow)) return false;

   return true;
}
//+------------------------------------------------------------------+
