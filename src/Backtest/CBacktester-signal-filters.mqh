//+------------------------------------------------------------------+
//| CBacktester-signal-filters.mqh  - XAUUSD Scalper EA             |
//| Private method implementations for CBacktester                  |
//| Included from CBacktester.mqh AFTER class declaration           |
//+------------------------------------------------------------------+

//--- DOW filter: block Monday(1) and Friday(5)
bool CBacktester::_isDowBlocked(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (dt.day_of_week == 1 || dt.day_of_week == 5);
}

//--- Session index from bar open time (server time hour)
int CBacktester::_getSession(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(dt.hour < 8)  return 0; // Asia    00-08
   if(dt.hour < 16) return 1; // London  08-16
   return 2;                  // New York 16-24
}

//--- Drawdown gate: pause after 4 consecutive losses; resume on session change
bool CBacktester::_drawdownAllowed(datetime t)
{
   int cur = _getSession(t);
   if(m_pausedSession >= 0)
   {
      if(cur != m_pausedSession) { m_pausedSession = -1; m_consecLosses = 0; return true; }
      return false;
   }
   if(m_consecLosses >= 4) { m_pausedSession = cur; return false; }
   return true;
}

//--- Signal at bar[i]: MACD histogram flip + RSI + M15 EMA50 slope
bool CBacktester::_isSignal(int i, int &dir)
{
   double hist[2], rsi[1], ema[2];
   ArraySetAsSeries(hist, true);
   ArraySetAsSeries(rsi,  true);
   ArraySetAsSeries(ema,  true);

   // hist[0]=bar[i], hist[1]=bar[i+1] (1 bar earlier = previous)
   if(CopyBuffer(m_macdH, 2, i, 2, hist) <= 0) return false; // buffer 2 = histogram
   if(CopyBuffer(m_rsiH,  0, i, 1, rsi)  <= 0) return false;

   // Map M3 bar time to corresponding M15 bar index for EMA offset
   int m15Idx = iBarShift(m_symbol, PERIOD_M15, m_ratesM3[i].time, false);
   if(m15Idx < 1) return false; // need 2 M15 bars to compute slope
   if(CopyBuffer(m_emaH, 0, m15Idx, 2, ema) <= 0) return false;

   double slope = (ema[0] - ema[1]) / (_Point * 10); // pips/bar for XAUUSD

   // Buy: hist flips neg→pos, RSI oversold, EMA uptrend
   if(hist[1] < 0.0 && hist[0] > 0.0 && rsi[0] < 35.0 && slope > +0.1) { dir = +1; return true; }
   // Sell: hist flips pos→neg, RSI overbought, EMA downtrend
   if(hist[1] > 0.0 && hist[0] < 0.0 && rsi[0] > 65.0 && slope < -0.1) { dir = -1; return true; }
   return false;
}

//--- PnL in account currency using broker tick value/size
double CBacktester::_calcPnL(int dir, double entry, double ex)
{
   double tVal = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tSz  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tSz <= 0.0) return 0.0;
   return (ex - entry) * dir * BT_LOT * (tVal / tSz);
}

//--- Exit detection: TP takes priority over SL when both hit same bar
bool CBacktester::_detectExit(VirtualTrade &t, int idx)
{
   double hi = m_ratesM3[idx].high;
   double lo = m_ratesM3[idx].low;
   bool tpHit = (t.direction == +1) ? (hi >= t.tp) : (lo <= t.tp);
   bool slHit = (t.direction == +1) ? (lo <= t.sl) : (hi >= t.sl);
   if(tpHit) { t.exit_price = t.tp; t.exit_reason = "TP"; return true; }
   if(slHit) { t.exit_price = t.sl; t.exit_reason = "SL"; return true; }
   return false;
}
//+------------------------------------------------------------------+
