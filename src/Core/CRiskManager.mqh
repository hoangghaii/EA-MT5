//+------------------------------------------------------------------+
//| CRiskManager.mqh  - XAUUSD Scalper EA Phase 2                   |
//| Consecutive loss counter with GlobalVariable persistence          |
//+------------------------------------------------------------------+
#property strict

class CRiskManager
{
private:
   int    m_consecutiveLosses;
   string m_gvKey; // GlobalVariable key scoped to magic number

public:
   void Init(ulong magic);
   void Deinit() {}
   void OnDeal(double profit);  // call from OnTradeTransaction
   void Reset();
   int  GetConsecutiveLosses() { return m_consecutiveLosses; }
};

//--- Load persisted loss count from GlobalVariable; key scoped by magic
void CRiskManager::Init(ulong magic)
{
   m_gvKey = "EA_ConsecLosses_" + IntegerToString((long)magic);

   if(GlobalVariableCheck(m_gvKey))
      m_consecutiveLosses = (int)GlobalVariableGet(m_gvKey);
   else
      m_consecutiveLosses = 0;

   PrintFormat("CRiskManager::Init loaded %d losses from GV[%s]",
               m_consecutiveLosses, m_gvKey);
}

//--- Update counter after each closed deal; persist immediately
void CRiskManager::OnDeal(double profit)
{
   if(profit < 0.0)
   {
      m_consecutiveLosses++;
      PrintFormat("CRiskManager: loss #%d (profit=%.2f)", m_consecutiveLosses, profit);
   }
   else
   {
      m_consecutiveLosses = 0;
      Print("CRiskManager: win — consecutive losses reset to 0");
   }
   GlobalVariableSet(m_gvKey, (double)m_consecutiveLosses);
}

//--- Force reset (called by CDrawdownFilter after session change)
void CRiskManager::Reset()
{
   m_consecutiveLosses = 0;
   GlobalVariableSet(m_gvKey, 0.0);
   Print("CRiskManager::Reset — counter cleared");
}
//+------------------------------------------------------------------+
