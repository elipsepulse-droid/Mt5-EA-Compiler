//+------------------------------------------------------------------+
//|                     GoldSniper_Pro_v2.mq5                        |
//|       Aggressive XAUUSD M1/M5 Scalper — Full Secret Sauce v2    |
//|    + Live Dashboard | Profit Tracker | Account Info | DD Guard   |
//|    Compatible: Exness USCC Cents / USD Standard | MT5            |
//+------------------------------------------------------------------+
#property copyright   "GoldSniper Pro v2.0"
#property version     "2.00"
#property description "XAUUSD M1/M5 Scalper with Live Dashboard"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade        Trade;
CPositionInfo PosInfo;
CAccountInfo  AccInfo;

//+------------------------------------------------------------------+
//|                        INPUT PARAMETERS                          |
//+------------------------------------------------------------------+

input group "━━━━━━ RISK MANAGEMENT ━━━━━━"
input double   InpRiskPct        = 1.5;      // Risk % Per Trade
input double   InpMaxDailyDD     = 5.0;      // Max Daily Drawdown % (halt)
input double   InpMaxTotalDD     = 15.0;     // Max Total Drawdown % (halt)
input int      InpMaxTrades      = 2;        // Max Simultaneous Trades

input group "━━━━━━ ATR ENGINE ━━━━━━"
input int      InpATRPeriod      = 14;       // ATR Period
input double   InpSL_ATR         = 1.5;      // Stop Loss ATR Multiplier
input double   InpTP1_ATR        = 1.5;      // TP1 ATR Multiplier (partial 50%)
input double   InpTP2_ATR        = 3.0;      // TP2 ATR Multiplier (full close)

input group "━━━━━━ INDICATORS ━━━━━━"
input int      InpFastEMA        = 9;        // Fast EMA Period
input int      InpSlowEMA        = 21;       // Slow EMA Period
input int      InpTrendEMA       = 50;       // Trend EMA Period (HTF)
input int      InpRSIPeriod      = 7;        // RSI Period (aggressive=7)
input double   InpRSI_OB         = 72.0;     // RSI Overbought Level
input double   InpRSI_OS         = 28.0;     // RSI Oversold Level
input int      InpADXPeriod      = 14;       // ADX Period
input double   InpADXMin         = 20.0;     // Min ADX (trend filter gate)

input group "━━━━━━ SCORING ENGINE ━━━━━━"
input int      InpMinScore       = 6;        // Min Confluence Score to Fire (max=8)
input bool     InpRoundNumber    = true;     // Psychological Level Bonus (+1)

input group "━━━━━━ MTF FILTER ━━━━━━"
input bool     InpUseMTF         = true;     // Enable Multi-Timeframe Filter
input ENUM_TIMEFRAMES InpHTF     = PERIOD_H1;// Higher Timeframe Bias

input group "━━━━━━ SESSION FILTER ━━━━━━"
input bool     InpUseSession     = false;    // Session Filter (false = trade 24/5)
input int      InpLonStart       = 7;        // London Start Hour (GMT)
input int      InpLonEnd         = 12;       // London End Hour (GMT)
input int      InpNYStart        = 13;       // NY Start Hour (GMT)
input int      InpNYEnd          = 21;       // NY End Hour (GMT)

input group "━━━━━━ TRADE MANAGEMENT ━━━━━━"
input bool     InpPartialClose   = true;     // Partial Close 50% at TP1
input bool     InpBreakEven      = true;     // Move SL to Breakeven after TP1
input bool     InpTrailing       = true;     // Enable Trailing Stop
input double   InpTrailATR       = 1.0;      // Trailing Stop ATR Multiplier
input double   InpSpreadMax      = 30.0;     // Max Spread in Points (skip if wider)

input group "━━━━━━ EA SETTINGS ━━━━━━"
input int      InpMagic          = 20250318; // Magic Number
input int      InpSlippage       = 30;       // Max Slippage (points)
input bool     InpDebug          = false;    // Enable Debug Logs in Journal

input group "━━━━━━ DASHBOARD ━━━━━━"
input bool     InpShowDash       = true;     // Show Dashboard
input int      InpDashX          = 18;       // Dashboard X Position (from left)
input int      InpDashY          = 20;       // Dashboard Y Position (from top)
input color    InpColorBg        = C'13,17,28';      // Background Color
input color    InpColorHeader    = C'0,168,255';     // Header Accent Color
input color    InpColorProfit    = C'0,230,118';     // Profit Color (green)
input color    InpColorLoss      = C'255,82,82';     // Loss Color (red)
input color    InpColorLabel     = C'148,163,184';   // Label Text Color
input color    InpColorValue     = C'226,232,240';   // Value Text Color
input color    InpColorDivider   = C'30,41,59';      // Divider Color
input color    InpColorBadgeUSD  = C'0,168,255';     // USD Badge Color
input color    InpColorBadgeCent = C'255,170,0';     // Cent Badge Color

//+------------------------------------------------------------------+
//|                       GLOBAL VARIABLES                           |
//+------------------------------------------------------------------+
double   g_DayStartBalance;
double   g_WeekStartBalance;
double   g_PeakBalance;
datetime g_DayStart;
datetime g_WeekStart;
bool     g_TradingHalted;
string   g_Symbol;
double   g_Point;
int      g_Digits;
double   g_MinLot, g_MaxLot, g_LotStep;
int      g_LastBuyScore;
int      g_LastSellScore;
string   g_LastSignal;
int      g_TotalTradesDay;
double   g_TotalProfitDay;
bool     g_IsCent;
string   g_AccType;

// Indicator handles
int h_FastEMA, h_SlowEMA, h_ATR, h_RSI, h_ADX;
int h_HTF_FastEMA, h_HTF_SlowEMA, h_HTF_TrendEMA;

// Trade tracking
struct TradeRecord {
   ulong  ticket;
   bool   tp1Hit;
   double initLots;
};
TradeRecord g_TradeLog[];

//+------------------------------------------------------------------+
//|             DASHBOARD OBJECT NAME HELPERS                        |
//+------------------------------------------------------------------+
#define DASH_PREFIX  "GS_"
#define FONT_MAIN    "Segoe UI"
#define FONT_BOLD    "Segoe UI Semibold"
#define DASH_W       290
#define DASH_H       410

// All dashboard label keys
string OBJ(string n) { return DASH_PREFIX + n; }

//+------------------------------------------------------------------+
//|                           OnInit                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Symbol   = Symbol();
   g_Point    = SymbolInfoDouble(g_Symbol, SYMBOL_POINT);
   g_Digits   = (int)SymbolInfoInteger(g_Symbol, SYMBOL_DIGITS);
   g_MinLot   = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MIN);
   g_MaxLot   = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_MAX);
   g_LotStep  = SymbolInfoDouble(g_Symbol, SYMBOL_VOLUME_STEP);

   if(Period() != PERIOD_M1 && Period() != PERIOD_M5)
   {
      Alert("GoldSniper: Attach to M1 or M5 only!");
      return INIT_FAILED;
   }

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   // Balance tracking
   double bal           = AccInfo.Balance();
   g_DayStartBalance    = bal;
   g_WeekStartBalance   = bal;
   g_PeakBalance        = bal;
   g_DayStart           = iTime(g_Symbol, PERIOD_D1, 0);
   g_WeekStart          = iTime(g_Symbol, PERIOD_W1, 0);
   g_TradingHalted      = false;
   g_LastBuyScore       = 0;
   g_LastSellScore      = 0;
   g_LastSignal         = "Waiting...";
   g_TotalTradesDay     = 0;
   g_TotalProfitDay     = 0.0;

   string cur  = AccInfo.Currency();
   g_IsCent    = (cur == "USC" || cur == "USCC" || cur == "cent");
   g_AccType   = g_IsCent ? "CENT (" + cur + ")" : "STANDARD (" + cur + ")";

   // Indicator handles
   h_FastEMA      = iMA(g_Symbol, PERIOD_CURRENT, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   h_SlowEMA      = iMA(g_Symbol, PERIOD_CURRENT, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   h_ATR          = iATR(g_Symbol, PERIOD_CURRENT, InpATRPeriod);
   h_RSI          = iRSI(g_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   h_ADX          = iADX(g_Symbol, PERIOD_CURRENT, InpADXPeriod);
   h_HTF_FastEMA  = iMA(g_Symbol, InpHTF, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   h_HTF_SlowEMA  = iMA(g_Symbol, InpHTF, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   h_HTF_TrendEMA = iMA(g_Symbol, InpHTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(h_FastEMA==INVALID_HANDLE || h_SlowEMA==INVALID_HANDLE || h_ATR==INVALID_HANDLE ||
      h_RSI==INVALID_HANDLE || h_ADX==INVALID_HANDLE ||
      h_HTF_FastEMA==INVALID_HANDLE || h_HTF_SlowEMA==INVALID_HANDLE || h_HTF_TrendEMA==INVALID_HANDLE)
   {
      Alert("GoldSniper: Indicator handle error.");
      return INIT_FAILED;
   }

   if(InpShowDash) BuildDashboard();

   if(InpDebug)
      PrintFormat("[GoldSniper v2 INIT] %s | %s | Bal:%.2f | MinLot:%.3f",
                  g_Symbol, g_AccType, bal, g_MinLot);

   EventSetMillisecondTimer(1000);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|                           OnDeinit                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   IndicatorRelease(h_FastEMA);  IndicatorRelease(h_SlowEMA);
   IndicatorRelease(h_ATR);      IndicatorRelease(h_RSI);
   IndicatorRelease(h_ADX);
   IndicatorRelease(h_HTF_FastEMA); IndicatorRelease(h_HTF_SlowEMA);
   IndicatorRelease(h_HTF_TrendEMA);
   ArrayFree(g_TradeLog);
}

//+------------------------------------------------------------------+
//|                         OnTimer (1s)                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpShowDash) UpdateDashboard();
}

//+------------------------------------------------------------------+
//|                           OnTick                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   // ── DAILY / WEEKLY RESET ─────────────────────────────────────────
   datetime nowDay  = iTime(g_Symbol, PERIOD_D1, 0);
   datetime nowWeek = iTime(g_Symbol, PERIOD_W1, 0);
   if(nowDay != g_DayStart)
   {
      g_DayStart        = nowDay;
      g_DayStartBalance = AccInfo.Balance();
      g_TradingHalted   = false;
      g_TotalTradesDay  = 0;
      g_TotalProfitDay  = 0.0;
   }
   if(nowWeek != g_WeekStart)
   {
      g_WeekStart      = nowWeek;
      g_WeekStartBalance = AccInfo.Balance();
   }

   if(g_TradingHalted) { if(InpShowDash) UpdateDashboard(); return; }
   if(CheckDrawdownBreaker()) { if(InpShowDash) UpdateDashboard(); return; }

   ManageTrades();

   // ── NEW BAR GATE ─────────────────────────────────────────────────
   static datetime s_LastBar = 0;
   datetime curBar = iTime(g_Symbol, PERIOD_CURRENT, 0);
   if(curBar == s_LastBar) return;
   s_LastBar = curBar;

   // ── SPREAD CHECK ─────────────────────────────────────────────────
   double bid    = SymbolInfoDouble(g_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(g_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / g_Point;
   if(spread > InpSpreadMax) return;

   if(CountMyTrades() >= InpMaxTrades) return;
   if(InpUseSession && !IsInSession()) return;

   // ── INDICATORS ───────────────────────────────────────────────────
   double atr      = GetBuf(h_ATR,     1);
   double fast1    = GetBuf(h_FastEMA, 1);
   double slow1    = GetBuf(h_SlowEMA, 1);
   double fast2    = GetBuf(h_FastEMA, 2);
   double slow2    = GetBuf(h_SlowEMA, 2);
   double rsi      = GetBuf(h_RSI,     1);
   double adxMain  = GetBuf(h_ADX,     1, 0);
   double adxPlus  = GetBuf(h_ADX,     1, 1);
   double adxMinus = GetBuf(h_ADX,     1, 2);
   double htfFast  = GetBuf(h_HTF_FastEMA,  1);
   double htfSlow  = GetBuf(h_HTF_SlowEMA,  1);
   double htfTrend = GetBuf(h_HTF_TrendEMA, 1);
   if(atr <= 0 || fast1 <= 0 || rsi <= 0) return;

   // ── CONFLUENCE SCORING ───────────────────────────────────────────
   int bS = 0, sS = 0;

   bool emaBull  = (fast1 > slow1);
   bool emaBear  = (fast1 < slow1);
   bool bullCross = (fast1 > slow1 && fast2 <= slow2);
   bool bearCross = (fast1 < slow1 && fast2 >= slow2);

   if(emaBull) bS += 2; else sS += 2;

   if(InpUseMTF)
   {
      if(htfFast > htfSlow && bid > htfTrend) bS += 2;
      else if(htfFast < htfSlow && bid < htfTrend) sS += 2;
   }
   else { if(bid > slow1) bS += 2; else sS += 2; }

   if(rsi > 50.0 && rsi < InpRSI_OB) bS += 2;
   if(rsi < 50.0 && rsi > InpRSI_OS) sS += 2;

   if(adxMain >= InpADXMin && adxPlus  > adxMinus) bS += 1;
   if(adxMain >= InpADXMin && adxMinus > adxPlus)  sS += 1;

   if(InpRoundNumber && IsNearRoundLevel(bid, atr))
   { if(emaBull) bS += 1; if(emaBear) sS += 1; }

   g_LastBuyScore  = bS;
   g_LastSellScore = sS;

   bool doLong  = (bS >= InpMinScore && emaBull);
   bool doShort = (sS >= InpMinScore && emaBear);
   if(bullCross && bS >= InpMinScore - 1) doLong  = true;
   if(bearCross && sS >= InpMinScore - 1) doShort = true;
   if(doLong && doShort) { doLong = (bS > sS); doShort = (sS > bS); }

   if(doLong  && !HasOpenTrade(ORDER_TYPE_BUY))
   { g_LastSignal = "BUY  Score:" + IntegerToString(bS); OpenTrade(ORDER_TYPE_BUY, atr); }
   else if(doShort && !HasOpenTrade(ORDER_TYPE_SELL))
   { g_LastSignal = "SELL Score:" + IntegerToString(sS); OpenTrade(ORDER_TYPE_SELL, atr); }
   else
      g_LastSignal = "Scanning... B:" + IntegerToString(bS) + " S:" + IntegerToString(sS);

   if(InpShowDash) UpdateDashboard();
}

//+------------------------------------------------------------------+
//|  OpenTrade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double atr)
{
   double bid    = SymbolInfoDouble(g_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(g_Symbol, SYMBOL_ASK);
   double spread = ask - bid;
   double slDist = atr * InpSL_ATR + spread * 1.5;
   double tp2D   = atr * InpTP2_ATR;

   double entry, sl, tp;
   if(type == ORDER_TYPE_BUY)
   { entry=ask; sl=NormalizeDouble(entry-slDist,g_Digits); tp=NormalizeDouble(entry+tp2D,g_Digits); }
   else
   { entry=bid; sl=NormalizeDouble(entry+slDist,g_Digits); tp=NormalizeDouble(entry-tp2D,g_Digits); }

   long   sLvlPts = SymbolInfoInteger(g_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = sLvlPts * g_Point + spread;
   if(minStop <= 0) minStop = 10 * g_Point;

   if(type == ORDER_TYPE_BUY)
   {
      if(entry - sl < minStop) sl = NormalizeDouble(entry - minStop * 1.2, g_Digits);
      if(tp - entry < minStop) tp = NormalizeDouble(entry + minStop * 2.0, g_Digits);
   }
   else
   {
      if(sl - entry < minStop) sl = NormalizeDouble(entry + minStop * 1.2, g_Digits);
      if(entry - tp < minStop) tp = NormalizeDouble(entry - minStop * 2.0, g_Digits);
   }

   double lots = CalcLots(MathAbs(entry - sl));
   if(lots < g_MinLot) return;

   bool sent = (type == ORDER_TYPE_BUY)
               ? Trade.Buy(lots, g_Symbol, 0, sl, tp, "GoldSniper BUY")
               : Trade.Sell(lots, g_Symbol, 0, sl, tp, "GoldSniper SELL");

   if(sent)
   {
      ulong ticket = Trade.ResultOrder();
      if(ticket > 0)
      {
         int idx = ArraySize(g_TradeLog);
         ArrayResize(g_TradeLog, idx + 1);
         g_TradeLog[idx].ticket   = ticket;
         g_TradeLog[idx].tp1Hit   = false;
         g_TradeLog[idx].initLots = lots;
         g_TotalTradesDay++;
         if(InpDebug)
            PrintFormat("[GS] %s | T:%d | Lots:%.2f | E:%.2f | SL:%.2f | TP:%.2f",
                        EnumToString(type), ticket, lots, entry, sl, tp);
      }
   }
}

//+------------------------------------------------------------------+
//|  ManageTrades — partial close, breakeven, trailing               |
//+------------------------------------------------------------------+
void ManageTrades()
{
   double atr = GetBuf(h_ATR, 1);
   if(atr <= 0) return;

   int sz = ArraySize(g_TradeLog);
   for(int i = 0; i < sz; i++)
   {
      ulong ticket = g_TradeLog[i].ticket;
      if(!PositionSelectByTicket(ticket)) continue;

      double openPx  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);
      double lots    = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double bid     = SymbolInfoDouble(g_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(g_Symbol, SYMBOL_ASK);
      double tp1Lvl  = (pt == POSITION_TYPE_BUY)
                       ? openPx + atr * InpTP1_ATR
                       : openPx - atr * InpTP1_ATR;

      if(InpPartialClose && !g_TradeLog[i].tp1Hit)
      {
         bool hitTP1 = (pt==POSITION_TYPE_BUY && bid>=tp1Lvl) ||
                       (pt==POSITION_TYPE_SELL && ask<=tp1Lvl);
         if(hitTP1)
         {
            double half = NormalizeDouble(lots * 0.5, 2);
            half = MathMax(half, g_MinLot);
            if(half < lots && Trade.PositionClosePartial(ticket, half))
            {
               g_TradeLog[i].tp1Hit = true;
               if(InpBreakEven)
               {
                  double sp = ask - bid;
                  double be = (pt==POSITION_TYPE_BUY)
                              ? NormalizeDouble(openPx + sp, g_Digits)
                              : NormalizeDouble(openPx - sp, g_Digits);
                  bool ok = (pt==POSITION_TYPE_BUY && be>curSL) ||
                            (pt==POSITION_TYPE_SELL && be<curSL);
                  if(ok) Trade.PositionModify(ticket, be, curTP);
               }
            }
         }
      }

      if(InpTrailing && g_TradeLog[i].tp1Hit)
      {
         double td = atr * InpTrailATR;
         if(pt == POSITION_TYPE_BUY)
         { double ns = NormalizeDouble(bid - td, g_Digits);
           if(ns > curSL + g_Point * 10) Trade.PositionModify(ticket, ns, curTP); }
         else
         { double ns = NormalizeDouble(ask + td, g_Digits);
           if(ns < curSL - g_Point * 10) Trade.PositionModify(ticket, ns, curTP); }
      }
   }
   PurgeClosedTrades();
}

//+------------------------------------------------------------------+
//|  CalcLots                                                         |
//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   if(slDist <= 0) return g_MinLot;
   double bal      = AccInfo.Balance();
   double riskAmt  = bal * (InpRiskPct / 100.0);
   double tickVal  = SymbolInfoDouble(g_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(g_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return g_MinLot;
   double lots = riskAmt / (slDist / tickSize * tickVal);
   lots = MathFloor(lots / g_LotStep) * g_LotStep;
   return NormalizeDouble(MathMax(MathMin(lots, g_MaxLot), g_MinLot), 2);
}

//+------------------------------------------------------------------+
//|  CheckDrawdownBreaker                                             |
//+------------------------------------------------------------------+
bool CheckDrawdownBreaker()
{
   double bal    = AccInfo.Balance();
   double equity = AccInfo.Equity();
   if(bal > g_PeakBalance) g_PeakBalance = bal;
   double ddd = (g_DayStartBalance > 0) ? (g_DayStartBalance - equity) / g_DayStartBalance * 100.0 : 0.0;
   double tdd = (g_PeakBalance > 0)     ? (g_PeakBalance     - equity) / g_PeakBalance     * 100.0 : 0.0;
   if(ddd >= InpMaxDailyDD || tdd >= InpMaxTotalDD)
   {
      if(!g_TradingHalted)
      {
         g_TradingHalted = true;
         g_LastSignal    = "⛔ HALTED — DD Limit";
         Alert(StringFormat("[GoldSniper] HALTED | DailyDD:%.2f%% | TotalDD:%.2f%%", ddd, tdd));
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|  Helpers                                                          |
//+------------------------------------------------------------------+
bool IsInSession()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt); int h = dt.hour;
   return ((h >= InpLonStart && h < InpLonEnd) || (h >= InpNYStart && h < InpNYEnd));
}
bool IsNearRoundLevel(double price, double atr)
{
   return (MathAbs(price - MathRound(price/5.0)*5.0) <= atr*0.5 ||
           MathAbs(price - MathRound(price/10.0)*10.0) <= atr*0.5);
}
double GetBuf(int handle, int shift, int buf = 0)
{
   double arr[]; ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buf, 0, shift+2, arr) > 0) return arr[shift];
   return 0.0;
}
int CountMyTrades()
{
   int c = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetSymbol(i)==g_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic) c++;
   return c;
}
bool HasOpenTrade(ENUM_ORDER_TYPE dir)
{
   ENUM_POSITION_TYPE pd = (dir==ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetSymbol(i)==g_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==pd) return true;
   return false;
}
void PurgeClosedTrades()
{
   int sz = ArraySize(g_TradeLog);
   for(int i = sz-1; i >= 0; i--)
      if(!PositionSelectByTicket(g_TradeLog[i].ticket))
      { for(int j=i; j<sz-1; j++) g_TradeLog[j]=g_TradeLog[j+1]; ArrayResize(g_TradeLog, --sz); }
}

//+------------------------------------------------------------------+
//|  Live floating P/L for EA's own trades                            |
//+------------------------------------------------------------------+
double GetFloatingPL()
{
   double pl = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetSymbol(i)==g_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic)
         pl += PositionGetDouble(POSITION_PROFIT);
   return pl;
}
int CountBuys()
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetSymbol(i)==g_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) c++;
   return c;
}
int CountSells()
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetSymbol(i)==g_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL) c++;
   return c;
}

//+------------------------------------------------------------------+
//|  DASHBOARD — low-level chart object utilities                     |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, int corner=0)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      corner);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
}

void CreateLabel(string name, int x, int y, string txt, color clr,
                 int fontSize=9, string font=FONT_MAIN, int corner=0)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetString(0,  name, OBJPROP_TEXT,        txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,    fontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,        font);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,      ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
}

void SetLabelText(string name, string txt, color clr)
{
   if(ObjectFind(0, name) >= 0)
   {
      ObjectSetString(0,  name, OBJPROP_TEXT,  txt);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }
}

void CreateDivider(string name, int x, int y, int w, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      1);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      0);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
}

//+------------------------------------------------------------------+
//|  BuildDashboard — create all static objects                       |
//+------------------------------------------------------------------+
void BuildDashboard()
{
   int X = InpDashX;
   int Y = InpDashY;
   int W = DASH_W;

   // ── MAIN BACKGROUND ─────────────────────────────────────────────
   CreateRect(OBJ("bg"),     X, Y,     W,   DASH_H, InpColorBg);
   CreateRect(OBJ("hdr_bg"), X, Y,     W,   52,     C'8,28,55');

   // ── HEADER ACCENT LINE ───────────────────────────────────────────
   CreateRect(OBJ("hdr_accent"), X, Y, 4, 52, InpColorHeader);

   // ── EA TITLE ─────────────────────────────────────────────────────
   CreateLabel(OBJ("title"),   X+14, Y+7,  "GoldSniper Pro",  InpColorHeader, 13, FONT_BOLD);
   CreateLabel(OBJ("ver"),     X+14, Y+28, "v2.0  |  XAUUSD Scalper", InpColorLabel, 8);

   // ── ACCOUNT BADGE (right side of header) ────────────────────────
   color badgeClr = g_IsCent ? InpColorBadgeCent : InpColorBadgeUSD;
   CreateRect(OBJ("badge_bg"), X+W-90, Y+10, 82, 20, badgeClr);
   CreateLabel(OBJ("badge_txt"), X+W-87, Y+14, g_IsCent ? "CENT ACCOUNT" : "USD ACCOUNT",
               C'10,10,10', 8, FONT_BOLD);

   // ── DIVIDER 1 ────────────────────────────────────────────────────
   CreateDivider(OBJ("div1"), X, Y+52, W, InpColorDivider);

   // ── ACCOUNT INFO SECTION ─────────────────────────────────────────
   int ay = Y+58;
   CreateLabel(OBJ("sec_acc"),    X+14, ay,    "◈  ACCOUNT INFO",  InpColorHeader, 8, FONT_BOLD);
   CreateLabel(OBJ("lbl_broker"), X+14, ay+16, "Broker",           InpColorLabel,  8);
   CreateLabel(OBJ("val_broker"), X+115,ay+16, "—",                InpColorValue,  8);
   CreateLabel(OBJ("lbl_accno"),  X+14, ay+30, "Account #",        InpColorLabel,  8);
   CreateLabel(OBJ("val_accno"),  X+115,ay+30, "—",                InpColorValue,  8);
   CreateLabel(OBJ("lbl_type"),   X+14, ay+44, "Type",             InpColorLabel,  8);
   CreateLabel(OBJ("val_type"),   X+115,ay+44, "—",                InpColorValue,  8);
   CreateLabel(OBJ("lbl_cur"),    X+14, ay+58, "Currency",         InpColorLabel,  8);
   CreateLabel(OBJ("val_cur"),    X+115,ay+58, "—",                InpColorValue,  8);
   CreateLabel(OBJ("lbl_lev"),    X+14, ay+72, "Leverage",         InpColorLabel,  8);
   CreateLabel(OBJ("val_lev"),    X+115,ay+72, "—",                InpColorValue,  8);

   // ── DIVIDER 2 ────────────────────────────────────────────────────
   int d2y = ay + 90;
   CreateDivider(OBJ("div2"), X, d2y, W, InpColorDivider);

   // ── PROFIT TRACKER ───────────────────────────────────────────────
   int py = d2y + 6;
   CreateLabel(OBJ("sec_profit"),   X+14, py,     "◈  PROFIT TRACKER", InpColorHeader, 8, FONT_BOLD);
   CreateLabel(OBJ("lbl_bal"),      X+14, py+16,  "Balance",           InpColorLabel,  8);
   CreateLabel(OBJ("val_bal"),      X+115,py+16,  "—",                 InpColorValue,  8);
   CreateLabel(OBJ("lbl_equity"),   X+14, py+30,  "Equity",            InpColorLabel,  8);
   CreateLabel(OBJ("val_equity"),   X+115,py+30,  "—",                 InpColorValue,  8);
   CreateLabel(OBJ("lbl_daily"),    X+14, py+46,  "Daily Profit",      InpColorLabel,  9);
   CreateLabel(OBJ("val_daily"),    X+115,py+46,  "+0.00% | +0.00",    InpColorProfit, 9, FONT_BOLD);
   CreateLabel(OBJ("lbl_weekly"),   X+14, py+62,  "Weekly Profit",     InpColorLabel,  9);
   CreateLabel(OBJ("val_weekly"),   X+115,py+62,  "+0.00% | +0.00",    InpColorProfit, 9, FONT_BOLD);
   CreateLabel(OBJ("lbl_float"),    X+14, py+78,  "Floating P/L",      InpColorLabel,  9);
   CreateLabel(OBJ("val_float"),    X+115,py+78,  "0.00",              InpColorValue,  9, FONT_BOLD);

   // ── DIVIDER 3 ────────────────────────────────────────────────────
   int d3y = py + 96;
   CreateDivider(OBJ("div3"), X, d3y, W, InpColorDivider);

   // ── LIVE TRADES ──────────────────────────────────────────────────
   int ty = d3y + 6;
   CreateLabel(OBJ("sec_trades"),   X+14, ty,     "◈  LIVE TRADES",    InpColorHeader, 8, FONT_BOLD);
   CreateLabel(OBJ("lbl_buys"),     X+14, ty+16,  "Buy Orders",        InpColorLabel,  9);
   CreateLabel(OBJ("val_buys"),     X+115,ty+16,  "0",                 InpColorValue,  9, FONT_BOLD);
   CreateLabel(OBJ("lbl_sells"),    X+14, ty+30,  "Sell Orders",       InpColorLabel,  9);
   CreateLabel(OBJ("val_sells"),    X+115,ty+30,  "0",                 InpColorValue,  9, FONT_BOLD);
   CreateLabel(OBJ("lbl_tradesD"),  X+14, ty+44,  "Trades Today",      InpColorLabel,  9);
   CreateLabel(OBJ("val_tradesD"),  X+115,ty+44,  "0",                 InpColorValue,  9);
   CreateLabel(OBJ("lbl_spread"),   X+14, ty+58,  "Spread (pts)",      InpColorLabel,  9);
   CreateLabel(OBJ("val_spread"),   X+115,ty+58,  "—",                 InpColorValue,  9);

   // ── DIVIDER 4 ────────────────────────────────────────────────────
   int d4y = ty + 76;
   CreateDivider(OBJ("div4"), X, d4y, W, InpColorDivider);

   // ── CURRENT SETTINGS ─────────────────────────────────────────────
   int sy = d4y + 6;
   CreateLabel(OBJ("sec_set"),      X+14, sy,    "◈  CURRENT SETTINGS", InpColorHeader, 8, FONT_BOLD);
   CreateLabel(OBJ("lbl_risk"),     X+14, sy+16, "Risk / Trade",        InpColorLabel,  8);
   CreateLabel(OBJ("val_risk"),     X+115,sy+16, DoubleToString(InpRiskPct,1)+"%", InpColorValue, 8);
   CreateLabel(OBJ("lbl_score"),    X+14, sy+28, "Min Score",           InpColorLabel,  8);
   CreateLabel(OBJ("val_score"),    X+115,sy+28, IntegerToString(InpMinScore)+"/8", InpColorValue, 8);
   CreateLabel(OBJ("lbl_rsi"),      X+14, sy+40, "RSI Levels",          InpColorLabel,  8);
   CreateLabel(OBJ("val_rsi"),      X+115,sy+40,
               DoubleToString(InpRSI_OS,0)+"/"+DoubleToString(InpRSI_OB,0), InpColorValue, 8);
   CreateLabel(OBJ("lbl_ddd"),      X+14, sy+52, "Max Daily DD",        InpColorLabel,  8);
   CreateLabel(OBJ("val_ddd"),      X+115,sy+52, DoubleToString(InpMaxDailyDD,1)+"%", InpColorValue, 8);
   CreateLabel(OBJ("lbl_tdd"),      X+14, sy+64, "Max Total DD",        InpColorLabel,  8);
   CreateLabel(OBJ("val_tdd"),      X+115,sy+64, DoubleToString(InpMaxTotalDD,1)+"%", InpColorValue, 8);
   CreateLabel(OBJ("lbl_tf"),       X+14, sy+76, "Timeframe",           InpColorLabel,  8);
   CreateLabel(OBJ("val_tf"),       X+115,sy+76, EnumToString((ENUM_TIMEFRAMES)Period()), InpColorValue, 8);
   CreateLabel(OBJ("lbl_mtf"),      X+14, sy+88, "MTF Bias",            InpColorLabel,  8);
   CreateLabel(OBJ("val_mtf"),      X+115,sy+88, InpUseMTF ? "ON  ("+EnumToString(InpHTF)+")" : "OFF",
               InpUseMTF ? InpColorProfit : InpColorLabel, 8);
   CreateLabel(OBJ("lbl_sess"),     X+14, sy+100,"Session Filter",      InpColorLabel,  8);
   CreateLabel(OBJ("val_sess"),     X+115,sy+100,InpUseSession ? "ON (London/NY)" : "OFF — 24/5",
               InpUseSession ? InpColorProfit : InpColorLabel, 8);

   // ── DIVIDER 5 ────────────────────────────────────────────────────
   int d5y = sy + 118;
   CreateDivider(OBJ("div5"), X, d5y, W, InpColorDivider);

   // ── SIGNAL + STATUS BAR ──────────────────────────────────────────
   int stY = d5y + 8;
   CreateLabel(OBJ("lbl_sig"),     X+14, stY,    "Last Signal",   InpColorLabel, 8);
   CreateLabel(OBJ("val_sig"),     X+14, stY+14, "Scanning...",   InpColorValue, 9, FONT_BOLD);
   CreateLabel(OBJ("lbl_status"),  X+14, stY+30, "EA Status",     InpColorLabel, 8);
   CreateRect(OBJ("status_bg"),    X+110,stY+27, 80, 17, InpColorProfit);
   CreateLabel(OBJ("val_status"),  X+114,stY+28, "  ACTIVE  ",   C'10,10,10', 8, FONT_BOLD);

   // ── FOOTER ───────────────────────────────────────────────────────
   CreateRect(OBJ("footer_bg"),  X, Y+DASH_H-22, W, 22, C'8,28,55');
   CreateLabel(OBJ("footer_txt"),X+14, Y+DASH_H-16,
               "GoldSniper Pro v2.0  |  Magic: "+IntegerToString(InpMagic), InpColorLabel, 7);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//|  UpdateDashboard — refresh all live values                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   if(!InpShowDash) return;

   double bal    = AccInfo.Balance();
   double equity = AccInfo.Equity();
   double fpl    = GetFloatingPL();
   double bid    = SymbolInfoDouble(g_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(g_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / g_Point;

   // Daily / Weekly profit
   double dayProfitUSD = bal - g_DayStartBalance + fpl;
   double dayProfitPct = (g_DayStartBalance > 0) ? dayProfitUSD / g_DayStartBalance * 100.0 : 0.0;
   double wkProfitUSD  = bal - g_WeekStartBalance + fpl;
   double wkProfitPct  = (g_WeekStartBalance > 0) ? wkProfitUSD / g_WeekStartBalance * 100.0 : 0.0;

   string cur = AccInfo.Currency();
   long   lev = AccInfo.Leverage();

   // ── Account info ──────────────────────────────────────────────────
   SetLabelText(OBJ("val_broker"), AccInfo.Company(),        InpColorValue);
   SetLabelText(OBJ("val_accno"),  IntegerToString(AccInfo.Login()), InpColorValue);
   SetLabelText(OBJ("val_type"),   g_AccType,                 g_IsCent ? InpColorBadgeCent : InpColorBadgeUSD);
   SetLabelText(OBJ("val_cur"),    cur,                       InpColorValue);
   SetLabelText(OBJ("val_lev"),    "1:" + IntegerToString(lev), InpColorValue);

   // ── Balance / Equity ─────────────────────────────────────────────
   SetLabelText(OBJ("val_bal"),    DoubleToString(bal,   2) + " " + cur, InpColorValue);
   SetLabelText(OBJ("val_equity"), DoubleToString(equity,2) + " " + cur,
                equity >= bal ? InpColorProfit : InpColorLoss);

   // ── Daily Profit ─────────────────────────────────────────────────
   string dayStr = StringFormat("%+.2f%% | %+.2f %s", dayProfitPct, dayProfitUSD, cur);
   SetLabelText(OBJ("val_daily"),  dayStr, dayProfitUSD >= 0 ? InpColorProfit : InpColorLoss);

   // ── Weekly Profit ────────────────────────────────────────────────
   string wkStr  = StringFormat("%+.2f%% | %+.2f %s", wkProfitPct,  wkProfitUSD,  cur);
   SetLabelText(OBJ("val_weekly"), wkStr,  wkProfitUSD  >= 0 ? InpColorProfit : InpColorLoss);

   // ── Floating P/L ─────────────────────────────────────────────────
   SetLabelText(OBJ("val_float"),  StringFormat("%+.2f %s", fpl, cur),
                fpl >= 0 ? InpColorProfit : InpColorLoss);

   // ── Live Trades ──────────────────────────────────────────────────
   int buys  = CountBuys();
   int sells = CountSells();
   SetLabelText(OBJ("val_buys"),    IntegerToString(buys),  buys  > 0 ? InpColorProfit : InpColorValue);
   SetLabelText(OBJ("val_sells"),   IntegerToString(sells), sells > 0 ? InpColorLoss   : InpColorValue);
   SetLabelText(OBJ("val_tradesD"), IntegerToString(g_TotalTradesDay), InpColorValue);
   SetLabelText(OBJ("val_spread"),  StringFormat("%.1f", spread),
                spread > InpSpreadMax * 0.7 ? InpColorLoss : InpColorValue);

   // ── Signal ───────────────────────────────────────────────────────
   SetLabelText(OBJ("val_sig"), g_LastSignal,
                StringFind(g_LastSignal, "BUY")  >= 0 ? InpColorProfit :
                StringFind(g_LastSignal, "SELL") >= 0 ? InpColorLoss   :
                StringFind(g_LastSignal, "HALT") >= 0 ? InpColorLoss   : InpColorValue);

   // ── Status badge ─────────────────────────────────────────────────
   if(g_TradingHalted)
   {
      ObjectSetInteger(0, OBJ("status_bg"), OBJPROP_BGCOLOR, InpColorLoss);
      SetLabelText(OBJ("val_status"), "  HALTED  ", C'10,10,10');
   }
   else
   {
      ObjectSetInteger(0, OBJ("status_bg"), OBJPROP_BGCOLOR, InpColorProfit);
      SetLabelText(OBJ("val_status"), "  ACTIVE  ", C'10,10,10');
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//|  DeleteDashboard — clean up all objects on deinit                |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   string names[] = {
      "bg","hdr_bg","hdr_accent","title","ver","badge_bg","badge_txt",
      "div1","sec_acc","lbl_broker","val_broker","lbl_accno","val_accno",
      "lbl_type","val_type","lbl_cur","val_cur","lbl_lev","val_lev",
      "div2","sec_profit","lbl_bal","val_bal","lbl_equity","val_equity",
      "lbl_daily","val_daily","lbl_weekly","val_weekly","lbl_float","val_float",
      "div3","sec_trades","lbl_buys","val_buys","lbl_sells","val_sells",
      "lbl_tradesD","val_tradesD","lbl_spread","val_spread",
      "div4","sec_set","lbl_risk","val_risk","lbl_score","val_score",
      "lbl_rsi","val_rsi","lbl_ddd","val_ddd","lbl_tdd","val_tdd",
      "lbl_tf","val_tf","lbl_mtf","val_mtf","lbl_sess","val_sess",
      "div5","lbl_sig","val_sig","lbl_status","status_bg","val_status",
      "footer_bg","footer_txt"
   };
   for(int i = 0; i < ArraySize(names); i++)
      ObjectDelete(0, OBJ(names[i]));
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
//|                         END OF FILE                              |
//+------------------------------------------------------------------+
