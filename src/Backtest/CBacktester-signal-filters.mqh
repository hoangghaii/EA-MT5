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
   // MQL5 iMACD has only buffer 0 (MACD line) and buffer 1 (signal line)
   // Histogram = MACD line - signal line (no separate buffer 2)
   double macdLine[2], sigLine[2], rsi[1], ema[2];
   ArraySetAsSeries(macdLine, true);
   ArraySetAsSeries(sigLine,  true);
   ArraySetAsSeries(rsi,      true);
   ArraySetAsSeries(ema,      true);

   if(CopyBuffer(m_macdH, 0, i, 2, macdLine) <= 0) { m_dBuf++; return false; }
   if(CopyBuffer(m_macdH, 1, i, 2, sigLine)  <= 0) { m_dBuf++; return false; }
   if(CopyBuffer(m_rsiH,  0, i, 1, rsi)      <= 0) { m_dBuf++; return false; }

   // hist[0]=current bar, hist[1]=previous bar
   double hist0 = macdLine[0] - sigLine[0];
   double hist1 = macdLine[1] - sigLine[1];

   // Map M3 bar time to corresponding M15 bar index for EMA offset
   int m15Idx = iBarShift(m_symbol, PERIOD_M15, m_ratesM3[i].time, false);
   if(m15Idx < 1) { m_dM15++; return false; }
   if(CopyBuffer(m_emaH, 0, m15Idx, 2, ema) <= 0) { m_dBuf++; return false; }

   double slope = (ema[0] - ema[1]) / (_Point * 10); // pips/bar for XAUUSD

   bool macdFlipBuy  = (hist1 < 0.0 && hist0 > 0.0);
   bool macdFlipSell = (hist1 > 0.0 && hist0 < 0.0);
   if(!macdFlipBuy && !macdFlipSell) { m_dMacd++; return false; }

   // RSI check
   bool rsiBuy  = (rsi[0] < 35.0);
   bool rsiSell = (rsi[0] > 65.0);
   if((macdFlipBuy && !rsiBuy) || (macdFlipSell && !rsiSell)) { m_dRsi++; return false; }

   // Slope check
   bool slopeBuy  = (slope > +0.1);
   bool slopeSell = (slope < -0.1);
   if((macdFlipBuy && !slopeBuy) || (macdFlipSell && !slopeSell)) { m_dSlope++; return false; }

   if(macdFlipBuy  && rsiBuy  && slopeBuy)  { dir = +1; return true; }
   if(macdFlipSell && rsiSell && slopeSell) { dir = -1; return true; }
   return false;
}

//--- PnL in account currency using broker tick value/size
double CBacktester::_calcPnL(int dir, double entry, double ex)
{
   double tVal = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tSz  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tSz <= 0.0) return 0.0;
   return (ex - entry) * dir * m_lot * (tVal / tSz);
}

//--- Exit detection: TP > SL priority; break-even stop applied if enabled
bool CBacktester::_detectExit(VirtualTrade &t, int idx)
{
   double hi = m_ratesM3[idx].high;
   double lo = m_ratesM3[idx].low;

   // Break-even: once price reaches 1:1 level, slide SL to entry (only once)
   if(m_beStop)
   {
      double slDist = MathAbs(t.tp - t.entry_price) / m_rr; // 1 × SL distance
      double beLvl  = t.entry_price + t.direction * slDist;
      bool   beHit  = (t.direction == +1) ? (hi >= beLvl) : (lo <= beLvl);
      // Only move if SL still at original loss-side (haven't moved yet)
      bool   notMoved = (t.direction == +1) ? (t.sl < t.entry_price - _Point * 0.5)
                                            : (t.sl > t.entry_price + _Point * 0.5);
      if(beHit && notMoved) t.sl = t.entry_price;
   }

   bool tpHit = (t.direction == +1) ? (hi >= t.tp) : (lo <= t.tp);
   bool slHit = (t.direction == +1) ? (lo <= t.sl) : (hi >= t.sl);
   if(tpHit) { t.exit_price = t.tp; t.exit_reason = "TP"; return true; }
   if(slHit)
   {
      t.exit_price  = t.sl;
      t.exit_reason = (MathAbs(t.sl - t.entry_price) < _Point) ? "BE" : "SL";
      return true;
   }
   return false;
}

//--- Open pyramid positions at signal bar[i]; returns count of positions opened
int CBacktester::_openPyramid(VirtualTrade &open[], int sigDir, int i)
{
   double base  = m_ratesM3[i - 1].open;
   double barHi = m_ratesM3[i - 1].high;
   double barLo = m_ratesM3[i - 1].low;
   int    cnt   = 0;
   if(m_pyramid > ArraySize(open)) ArrayResize(open, m_pyramid);

   for(int p = 0; p < m_pyramid; p++)
   {
      // BUY: add at progressively lower prices (better fill); SELL: higher
      double e = base - sigDir * p * m_pyrDelta * _Point;
      // p==0 always fills at bar open; p>0 requires bar to reach that level
      bool reached = (p == 0) || ((sigDir == +1) ? (barLo <= e) : (barHi >= e));
      if(!reached) break;

      open[cnt].direction   = sigDir;
      open[cnt].entry_time  = m_ratesM3[i - 1].time;
      open[cnt].entry_price = e;
      open[cnt].sl          = e - sigDir * BT_SL_PTS * _Point;
      open[cnt].tp          = e + sigDir * BT_SL_PTS * _Point * m_rr;
      open[cnt].exit_price  = 0;
      open[cnt].exit_time   = 0;
      open[cnt].pnl         = 0;
      open[cnt].exit_reason = "OPEN";
      cnt++;
   }
   return cnt;
}
//+------------------------------------------------------------------+
