//+------------------------------------------------------------------+
//| CSignalEngine.mqh  - XAUUSD Scalper EA Phase 1                  |
//| Signal detection: MACD histogram 2-bar flip + RSI + M15 EMA50   |
//+------------------------------------------------------------------+
#property strict

class CSignalEngine
{
private:
   int    m_macdHandle;
   int    m_rsiHandle;
   int    m_emaHandle;

   bool   _copyMACD(double &hist[], int count);
   bool   _copyRSI(double &rsi[],  int count);
   bool   _copyEMA(double &ema[],  int count);
   double _emaSlope(double &ema[]);

public:
   bool   Init();
   void   Deinit();
   int    CheckSignal(); // +1 buy | -1 sell | 0 none
};

//--- Init: create indicator handles; return false on any INVALID_HANDLE
bool CSignalEngine::Init()
{
   m_macdHandle = iMACD(_Symbol, PERIOD_M3, 12, 26, 9, PRICE_CLOSE);
   m_rsiHandle  = iRSI(_Symbol,  PERIOD_M3, 14, PRICE_CLOSE);
   m_emaHandle  = iMA(_Symbol,   PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(m_macdHandle == INVALID_HANDLE ||
      m_rsiHandle  == INVALID_HANDLE ||
      m_emaHandle  == INVALID_HANDLE)
   {
      Print("CSignalEngine::Init - handle creation failed, error=", GetLastError());
      return false;
   }
   return true;
}

//--- Deinit: release all indicator handles
void CSignalEngine::Deinit()
{
   if(m_macdHandle != INVALID_HANDLE) IndicatorRelease(m_macdHandle);
   if(m_rsiHandle  != INVALID_HANDLE) IndicatorRelease(m_rsiHandle);
   if(m_emaHandle  != INVALID_HANDLE) IndicatorRelease(m_emaHandle);
}

//--- Compute MACD histogram: buffer0 (MACD line) - buffer1 (signal line)
//    MQL5 iMACD has only buffer 0 (main) and buffer 1 (signal); no buffer 2
bool CSignalEngine::_copyMACD(double &hist[], int count)
{
   double macdLine[], sigLine[];
   ArraySetAsSeries(macdLine, true);
   ArraySetAsSeries(sigLine,  true);
   ArraySetAsSeries(hist,     true);
   if(CopyBuffer(m_macdHandle, 0, 0, count, macdLine) <= 0 ||
      CopyBuffer(m_macdHandle, 1, 0, count, sigLine)  <= 0)
   {
      PrintFormat("CSignalEngine: CopyBuffer MACD failed, error=%d", GetLastError());
      return false;
   }
   ArrayResize(hist, count);
   for(int k = 0; k < count; k++) hist[k] = macdLine[k] - sigLine[k];
   return true;
}

//--- Copy RSI buffer 0
bool CSignalEngine::_copyRSI(double &rsi[], int count)
{
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(m_rsiHandle, 0, 0, count, rsi) <= 0)
   {
      PrintFormat("CSignalEngine: CopyBuffer RSI failed, error=%d", GetLastError());
      return false;
   }
   return true;
}

//--- Copy EMA buffer 0 (M15 context)
bool CSignalEngine::_copyEMA(double &ema[], int count)
{
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(m_emaHandle, 0, 0, count, ema) <= 0)
   {
      PrintFormat("CSignalEngine: CopyBuffer EMA failed, error=%d", GetLastError());
      return false;
   }
   return true;
}

//--- EMA slope in pips/bar; _Point*10 = 1 pip for XAUUSD
double CSignalEngine::_emaSlope(double &ema[])
{
   return (ema[0] - ema[1]) / (_Point * 10);
}

//--- Evaluate all 3 conditions; return +1, -1, or 0
int CSignalEngine::CheckSignal()
{
   double hist[3], rsi[3], ema[3];

   if(!_copyMACD(hist, 3)) return 0;
   if(!_copyRSI(rsi,  3))  return 0;
   if(!_copyEMA(ema,  3))  return 0;

   double slope = _emaSlope(ema);

   // Buy: histogram flips negative→positive, RSI oversold, M15 EMA uptrend
   if(hist[1] < 0.0 && hist[0] > 0.0 && rsi[0] < 35.0 && slope > +0.1)
      return +1;

   // Sell: histogram flips positive→negative, RSI overbought, M15 EMA downtrend
   if(hist[1] > 0.0 && hist[0] < 0.0 && rsi[0] > 65.0 && slope < -0.1)
      return -1;

   return 0;
}
//+------------------------------------------------------------------+
