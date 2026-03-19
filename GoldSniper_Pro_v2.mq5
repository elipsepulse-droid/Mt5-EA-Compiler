//+------------------------------------------------------------------+
//|         EA_Scalping_Grid_GOLD_BTC_v3.8.mq5                       |
//|     Universal Grid Scalping Robot - XAUUSD & BTCUSD M5           |
//|                                                                  |
//|  v3.8 CHANGES:                                                   |
//|  - RSI changed to 40/60 for more frequent trades                 |
//|  - Early Grid Exit added: closes entire grid if total floating   |
//|    loss hits -$0.05 USD (or -5 USC on cent account)              |
//|  - Early exit applies to ALL symbols (XAUUSD, BTCUSD)           |
//|  - Early exit works on both USD and USC cent accounts            |
//|  - Dashboard updated to show Early Exit threshold                |
//+------------------------------------------------------------------+
#property copyright   "EA SCALPING ROBOT / DANE - v3.8"
#property version     "3.80"
#property description "Grid EA v3.8 — RSI 40/60 + Early Grid Exit Protection"
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

input group "====== ENTRY SIGNAL: RSI ======"
input int                InpRSI_Period  = 14;
input ENUM_APPLIED_PRICE InpRSI_Price   = PRICE_CLOSE;
input int                InpRSI_Shift   = 1;
input double             InpRSI_BuyLvl  = 40.0;   // RSI BUY  level (40 = more frequent trades)
input double             InpRSI_SellLvl = 60.0;   // RSI SELL level (60 = more frequent trades)

input group "====== EARLY GRID EXIT PROTECTION (NEW v3.8) ======"
// Closes the ENTIRE grid immediately when total floating loss hits this amount
// Applies to ALL symbols (XAUUSD, BTCUSD) on both USD and USC accounts
// USD account example: 0.05 = close grid if total loss reaches -$0.05
// USC account example: 0.05 = close grid if total loss reaches -0.05 USC (= -$0.0005 real)
// Set higher for USC accounts e.g. 5.0 USC — see recommended values below
input bool   InpUseEarlyExit     = true;  // Enable early grid exit protection
input double InpEarlyExitLossUSD = 0.05;  // USD accounts: early exit at -$0.05 loss
input double InpEarlyExitLossUSC = 5.0;   // USC cent accounts: early exit at -5 USC loss

input group "====== OPTION 1 — EXTREME RSI TREND BYPASS ======"
// When RSI reaches extreme levels, trend filter is ignored automatically
// This prevents the EA from being paralyzed on big crash/rally days
// Example: RSI drops to 14 today → bypass activates → BUY on bounce captured
input double InpExtremeRSILow  = 25.0; // RSI below this → bypass trend filter for BUY
input double InpExtremeRSIHigh = 75.0; // RSI above this → bypass trend filter for SELL

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

input group "====== DEBUG ======"
input bool InpDebugLog = true; // Print signal status on every new bar (check Experts tab)
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
double   g_maxProfitMult;
double   g_gridSLMult;
double   g_earlyExitLoss;    // Early exit threshold in account currency (USC or USD)

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
         g_gridSize       = g_isCentAcct ? 3 : 5;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = 40.0;   // v3.8: 40/60 for more frequent trades
         g_rsiSellLvl     = 60.0;
         g_trailStartPips = 100.0;
         g_trailStepPips  = 50.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = 5.0;
         g_earlyExitLoss  = g_isCentAcct ? InpEarlyExitLossUSC : InpEarlyExitLossUSD;
      }
      else if(g_isGold)
      {
         g_spacingPips    = 80;
         g_gridSize       = g_isCentAcct ? 4 : 6;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = 40.0;   // v3.8: 40/60 for more frequent trades
         g_rsiSellLvl     = 60.0;
         g_trailStartPips = 40.0;
         g_trailStepPips  = 20.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = g_isCentAcct ? 5.0 : 6.0;
         g_earlyExitLoss  = g_isCentAcct ? InpEarlyExitLossUSC : InpEarlyExitLossUSD;
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
         g_maxProfitMult  = InpMaxProfitMult;
         g_gridSLMult     = InpGridSLMult;
         g_earlyExitLoss  = g_isCentAcct ? InpEarlyExitLossUSC : InpEarlyExitLossUSD;
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
      g_maxProfitMult  = InpMaxProfitMult;
      g_gridSLMult     = InpGridSLMult;
      g_earlyExitLoss  = g_isCentAcct ? InpEarlyExitLossUSC : InpEarlyExitLossUSD;
   }

   // ---------------------------------------------------------------
   // PIP SIZE CALCULATION — digit-aware for all Exness symbol types
   //
   // XAUUSD  / XAUUSDm  (_Digits=2): _Point=0.01  → 1 pip = 0.10  → mult=10
   // XAUUSDm / XAUUSDc  (_Digits=3): _Point=0.001 → 1 pip = 0.10  → mult=100
   // BTCUSD  / BTCUSDm  (_Digits=2): _Point=0.01  → 1 pip = 0.10  → mult=10
   //
   // Formula: pipSize = 10^(_Digits-1) * _Point
   // This guarantees 1 pip = $0.10 movement regardless of broker decimal count
   // ---------------------------------------------------------------
   double pipSize;
   if(_Digits == 3)       pipSize = 0.100;   // e.g. XAUUSDm with 3 decimals
   else if(_Digits == 2)  pipSize = 0.100;   // e.g. XAUUSD  with 2 decimals
   else if(_Digits == 5)  pipSize = 0.00010; // FX pairs with 5 decimals
   else if(_Digits == 4)  pipSize = 0.0010;  // FX pairs with 4 decimals
   else                   pipSize = _Point * 10.0; // fallback

   g_spacingPoints    = g_spacingPips    * pipSize;
   g_trailStartPoints = g_trailStartPips * pipSize;
   g_trailStepPoints  = g_trailStepPips  * pipSize;

   Print("Symbol digits: ", _Digits, " | _Point: ", _Point,
         " | Pip size used: ", pipSize,
         " | Spacing in price: ", g_spacingPoints);

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
   { Alert("EA v3.7 ERROR: Indicator handle failed!"); return INIT_FAILED; }

   // --- Safe balance initialization ---
   // Problem: AccountInfoDouble(ACCOUNT_BALANCE) can return 0.00 if called
   // before the terminal finishes loading account data after attach.
   // Fix: retry up to 10 times with 100ms pause until we get a valid balance.
   double safeBalance = 0;
   for(int attempt = 0; attempt < 10; attempt++)
   {
      safeBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(safeBalance > 0) break;
      Sleep(100); // wait 100ms and try again
   }
   // If still 0 after retries (shouldn't happen), use equity as fallback
   if(safeBalance <= 0)
      safeBalance = AccountInfoDouble(ACCOUNT_EQUITY);

   g_dailyStartBalance  = safeBalance;
   g_weeklyStartBalance = safeBalance;
   g_currentDay         = GetDayStart();
   g_currentWeek        = GetWeekStart();

   if(InpShowDashboard) CreateDashboard();

   Print("=== EA GRID v3.8 INITIALIZED on ", _Symbol, " ===");
   Print("Account : ", (g_isCentAcct ? "CENT (USC)" : "STANDARD (USD)"),
         " | Balance: ", DoubleToString(safeBalance,2), " ", g_currency);
   Print("Symbol  : ", _Symbol, " | Grid: ", g_gridSize,
         " orders | Spacing: ", g_spacingPips, " pips | Lot: ", g_lotSize);
   Print("RSI     : BUY=", g_rsiBuyLvl, " SELL=", g_rsiSellLvl,
         " | Bypass: <", InpExtremeRSILow, " / >", InpExtremeRSIHigh);
   Print("Early Exit : ENABLED at -", DoubleToString(g_earlyExitLoss,2), " ", g_currency,
         " | Max Profit: ", g_maxProfitMult, "x | Grid SL: ", g_gridSLMult, "x");

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
   CleanOrphanedPending();   // ← v3.5 FIX: cancel pending orders with no active parent

   // Update dashboard on every tick
   if(InpShowDashboard) UpdateDashboard();

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   // Daily loss protection removed — EA trades freely all day

   // Use 10 bars minimum — safer buffer for all indicator calculations
   // EMA(300) needs 300 bars to warm up; CopyBuffer only needs recent values
   // but requesting too few can cause silent failures on newly attached charts
   int bars = MathMax(MathMax(InpRSI_Shift, InpTF_Shift), InpExit_Shift) + 10;

   double rsi_val[], tf_fast[], tf_slow[], exit_fast[], exit_slow[];
   ArraySetAsSeries(rsi_val,   true); ArraySetAsSeries(tf_fast,   true);
   ArraySetAsSeries(tf_slow,   true); ArraySetAsSeries(exit_fast, true);
   ArraySetAsSeries(exit_slow, true);

   // CopyBuffer failure check — now with explanation printed to Experts tab
   if(CopyBuffer(rsi_handle,       0,0,bars,rsi_val)   < bars)
   { if(InpDebugLog) Print("DEBUG: RSI buffer not ready yet — waiting for more bars."); return; }
   if(CopyBuffer(tf_fast_handle,   0,0,bars,tf_fast)   < bars)
   { if(InpDebugLog) Print("DEBUG: EMA(",InpTF_FastPeriod,") buffer not ready yet."); return; }
   if(CopyBuffer(tf_slow_handle,   0,0,bars,tf_slow)   < bars)
   { if(InpDebugLog) Print("DEBUG: EMA(",InpTF_SlowPeriod,") buffer not ready — needs ",InpTF_SlowPeriod," bars of history."); return; }
   if(CopyBuffer(exit_fast_handle, 0,0,bars,exit_fast) < bars)
   { if(InpDebugLog) Print("DEBUG: Exit EMA(",InpExit_FastPeriod,") buffer not ready yet."); return; }
   if(CopyBuffer(exit_slow_handle, 0,0,bars,exit_slow) < bars)
   { if(InpDebugLog) Print("DEBUG: Exit EMA(",InpExit_SlowPeriod,") buffer not ready yet."); return; }

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

   // ================================================================
   //  TREND FILTER
   // ================================================================
   bool tUp = (tf_fast[InpTF_Shift] > tf_slow[InpTF_Shift]);
   bool tDn = (tf_fast[InpTF_Shift] < tf_slow[InpTF_Shift]);

   // ================================================================
   //  RSI ENTRY SIGNALS
   // ================================================================
   int rs = InpRSI_Shift;
   double currentRSI = rsi_val[rs];
   double prevRSI    = rsi_val[rs+1];

   bool buyOK  = (currentRSI >  g_rsiBuyLvl  && prevRSI <= g_rsiBuyLvl);
   bool sellOK = (currentRSI <  g_rsiSellLvl && prevRSI >= g_rsiSellLvl);

   // ================================================================
   //  OPTION 1 — SMART TREND BYPASS FOR EXTREME RSI
   //
   //  Normal conditions  (RSI 25–75):
   //    Trend filter is ACTIVE — only trade with the trend
   //
   //  Extreme oversold   (RSI previous bar < 25):
   //    Trend filter BYPASSED for BUY — RSI bounce is more reliable
   //    than trend direction at these levels (e.g. today RSI=14)
   //
   //  Extreme overbought (RSI previous bar > 75):
   //    Trend filter BYPASSED for SELL — same logic reversed
   // ================================================================
   bool extremeOversold   = (prevRSI < InpExtremeRSILow);   // e.g. prev bar RSI < 25
   bool extremeOverbought = (prevRSI > InpExtremeRSIHigh);  // e.g. prev bar RSI > 75

   // Final entry decisions combining signal + trend/bypass
   bool doOpenBuy  = buyOK  && (tUp || extremeOversold)   && !hasBuys;
   bool doOpenSell = sellOK && (tDn || extremeOverbought) && !hasSells;

   // ================================================================
   //  DEBUG: Full status print every new bar
   // ================================================================
   if(InpDebugLog)
   {
      string trendStr  = tUp ? "UPTREND" : (tDn ? "DOWNTREND" : "FLAT");
      string bypassStr = extremeOversold ? " [BYPASS:oversold<"+DoubleToString(InpExtremeRSILow,0)+"]"
                       : extremeOverbought ? " [BYPASS:overbought>"+DoubleToString(InpExtremeRSIHigh,0)+"]"
                       : "";
      Print("--- NEW BAR --- ",
            "RSI[1]=", DoubleToString(currentRSI,2),
            " RSI[2]=", DoubleToString(prevRSI,2),
            " | BuyOK=", buyOK, " SellOK=", sellOK,
            " | Trend=", trendStr, bypassStr,
            " EMA", InpTF_FastPeriod, "=", DoubleToString(tf_fast[InpTF_Shift],3),
            " EMA", InpTF_SlowPeriod, "=", DoubleToString(tf_slow[InpTF_Shift],3));

      if(!buyOK && !sellOK)
         Print("  → Waiting: RSI=", DoubleToString(currentRSI,2),
               " (need cross of ", g_rsiBuyLvl, " for BUY or ", g_rsiSellLvl, " for SELL)");
      else if(buyOK && !tUp && !extremeOversold)
         Print("  → BUY blocked: RSI crossed UP but DOWNTREND active.",
               " Need UPTREND or RSI prev <", InpExtremeRSILow, " (was ", DoubleToString(prevRSI,2), ")");
      else if(sellOK && !tDn && !extremeOverbought)
         Print("  → SELL blocked: RSI crossed DOWN but UPTREND active.",
               " Need DOWNTREND or RSI prev >", InpExtremeRSIHigh, " (was ", DoubleToString(prevRSI,2), ")");
      else if(doOpenBuy && extremeOversold)
         Print("  → BUY EXTREME BYPASS: RSI prev=", DoubleToString(prevRSI,2),
               " < ", InpExtremeRSILow, " — trend filter overridden! Opening BUY grid.");
      else if(doOpenSell && extremeOverbought)
         Print("  → SELL EXTREME BYPASS: RSI prev=", DoubleToString(prevRSI,2),
               " > ", InpExtremeRSIHigh, " — trend filter overridden! Opening SELL grid.");
      else if(buyOK && tUp && hasBuys)
         Print("  → BUY blocked: grid already active.");
      else if(sellOK && tDn && hasSells)
         Print("  → SELL blocked: grid already active.");
   }

   if(doOpenBuy)  OpenBuyGrid();
   if(doOpenSell) OpenSellGrid();
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
//  GRID PROFIT MONITOR — includes Early Grid Exit (v3.8)
//  3 layers of protection in priority order:
//  1. EARLY EXIT  : total floating loss hits -$0.05 USD / -5 USC → instant close
//  2. MAX PROFIT  : total floating profit hits 4x spacing → close and take profit
//  3. GRID SL     : total floating loss hits 5x/6x spacing → last resort close
//==========================================================================
void MonitorGridProfit()
{
   if(CountPositions(POSITION_TYPE_BUY)==0 && CountPositions(POSITION_TYPE_SELL)==0) return;

   double totalPnL = GetTotalGridProfit();

   // ------------------------------------------------------------------
   // LAYER 1 — EARLY EXIT (NEW v3.8)
   // Closes entire grid immediately when floating loss hits threshold
   // Works on ALL symbols (XAUUSD, BTCUSD) and ALL account types (USD, USC)
   // USD account: -$0.05 | USC account: -5 USC
   // ------------------------------------------------------------------
   if(InpUseEarlyExit && totalPnL <= -g_earlyExitLoss)
   {
      Print("⚡ EARLY EXIT TRIGGERED: Floating loss = ",
            DoubleToString(totalPnL, 2), " ", g_currency,
            " | Threshold = -", DoubleToString(g_earlyExitLoss, 2), " ", g_currency,
            " | Closing entire grid to protect account.");
      CloseAllGridOrders();
      return;
   }

   // ------------------------------------------------------------------
   // LAYER 2 — MAX PROFIT TARGET
   // ------------------------------------------------------------------
   double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pv   = (tv / ts) * g_spacingPoints * g_lotSize;
   double maxP =  g_maxProfitMult * pv;
   double maxL = -g_gridSLMult    * pv;

   if(InpCloseAtMaxProfit && totalPnL >= maxP)
   {
      Print("✅ MAX PROFIT HIT: ", DoubleToString(totalPnL,2), " ",
            g_currency, " → Closing grid.");
      CloseAllGridOrders();
      return;
   }

   // ------------------------------------------------------------------
   // LAYER 3 — GRID STOP LOSS (last resort)
   // ------------------------------------------------------------------
   if(totalPnL <= maxL)
   {
      Print("🛑 GRID SL HIT: ", DoubleToString(totalPnL,2), " ",
            g_currency, " → Closing grid.");
      CloseAllGridOrders();
   }
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
   int w = 345;

   // Main background
   DashRect("BG",        x,   y,    w,  345, C'18,36,48',   C'0,120,160', 2);

   // Title bar
   DashRect("TITLE_BG",  x,   y,    w,   36, C'0,90,130',   C'0,140,180', 0);
   DashLabel("TITLE",    x+10, y+8,  "⚡ DANE GRID EA v3.8",  13, clrWhite, true);
   DashLabel("BY",       x+218,y+10, "by Dane",                9, clrAqua,  false);

   // Account badge
   DashRect("ACC_BG",    x+w-92, y+6, 84, 22, C'0,60,90', C'0,180,220', 1);
   DashLabel("ACC_TYPE", x+w-88, y+10,"LOADING...", 9, clrYellow, false);

   // Section: Signal Mode (NEW in v3.7)
   DashRect("MODE_BG",   x, y+40, w, 34, C'0,70,100', C'0,140,180', 0);
   DashLabel("MODE_L",   x+10, y+50, "Signal Mode :", 9, clrSilver, false);
   DashLabel("MODE_V",   x+110,y+50, "NORMAL",        9, clrLime,   true);
   DashLabel("RSI_L",    x+210,y+50, "RSI :",         9, clrSilver, false);
   DashLabel("RSI_V",    x+245,y+50, "--",            9, clrWhite,  true);

   // Section: Profit Tracker
   DashRect("PROF_BG",   x, y+78,  w, 78, C'15,33,44', C'0,100,140', 0);
   DashLabel("PROF_HDR", x+10, y+82, "PROFIT TRACKER",  9, C'0,200,220', true);
   DashLabel("D_LBL",    x+10, y+100,"Daily Profit :",  10, clrSilver,   false);
   DashLabel("W_LBL",    x+10, y+120,"Weekly Profit :", 10, clrSilver,   false);
   DashLabel("D_VAL",    x+140,y+100,"0.00% | 0.00",   10, clrWhite,    false);
   DashLabel("W_VAL",    x+140,y+120,"0.00% | 0.00",   10, clrWhite,    false);

   // Section: Live Trades
   DashRect("TRADE_BG",  x, y+160, w, 78, C'15,33,44', C'0,100,140', 0);
   DashLabel("TRADE_HDR",x+10, y+164,"LIVE TRADES",     9, C'0,200,220', true);
   DashLabel("T_BUY_L",  x+10, y+182,"Buy Orders :",   10, clrSilver,   false);
   DashLabel("T_SEL_L",  x+10, y+202,"Sell Orders :",  10, clrSilver,   false);
   DashLabel("T_PL_L",   x+185,y+182,"Floating P/L :", 10, clrSilver,   false);
   DashLabel("T_BUY_V",  x+115,y+182,"0",              10, clrLime,     false);
   DashLabel("T_SEL_V",  x+115,y+202,"0",              10, clrRed,      false);
   DashLabel("T_PL_V",   x+285,y+182,"0.00",           10, clrWhite,    false);

   // Section: Settings
   DashRect("SET_BG",    x, y+242, w, 88, C'15,33,44', C'0,100,140', 0);
   DashLabel("SET_HDR",  x+10, y+246,"CURRENT SETTINGS",  9, C'0,200,220', true);
   DashLabel("S1_L",     x+10, y+264,"Grid Size :",       10, clrSilver,   false);
   DashLabel("S2_L",     x+10, y+282,"Spacing :",         10, clrSilver,   false);
   DashLabel("S3_L",     x+10, y+300,"Lot Size :",        10, clrSilver,   false);
   DashLabel("S4_L",     x+185,y+264,"RSI Levels :",      10, clrSilver,   false);
   DashLabel("S5_L",     x+185,y+282,"Max Profit :",      10, clrSilver,   false);
   DashLabel("S6_L",     x+185,y+300,"Grid SL :",         10, clrSilver,   false);
   DashLabel("S1_V",     x+105,y+264,"--",                10, clrYellow,   false);
   DashLabel("S2_V",     x+105,y+282,"--",                10, clrYellow,   false);
   DashLabel("S3_V",     x+105,y+300,"--",                10, clrYellow,   false);
   DashLabel("S4_V",     x+280,y+264,"--",                10, clrYellow,   false);
   DashLabel("S5_V",     x+280,y+282,"--",                10, clrYellow,   false);
   DashLabel("S6_V",     x+280,y+300,"--",                10, clrYellow,   false);

   // Footer
   DashLabel("FOOT",     x+10, y+328,"Best PHT: 8:00 PM – 11:00 PM  |  24/5 ACTIVE", 8, C'0,160,200', false);

   ChartRedraw(0);
}

//--- Update all live values on dashboard every tick
void UpdateDashboard()
{
   if(!InpShowDashboard) return;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL   = balance - g_dailyStartBalance;
   double weeklyPnL  = balance - g_weeklyStartBalance;
   double dailyPct   = (g_dailyStartBalance  > 0) ? (dailyPnL  / g_dailyStartBalance  * 100.0) : 0;
   double weeklyPct  = (g_weeklyStartBalance > 0) ? (weeklyPnL / g_weeklyStartBalance * 100.0) : 0;
   double floatPnL   = GetTotalGridProfit();
   int    buyCount   = CountPositions(POSITION_TYPE_BUY);
   int    sellCount  = CountPositions(POSITION_TYPE_SELL);

   // Get live RSI
   double rsiNow[];
   ArraySetAsSeries(rsiNow, true);
   double currentRSI = 0;
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsiNow) >= 3)
      currentRSI = rsiNow[1];

   // Account badge
   DashLabelUpdate("ACC_TYPE", g_isCentAcct ? "CENT (USC)" : "STANDARD",
                   g_isCentAcct ? clrYellow : clrLime);

   // Signal Mode row (NEW v3.7)
   bool extremeLow  = (currentRSI > 0 && currentRSI <= InpExtremeRSILow);
   bool extremeHigh = (currentRSI > 0 && currentRSI >= InpExtremeRSIHigh);
   if(extremeLow)
   {
      DashLabelUpdate("MODE_V", "⚡ EXTREME BUY",  clrAqua);
   }
   else if(extremeHigh)
   {
      DashLabelUpdate("MODE_V", "⚡ EXTREME SELL", clrOrange);
   }
   else
   {
      DashLabelUpdate("MODE_V", "NORMAL (Trend ON)", clrLime);
   }

   // Live RSI value with color
   color rsiColor = currentRSI <= 30  ? clrAqua   :
                    currentRSI >= 70  ? clrOrange  :
                    clrWhite;
   DashLabelUpdate("RSI_V", DoubleToString(currentRSI,1), rsiColor);

   // Daily profit
   color dColor = (dailyPnL >= 0) ? clrLime : clrRed;
   string dSign = (dailyPnL >= 0) ? "+" : "";
   DashLabelUpdate("D_VAL",
      dSign+DoubleToString(dailyPct,2)+"% | "+dSign+DoubleToString(dailyPnL,2)+" "+g_currency,
      dColor);

   // Weekly profit
   color wColor = (weeklyPnL >= 0) ? clrLime : clrRed;
   string wSign = (weeklyPnL >= 0) ? "+" : "";
   DashLabelUpdate("W_VAL",
      wSign+DoubleToString(weeklyPct,2)+"% | "+wSign+DoubleToString(weeklyPnL,2)+" "+g_currency,
      wColor);

   // Trade counts
   DashLabelUpdate("T_BUY_V", IntegerToString(buyCount),  buyCount  > 0 ? clrLime   : clrSilver);
   DashLabelUpdate("T_SEL_V", IntegerToString(sellCount), sellCount > 0 ? clrRed    : clrSilver);

   // Floating P/L
   color plColor = (floatPnL >= 0) ? clrLime : clrRed;
   string plSign = (floatPnL >= 0) ? "+" : "";
   DashLabelUpdate("T_PL_V",
      plSign+DoubleToString(floatPnL,2)+" "+g_currency, plColor);

   // Settings
   DashLabelUpdate("S1_V", IntegerToString(g_gridSize),                              clrYellow);
   DashLabelUpdate("S2_V", DoubleToString(g_spacingPips,0)+" pips",                  clrYellow);
   DashLabelUpdate("S3_V", DoubleToString(g_lotSize,3),                              clrYellow);
   DashLabelUpdate("S4_V", DoubleToString(g_rsiBuyLvl,0)+"/"+DoubleToString(g_rsiSellLvl,0), clrYellow);
   DashLabelUpdate("S5_V", DoubleToString(g_maxProfitMult,0)+"x",                   clrYellow);
   DashLabelUpdate("S6_V", DoubleToString(g_gridSLMult,0)+"x",                      clrYellow);

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
//  CLEAN ORPHANED PENDING ORDERS — v3.5 FIX
//
//  Problem: When a market order closes by hitting its own TP, the EA's
//           remaining sell/buy limit orders stay open ("orphaned").
//           If price reverses back to those levels, they fire unexpectedly.
//
//  Fix logic (runs every tick):
//  - If BUY  limits exist  BUT no active buy  position → cancel all BUY  limits
//  - If SELL limits exist  BUT no active sell position → cancel all SELL limits
//
//  This ensures pending grid orders are always cleaned up automatically
//  whenever the market order that spawned them closes for any reason
//  (TP hit, manual close, EA exit signal, Grid SL).
//==========================================================================
void CleanOrphanedPending()
{
   bool hasActiveBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
   bool hasActiveSells = (CountPositions(POSITION_TYPE_SELL) > 0);

   bool hasBuyPending  = false;
   bool hasSellPending = false;

   // Check if any EA pending orders exist
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!ordInfo.SelectByIndex(i)) continue;
      if(ordInfo.Magic()  != InpMagicNumber) continue;
      if(ordInfo.Symbol() != _Symbol)        continue;

      if(StringFind(ordInfo.Comment(), "BUY_GRID_")  == 0) hasBuyPending  = true;
      if(StringFind(ordInfo.Comment(), "SELL_GRID_") == 0) hasSellPending = true;
   }

   // Cancel orphaned BUY limits — pending buys with no active buy position
   if(hasBuyPending && !hasActiveBuys)
   {
      Print("ORPHAN CLEANUP: BUY limits found with no active BUY position → cancelling.");
      CancelPendingByComment("BUY_GRID_");
   }

   // Cancel orphaned SELL limits — pending sells with no active sell position
   if(hasSellPending && !hasActiveSells)
   {
      Print("ORPHAN CLEANUP: SELL limits found with no active SELL position → cancelling.");
      CancelPendingByComment("SELL_GRID_");
   }
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
//| END OF EA v3.7                                                   |
//+------------------------------------------------------------------+
