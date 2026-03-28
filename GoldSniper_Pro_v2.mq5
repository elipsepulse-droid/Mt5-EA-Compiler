//+------------------------------------------------------------------+
//|  Breakout Pending Order Scalper — GOLD & BTC Edition             |
//|  Strategy : Consolidation Range + Buy Stop / Sell Stop           |
//|  Symbols  : XAUUSD / XAUUSDm / BTCUSD / BTCUSDm (auto-detect)  |
//|  Version  : 2.3 (On-Chart Dashboard + MT5 News Filter)          |
//+------------------------------------------------------------------+
// NEW in v2.3:
//  [D1] On-chart dashboard: balance, equity, day P&L, pending/open
//       order status, spread, ATR, session, news — all live
//  [D2] Dashboard auto-cleans on EA remove
//  [N1] News filter using MT5 built-in Economic Calendar API
//  [N2] Blocks new orders X minutes before and after high-impact US events
//  [N3] Optional: also deletes pending orders when news window opens
//  [N4] Configurable: filter moderate news too
//  [N5] Dashboard shows next upcoming news event + countdown
//  All v2.1 and v2.2 fixes and features fully retained
//+------------------------------------------------------------------+

#property copyright "bs.autotrade / Multi-Symbol Edition"
#property version   "2.30"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        Trade;
COrderInfo    OrderInfo;
CPositionInfo PositionInfo;

//--- ═══════════════════════════════════════════════════════════════
//    CONSTANTS
//--- ═══════════════════════════════════════════════════════════════
#define DASH_PFX   "TPOV23_"   // prefix for all chart objects
#define DASH_W     240          // dashboard width  (pixels)
#define DASH_H     275          // dashboard height (pixels)
#define ROW_H      16           // row height       (pixels)

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
input ENUM_SYMBOL_TYPE SymbolMode          = SYM_AUTO; // Symbol preset

input group "═══ TRADE SETUP ═══"
input double LotSize                       = 0.01;     // Lot Size
input int    RangeBars                     = 5;        // Consolidation bars to scan
input int    EntryBufferPoints             = 50;       // Base entry buffer (auto-scaled)
input long   MagicNumber                   = 202502;   // EA Magic Number

input group "═══ STOP LOSS & TAKE PROFIT ═══"
input bool   UseATR_SL                     = true;     // Use ATR-based SL
input double ATR_SL_Multiplier             = 1.5;      // ATR × this = SL distance
input double ATR_TP_Multiplier             = 2.5;      // ATR × this = TP distance
input int    FixedSL_Points                = 300;      // Fixed SL points (ATR off)
input int    FixedTP_Points                = 500;      // Fixed TP points (ATR off)
input int    ATR_Period                    = 14;       // ATR period

input group "═══ TRAILING & BREAKEVEN ═══"
input bool   UseTrailing                   = true;     // Enable trailing stop
input int    TrailingStart_Points          = 200;      // Profit pts to start trailing
input int    TrailingStep_Points           = 100;      // Trailing step in pts
input bool   UseBreakeven                  = true;     // Enable breakeven
input int    BreakevenActivate             = 150;      // Profit pts to activate BE
input int    BreakevenOffset               = 10;       // BE SL offset above entry

input group "═══ FILTERS ═══"
input int    MaxSpreadPoints               = 80;       // Max spread pts (0=off, auto-scaled)
input bool   UseSessionFilter              = false;    // OFF = 24/7 trading
input int    SessionStartHour              = 7;        // Session start (broker time)
input int    SessionEndHour                = 20;       // Session end   (broker time)
input bool   UseCancelOpposite             = true;     // OCO: cancel other side on fill
input bool   UseVolatilityFilter           = true;     // Skip if ATR too low
input double MinATR_Points                 = 50.0;     // Min ATR pts (auto-scaled)

input group "═══ NEWS FILTER ═══"
input bool   UseNewsFilter                 = true;     // Enable news filter (US events)
input int    NewsMinutesBefore             = 30;       // Mins before news: block orders
input int    NewsMinutesAfter              = 30;       // Mins after  news: block orders
input bool   NewsDeletePending             = true;     // Delete pending orders on news
input bool   NewsFilterModerate            = false;    // Also block moderate-impact news

input group "═══ RISK MANAGEMENT ═══"
input double MaxDailyLossPct               = 3.0;      // Max daily loss % (0=off)
input int    MaxOpenOrders                 = 2;        // Max pending+open orders
input bool   CloseOnNewBar                 = false;    // Close trades on new bar
input int    PendingExpireBars             = 3;        // Pending auto-expire bars (0=off)

input group "═══ DASHBOARD ═══"
input bool   ShowDashboard                 = true;     // Show on-chart dashboard
input int    DashX                         = 10;       // Dashboard X offset (pixels)
input int    DashY                         = 30;       // Dashboard Y offset (pixels)
input ENUM_BASE_CORNER DashCorner          = CORNER_LEFT_UPPER; // Dashboard corner

//--- ═══════════════════════════════════════════════════════════════
//    GLOBALS — STRATEGY
//--- ═══════════════════════════════════════════════════════════════
datetime g_lastBarTime     = 0;
double   g_dayStartBalance = 0.0;
datetime g_today           = 0;
int      g_atrHandle       = INVALID_HANDLE;

// Scaled effective values (set once in ApplySymbolPreset)
double   g_entryBuffer     = 0.0;
double   g_fixedSL         = 0.0;
double   g_fixedTP         = 0.0;
double   g_trailStart      = 0.0;
double   g_trailStep       = 0.0;
double   g_beActivate      = 0.0;
double   g_beOffset        = 0.0;
double   g_maxSpread       = 0.0;
double   g_minATR          = 0.0;
string   g_symbolLabel     = "";

//--- ═══════════════════════════════════════════════════════════════
//    GLOBALS — NEWS FILTER
//--- ═══════════════════════════════════════════════════════════════
bool     g_newsBlocked     = false;
string   g_newsEventName   = "";
datetime g_newsEventTime   = 0;
datetime g_newsLastCheck   = 0;  // throttle: re-check every 60s

//--- ═══════════════════════════════════════════════════════════════
//    GLOBALS — DASHBOARD THROTTLE
//--- ═══════════════════════════════════════════════════════════════
datetime g_dashLastUpdate  = 0;

//+------------------------------------------------------------------+
//  INIT
//+------------------------------------------------------------------+
int OnInit()
{
   ENUM_ORDER_TYPE_FILLING fill = GetFillMode();
   Trade.SetTypeFilling(fill);
   Trade.SetExpertMagicNumber((ulong)MagicNumber);
   Trade.SetDeviationInPoints(20);

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Alert("TUYUL PO v2.3: ATR handle failed — EA will not run.");
      return(INIT_FAILED);
   }

   ApplySymbolPreset();

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_today           = iTime(_Symbol, PERIOD_D1, 0);

   if(ShowDashboard) CreateDashboard();

   PrintFormat("TUYUL PO v2.3 | %s [%s] | TF:%s | Fill:%s | News:%s",
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
   //--- Daily reset
   datetime todayD1 = iTime(_Symbol, PERIOD_D1, 0);
   if(todayD1 != g_today)
   {
      g_today           = todayD1;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   //--- Daily loss breaker
   if(MaxDailyLossPct > 0.0 && IsDailyLossBreached())
   {
      CloseAllPositions();
      DeleteAllPending();
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   //--- Trailing + Breakeven every tick
   ManageOpenPositions();

   //--- OCO every tick
   if(UseCancelOpposite)
      ManageOCO();

   //--- News filter refresh (max once per 60s)
   if(UseNewsFilter && (TimeCurrent() - g_newsLastCheck) >= 60)
      RefreshNewsFilter();

   //--- Dashboard update (max once per 2s to avoid overhead)
   if(ShowDashboard && (TimeCurrent() - g_dashLastUpdate) >= 2)
   {
      UpdateDashboard();
      g_dashLastUpdate = TimeCurrent();
   }

   //--- News blocked: delete pending if configured
   if(g_newsBlocked && NewsDeletePending)
      DeleteAllPending();

   //--- New bar detection
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   if(CloseOnNewBar)
      CloseAllPositions();

   if(PendingExpireBars > 0)
      ExpireOldPendings();

   //--- All pre-order filters
   if(UseSessionFilter && !IsSessionActive())   return;
   if(g_newsBlocked)                             return;
   if(g_maxSpread > 0.0 &&
      GetCurrentSpread() > g_maxSpread)          return;
   if(CountAllOrders() >= MaxOpenOrders)         return;

   double atr = GetATR();
   if(atr <= 0.0)                                return;
   if(UseVolatilityFilter && atr < g_minATR)     return;

   PlacePendingOrders(atr);
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
   if(res == SYM_GOLD)       { scale = 1.0;  g_symbolLabel = "GOLD"; }
   else if(res == SYM_BTC)   {
      double price  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      scale         = MathMax(10.0, MathMin(100.0, price / 3000.0));
      g_symbolLabel = "BTC";
   }
   else                      { scale = 1.0;  g_symbolLabel = "CUSTOM"; }

   g_entryBuffer = EntryBufferPoints    * _Point * scale;
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
//  [N1] NEWS FILTER — MT5 Built-in Economic Calendar
//+------------------------------------------------------------------+
void RefreshNewsFilter()
{
   g_newsLastCheck = TimeCurrent();
   g_newsBlocked   = false;
   g_newsEventName = "";
   g_newsEventTime = 0;

   datetime from = TimeCurrent() - NewsMinutesBefore * 60;
   datetime to   = TimeCurrent() + NewsMinutesAfter  * 60;

   MqlCalendarValue values[];
   // Query US calendar events
   int cnt = CalendarValueHistory(values, from, to, "US");

   if(cnt <= 0)
   {
      // Also try "USD" currency filter as fallback
      cnt = CalendarValueHistory(values, from, to, NULL, "USD");
   }

   if(cnt <= 0) return; // no events or calendar unavailable

   for(int i = 0; i < cnt; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;

      bool isHigh = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
      bool isMod  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);

      if(!isHigh && !(NewsFilterModerate && isMod)) continue;

      // This event falls within our block window
      g_newsBlocked   = true;
      g_newsEventName = ev.name;
      g_newsEventTime = values[i].time;
      return; // one high-impact event is enough to block
   }

   // No blocking event in window — also look ahead for NEXT event
   // (up to 4 hours ahead, for dashboard display only)
   datetime nextFrom = TimeCurrent();
   datetime nextTo   = TimeCurrent() + 4 * 3600;
   MqlCalendarValue nextVals[];
   int nc = CalendarValueHistory(nextVals, nextFrom, nextTo, "US");
   if(nc <= 0) nc = CalendarValueHistory(nextVals, nextFrom, nextTo, NULL, "USD");

   datetime bestTime = 0;
   string   bestName = "";
   for(int i = 0; i < nc; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(nextVals[i].event_id, ev)) continue;
      bool isHigh = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
      bool isMod  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(!isHigh && !(NewsFilterModerate && isMod)) continue;
      if(bestTime == 0 || nextVals[i].time < bestTime)
      {
         bestTime = nextVals[i].time;
         bestName = ev.name;
      }
   }
   g_newsEventTime = bestTime;
   g_newsEventName = bestName;
}

//+------------------------------------------------------------------+
//  CORE: Place Buy Stop + Sell Stop
//+------------------------------------------------------------------+
void PlacePendingOrders(double atr)
{
   double high = GetHighest(RangeBars);
   double low  = GetLowest(RangeBars);
   if(high <= 0.0 || low <= 0.0 || high <= low) return;

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

   if(buyEntry  < ask + minDist)           return;
   if(sellEntry > bid - minDist)           return;
   if(slDist < minDist || tpDist < minDist) return;

   if(!HasPendingOfType(ORDER_TYPE_BUY_STOP))
      if(!Trade.BuyStop(LotSize, buyEntry, _Symbol, buySL, buyTP,
                        ORDER_TIME_GTC, 0, "TUYUL_BUY"))
         Print("BuyStop FAILED: ", Trade.ResultRetcodeDescription());

   if(!HasPendingOfType(ORDER_TYPE_SELL_STOP))
      if(!Trade.SellStop(LotSize, sellEntry, _Symbol, sellSL, sellTP,
                         ORDER_TIME_GTC, 0, "TUYUL_SELL"))
         Print("SellStop FAILED: ", Trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//  OCO MANAGEMENT
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
      if(!PositionSelectByIndex(i))                               continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)          continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double price = (posType == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitDist = (posType == POSITION_TYPE_BUY)
                          ? price - openPrice
                          : openPrice - price;

      double newSL = currentSL;

      if(UseBreakeven && profitDist >= g_beActivate)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            double beSL = NormalizeDouble(openPrice + g_beOffset, _Digits);
            if(beSL > newSL) newSL = beSL;
         }
         else
         {
            double beSL = NormalizeDouble(openPrice - g_beOffset, _Digits);
            if(newSL <= 0.0 || beSL < newSL) newSL = beSL;
         }
      }

      if(UseTrailing && profitDist >= g_trailStart)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            double tSL = NormalizeDouble(price - g_trailStep, _Digits);
            if(tSL > newSL) newSL = tSL;
         }
         else
         {
            double tSL = NormalizeDouble(price + g_trailStep, _Digits);
            if(newSL <= 0.0 || tSL < newSL) newSL = tSL;
         }
      }

      if(MathAbs(newSL - currentSL) > _Point)
         if(PositionSelectByTicket(ticket))
            Trade.PositionModify(ticket, newSL, currentTP);
   }
}

//+------------------------------------------------------------------+
//  ██████████  DASHBOARD  ██████████
//+------------------------------------------------------------------+

// Create background rectangle (called once in OnInit)
void CreateDashboard()
{
   string bg = DASH_PFX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,      DashCorner);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   DashX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   DashY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       DASH_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       DASH_H);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     C'18,18,30');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR,C'60,100,200');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
   ChartRedraw(0);
}

// Create or update a text label in the dashboard
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

// Full dashboard refresh
void UpdateDashboard()
{
   double  bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double  eq      = AccountInfoDouble(ACCOUNT_EQUITY);
   double  dayPnL  = eq - g_dayStartBalance;
   double  spread  = GetCurrentSpread();
   double  atr     = GetATR();
   bool    sessOK  = !UseSessionFilter || IsSessionActive();
   bool    sprOK   = (g_maxSpread <= 0) || (spread <= g_maxSpread);
   bool    atrOK   = !UseVolatilityFilter || (atr >= g_minATR);

   // Row 0 — Header
   DashRow("R00", "◆ TUYUL PO  v2.3", 0, C'100,180,255', 9);

   // Row 1 — Symbol + mode
   DashRow("R01", StringFormat("%-12s [%s]", _Symbol, g_symbolLabel),
           1, C'160,160,160');

   // Row 2 — Separator
   DashRow("R02", "────────────────────────────", 2, C'50,50,80');

   // Row 3 — Account header
   DashRow("R03", "ACCOUNT", 3, C'180,180,100');

   // Row 4 — Balance / Equity
   DashRow("R04", StringFormat("Bal: $%-10.2f  Eq: $%.2f", bal, eq),
           4, clrWhite);

   // Row 5 — Day P&L
   color  pnlClr = (dayPnL >= 0) ? clrLimeGreen : clrTomato;
   string pnlStr = StringFormat("Day P&L:  %s$%.2f",
                                 dayPnL >= 0 ? "+" : "", dayPnL);
   DashRow("R05", pnlStr, 5, pnlClr);

   // Row 6 — Separator
   DashRow("R06", "────────────────────────────", 6, C'50,50,80');

   // Row 7 — Orders header
   DashRow("R07", "ORDERS", 7, C'180,180,100');

   // Row 8 — Buy Stop
   string bsPrice = "NONE";
   string ssPrice = "NONE";
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderSelect(t))                              continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)               continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber)     continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP)
         bsPrice = StringFormat("%.2f", OrderGetDouble(ORDER_PRICE_OPEN));
      if(ot == ORDER_TYPE_SELL_STOP)
         ssPrice = StringFormat("%.2f", OrderGetDouble(ORDER_PRICE_OPEN));
   }
   color bsClr = (bsPrice != "NONE") ? clrLimeGreen : C'100,100,100';
   color ssClr = (ssPrice != "NONE") ? clrTomato     : C'100,100,100';
   DashRow("R08", StringFormat("Buy  Stop: %-14s", bsPrice), 8,  bsClr);
   DashRow("R09", StringFormat("Sell Stop: %-14s", ssPrice), 9,  ssClr);

   // Row 10 — Open position
   string posStr   = "Flat";
   string floatStr = "";
   color  posClr   = C'120,120,120';
   color  flClr    = C'120,120,120';
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != _Symbol)                           continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)   continue;
      ENUM_POSITION_TYPE pt =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double pft  = PositionGetDouble(POSITION_PROFIT);
      posStr  = StringFormat("%s  %.2f @ %.2f",
                              pt == POSITION_TYPE_BUY ? "LONG" : "SHORT",
                              vol, open);
      floatStr= StringFormat("Float:  %s$%.2f",
                              pft >= 0 ? "+" : "", pft);
      posClr  = (pt == POSITION_TYPE_BUY) ? clrDeepSkyBlue : clrOrange;
      flClr   = (pft >= 0) ? clrLimeGreen : clrTomato;
      break; // show first position only
   }
   DashRow("R10", StringFormat("Pos:  %-20s", posStr), 10, posClr);
   DashRow("R11", StringFormat("%-28s", floatStr),     11, flClr);

   // Row 12 — Separator
   DashRow("R12", "────────────────────────────", 12, C'50,50,80');

   // Row 13 — Filters header
   DashRow("R13", "FILTERS", 13, C'180,180,100');

   // Row 14 — Spread
   string sprTxt = StringFormat("Spread: %-6.0f pts  %s",
                                  spread / _Point,
                                  sprOK ? "OK" : "HIGH");
   DashRow("R14", sprTxt, 14, sprOK ? clrLimeGreen : clrTomato);

   // Row 15 — ATR
   string atrTxt = StringFormat("ATR:    %-6.0f pts  %s",
                                  atr / _Point,
                                  atrOK ? "OK" : "LOW");
   DashRow("R15", atrTxt, 15, atrOK ? clrLimeGreen : clrGold);

   // Row 16 — Session
   string sessTxt = UseSessionFilter
                    ? StringFormat("Session: %s  (%02d-%02dh)",
                                   sessOK ? "ACTIVE" : "CLOSED",
                                   SessionStartHour, SessionEndHour)
                    : "Session: 24/7 (no limit)";
   DashRow("R16", sessTxt, 16, sessOK ? clrLimeGreen : C'120,120,120');

   // Row 17 — News
   string newsTxt;
   color  newsClr;
   if(!UseNewsFilter)
   {
      newsTxt = "News:   FILTER OFF";
      newsClr = C'120,120,120';
   }
   else if(g_newsBlocked)
   {
      newsTxt = StringFormat("News: !! BLOCKED !!");
      newsClr = clrTomato;
   }
   else
   {
      newsTxt = "News:   CLEAR";
      newsClr = clrLimeGreen;
   }
   DashRow("R17", newsTxt, 17, newsClr);

   // Row 18 — Next event
   if(UseNewsFilter && g_newsEventTime > 0 && !g_newsBlocked)
   {
      int minsLeft = (int)((g_newsEventTime - TimeCurrent()) / 60);
      string nextTxt;
      if(minsLeft < 0)
         nextTxt = StringFormat("Next: %-16s (passed)", g_newsEventName);
      else if(minsLeft < 60)
         nextTxt = StringFormat("Next: %-10s  in %dm", g_newsEventName, minsLeft);
      else
         nextTxt = StringFormat("Next: %-10s  in %dh%dm",
                                 g_newsEventName, minsLeft/60, minsLeft%60);
      DashRow("R18", nextTxt, 18, C'200,160,60');
   }
   else if(UseNewsFilter && g_newsBlocked)
   {
      DashRow("R18", StringFormat("Event: %-18s", g_newsEventName), 18, clrOrange);
   }
   else
   {
      DashRow("R18", "", 18, clrBlack);
   }

   ChartRedraw(0);
}

// Delete all dashboard objects
void DeleteDashboard()
{
   ObjectsDeleteAll(0, DASH_PFX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//  HELPERS
//+------------------------------------------------------------------+

ENUM_ORDER_TYPE_FILLING GetFillMode()
{
   uint f = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_FLAGS);
   if(f & SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if(f & SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

double GetHighest(int bars)
{
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= bars; i++)
   { double v = iHigh(_Symbol, PERIOD_CURRENT, i); if(v > h) h = v; }
   return h;
}

double GetLowest(int bars)
{
   double l = iLow(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= bars; i++)
   { double v = iLow(_Symbol, PERIOD_CURRENT, i); if(v < l) l = v; }
   return l;
}

double GetATR()
{
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1) return 0.0;
   return buf[0];
}

double GetCurrentSpread()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

bool IsSessionActive()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= SessionStartHour && dt.hour < SessionEndHour);
}

bool IsDailyLossBreached()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return((g_dayStartBalance - eq) >= g_dayStartBalance * MaxDailyLossPct / 100.0);
}

int CountAllOrders()
{
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(!t || !OrderSelect(t))                               continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber)  continue;
      n++;
   }
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != _Symbol)                         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      n++;
   }
   return n;
}

bool HasPendingOfType(ENUM_ORDER_TYPE ot)
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(!t || !OrderSelect(t))                               continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber)  continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == ot)  return true;
   }
   return false;
}

bool HasPositionOfType(ENUM_POSITION_TYPE pt)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != _Symbol)                         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pt) return true;
   }
   return false;
}

void DeletePendingOfType(ENUM_ORDER_TYPE ot)
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(!t || !OrderSelect(t))                               continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber)  continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == ot)
         Trade.OrderDelete(t);
   }
}

void DeleteAllPending()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(!t || !OrderSelect(t))                               continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber)  continue;
      Trade.OrderDelete(t);
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol)                         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      Trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET));
   }
}

void ExpireOldPendings()
{
   datetime cutoff = iTime(_Symbol, PERIOD_CURRENT, PendingExpireBars);
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(!t || !OrderSelect(t))                               continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)            continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber)  continue;
      if((datetime)OrderGetInteger(ORDER_TIME_SETUP) < cutoff)
         Trade.OrderDelete(t);
   }
}
//+------------------------------------------------------------------+
