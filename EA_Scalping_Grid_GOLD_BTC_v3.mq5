//+------------------------------------------------------------------+
//|         EA_Scalping_Grid_GOLD_BTC_v3.3.mq5                       |
//|     Universal Grid Scalping Robot - XAUUSD & BTCUSD M5           |
//|                                                                  |
//|  v3.3 NEW: Live Dashboard Panel on chart showing:                |
//|   - Daily Profit (% and USC/USD)                                 |
//|   - Weekly Profit (% and USC/USD)                                |
//|   - Account type (USC cent or USD standard)                      |
//|   - Current EA settings (grid, spacing, lot, RSI)               |
//|   - Active trades count and floating P/L                         |
//|   - Lot size fully editable from inputs                          |
//+------------------------------------------------------------------+
#property copyright   "EA SCALPING ROBOT / DANE - v3.3"
#property version     "3.30"
#property description "Grid EA with Live Dashboard — XAUUSD/BTCUSD Cent & Standard"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//==========================================================================
//  INPUTS
//==========================================================================

input group "====== SYMBOL MODE ======"
input bool InpAutoDetect = true;       // Auto-detect symbol & account type

input group "====== GRID SETUP ======"
input int    InpGridSize       = 4;    // Grid Size (orders per side)
input double InpSpacingPips    = 80;   // Spacing in Pips
input double InpLotSize        = 0.01; // *** EDITABLE LOT SIZE — increase as capital grows ***
input bool   InpMoveGrid       = true; // Move Grid

input group "====== TRADE MANAGEMENT ======"
input bool   InpTPPerTrade       = true;
input double InpTPMultiplier     = 1.0;
input bool   InpCloseAtMaxProfit = true;
input double InpMaxProfitMult    = 4.0;
input double InpGridSLMult       = 5.0;

input group "====== TRAILING STOP ======"
input bool   InpUseTrailing    = true;
input double InpTrailStartPips = 40;
input double InpTrailStepPips  = 20;

input group "====== DAILY LOSS PROTECTION ======"
input bool   InpUseDailyLoss   = true;
input double InpDailyLossAmt   = 500.0; // In YOUR account currency (USC or USD)

input group "====== ENTRY SIGNAL: RSI ======"
input int                InpRSI_Period  = 14;
input ENUM_APPLIED_PRICE InpRSI_Price   = PRICE_CLOSE;
input int                InpRSI_Shift   = 1;
input double             InpRSI_BuyLvl  = 35.0;
input double             InpRSI_SellLvl = 65.0;

input group "====== TREND FILTER: Two EMAs ======"
input int                InpTF_FastPeriod = 100;
input ENUM_MA_METHOD     InpTF_FastMethod = MODE_EMA;
input int                InpTF_SlowPeriod = 300;
input ENUM_MA_METHOD     InpTF_SlowMethod = MODE_EMA;
input ENUM_APPLIED_PRICE InpTF_Price      = PRICE_CLOSE;
input int                InpTF_Shift      = 1;

input group "====== EXIT SIGNAL: Two EMAs Crossing ======"
input int                InpExit_FastPeriod = 50;
input ENUM_MA_METHOD     InpExit_FastMethod = MODE_EMA;
input int                InpExit_SlowPeriod = 200;
input ENUM_MA_METHOD     InpExit_SlowMethod = MODE_EMA;
input ENUM_APPLIED_PRICE InpExit_Price      = PRICE_CLOSE;
input int                InpExit_Shift      = 1;

input group "====== DASHBOARD ======"
input bool   InpShowDashboard  = true;    // Show dashboard panel on chart
input int    InpDashX          = 10;      // Dashboard X position (pixels from left)
input int    InpDashY          = 20;      // Dashboard Y position (pixels from top)

input group "====== GENERAL ======"
input ulong  InpMagicNumber = 654321;
input int    InpSlippage    = 50;

//==========================================================================
//  GLOBALS
//==========================================================================
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    ordInfo;

int      rsi_handle;
int      tf_fast_handle, tf_slow_handle;
int      exit_fast_handle, exit_slow_handle;

double   g_spacingPips;
int      g_gridSize;
double   g_lotSize;
double   g_rsiBuyLvl;
double   g_rsiSellLvl;
double   g_trailStartPips;
double   g_trailStepPips;
double   g_dailyLossAmt;
double   g_maxProfitMult;
double   g_gridSLMult;

double   g_spacingPoints;
double   g_trailStartPoints;
double   g_trailStepPoints;

bool     g_isBTC      = false;
bool     g_isGold     = false;
bool     g_isCentAcct = false;
string   g_currency   = "USD";

// Profit tracking
datetime g_lastBarTime        = 0;
datetime g_currentDay         = 0;
datetime g_currentWeek        = 0;
double   g_dailyStartBalance  = 0;
double   g_weeklyStartBalance = 0;

// Dashboard object names
#define DASH_PREFIX  "DANE_DASH_"

//==========================================================================
//  INIT
//==========================================================================
int OnInit()
{
   string sym = _Symbol;
   StringToUpper(sym);
   g_isBTC  = (StringFind(sym, "BTC")  >= 0);
   g_isGold = (StringFind(sym, "XAU")  >= 0 || StringFind(sym, "GOLD") >= 0);

   g_currency   = AccountInfoString(ACCOUNT_CURRENCY);
   string cur   = g_currency;
   StringToUpper(cur);
   g_isCentAcct = (StringFind(cur, "USC") >= 0 || StringFind(cur, "CENT") >= 0);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpAutoDetect)
   {
      if(g_isBTC)
      {
         g_spacingPips    = 250;
         g_gridSize       = g_isCentAcct ? 3    : 5;
         g_lotSize        = InpLotSize;   // Always use editable input lot
         g_rsiBuyLvl      = 30.0;
         g_rsiSellLvl     = 70.0;
         g_trailStartPips = 100.0;
         g_trailStepPips  = 50.0;
         g_dailyLossAmt   = g_isCentAcct ? MathMin(balance*0.25, 500.0) : 100.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = 5.0;
      }
      else if(g_isGold)
      {
         g_spacingPips    = 80;
         g_gridSize       = g_isCentAcct ? 4 : 6;
         g_lotSize        = InpLotSize;   // Always use editable input lot
         g_rsiBuyLvl      = 35.0;
         g_rsiSellLvl     = 65.0;
         g_trailStartPips = 40.0;
         g_trailStepPips  = 20.0;
         g_dailyLossAmt   = g_isCentAcct ? MathMin(balance*0.25, 500.0) : 50.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = g_isCentAcct ? 5.0 : 6.0;
      }
      else
      {
         g_spacingPips    = InpSpacingPips;
         g_gridSize       = InpGridSize;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = InpRSI_BuyLvl;
         g_rsiSellLvl     = InpRSI_SellLvl;
         g_trailStartPips = InpTrailStartPips;
         g_trailStepPips  = InpTrailStepPips;
         g_dailyLossAmt   = InpDailyLossAmt;
         g_maxProfitMult  = InpMaxProfitMult;
         g_gridSLMult     = InpGridSLMult;
      }
   }
   else
   {
      g_spacingPips    = InpSpacingPips;
      g_gridSize       = InpGridSize;
      g_lotSize        = InpLotSize;
      g_rsiBuyLvl      = InpRSI_BuyLvl;
      g_rsiSellLvl     = InpRSI_SellLvl;
      g_trailStartPips = InpTrailStartPips;
      g_trailStepPips  = InpTrailStepPips;
      g_dailyLossAmt   = InpDailyLossAmt;
      g_maxProfitMult  = InpMaxProfitMult;
      g_gridSLMult     = InpGridSLMult;
   }

   g_spacingPoints    = g_spacingPips    * 10.0 * _Point;
   g_trailStartPoints = g_trailStartPips * 10.0 * _Point;
   g_trailStepPoints  = g_trailStepPips  * 10.0 * _Point;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   rsi_handle       = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, InpRSI_Price);
   tf_fast_handle   = iMA(_Symbol, PERIOD_CURRENT, InpTF_FastPeriod, 0, InpTF_FastMethod, InpTF_Price);
   tf_slow_handle   = iMA(_Symbol, PERIOD_CURRENT, InpTF_SlowPeriod, 0, InpTF_SlowMethod, InpTF_Price);
   exit_fast_handle = iMA(_Symbol, PERIOD_CURRENT, InpExit_FastPeriod, 0, InpExit_FastMethod, InpExit_Price);
   exit_slow_handle = iMA(_Symbol, PERIOD_CURRENT, InpExit_SlowPeriod, 0, InpExit_SlowMethod, InpExit_Price);

   if(rsi_handle==INVALID_HANDLE || tf_fast_handle==INVALID_HANDLE ||
      tf_slow_handle==INVALID_HANDLE || exit_fast_handle==INVALID_HANDLE ||
      exit_slow_handle==INVALID_HANDLE)
   { Alert("EA v3.3 ERROR: Indicator handle failed!"); return INIT_FAILED; }

   g_dailyStartBalance  = balance;
   g_weeklyStartBalance = balance;
   g_currentDay         = GetDayStart();
   g_currentWeek        = GetWeekStart();

   if(InpShowDashboard) CreateDashboard();

   Print("=== EA GRID v3.3 INITIALIZED on ", _Symbol, " ===");
   Print("Account: ", (g_isCentAcct ? "CENT (USC)" : "STANDARD (USD)"),
         " | Balance: ", DoubleToString(balance,2), " ", g_currency);
   Print("Lot: ", g_lotSize, " | Grid: ", g_gridSize,
         " orders | Spacing: ", g_spacingPips, " pips");
   Print("RSI: ", g_rsiBuyLvl, "/", g_rsiSellLvl,
         " | Daily Loss Limit: ", g_dailyLossAmt, " ", g_currency);

   return INIT_SUCCEEDED;
}

//==========================================================================
//  DEINIT — clean up dashboard
//==========================================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(rsi_handle);
   IndicatorRelease(tf_fast_handle);
   IndicatorRelease(tf_slow_handle);
   IndicatorRelease(exit_fast_handle);
   IndicatorRelease(exit_slow_handle);
   DeleteDashboard();
}

//==========================================================================
//  MAIN TICK
//==========================================================================
void OnTick()
{
   ResetDailyTracker();
   MonitorGridProfit();
   ManageTrailingStop();

   // Update dashboard on every tick
   if(InpShowDashboard) UpdateDashboard();

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   if(InpUseDailyLoss && IsDailyLossBreached()) return;

   int bars = MathMax(MathMax(InpRSI_Shift, InpTF_Shift), InpExit_Shift) + 3;

   double rsi_val[], tf_fast[], tf_slow[], exit_fast[], exit_slow[];
   ArraySetAsSeries(rsi_val,   true); ArraySetAsSeries(tf_fast,   true);
   ArraySetAsSeries(tf_slow,   true); ArraySetAsSeries(exit_fast, true);
   ArraySetAsSeries(exit_slow, true);

   if(CopyBuffer(rsi_handle,       0,0,bars,rsi_val)   < bars) return;
   if(CopyBuffer(tf_fast_handle,   0,0,bars,tf_fast)   < bars) return;
   if(CopyBuffer(tf_slow_handle,   0,0,bars,tf_slow)   < bars) return;
   if(CopyBuffer(exit_fast_handle, 0,0,bars,exit_fast) < bars) return;
   if(CopyBuffer(exit_slow_handle, 0,0,bars,exit_slow) < bars) return;

   bool hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
   bool hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);

   // Exit signals
   if(hasBuys || hasSells)
   {
      int s = InpExit_Shift;
      bool xBear = (exit_fast[s] <  exit_slow[s]   && exit_fast[s+1] >= exit_slow[s+1]);
      bool xBull = (exit_fast[s] >  exit_slow[s]   && exit_fast[s+1] <= exit_slow[s+1]);
      if(xBear && hasBuys)
      { ClosePositionsByType(POSITION_TYPE_BUY);  CancelPendingByComment("BUY_GRID_"); }
      if(xBull && hasSells)
      { ClosePositionsByType(POSITION_TYPE_SELL); CancelPendingByComment("SELL_GRID_"); }
      hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
      hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);
   }

   // Trend filter
   bool tUp = (tf_fast[InpTF_Shift] > tf_slow[InpTF_Shift]);
   bool tDn = (tf_fast[InpTF_Shift] < tf_slow[InpTF_Shift]);

   // RSI entry
   int rs = InpRSI_Shift;
   bool buyOK  = (rsi_val[rs] >  g_rsiBuyLvl  && rsi_val[rs+1] <= g_rsiBuyLvl);
   bool sellOK = (rsi_val[rs] <  g_rsiSellLvl && rsi_val[rs+1] >= g_rsiSellLvl);

   if(buyOK  && tUp && !hasBuys)  OpenBuyGrid();
   if(sellOK && tDn && !hasSells) OpenSellGrid();
}

//==========================================================================
//  GRID FUNCTIONS
//==========================================================================
void OpenBuyGrid()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=0; i<g_gridSize; i++)
   {
      double price = NormalizeDouble(ask - i*g_spacingPoints, _Digits);
      double tp    = InpTPPerTrade ? NormalizeDouble(price + InpTPMultiplier*g_spacingPoints,_Digits) : 0;
      string cmt   = "BUY_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      if(i==0) trade.Buy(g_lotSize,_Symbol,0,0,tp,cmt);
      else     trade.BuyLimit(g_lotSize,price,_Symbol,0,tp,ORDER_TIME_GTC,0,cmt);
   }
}

void OpenSellGrid()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i=0; i<g_gridSize; i++)
   {
      double price = NormalizeDouble(bid + i*g_spacingPoints, _Digits);
      double tp    = InpTPPerTrade ? NormalizeDouble(price - InpTPMultiplier*g_spacingPoints,_Digits) : 0;
      string cmt   = "SELL_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      if(i==0) trade.Sell(g_lotSize,_Symbol,0,0,tp,cmt);
      else     trade.SellLimit(g_lotSize,price,_Symbol,0,tp,ORDER_TIME_GTC,0,cmt);
   }
}

//==========================================================================
//  TRAILING STOP
//==========================================================================
void ManageTrailingStop()
{
   if(!InpUseTrailing) return;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss();
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      { if(bid-op>=g_trailStartPoints){ double nsl=NormalizeDouble(bid-g_trailStepPoints,_Digits);
        if(nsl>sl+_Point) trade.PositionModify(posInfo.Ticket(),nsl,posInfo.TakeProfit()); } }
      else if(posInfo.PositionType()==POSITION_TYPE_SELL)
      { if(op-ask>=g_trailStartPoints){ double nsl=NormalizeDouble(ask+g_trailStepPoints,_Digits);
        if(sl==0||nsl<sl-_Point) trade.PositionModify(posInfo.Ticket(),nsl,posInfo.TakeProfit()); } }
   }
}

//==========================================================================
//  GRID PROFIT MONITOR
//==========================================================================
void MonitorGridProfit()
{
   if(CountPositions(POSITION_TYPE_BUY)==0 && CountPositions(POSITION_TYPE_SELL)==0) return;
   double tp=GetTotalGridProfit();
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double pv=(tv/ts)*(_Point*10.0)*g_lotSize;
   double maxP= g_maxProfitMult*g_spacingPips*pv;
   double maxL=-g_gridSLMult   *g_spacingPips*pv;
   if(InpCloseAtMaxProfit && tp>=maxP){ Print("MAX PROFIT → closing grid."); CloseAllGridOrders(); return; }
   if(tp<=maxL){ Print("GRID SL → closing grid."); CloseAllGridOrders(); }
}

//==========================================================================
//  DAILY / WEEKLY TRACKERS
//==========================================================================
datetime GetDayStart()
{ MqlDateTime d; TimeToStruct(TimeCurrent(),d); d.hour=0;d.min=0;d.sec=0; return StructToTime(d); }

datetime GetWeekStart()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   int dow = d.day_of_week; // 0=Sun
   datetime cur = GetDayStart();
   return cur - dow*86400;
}

void ResetDailyTracker()
{
   datetime today = GetDayStart();
   if(today != g_currentDay)
   {
      g_currentDay        = today;
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("New day — balance reset: ", DoubleToString(g_dailyStartBalance,2), " ", g_currency);
   }
   datetime week = GetWeekStart();
   if(week != g_currentWeek)
   {
      g_currentWeek        = week;
      g_weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("New week — weekly balance reset: ", DoubleToString(g_weeklyStartBalance,2), " ", g_currency);
   }
}

bool IsDailyLossBreached()
{
   double lost = g_dailyStartBalance - AccountInfoDouble(ACCOUNT_BALANCE);
   if(lost >= g_dailyLossAmt)
   { Print("DAILY LOSS LIMIT: pausing entries."); return true; }
   return false;
}

//==========================================================================
//  ██████╗  █████╗ ███████╗██╗  ██╗██████╗  ██████╗  █████╗ ██████╗ ██████╗ 
//  ██╔══██╗██╔══██╗██╔════╝██║  ██║██╔══██╗██╔═══██╗██╔══██╗██╔══██╗██╔══██╗
//  ██║  ██║███████║███████╗███████║██████╔╝██║   ██║███████║██████╔╝██║  ██║
//  ██║  ██║██╔══██║╚════██║██╔══██║██╔══██╗██║   ██║██╔══██║██╔══██╗██║  ██║
//  ██████╔╝██║  ██║███████║██║  ██║██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝
//  LIVE DASHBOARD PANEL
//==========================================================================

void CreateDashboard()
{
   DeleteDashboard();
   int x = InpDashX;
   int y = InpDashY;
   int w = 340;  // panel width
   
   // Background panel
   DashRect("BG",       x,   y,    w,  310, C'20,40,50',   C'0,120,160', 2);
   
   // Title bar
   DashRect("TITLE_BG", x,   y,    w,   36, C'0,100,140',  C'0,120,160', 0);
   DashLabel("TITLE",   x+10, y+8,  "⚡ DANE GRID EA v3.3",  13, clrWhite,    true);
   DashLabel("VERSION", x+220,y+10, "by Dane",               9,  clrAqua,    false);

   // Account type badge
   DashRect("ACC_BG",   x+w-90, y+6, 80, 22, C'0,60,90', C'0,180,220', 1);
   DashLabel("ACC_TYPE",x+w-85, y+10,"LOADING...", 9, clrYellow, false);

   // Section: Profit
   DashRect("PROF_BG",  x, y+40, w, 78, C'15,35,45', C'0,100,140', 0);
   DashLabel("PROF_HDR",x+10, y+44, "PROFIT TRACKER", 9, C'0,200,220', true);
   DashLabel("D_LBL",   x+10, y+62, "Daily Profit :",   10, clrSilver, false);
   DashLabel("W_LBL",   x+10, y+82, "Weekly Profit :",  10, clrSilver, false);
   DashLabel("D_VAL",   x+150,y+62, "0.00% | 0.00",    10, clrWhite,  false);
   DashLabel("W_VAL",   x+150,y+82, "0.00% | 0.00",    10, clrWhite,  false);

   // Section: Live Trade Status
   DashRect("TRADE_BG", x, y+122, w, 78, C'15,35,45', C'0,100,140', 0);
   DashLabel("TRADE_HDR",x+10,y+126,"LIVE TRADES",      9, C'0,200,220', true);
   DashLabel("T_BUY_L", x+10, y+144,"Buy Orders :",    10, clrSilver, false);
   DashLabel("T_SEL_L", x+10, y+164,"Sell Orders :",   10, clrSilver, false);
   DashLabel("T_PL_L",  x+185,y+144,"Floating P/L :",  10, clrSilver, false);
   DashLabel("T_BUY_V", x+110,y+144,"0",               10, clrLime,   false);
   DashLabel("T_SEL_V", x+110,y+164,"0",               10, clrRed,    false);
   DashLabel("T_PL_V",  x+280,y+144,"0.00",            10, clrWhite,  false);

   // Section: Settings
   DashRect("SET_BG",   x, y+204, w, 98, C'15,35,45', C'0,100,140', 0);
   DashLabel("SET_HDR", x+10, y+208,"CURRENT SETTINGS",  9, C'0,200,220', true);
   DashLabel("S1_L",    x+10, y+226,"Grid Size :",       10, clrSilver, false);
   DashLabel("S2_L",    x+10, y+244,"Spacing :",         10, clrSilver, false);
   DashLabel("S3_L",    x+10, y+262,"Lot Size :",        10, clrSilver, false);
   DashLabel("S4_L",    x+185,y+226,"RSI Levels :",      10, clrSilver, false);
   DashLabel("S5_L",    x+185,y+244,"Max Profit :",      10, clrSilver, false);
   DashLabel("S6_L",    x+185,y+262,"Grid SL :",         10, clrSilver, false);
   DashLabel("S1_V",    x+100,y+226,"--",                10, clrYellow, false);
   DashLabel("S2_V",    x+100,y+244,"--",                10, clrYellow, false);
   DashLabel("S3_V",    x+100,y+262,"--",                10, clrYellow, false);
   DashLabel("S4_V",    x+275,y+226,"--",                10, clrYellow, false);
   DashLabel("S5_V",    x+275,y+244,"--",                10, clrYellow, false);
   DashLabel("S6_V",    x+275,y+262,"--",                10, clrYellow, false);

   // Footer
   DashLabel("FOOT",    x+10, y+290,"Best PHT: 8:00 PM – 11:00 PM  |  24/5 ACTIVE", 8, C'0,160,200', false);

   ChartRedraw(0);
}

//--- Update all live values on dashboard
void UpdateDashboard()
{
   if(!InpShowDashboard) return;

   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL    = balance - g_dailyStartBalance;
   double weeklyPnL   = balance - g_weeklyStartBalance;
   double dailyPct    = (g_dailyStartBalance  > 0) ? (dailyPnL  / g_dailyStartBalance  * 100.0) : 0;
   double weeklyPct   = (g_weeklyStartBalance > 0) ? (weeklyPnL / g_weeklyStartBalance * 100.0) : 0;
   double floatPnL    = GetTotalGridProfit();
   int    buyCount    = CountPositions(POSITION_TYPE_BUY);
   int    sellCount   = CountPositions(POSITION_TYPE_SELL);

   // Account type badge
   string accLabel = g_isCentAcct ? "CENT (USC)" : "STANDARD";
   DashLabelUpdate("ACC_TYPE", accLabel, g_isCentAcct ? clrYellow : clrLime);

   // Daily profit
   color dColor = (dailyPnL >= 0) ? clrLime : clrRed;
   string dSign  = (dailyPnL >= 0) ? "+" : "";
   DashLabelUpdate("D_VAL",
      dSign + DoubleToString(dailyPct,2) + "% | " +
      dSign + DoubleToString(dailyPnL,2) + " " + g_currency,
      dColor);

   // Weekly profit
   color wColor = (weeklyPnL >= 0) ? clrLime : clrRed;
   string wSign  = (weeklyPnL >= 0) ? "+" : "";
   DashLabelUpdate("W_VAL",
      wSign + DoubleToString(weeklyPct,2) + "% | " +
      wSign + DoubleToString(weeklyPnL,2) + " " + g_currency,
      wColor);

   // Live trade counts
   DashLabelUpdate("T_BUY_V", IntegerToString(buyCount),  buyCount  > 0 ? clrLime   : clrSilver);
   DashLabelUpdate("T_SEL_V", IntegerToString(sellCount), sellCount > 0 ? clrRed    : clrSilver);

   // Floating P/L
   color plColor = (floatPnL >= 0) ? clrLime : clrRed;
   string plSign = (floatPnL >= 0) ? "+" : "";
   DashLabelUpdate("T_PL_V",
      plSign + DoubleToString(floatPnL,2) + " " + g_currency,
      plColor);

   // Settings (static but updated once to reflect auto-detected values)
   DashLabelUpdate("S1_V", IntegerToString(g_gridSize),            clrYellow);
   DashLabelUpdate("S2_V", DoubleToString(g_spacingPips,0)+" pips",clrYellow);
   DashLabelUpdate("S3_V", DoubleToString(g_lotSize,3),            clrYellow);
   DashLabelUpdate("S4_V", DoubleToString(g_rsiBuyLvl,0)+"/"+DoubleToString(g_rsiSellLvl,0), clrYellow);
   DashLabelUpdate("S5_V", DoubleToString(g_maxProfitMult,0)+"x", clrYellow);
   DashLabelUpdate("S6_V", DoubleToString(g_gridSLMult,0)+"x",    clrYellow);

   ChartRedraw(0);
}

//==========================================================================
//  DASHBOARD HELPER FUNCTIONS
//==========================================================================
void DashRect(string name, int x, int y, int w, int h, color bg, color border, int thick)
{
   string obj = DASH_PREFIX + name;
   ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH,      thick);
   ObjectSetInteger(0, obj, OBJPROP_BACK,       false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
}

void DashLabel(string name, int x, int y, string text, int size, color clr, bool bold)
{
   string obj = DASH_PREFIX + name;
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  obj, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE,  size);
   ObjectSetString(0,  obj, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, obj, OBJPROP_BACK,      false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE,false);
}

void DashLabelUpdate(string name, string text, color clr)
{
   string obj = DASH_PREFIX + name;
   if(ObjectFind(0, obj) >= 0)
   {
      ObjectSetString(0,  obj, OBJPROP_TEXT,  text);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   }
}

void DeleteDashboard()
{
   int total = ObjectsTotal(0);
   for(int i = total-1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, DASH_PREFIX) == 0)
         ObjectDelete(0, name);
   }
   ChartRedraw(0);
}

//==========================================================================
//  HELPERS
//==========================================================================
int CountPositions(ENUM_POSITION_TYPE type)
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber&&posInfo.Symbol()==_Symbol&&
            posInfo.PositionType()==type) n++;
   return n;
}

double GetTotalGridProfit()
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber&&posInfo.Symbol()==_Symbol)
            p+=posInfo.Profit()+posInfo.Swap();
   return p;
}

void ClosePositionsByType(ENUM_POSITION_TYPE type)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber&&posInfo.Symbol()==_Symbol&&
            posInfo.PositionType()==type)
            trade.PositionClose(posInfo.Ticket());
}

void CancelPendingByComment(string prefix)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(ordInfo.SelectByIndex(i))
         if(ordInfo.Magic()==InpMagicNumber&&ordInfo.Symbol()==_Symbol&&
            StringFind(ordInfo.Comment(),prefix)==0)
            trade.OrderDelete(ordInfo.Ticket());
}

void CloseAllGridOrders()
{
   ClosePositionsByType(POSITION_TYPE_BUY);
   ClosePositionsByType(POSITION_TYPE_SELL);
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(ordInfo.SelectByIndex(i))
         if(ordInfo.Magic()==InpMagicNumber&&ordInfo.Symbol()==_Symbol)
            trade.OrderDelete(ordInfo.Ticket());
}

//+------------------------------------------------------------------+
//| END OF EA v3.3                                                   |
//+------------------------------------------------------------------+
