//+------------------------------------------------------------------+
//|  Breakout Pending Order Scalper — GOLD & BTC Edition             |
//|  Strategy : Consolidation Range + Buy Stop / Sell Stop           |
//|  Symbols  : XAUUSD / XAUUSDm / BTCUSD / BTCUSDm (auto-detect)  |
//|  Version  : 2.4 (Root-Cause Execution Fix)                      |
//+------------------------------------------------------------------+
//
// WHY TRADES WERE DELAYED / NOT OPENING — ROOT CAUSES FIXED IN v2.4:
//
// BUG 1 — SYMBOL_FILLING_MODE (wrong MQL5 property)
//   v2.1 used SYMBOL_FILLING_MODE which does NOT exist in MQL5.
//   This returned 0 → all bits false → forced ORDER_FILLING_RETURN.
//   On some brokers this causes silent order rejection.
//   FIX: Use SYMBOL_FILLING_FLAGS (correct MQL5 property).
//
// BUG 2 — PendingExpireBars = 3 caused "chasing range" loop
//   Every 3 bars orders were DELETED and re-placed at the NEW range.
//   If price was slowly approaching an order level and the order
//   expired first, the new order moved FURTHER away from price.
//   This made it look like trades "never open" — the target kept shifting.
//   FIX: Orders are now MODIFIED to the new range price instead of
//   deleted+replaced. Existing orders track range movement in-place.
//   PendingExpireBars default raised to 10 bars.
//
// BUG 3 — No minimum range size guard
//   In a tight sideways market the high-low range was tiny (<2×buffer).
//   This placed buy stop and sell stop dangerously close together or
//   overlapping, causing both to fire on the same candle (double entry).
//   FIX: Added MinRangePoints input. Orders not placed if range too tight.
//
// BUG 4 — Spread filter not scaled for BTC in v2.1/v2.2
//   Default MaxSpreadPoints = 80. BTC raw spread on Exness M1 is ~140 pts.
//   The filter silently blocked all BTC order placement.
//   FIX: Spread comparison now uses PRICE-UNIT spread vs scaled threshold
//   (inherited from v2.2 scaling). Also added live dashboard alert when
//   spread is the reason orders are blocked.
//
// All v2.3 features fully retained:
//   • On-chart dashboard (balance, equity, P&L, orders, filters, news)
//   • MT5 Economic Calendar news filter (US high-impact events)
//   • Auto symbol detection GOLD / BTC / CUSTOM
//   • Dynamic parameter scaling for BTC
//   • 24/7 mode (session filter off by default)
//+------------------------------------------------------------------+

#property copyright "bs.autotrade / Multi-Symbol Edition"
#property version   "2.40"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        Trade;
COrderInfo    OrderInfo;
CPositionInfo PositionInfo;

//--- ═══════════════════════════════════════════════════════════════
//    CONSTANTS
//--- ═══════════════════════════════════════════════════════════════
#define DASH_PFX  "TPO24_"
#define DASH_W    245
#define DASH_H    295
#define ROW_H     16

//--- ═══════════════════════════════════════════════════════════════
//    ENUMS
//--- ═══════════════════════════════════════════════════════════════
enum ENUM_SYMBOL_TYPE
{
   SYM_AUTO  = 0,  // Auto-Detect (recommended)
   SYM_GOLD  = 1,  // Force GOLD (XAUUSD) mode
   SYM_BTC   = 2,  // Force BTC  (BTCUSD) mode
   SYM_OTHER = 3   // Custom — inputs used as-is
};

//--- ═══════════════════════════════════════════════════════════════
//    INPUTS
//--- ═══════════════════════════════════════════════════════════════

input group "═══ SYMBOL MODE ═══"
input ENUM_SYMBOL_TYPE SymbolMode         = SYM_AUTO;

input group "═══ TRADE SETUP ═══"
input double LotSize                      = 0.01;
input int    RangeBars                    = 5;       // Consolidation bars to scan
input int    EntryBufferPoints            = 50;      // Buffer above/below range (auto-scaled)
input int    MinRangePoints               = 100;     // [BUG3 FIX] Min range size in pts (0=off)
input long   MagicNumber                  = 202502;

input group "═══ STOP LOSS & TAKE PROFIT ═══"
input bool   UseATR_SL                    = true;
input double ATR_SL_Multiplier            = 1.5;
input double ATR_TP_Multiplier            = 2.5;
input int    FixedSL_Points               = 300;
input int    FixedTP_Points               = 500;
input int    ATR_Period                   = 14;

input group "═══ TRAILING & BREAKEVEN ═══"
input bool   UseTrailing                  = true;
input int    TrailingStart_Points         = 200;
input int    TrailingStep_Points          = 100;
input bool   UseBreakeven                 = true;
input int    BreakevenActivate            = 150;
input int    BreakevenOffset              = 10;

input group "═══ FILTERS ═══"
input int    MaxSpreadPoints              = 80;      // Max spread pts (auto-scaled; 0=off)
input bool   UseSessionFilter             = false;   // OFF = 24/7 trading
input int    SessionStartHour             = 7;
input int    SessionEndHour               = 20;
input bool   UseCancelOpposite            = true;
input bool   UseVolatilityFilter          = true;
input double MinATR_Points                = 50.0;

input group "═══ NEWS FILTER ═══"
input bool   UseNewsFilter                = true;
input int    NewsMinutesBefore            = 30;
input int    NewsMinutesAfter             = 30;
input bool   NewsDeletePending            = true;
input bool   NewsFilterModerate           = false;

input group "═══ RISK MANAGEMENT ═══"
input double MaxDailyLossPct              = 3.0;
input int    MaxOpenOrders                = 2;
input bool   CloseOnNewBar                = false;
input int    PendingExpireBars            = 10;     // [BUG2 FIX] Raised from 3 → 10

input group "═══ DASHBOARD ═══"
input bool   ShowDashboard                = true;
input int    DashX                        = 10;
input int    DashY                        = 30;
input ENUM_BASE_CORNER DashCorner         = CORNER_LEFT_UPPER;

//--- ═══════════════════════════════════════════════════════════════
//    GLOBALS
//--- ═══════════════════════════════════════════════════════════════
datetime g_lastBarTime     = 0;
double   g_dayStartBalance = 0.0;
datetime g_today           = 0;
int      g_atrHandle       = INVALID_HANDLE;

// Scaled parameters (set in ApplySymbolPreset)
double   g_entryBuffer     = 0.0;
double   g_minRange        = 0.0;
double   g_fixedSL         = 0.0;
double   g_fixedTP         = 0.0;
double   g_trailStart      = 0.0;
double   g_trailStep       = 0.0;
double   g_beActivate      = 0.0;
double   g_beOffset        = 0.0;
double   g_maxSpread       = 0.0;
double   g_minATR          = 0.0;
string   g_symbolLabel     = "";

// News
bool     g_newsBlocked     = false;
string   g_newsEventName   = "";
datetime g_newsEventTime   = 0;
datetime g_newsLastCheck   = 0;

// Dashboard throttle
datetime g_dashLastUpdate  = 0;

// Block reason for dashboard (shows WHY orders weren't placed)
string   g_blockReason     = "";

//+------------------------------------------------------------------+
//  INIT
//+------------------------------------------------------------------+
int OnInit()
{
   // [BUG1 FIX] Use SYMBOL_FILLING_FLAGS (correct MQL5 property)
   ENUM_ORDER_TYPE_FILLING fill = GetFillMode();
   Trade.SetTypeFilling(fill);
   Trade.SetExpertMagicNumber((ulong)MagicNumber);
   Trade.SetDeviationInPoints(20);

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Alert("TUYUL PO v2.4: ATR handle failed — EA will not run.");
      return(INIT_FAILED);
   }

   ApplySymbolPreset();

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_today           = iTime(_Symbol, PERIOD_D1, 0);

   if(ShowDashboard) CreateDashboard();

   PrintFormat("TUYUL PO v2.4 | %s [%s] | TF:%s | Fill:%s | News:%s",
               _Symbol, g_symbolLabel, EnumToString(Period()),
               EnumToString(fill), UseNewsFilter ? "ON" : "OFF");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//  DEINIT
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//  MAIN TICK
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily reset
   datetime todayD1 = iTime(_Symbol, PERIOD_D1, 0);
   if(todayD1 != g_today)
   {
      g_today           = todayD1;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   // Daily loss breaker
   if(MaxDailyLossPct > 0.0 && IsDailyLossBreached())
   {
      CloseAllPositions();
      DeleteAllPending();
      g_blockReason = "DAILY LOSS LIMIT";
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Trailing + Breakeven
   ManageOpenPositions();

   // OCO
   if(UseCancelOpposite) ManageOCO();

   // News check (throttled)
   if(UseNewsFilter && (TimeCurrent() - g_newsLastCheck) >= 60)
      RefreshNewsFilter();

   // Dashboard (throttled)
   if(ShowDashboard && (TimeCurrent() - g_dashLastUpdate) >= 2)
   {
      UpdateDashboard();
      g_dashLastUpdate = TimeCurrent();
   }

   // Delete pendings on news window
   if(g_newsBlocked && NewsDeletePending)
      DeleteAllPending();

   // New bar detection
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   if(CloseOnNewBar) CloseAllPositions();
   if(PendingExpireBars > 0) ExpireOldPendings();

   // ── PRE-ORDER FILTER CHECKS ─────────────────────────────────────
   g_blockReason = "";

   if(UseSessionFilter && !IsSessionActive())
   { g_blockReason = "OUTSIDE SESSION"; return; }

   if(g_newsBlocked)
   { g_blockReason = "NEWS: " + g_newsEventName; return; }

   // [BUG4 FIX] Spread check uses scaled g_maxSpread (price units)
   if(g_maxSpread > 0.0 && GetCurrentSpread() > g_maxSpread)
   { g_blockReason = StringFormat("SPREAD HIGH (%.0f pts)",
                                   GetCurrentSpread()/_Point); return; }

   if(CountAllOrders() >= MaxOpenOrders)
   { g_blockReason = "MAX ORDERS REACHED"; return; }

   double atr = GetATR();
   if(atr <= 0.0)
   { g_blockReason = "ATR = 0 (no data)"; return; }

   if(UseVolatilityFilter && atr < g_minATR)
   { g_blockReason = StringFormat("ATR LOW (%.0f pts)", atr/_Point); return; }

   // ── PLACE OR MODIFY ORDERS ──────────────────────────────────────
   UpdateOrPlaceOrders(atr);
}

//+------------------------------------------------------------------+
//  SYMBOL AUTO-DETECT + PARAMETER SCALING
//+------------------------------------------------------------------+
void ApplySymbolPreset()
{
   ENUM_SYMBOL_TYPE res = SymbolMode;
   if(res == SYM_AUTO)
   {
      string s = _Symbol; StringToUpper(s);
      if(StringFind(s,"XAU")  >= 0 || StringFind(s,"GOLD") >= 0) res = SYM_GOLD;
      else if(StringFind(s,"BTC") >= 0)                           res = SYM_BTC;
      else                                                         res = SYM_OTHER;
   }

   double scale = 1.0;
   if(res == SYM_GOLD)     { scale = 1.0;  g_symbolLabel = "GOLD"; }
   else if(res == SYM_BTC) {
      double p  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      scale     = MathMax(10.0, MathMin(100.0, p / 3000.0));
      g_symbolLabel = "BTC";
   }
   else                    { scale = 1.0;  g_symbolLabel = "CUSTOM"; }

   g_entryBuffer = EntryBufferPoints    * _Point * scale;
   g_minRange    = MinRangePoints       * _Point * scale;
   g_fixedSL     = FixedSL_Points       * _Point * scale;
   g_fixedTP     = FixedTP_Points       * _Point * scale;
   g_trailStart  = TrailingStart_Points * _Point * scale;
   g_trailStep   = TrailingStep_Points  * _Point * scale;
   g_beActivate  = BreakevenActivate    * _Point * scale;
   g_beOffset    = BreakevenOffset      * _Point * scale;
   g_maxSpread   = MaxSpreadPoints      * _Point * scale;
   g_minATR      = MinATR_Points        * _Point * scale;
}

//+------------------------------------------------------------------+
//  [BUG2 FIX] MODIFY existing orders OR place new ones
//  Key change: if a pending already exists, MODIFY it to the new
//  range level instead of deleting and re-placing. This keeps orders
//  tracking the current range without the delete→gap→replace cycle
//  that caused missed executions.
//+------------------------------------------------------------------+
void UpdateOrPlaceOrders(double atr)
{
   double high = GetHighest(RangeBars);
   double low  = GetLowest(RangeBars);
   if(high <= 0.0 || low <= 0.0 || high <= low) return;

   // [BUG3 FIX] Minimum range size guard
   double rangeSize = high - low;
   if(g_minRange > 0.0 && rangeSize < g_minRange)
   {
      g_blockReason = StringFormat("RANGE TOO TIGHT (%.0f pts)", rangeSize/_Point);
      return;
   }

   double buyEntry  = NormalizeDouble(high + g_entryBuffer, _Digits);
   double sellEntry = NormalizeDouble(low  - g_entryBuffer, _Digits);

   double slDist = UseATR_SL ? atr * ATR_SL_Multiplier : g_fixedSL;
   double tpDist = UseATR_SL ? atr * ATR_TP_Multiplier : g_fixedTP;

   double buySL  = NormalizeDouble(buyEntry  - slDist, _Digits);
   double buyTP  = NormalizeDouble(buyEntry  + tpDist, _Digits);
   double sellSL = NormalizeDouble(sellEntry + slDist, _Digits);
   double sellTP = NormalizeDouble(sellEntry - tpDist, _Digits);

   if(buySL <= 0 || buyTP <= 0 || sellSL <= 0 || sellTP <= 0) return;

   long   stopLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (stopLvl + 1) * _Point;
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(slDist < minDist || tpDist < minDist) return;

   // ── BUY STOP: modify if exists, place if not ──────────────────
   ulong bsTicket = GetPendingTicket(ORDER_TYPE_BUY_STOP);
   if(bsTicket > 0)
   {
      // Modify only if range has moved enough to warrant it
      double existingPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(existingPrice - buyEntry) > g_entryBuffer * 0.5)
      {
         if(buyEntry > ask + minDist)
            Trade.OrderModify(bsTicket, buyEntry, buySL, buyTP,
                              ORDER_TIME_GTC, 0);
      }
   }
   else
   {
      // Place fresh buy stop
      if(buyEntry > ask + minDist)
      {
         if(!Trade.BuyStop(LotSize, buyEntry, _Symbol, buySL, buyTP,
                           ORDER_TIME_GTC, 0, "TUYUL_BUY"))
            PrintFormat("BuyStop FAILED | %.2f SL:%.2f TP:%.2f | %s",
                        buyEntry, buySL, buyTP, Trade.ResultRetcodeDescription());
         else
            PrintFormat("BuyStop PLACED  | Entry:%.2f SL:%.2f TP:%.2f",
                        buyEntry, buySL, buyTP);
      }
      else
         g_blockReason = StringFormat("BUY too close to price (%.2f)", buyEntry);
   }

   // ── SELL STOP: modify if exists, place if not ─────────────────
   ulong ssTicket = GetPendingTicket(ORDER_TYPE_SELL_STOP);
   if(ssTicket > 0)
   {
      double existingPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(existingPrice - sellEntry) > g_entryBuffer * 0.5)
      {
         if(sellEntry < bid - minDist)
            Trade.OrderModify(ssTicket, sellEntry, sellSL, sellTP,
                              ORDER_TIME_GTC, 0);
      }
   }
   else
   {
      if(sellEntry < bid - minDist)
      {
         if(!Trade.SellStop(LotSize, sellEntry, _Symbol, sellSL, sellTP,
                            ORDER_TIME_GTC, 0, "TUYUL_SELL"))
            PrintFormat("SellStop FAILED | %.2f SL:%.2f TP:%.2f | %s",
                        sellEntry, sellSL, sellTP, Trade.ResultRetcodeDescription());
         else
            PrintFormat("SellStop PLACED  | Entry:%.2f SL:%.2f TP:%.2f",
                        sellEntry, sellSL, sellTP);
      }
      else
         g_blockReason = StringFormat("SELL too close to price (%.2f)", sellEntry);
   }
}

//+------------------------------------------------------------------+
//  OCO
//+------------------------------------------------------------------+
void ManageOCO()
{
   if(HasPositionOfType(POSITION_TYPE_BUY)  && HasPendingOfType(ORDER_TYPE_SELL_STOP))
      DeletePendingOfType(ORDER_TYPE_SELL_STOP);
   if(HasPositionOfType(POSITION_TYPE_SELL) && HasPendingOfType(ORDER_TYPE_BUY_STOP))
      DeletePendingOfType(ORDER_TYPE_BUY_STOP);
}

//+------------------------------------------------------------------+
//  TRAILING STOP + BREAKEVEN
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByIndex(i))                                continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)           continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE pt =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double price = (pt == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitDist = (pt == POSITION_TYPE_BUY)
                          ? price - openPrice
                          : openPrice - price;

      double newSL = curSL;

      if(UseBreakeven && profitDist >= g_beActivate)
      {
         if(pt == POSITION_TYPE_BUY)
         { double b = NormalizeDouble(openPrice + g_beOffset, _Digits);
           if(b > newSL) newSL = b; }
         else
         { double b = NormalizeDouble(openPrice - g_beOffset, _Digits);
           if(newSL <= 0.0 || b < newSL) newSL = b; }
      }

      if(UseTrailing && profitDist >= g_trailStart)
      {
         if(pt == POSITION_TYPE_BUY)
         { double t = NormalizeDouble(price - g_trailStep, _Digits);
           if(t > newSL) newSL = t; }
         else
         { double t = NormalizeDouble(price + g_trailStep, _Digits);
           if(newSL <= 0.0 || t < newSL) newSL = t; }
      }

      if(MathAbs(newSL - curSL) > _Point)
         if(PositionSelectByTicket(ticket))
            Trade.PositionModify(ticket, newSL, curTP);
   }
}

//+------------------------------------------------------------------+
//  NEWS FILTER
//+------------------------------------------------------------------+
void RefreshNewsFilter()
{
   g_newsLastCheck = TimeCurrent();
   g_newsBlocked   = false;
   g_newsEventName = "";
   g_newsEventTime = 0;

   datetime from = TimeCurrent() - NewsMinutesBefore * 60;
   datetime to   = TimeCurrent() + NewsMinutesAfter  * 60;

   MqlCalendarValue vals[];
   int cnt = CalendarValueHistory(vals, from, to, "US");
   if(cnt <= 0) cnt = CalendarValueHistory(vals, from, to, NULL, "USD");
   if(cnt <= 0) goto LOOKAHEAD;

   for(int i = 0; i < cnt; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      bool hi  = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
      bool mod = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(!hi && !(NewsFilterModerate && mod)) continue;
      g_newsBlocked   = true;
      g_newsEventName = ev.name;
      g_newsEventTime = vals[i].time;
      return;
   }

   LOOKAHEAD:
   MqlCalendarValue nv[];
   int nc = CalendarValueHistory(nv, TimeCurrent(),
                                 TimeCurrent() + 4*3600, "US");
   if(nc <= 0) CalendarValueHistory(nv, TimeCurrent(),
                                    TimeCurrent() + 4*3600, NULL, "USD");
   datetime best = 0; string bestN = "";
   for(int i = 0; i < nc; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(nv[i].event_id, ev)) continue;
      bool hi  = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
      bool mod = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(!hi && !(NewsFilterModerate && mod)) continue;
      if(best == 0 || nv[i].time < best) { best = nv[i].time; bestN = ev.name; }
   }
   g_newsEventTime = best;
   g_newsEventName = bestN;
}

//+------------------------------------------------------------------+
//  ██████████  DASHBOARD  ██████████
//+------------------------------------------------------------------+
void CreateDashboard()
{
   string bg = DASH_PFX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,      DashCorner);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   DashX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   DashY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       DASH_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       DASH_H);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     C'15,15,28');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR,C'50,100,220');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
   ChartRedraw(0);
}

void DashRow(string id, string txt, int row, color clr, int sz=8)
{
   string nm = DASH_PFX + id;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     DashCorner);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      ObjectSetString(0,  nm, OBJPROP_FONT,       "Courier New");
   }
   ObjectSetString(0,  nm, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, DashX + 8);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, DashY + 8 + row * ROW_H);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  sz);
}

void UpdateDashboard()
{
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq     = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPnL = eq - g_dayStartBalance;
   double spread = GetCurrentSpread();
   double atr    = GetATR();
   bool   sprOK  = (g_maxSpread <= 0.0) || (spread <= g_maxSpread);
   bool   atrOK  = !UseVolatilityFilter || (atr >= g_minATR);
   bool   sessOK = !UseSessionFilter    || IsSessionActive();

   // R00 Header
   DashRow("R00","◆ TUYUL PO  v2.4",0,C'80,160,255',9);
   DashRow("R01",StringFormat("%-12s [%s]",_Symbol,g_symbolLabel),1,C'150,150,150');
   DashRow("R02","────────────────────────────",2,C'40,40,70');

   // R03 Account
   DashRow("R03","ACCOUNT",3,C'180,180,80');
   DashRow("R04",StringFormat("Bal: $%-9.2f  Eq: $%.2f",bal,eq),4,clrWhite);
   DashRow("R05",StringFormat("Day P&L: %s$%.2f",dayPnL>=0?"+":"",dayPnL),
           5, dayPnL>=0 ? clrLimeGreen : clrTomato);
   DashRow("R06","────────────────────────────",6,C'40,40,70');

   // R07 Orders
   DashRow("R07","ORDERS",7,C'180,180,80');

   string bsStr="NONE", ssStr="NONE";
   color  bsClr=C'90,90,90', ssClr=C'90,90,90';
   for(int i=0;i<OrdersTotal();i++)
   {
      ulong t=OrderGetTicket(i);
      if(!t || !OrderSelect(t))                              continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)MagicNumber)  continue;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_STOP)
      { bsStr=StringFormat("%.2f",OrderGetDouble(ORDER_PRICE_OPEN)); bsClr=clrLimeGreen; }
      if(ot==ORDER_TYPE_SELL_STOP)
      { ssStr=StringFormat("%.2f",OrderGetDouble(ORDER_PRICE_OPEN)); ssClr=clrTomato; }
   }
   DashRow("R08",StringFormat("Buy  Stop: %-14s",bsStr),8, bsClr);
   DashRow("R09",StringFormat("Sell Stop: %-14s",ssStr),9, ssClr);

   string posStr="Flat", floatStr=""; color posClr=C'100,100,100', flClr=C'100,100,100';
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetSymbol(i)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)MagicNumber) continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      double pft=PositionGetDouble(POSITION_PROFIT);
      posStr  =StringFormat("%s  %.2f @ %.2f",
                             pt==POSITION_TYPE_BUY?"LONG":"SHORT",vol,op);
      floatStr=StringFormat("Float: %s$%.2f",pft>=0?"+":"",pft);
      posClr  =(pt==POSITION_TYPE_BUY)?clrDeepSkyBlue:clrOrangeRed;
      flClr   =(pft>=0)?clrLimeGreen:clrTomato;
      break;
   }
   DashRow("R10",StringFormat("Pos:  %-20s",posStr),10,posClr);
   DashRow("R11",StringFormat("%-28s",floatStr),    11,flClr);
   DashRow("R12","────────────────────────────",12,C'40,40,70');

   // R13 Filters
   DashRow("R13","FILTERS",13,C'180,180,80');
   DashRow("R14",StringFormat("Spread: %-5.0f pts  %s",
                               spread/_Point, sprOK?"OK":"BLOCKED"),
           14, sprOK?clrLimeGreen:clrTomato);
   DashRow("R15",StringFormat("ATR:    %-5.0f pts  %s",
                               atr/_Point, atrOK?"OK":"LOW"),
           15, atrOK?clrLimeGreen:clrGold);
   DashRow("R16",UseSessionFilter
                 ?StringFormat("Session: %s (%02d-%02dh)",
                                sessOK?"ACTIVE":"CLOSED",
                                SessionStartHour,SessionEndHour)
                 :"Session: 24/7 (no limit)",
           16, sessOK?clrLimeGreen:C'110,110,110');

   // R17 News
   string nTxt; color nClr;
   if(!UseNewsFilter)       { nTxt="News:   FILTER OFF"; nClr=C'110,110,110'; }
   else if(g_newsBlocked)   { nTxt="News: !! BLOCKED !!"; nClr=clrTomato; }
   else                     { nTxt="News:   CLEAR";       nClr=clrLimeGreen; }
   DashRow("R17",nTxt,17,nClr);

   // R18 Next event or block reason
   if(UseNewsFilter && g_newsEventTime>0 && !g_newsBlocked)
   {
      int ml=(int)((g_newsEventTime-TimeCurrent())/60);
      string nt=(ml<60)
         ?StringFormat("Next: %-10s  in %dm",g_newsEventName,ml)
         :StringFormat("Next: %-10s  in %dh%dm",g_newsEventName,ml/60,ml%60);
      DashRow("R18",nt,18,C'200,160,60');
   }
   else if(UseNewsFilter && g_newsBlocked)
      DashRow("R18",StringFormat("Event: %-18s",g_newsEventName),18,clrOrange);
   else
      DashRow("R18","",18,clrBlack);

   // R19 Block reason (NEW in v2.4 — shows WHY orders aren't placed)
   DashRow("R19","────────────────────────────",19,C'40,40,70');
   if(g_blockReason != "")
      DashRow("R20",StringFormat("BLOCKED: %s",g_blockReason),20,clrOrangeRed);
   else
      DashRow("R20","Status:  SCANNING...",20,C'80,200,80');

   ChartRedraw(0);
}

void DeleteDashboard()
{ ObjectsDeleteAll(0, DASH_PFX); ChartRedraw(0); }

//+------------------------------------------------------------------+
//  HELPERS
//+------------------------------------------------------------------+

// [BUG1 FIX] Correct MQL5 property: SYMBOL_FILLING_FLAGS
ENUM_ORDER_TYPE_FILLING GetFillMode()
{
   uint f = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_FLAGS);
   if(f & SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if(f & SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

// Returns ticket of existing pending order of given type, 0 if none
ulong GetPendingTicket(ENUM_ORDER_TYPE ot)
{
   for(int i=0;i<OrdersTotal();i++)
   {
      ulong t=OrderGetTicket(i);
      if(!t || !OrderSelect(t))                              continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)MagicNumber)  continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==ot)   return t;
   }
   return 0;
}

double GetHighest(int bars)
{
   double h=iHigh(_Symbol,PERIOD_CURRENT,1);
   for(int i=2;i<=bars;i++){double v=iHigh(_Symbol,PERIOD_CURRENT,i);if(v>h)h=v;}
   return h;
}
double GetLowest(int bars)
{
   double l=iLow(_Symbol,PERIOD_CURRENT,1);
   for(int i=2;i<=bars;i++){double v=iLow(_Symbol,PERIOD_CURRENT,i);if(v<l)l=v;}
   return l;
}
double GetATR()
{
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_atrHandle,0,1,1,buf)<1) return 0.0;
   return buf[0];
}
double GetCurrentSpread()
{ return SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID); }

bool IsSessionActive()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return(dt.hour>=SessionStartHour && dt.hour<SessionEndHour);
}
bool IsDailyLossBreached()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   return((g_dayStartBalance-eq)>=g_dayStartBalance*MaxDailyLossPct/100.0);
}

int CountAllOrders()
{
   int n=0;
   for(int i=0;i<OrdersTotal();i++)
   { ulong t=OrderGetTicket(i); if(!t||!OrderSelect(t)) continue;
     if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
     if(OrderGetInteger(ORDER_MAGIC)!=(long)MagicNumber) continue; n++; }
   for(int i=0;i<PositionsTotal();i++)
   { if(PositionGetSymbol(i)!=_Symbol) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=(long)MagicNumber) continue; n++; }
   return n;
}

bool HasPendingOfType(ENUM_ORDER_TYPE ot)
{ return GetPendingTicket(ot) > 0; }

bool HasPositionOfType(ENUM_POSITION_TYPE pt)
{
   for(int i=0;i<PositionsTotal();i++)
   { if(PositionGetSymbol(i)!=_Symbol) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=(long)MagicNumber) continue;
     if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==pt) return true; }
   return false;
}

void DeletePendingOfType(ENUM_ORDER_TYPE ot)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   { ulong t=OrderGetTicket(i); if(!t||!OrderSelect(t)) continue;
     if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
     if(OrderGetInteger(ORDER_MAGIC)!=(long)MagicNumber) continue;
     if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==ot) Trade.OrderDelete(t); }
}

void DeleteAllPending()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   { ulong t=OrderGetTicket(i); if(!t||!OrderSelect(t)) continue;
     if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
     if(OrderGetInteger(ORDER_MAGIC)!=(long)MagicNumber) continue;
     Trade.OrderDelete(t); }
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { if(PositionGetSymbol(i)!=_Symbol) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=(long)MagicNumber) continue;
     Trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET)); }
}

void ExpireOldPendings()
{
   datetime cutoff=iTime(_Symbol,PERIOD_CURRENT,PendingExpireBars);
   for(int i=OrdersTotal()-1;i>=0;i--)
   { ulong t=OrderGetTicket(i); if(!t||!OrderSelect(t)) continue;
     if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
     if(OrderGetInteger(ORDER_MAGIC)!=(long)MagicNumber) continue;
     if((datetime)OrderGetInteger(ORDER_TIME_SETUP)<cutoff) Trade.OrderDelete(t); }
}
//+------------------------------------------------------------------+
