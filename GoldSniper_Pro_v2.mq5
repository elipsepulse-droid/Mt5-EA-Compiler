//+------------------------------------------------------------------+ //|                  TuyulGoldScalper_Improved.mq5                  | //|   XAUUSD Pending-Order Breakout Straddle Scalper (MT5)          | //|   Based on consolidation breakout logic with risk controls      | //+------------------------------------------------------------------+ #property strict #property version   "2.00" #property copyright "OpenAI"

#include <Trade/Trade.mqh> #include <Trade/OrderInfo.mqh> #include <Trade/PositionInfo.mqh>

CTrade        trade; COrderInfo    orderInfo; CPositionInfo posInfo;

//--------------------------- Inputs --------------------------------- input group "Core" input long     MagicNumber          = 20250327; input bool     ShowDashboard        = true; input bool     OneCycleAtATime      = true; input bool     CancelOppositePending= true; input int      PendingExpiryMin     = 5; input int      CooldownBars         = 3;

input group "Lot / Risk" input double   FixedLot             = 0.01; input bool     UseAutoLot           = false; input double   RiskPercent          = 1.0; input double   MaxLot               = 50.0;

input group "Signal / Range" input int      ATR_Period           = 14; input double   ATR_Multiplier       = 0.5; input int      MinPendingDistPoints = 15; input int      MaxPendingDistPoints = 150; input int      ConsolBars           = 5; input double   ConsolATR_Factor     = 0.8;

input group "Exit" input int      StopLossPoints       = 150; input int      TakeProfitPoints     = 200; input bool     UseBreakEven         = true; input int      BreakEvenStartPoints = 80; input int      BreakEvenLockPoints  = 1; input bool     UseTrailingStop      = true; input int      TrailStartPoints     = 100; input int      TrailStepPoints      = 50;

input group "Filters" input int      MaxSpreadPoints      = 10; input int      MaxDeviationPoints   = 3; input bool     UseSessionFilter     = true; input int      SessionStartHour     = 8; input int      SessionEndHour       = 22; input bool     UseTrendFilter       = false; input int      EMA_Fast             = 20; input int      EMA_Slow             = 50; input bool     UseADXFilter         = false; input int      ADX_Period           = 14; input double   MinADX               = 18.0; input bool     UseATRVolFilter      = false; input int      MinATRPoints         = 50;

input group "Safety" input bool     EnforceStopLevel     = true; input bool     DeleteStalePendings  = true; input int      MaxBarsToHoldPending = 10;

//--------------------------- Globals -------------------------------- double   g_point      = 0.0; int      g_digits      = 0; int      g_atrHandle   = INVALID_HANDLE; int      g_emaFast     = INVALID_HANDLE; int      g_emaSlow     = INVALID_HANDLE; int      g_adxHandle   = INVALID_HANDLE;

datetime g_lastBarTime = 0; datetime g_lastCloseTime = 0; int      g_barsSinceClose = 9999; int      g_totalPlacedCycles = 0; double   g_sessionProfit = 0.0; string   g_status = "Waiting...";

//--------------------------- Helpers -------------------------------- int CountOurPositions() { int cnt = 0; for(int i = PositionsTotal() - 1; i >= 0; i--) { if(!posInfo.SelectByIndex(i)) continue; if(posInfo.Symbol() != Symbol()) continue; if((long)posInfo.Magic() != MagicNumber) continue; cnt++; } return cnt; }

int CountOurPending(ENUM_ORDER_TYPE typeFilter = WRONG_VALUE) { int cnt = 0; for(int i = OrdersTotal() - 1; i >= 0; i--) { if(!orderInfo.SelectByIndex(i)) continue; if(orderInfo.Symbol() != Symbol()) continue; if((long)orderInfo.Magic() != MagicNumber) continue; if(typeFilter != WRONG_VALUE && orderInfo.OrderType() != typeFilter) continue; cnt++; } return cnt; }

bool IsOurPositionOpen() { return CountOurPositions() > 0; }

bool IsInSession() { if(!UseSessionFilter) return true; MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); int h = dt.hour; if(SessionStartHour < SessionEndHour) return (h >= SessionStartHour && h < SessionEndHour); return (h >= SessionStartHour || h < SessionEndHour); }

bool NewBar() { datetime t = iTime(Symbol(), PERIOD_CURRENT, 0); if(t != g_lastBarTime) { g_lastBarTime = t; return true; } return false; }

bool GetATR(double &atrValue) { double buf[]; ArraySetAsSeries(buf, true); if(CopyBuffer(g_atrHandle, 0, 0, 3, buf) < 2) return false; atrValue = buf[1]; return (atrValue > 0.0); }

bool GetEMA(int handle, double &value) { if(handle == INVALID_HANDLE) return false; double buf[]; ArraySetAsSeries(buf, true); if(CopyBuffer(handle, 0, 0, 3, buf) < 2) return false; value = buf[1]; return true; }

bool GetADX(double &adxValue) { if(g_adxHandle == INVALID_HANDLE) return false; double buf[]; ArraySetAsSeries(buf, true); if(CopyBuffer(g_adxHandle, 0, 0, 3, buf) < 2) return false; adxValue = buf[1]; return true; }

bool IsConsolidating(double atrValue) { if(ConsolBars < 2) return false;

double hi = iHigh(Symbol(), PERIOD_CURRENT, 1); double lo = iLow(Symbol(), PERIOD_CURRENT, 1); for(int i = 2; i <= ConsolBars; i++) { double h = iHigh(Symbol(), PERIOD_CURRENT, i); double l = iLow(Symbol(), PERIOD_CURRENT, i); if(h > hi) hi = h; if(l < lo) lo = l; }

double range = hi - lo; return (range < atrValue * ConsolATR_Factor); }

bool TrendAllowsBuySell(bool &allowBuy, bool &allowSell) { allowBuy = true; allowSell = true;

if(!UseTrendFilter) return true;

double fast = 0.0, slow = 0.0; if(!GetEMA(g_emaFast, fast) || !GetEMA(g_emaSlow, slow)) return false;

// Simple directional bias: only allow breakout in direction of EMA alignment. if(fast > slow) allowSell = false; else if(fast < slow) allowBuy = false;

return true; }

bool AdxAllowsTrade() { if(!UseADXFilter) return true; double adx = 0.0; if(!GetADX(adx)) return false; return (adx >= MinADX); }

bool AtrAllowsTrade(double atrValue) { if(!UseATRVolFilter) return true; double atrPoints = atrValue / g_point; return (atrPoints >= MinATRPoints); }

double NormalizeLot(double lot) { double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN); double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX); double step   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP); if(MaxLot > 0.0) maxLot = MathMin(maxLot, MaxLot); lot = MathMax(minLot, MathMin(maxLot, lot)); if(step > 0.0) lot = MathFloor(lot / step) * step; int prec = 2; return NormalizeDouble(lot, prec); }

double CalcAutoLot(double slDistancePrice) { if(slDistancePrice <= 0.0) return NormalizeLot(FixedLot);

double balance  = AccountInfoDouble(ACCOUNT_BALANCE); double riskCash = balance * RiskPercent / 100.0; double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE); double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE); if(tickVal <= 0.0 || tickSize <= 0.0) return NormalizeLot(FixedLot);

double lot = riskCash / ((slDistancePrice / tickSize) * tickVal); return NormalizeLot(lot); }

double StopLevelPoints() { int stops = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL); return (double)stops; }

bool CanPlaceAtDistance(double entryPrice, ENUM_ORDER_TYPE type) { if(!EnforceStopLevel) return true;

double levelPts = StopLevelPoints(); if(levelPts <= 0.0) return true;

double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK); double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID); double distPts = 0.0;

if(type == ORDER_TYPE_BUY_STOP) distPts = (entryPrice - ask) / g_point; else if(type == ORDER_TYPE_SELL_STOP) distPts = (bid - entryPrice) / g_point; else return false;

return (distPts >= levelPts); }

void DeleteAllOurPendings() { for(int i = OrdersTotal() - 1; i >= 0; i--) { if(!orderInfo.SelectByIndex(i)) continue; if(orderInfo.Symbol() != Symbol()) continue; if((long)orderInfo.Magic() != MagicNumber) continue; if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP || orderInfo.OrderType() == ORDER_TYPE_SELL_STOP) trade.OrderDelete(orderInfo.Ticket()); } }

void DeleteOppositePendingAfterEntry() { if(!CancelOppositePending) return;

bool hasBuy = false, hasSell = false; for(int i = 0; i < PositionsTotal(); i++) { if(!posInfo.SelectByIndex(i)) continue; if(posInfo.Symbol() != Symbol()) continue; if((long)posInfo.Magic() != MagicNumber) continue; if(posInfo.PositionType() == POSITION_TYPE_BUY) hasBuy = true; if(posInfo.PositionType() == POSITION_TYPE_SELL) hasSell = true; }

if(hasBuy || hasSell) DeleteAllOurPendings(); }

datetime GetNewestOurPendingTime() { datetime newest = 0; for(int i = OrdersTotal() - 1; i >= 0; i--) { if(!orderInfo.SelectByIndex(i)) continue; if(orderInfo.Symbol() != Symbol()) continue; if((long)orderInfo.Magic() != MagicNumber) continue; if(orderInfo.OrderType() != ORDER_TYPE_BUY_STOP && orderInfo.OrderType() != ORDER_TYPE_SELL_STOP) continue; datetime t = (datetime)orderInfo.TimeSetup(); if(t > newest) newest = t; } return newest; }

void DeleteStalePendingsIfNeeded() { if(!DeleteStalePendings) return; if(MaxBarsToHoldPending <= 0) return;

int secPerBar = PeriodSeconds(PERIOD_CURRENT); if(secPerBar <= 0) return;

datetime newest = GetNewestOurPendingTime(); if(newest <= 0) return;

if((TimeCurrent() - newest) > (MaxBarsToHoldPending * secPerBar)) DeleteAllOurPendings(); }

void UpdatePositionProtection() { for(int i = PositionsTotal() - 1; i >= 0; i--) { if(!posInfo.SelectByIndex(i)) continue; if(posInfo.Symbol() != Symbol()) continue; if((long)posInfo.Magic() != MagicNumber) continue;

ulong  ticket = posInfo.Ticket();
  double openP  = posInfo.PriceOpen();
  double curSL  = posInfo.StopLoss();
  double curTP  = posInfo.TakeProfit();
  double curPx  = posInfo.PriceCurrent();

  if(posInfo.PositionType() == POSITION_TYPE_BUY)
  {
     double profitPts = (curPx - openP) / g_point;

     if(UseBreakEven && profitPts >= BreakEvenStartPoints)
     {
        double beSL = NormalizeDouble(openP + BreakEvenLockPoints * g_point, g_digits);
        if(curSL == 0.0 || beSL > curSL)
           trade.PositionModify(ticket, beSL, curTP);
     }

     if(UseTrailingStop && profitPts >= TrailStartPoints)
     {
        double trailSL = NormalizeDouble(curPx - TrailStepPoints * g_point, g_digits);
        if(trailSL > curSL)
           trade.PositionModify(ticket, trailSL, curTP);
     }
  }
  else if(posInfo.PositionType() == POSITION_TYPE_SELL)
  {
     double profitPts = (openP - curPx) / g_point;

     if(UseBreakEven && profitPts >= BreakEvenStartPoints)
     {
        double beSL = NormalizeDouble(openP - BreakEvenLockPoints * g_point, g_digits);
        if(curSL == 0.0 || curSL > beSL)
           trade.PositionModify(ticket, beSL, curTP);
     }

     if(UseTrailingStop && profitPts >= TrailStartPoints)
     {
        double trailSL = NormalizeDouble(curPx + TrailStepPoints * g_point, g_digits);
        if(curSL == 0.0 || trailSL < curSL)
           trade.PositionModify(ticket, trailSL, curTP);
     }
  }

} }

bool PlaceStraddle(double atrValue) { double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK); double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

int distPts = (int)MathRound((atrValue * ATR_Multiplier) / g_point); distPts = MathMax(MinPendingDistPoints, MathMin(MaxPendingDistPoints, distPts));

double dist = distPts * g_point; double buyPrice  = NormalizeDouble(ask + dist, g_digits); double sellPrice = NormalizeDouble(bid - dist, g_digits);

if(!CanPlaceAtDistance(buyPrice, ORDER_TYPE_BUY_STOP)) { g_status = "BUY STOP too close to price"; return false; } if(!CanPlaceAtDistance(sellPrice, ORDER_TYPE_SELL_STOP)) { g_status = "SELL STOP too close to price"; return false; }

double slDist = StopLossPoints * g_point; double tpDist = TakeProfitPoints * g_point; double lot = UseAutoLot ? CalcAutoLot(slDist) : NormalizeLot(FixedLot);

datetime expiry = TimeCurrent() + (PendingExpiryMin * 60);

MqlTradeRequest req; MqlTradeResult  res; ZeroMemory(req); ZeroMemory(res);

req.action     = TRADE_ACTION_PENDING; req.symbol     = Symbol(); req.volume     = lot; req.type       = ORDER_TYPE_BUY_STOP; req.price      = buyPrice; req.sl         = NormalizeDouble(buyPrice - slDist, g_digits); req.tp         = NormalizeDouble(buyPrice + tpDist, g_digits); req.type_time  = ORDER_TIME_SPECIFIED; req.expiration = expiry; req.magic      = (ulong)MagicNumber; req.comment    = "TGS_BUY_STOP"; req.deviation  = (ulong)MaxDeviationPoints;

bool okBuy = OrderSend(req, res); if(!okBuy) Print("BUY STOP failed retcode=", res.retcode);

ZeroMemory(req); ZeroMemory(res);

req.action     = TRADE_ACTION_PENDING; req.symbol     = Symbol(); req.volume     = lot; req.type       = ORDER_TYPE_SELL_STOP; req.price      = sellPrice; req.sl         = NormalizeDouble(sellPrice + slDist, g_digits); req.tp         = NormalizeDouble(sellPrice - tpDist, g_digits); req.type_time  = ORDER_TIME_SPECIFIED; req.expiration = expiry; req.magic      = (ulong)MagicNumber; req.comment    = "TGS_SELL_STOP"; req.deviation  = (ulong)MaxDeviationPoints;

bool okSell = OrderSend(req, res); if(!okSell) Print("SELL STOP failed retcode=", res.retcode);

g_totalPlacedCycles++; g_status = StringFormat("Straddle placed | dist=%d pts | lot=%.2f", distPts, lot); return (okBuy || okSell); }

//--------------------------- MT5 Events ---------------------------- int OnInit() { g_point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT); g_digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

if(StringFind(Symbol(), "XAU") < 0 && StringFind(Symbol(), "GOLD") < 0) Print("Warning: EA is intended for gold symbols. Current symbol = ", Symbol());

g_atrHandle = iATR(Symbol(), PERIOD_CURRENT, ATR_Period); if(g_atrHandle == INVALID_HANDLE) return INIT_FAILED;

if(UseTrendFilter) { g_emaFast = iMA(Symbol(), PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE); g_emaSlow = iMA(Symbol(), PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE); if(g_emaFast == INVALID_HANDLE || g_emaSlow == INVALID_HANDLE) return INIT_FAILED; }

if(UseADXFilter) { g_adxHandle = iADX(Symbol(), PERIOD_CURRENT, ADX_Period); if(g_adxHandle == INVALID_HANDLE) return INIT_FAILED; }

trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(MaxDeviationPoints); trade.SetTypeFilling(ORDER_FILLING_IOC); trade.SetAsyncMode(false);

g_status = "Initialized"; return INIT_SUCCEEDED; }

void OnDeinit(const int reason) { if(g_atrHandle   != INVALID_HANDLE) IndicatorRelease(g_atrHandle); if(g_emaFast     != INVALID_HANDLE) IndicatorRelease(g_emaFast); if(g_emaSlow     != INVALID_HANDLE) IndicatorRelease(g_emaSlow); if(g_adxHandle   != INVALID_HANDLE) IndicatorRelease(g_adxHandle); Comment(""); }

void OnTick() { UpdatePositionProtection(); DeleteOppositePendingAfterEntry(); DeleteStalePendingsIfNeeded();

if(!NewBar()) { if(ShowDashboard) DrawDashboard(); return; }

if(g_lastCloseTime > 0) g_barsSinceClose++;

double atr = 0.0; if(!GetATR(atr)) { g_status = "ATR not ready"; if(ShowDashboard) DrawDashboard(); return; }

int spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD); if(spread > MaxSpreadPoints) { g_status = StringFormat("Spread too wide: %d", spread); if(ShowDashboard) DrawDashboard(); return; }

if(!IsInSession()) { g_status = "Outside session"; if(ShowDashboard) DrawDashboard(); return; }

if(g_barsSinceClose < CooldownBars) { g_status = StringFormat("Cooldown: %d bars left", CooldownBars - g_barsSinceClose); if(ShowDashboard) DrawDashboard(); return; }

if(!AdxAllowsTrade()) { g_status = "ADX filter blocked trade"; if(ShowDashboard) DrawDashboard(); return; }

if(!AtrAllowsTrade(atr)) { g_status = "ATR filter blocked trade"; if(ShowDashboard) DrawDashboard(); return; }

if(OneCycleAtATime && (CountOurPositions() > 0 || CountOurPending() > 0)) { g_status = "Active cycle already running"; if(ShowDashboard) DrawDashboard(); return; }

bool allowBuy = true, allowSell = true; if(!TrendAllowsBuySell(allowBuy, allowSell)) { g_status = "Trend filter data unavailable"; if(ShowDashboard) DrawDashboard(); return; }

if(IsConsolidating(atr)) { bool placed = false;

if(allowBuy && allowSell)
     placed = PlaceStraddle(atr);
  else if(allowBuy)
  {
     // One-sided bias version: place only buy stop.
     double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
     int distPts = (int)MathRound((atr * ATR_Multiplier) / g_point);
     distPts = MathMax(MinPendingDistPoints, MathMin(MaxPendingDistPoints, distPts));
     double buyPrice = NormalizeDouble(ask + distPts * g_point, g_digits);
     if(CanPlaceAtDistance(buyPrice, ORDER_TYPE_BUY_STOP))
     {
        double lot = UseAutoLot ? CalcAutoLot(StopLossPoints * g_point) : NormalizeLot(FixedLot);
        MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
        req.action = TRADE_ACTION_PENDING; req.symbol = Symbol(); req.volume = lot; req.type = ORDER_TYPE_BUY_STOP;
        req.price = buyPrice; req.sl = NormalizeDouble(buyPrice - StopLossPoints * g_point, g_digits);
        req.tp = NormalizeDouble(buyPrice + TakeProfitPoints * g_point, g_digits);
        req.type_time = ORDER_TIME_SPECIFIED; req.expiration = TimeCurrent() + PendingExpiryMin * 60;
        req.magic = (ulong)MagicNumber; req.comment = "TGS_BUY_ONLY"; req.deviation = (ulong)MaxDeviationPoints;
        placed = OrderSend(req, res);
     }
  }
  else if(allowSell)
  {
     double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
     int distPts = (int)MathRound((atr * ATR_Multiplier) / g_point);
     distPts = MathMax(MinPendingDistPoints, MathMin(MaxPendingDistPoints, distPts));
     double sellPrice = NormalizeDouble(bid - distPts * g_point, g_digits);
     if(CanPlaceAtDistance(sellPrice, ORDER_TYPE_SELL_STOP))
     {
        double lot = UseAutoLot ? CalcAutoLot(StopLossPoints * g_point) : NormalizeLot(FixedLot);
        MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); ZeroMemory(res);
        req.action = TRADE_ACTION_PENDING; req.symbol = Symbol(); req.volume = lot; req.type = ORDER_TYPE_SELL_STOP;
        req.price = sellPrice; req.sl = NormalizeDouble(sellPrice + StopLossPoints * g_point, g_digits);
        req.tp = NormalizeDouble(sellPrice - TakeProfitPoints * g_point, g_digits);
        req.type_time = ORDER_TIME_SPECIFIED; req.expiration = TimeCurrent() + PendingExpiryMin * 60;
        req.magic = (ulong)MagicNumber; req.comment = "TGS_SELL_ONLY"; req.deviation = (ulong)MaxDeviationPoints;
        placed = OrderSend(req, res);
     }
  }

  g_status = placed ? "Consolidation detected -> order placed" : "Consolidation detected -> place failed";

} else { g_status = "No consolidation"; }

if(ShowDashboard) DrawDashboard(); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest     &request, const MqlTradeResult      &result) { if(trans.type == TRADE_TRANSACTION_DEAL_ADD) { if(!HistoryDealSelect(trans.deal)) return; long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY); long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC); string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

if(magic == MagicNumber && sym == Symbol())
  {
     if(entry == DEAL_ENTRY_OUT)
     {
        g_lastCloseTime = TimeCurrent();
        g_barsSinceClose = 0;
        g_sessionProfit += HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
     }
  }

} }

//--------------------------- Dashboard ------------------------------ void DrawDashboard() { int spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD); double atr = 0.0; GetATR(atr);

string txt; txt  = "=== TUYUL GOLD SCALPER IMPROVED ===\n"; txt += "Symbol   : " + Symbol() + "\n"; txt += "Spread   : " + IntegerToString(spread) + " pts\n"; txt += "ATR      : " + DoubleToString(atr / g_point, 0) + " pts\n"; txt += "Positions: " + IntegerToString(CountOurPositions()) + "\n"; txt += "Pendings : " + IntegerToString(CountOurPending()) + "\n"; txt += "Profit   : " + DoubleToString(g_sessionProfit, 2) + "\n"; txt += "Cycles   : " + IntegerToString(g_totalPlacedCycles) + "\n"; txt += "Status   : " + g_status + "\n"; Comment(txt); } //+------------------------------------------------------------------+
