//+------------------------------------------------------------------+
//| CDrawdownFilter.mqh  - XAUUSD Scalper EA Phase 2                |
//| Pause trading after 4 consecutive losses; resume on new session  |
//+------------------------------------------------------------------+
#property strict

#include "../Core/CRiskManager.mqh"

#define MAX_CONSEC_LOSSES 4

class CDrawdownFilter
{
private:
   CRiskManager* m_risk;
   bool          m_paused;
   int           m_pausedSession; // session index when paused

   int _session(); // 0=Asia(00-08 GMT), 1=London(08-16), 2=NY(16-24)

public:
   void Init(CRiskManager* risk);
   void Deinit() {}
   bool IsAllowed();
};

//--- Store pointer to shared CRiskManager; init pause state
void CDrawdownFilter::Init(CRiskManager* risk)
{
   m_risk         = risk;
   m_paused       = false;
   m_pausedSession = -1;
}

//--- Return 0/1/2 for Asia/London/NY based on GMT hour
int CDrawdownFilter::_session()
{
   int hour = TimeHour(TimeGMT());
   if(hour < 8)  return 0; // Asia    00:00-08:00 GMT
   if(hour < 16) return 1; // London  08:00-16:00 GMT
   return 2;               // New York 16:00-24:00 GMT
}

//--- Gate: allow trade unless paused; resume on session boundary
bool CDrawdownFilter::IsAllowed()
{
   if(!m_paused)
   {
      if(m_risk.GetConsecutiveLosses() >= MAX_CONSEC_LOSSES)
      {
         m_paused        = true;
         m_pausedSession = _session();
         PrintFormat("CDrawdownFilter: paused after %d losses in session %d",
                     MAX_CONSEC_LOSSES, m_pausedSession);
      }
      return true;
   }

   // Paused: check if session has changed
   if(_session() != m_pausedSession)
   {
      m_paused = false;
      m_risk.Reset();
      PrintFormat("CDrawdownFilter: resumed in new session %d", _session());
      return true;
   }

   return false; // still paused
}
//+------------------------------------------------------------------+
