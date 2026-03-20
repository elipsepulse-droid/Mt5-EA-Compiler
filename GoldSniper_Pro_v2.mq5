//+------------------------------------------------------------------+
//|         EA_Scalping_Grid_GOLD_BTC_v3.9.mq5                       |
//|     Universal Grid Scalping Robot - XAUUSD & BTCUSD M5           |
//|                                                                  |
//|  v3.9 MAJOR UPGRADE — 14 New Improvements:                       |
//|  1.  Spread Filter          — skip entry if spread too wide      |
//|  2.  ATR Dynamic Spacing    — spacing adapts to volatility       |
//|  3.  ATR Dynamic Stop Loss  — SL adapts to current volatility    |
//|  4.  Volatility Shield      — pause if market in chaos mode      |
//|  5.  MACD Confirmation      — second entry confirmation          |
//|  6.  Breakeven Stop         — lock entry price once in profit    |
//|  7.  Dynamic Lot Sizing     — auto lot based on balance %        |
//|  8.  Volume Filter          — skip entry on dead/low volume      |
//|  9.  Candle Confirmation    — 2-bar RSI signal confirmation      |
//|  10. ADX Adaptive Grid Size — grid size based on trend strength  |
//|  11. Partial Take Profit    — close 50% at 1x, rest at 2x       |
//|  12. Re-Entry Logic         — re-enter after profitable grid     |
//|  13. Grid Recovery          — recover after SL hit               |
//|  14. Better Risk-Reward     — improved TP/SL ratio               |
//|                                                                  |
//|  RETAINED FROM v3.7:                                             |
//|  - RSI 30/70 entry levels                                        |
//|  - EMA(100/300) trend filter                                     |
//|  - EMA(50/200) exit signal                                       |
//|  - Option 1 Smart Bypass (RSI 25/75)                             |
//|  - Live Dashboard (updated)                                      |
//|  - Debug logging                                                 |
//|  - Auto symbol/account detection                                 |
//|  - Orphan pending order cleanup                                  |
//+------------------------------------------------------------------+
#property copyright   "EA SCALPING ROBOT / DANE - v4.1"
#property version     "4.10"
#property description "Grid EA v4.1 — News Filter + Regime Detection + RSI Divergence"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//==========================================================================
//  INPUTS
//==========================================================================

input group "====== ★ LOT SIZE QUICK CONTROL ★ ======"
// ★ THIS IS THE FIRST THING YOU SEE — Change lot size here easily ★
// STEP 1: Choose your mode below
// STEP 2a (MANUAL): Set InpUseDynamicLot=false → change InpLotSize to your desired lot
// STEP 2b (AUTO):   Set InpUseDynamicLot=true  → EA calculates lot from your balance %
input bool   InpUseDynamicLot  = true;   // true=AUTO lot | false=MANUAL lot
input double InpLotSize        = 0.01;   // ← MANUAL LOT: change this (only used when AUTO=false)
input double InpRiskPercent    = 1.0;    // ← AUTO LOT: risk % per grid (only used when AUTO=true)
input double InpMinLot         = 0.01;   // Auto lot minimum cap
input double InpMaxLot         = 1.00;   // Auto lot maximum cap

input group "====== SYMBOL MODE ======"
input bool InpAutoDetect = true;

input group "====== GRID SETUP ======"
input int    InpGridSize       = 4;
input double InpSpacingPips    = 80;
input bool   InpMoveGrid       = true;

input group "====== TRADE MANAGEMENT ======"
input bool   InpTPPerTrade       = true;
input double InpTPMultiplier     = 1.0;   // First partial TP at 1x spacing
input double InpTP2Multiplier    = 2.0;   // Second partial TP at 2x spacing (remaining 50%)
input bool   InpCloseAtMaxProfit = true;
input double InpMaxProfitMult    = 4.0;
input double InpGridSLMult       = 6.0;

input group "====== IMPROVEMENT 1: SPREAD FILTER ======"
input bool   InpUseSpreadFilter  = true;
input double InpMaxSpreadPips    = 20.0;  // Skip entry if spread > 20 pips

input group "====== IMPROVEMENT 2+3: ATR DYNAMIC SPACING & SL ======"
input bool   InpUseATR           = true;
input int    InpATR_Period        = 14;
input double InpATR_SpacingMult  = 0.7;  // Spacing = ATR x 0.7
input double InpATR_SLMult       = 2.0;  // Dynamic SL = ATR x 2.0

input group "====== IMPROVEMENT 4: VOLATILITY SHIELD ======"
input bool   InpUseVolShield     = true;
input double InpVolShieldMult    = 2.5;  // Pause if ATR > 2.5x its average

input group "====== IMPROVEMENT 5: MACD CONFIRMATION ======"
input bool   InpUseMACD          = true;
input int    InpMACD_Fast         = 12;
input int    InpMACD_Slow         = 26;
input int    InpMACD_Signal       = 9;

input group "====== IMPROVEMENT 6: BREAKEVEN STOP ======"
input bool   InpUseBreakeven     = true;
input double InpBreakevenPips    = 20.0; // Move SL to entry after 20 pips profit

input group "====== TRAILING STOP ======"
input bool   InpUseTrailing      = true;  // Enable trailing stop
input double InpTrailStartPips   = 40.0;  // Trail activates after X pips profit
input double InpTrailStepPips    = 20.0;  // Trail step size in pips

input group "====== IMPROVEMENT 7: DYNAMIC LOT SIZING ======"
// Lot size is controlled at the TOP of inputs — ★ LOT SIZE QUICK CONTROL ★
// No settings here — scroll to top to change lot size

input group "====== IMPROVEMENT 8: VOLUME FILTER ======"
input bool   InpUseVolFilter     = true;
input double InpMinVolMultiplier = 0.7;  // Skip if volume < 70% of average

input group "====== IMPROVEMENT 9: CANDLE CONFIRMATION ======"
input bool   InpUseCandleConfirm = true; // Wait 2 bars to confirm RSI signal

input group "====== IMPROVEMENT 10: ADX ADAPTIVE GRID SIZE ======"
input bool   InpUseADX           = true;
input int    InpADX_Period        = 14;
input double InpADX_Weak          = 20.0; // ADX < 20 = weak trend → 2 orders
input double InpADX_Strong        = 35.0; // ADX > 35 = strong trend → full grid

input group "====== IMPROVEMENT 12: RE-ENTRY AFTER PROFIT ======"
input bool   InpUseReEntry       = true;
input int    InpReEntryBars      = 3;    // Re-enter if signal still valid after X bars

input group "====== IMPROVEMENT 13: GRID RECOVERY ======"
input bool   InpUseRecovery      = true;
input double InpRecoveryLotMult  = 0.5;

input group "====== v4.1: NEWS FILTER (Manual Time Block) ======"
// EA automatically pauses new entries during high-impact news windows
// All times are GMT (Exness server time) — subtract 8hrs for PHT
// Example: GMT 12:30 = PHT 8:30 PM
input bool   InpUseNewsFilter    = true;  // Enable news time filter
input bool   InpBlockNFP         = true;  // Block 1st Friday 12:20-13:00 GMT (NFP)
input bool   InpBlockFed         = true;  // Block Wednesday 18:00-18:30 GMT (Fed — 8x/year)
input bool   InpBlockCPI         = true;  // Block 2nd/3rd Wed 12:20-13:00 GMT (CPI)
input bool   InpBlockThursday    = true;  // Block Thursday 12:20-12:50 GMT (Jobless Claims)
input int    InpNewsBufferMins   = 30;    // Minutes before AND after news to pause

input group "====== v4.1: MARKET REGIME DETECTION ======"
// ADX-based regime switch — changes strategy based on trend strength
// Ranging (ADX<25): Normal RSI strategy
// Trending (ADX 25-40): Hybrid — trend pullback entries added
// Extreme (ADX>40): Momentum mode — relax SELL/BUY levels for faster entry
input bool   InpUseRegime        = true;
input double InpADX_Ranging      = 25.0;  // Below = ranging market
input double InpADX_Trending     = 40.0;  // Above = extreme trend mode
input double InpRSI_ExtremeBuy   = 40.0;  // RSI BUY level in extreme DOWNTREND (ADX>40)
input double InpRSI_ExtremeSell  = 60.0;  // RSI SELL level in extreme UPTREND (ADX>40)

input group "====== v4.1: RSI DIVERGENCE EXIT ======"
// Detects when trend is exhausted — warns before reversal
// Bullish divergence: price lower low BUT RSI higher low = downtrend weakening
// Bearish divergence: price higher high BUT RSI lower high = uptrend weakening
input bool   InpUseDivergence    = true;  // Enable divergence detection
input int    InpDivLookback      = 5;     // Bars to look back for divergence

input group "====== ENTRY SIGNAL: RSI ======"
input int                InpRSI_Period  = 14;
input ENUM_APPLIED_PRICE InpRSI_Price   = PRICE_CLOSE;
input int                InpRSI_Shift   = 1;
input double             InpRSI_BuyLvl  = 30.0;
input double             InpRSI_SellLvl = 70.0;

input group "====== OPTION 1: EXTREME RSI BYPASS ======"
input double InpExtremeRSILow  = 25.0;
input double InpExtremeRSIHigh = 75.0;

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
input bool   InpShowDashboard = true;
input int    InpDashX         = 10;
input int    InpDashY         = 20;

input group "====== GENERAL ======"
input bool  InpDebugLog    = true;
input ulong InpMagicNumber = 654321;
input int   InpSlippage    = 50;

//==========================================================================
//  GLOBALS
//==========================================================================
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    ordInfo;

// Indicator handles
int rsi_handle, tf_fast_handle, tf_slow_handle;
int exit_fast_handle, exit_slow_handle;
int atr_handle, macd_handle, adx_handle;

// Runtime settings (auto-set)
double g_spacingPips, g_spacingPoints;
int    g_gridSize;
double g_lotSize;
double g_rsiBuyLvl, g_rsiSellLvl;
double g_trailStartPips, g_trailStepPips;
double g_trailStartPoints, g_trailStepPoints;
double g_maxProfitMult, g_gridSLMult;
double g_breakevenPoints;

// Account/symbol flags
bool   g_isBTC = false, g_isGold = false, g_isCentAcct = false;
string g_currency = "USD";
double g_activeLot = 0.01;

// v4.1 — News filter state
bool   g_newsActive    = false;   // true = news window active, block new entries
string g_newsEventName = "";      // name of current news event for dashboard/log

// v4.1 — Market regime state
// 0=ranging, 1=trending, 2=extreme trend
int    g_marketRegime  = 0;
string g_regimeName    = "RANGING";

// v4.1 — RSI Divergence state
bool   g_bullDivergence = false;  // Bullish divergence detected — downtrend weakening
bool   g_bearDivergence = false;  // Bearish divergence detected — uptrend weakening

// Candle confirmation tracking
bool     g_buySignalPending  = false;
bool     g_sellSignalPending = false;
int      g_signalBarsCount   = 0;
datetime g_signalBarTime     = 0;

// Re-entry tracking
bool     g_lastGridWasProfitable = false;
datetime g_lastGridCloseTime     = 0;
int      g_lastGridDirection     = 0; // 1=buy, -1=sell

// Recovery tracking
bool   g_recoveryMode      = false;
int    g_recoveryDirection = 0;
double g_recoveryEntryPrice = 0;

// Profit tracking
datetime g_lastBarTime        = 0;
datetime g_currentDay         = 0;
datetime g_currentWeek        = 0;
double   g_dailyStartBalance  = 0;
double   g_weeklyStartBalance = 0;
double   g_lastGridProfit     = 0;

// Partial TP tracking
bool g_partialTPDone[];  // tracks per position if 50% already closed

#define DASH_PREFIX "DANE_DASH_"

//==========================================================================
//  INIT
//==========================================================================
int OnInit()
{
   string sym = _Symbol;
   StringToUpper(sym);
   g_isBTC  = (StringFind(sym,"BTC") >= 0);
   g_isGold = (StringFind(sym,"XAU") >= 0 || StringFind(sym,"GOLD") >= 0);

   g_currency = AccountInfoString(ACCOUNT_CURRENCY);
   string cur = g_currency; StringToUpper(cur);
   g_isCentAcct = (StringFind(cur,"USC") >= 0 || StringFind(cur,"CENT") >= 0);

   // Safe balance load with retry
   double safeBalance = 0;
   for(int i=0; i<10; i++)
   { safeBalance = AccountInfoDouble(ACCOUNT_BALANCE); if(safeBalance>0) break; Sleep(100); }
   if(safeBalance <= 0) safeBalance = AccountInfoDouble(ACCOUNT_EQUITY);

   // Apply symbol presets
   if(InpAutoDetect)
   {
      if(g_isBTC)
      {
         g_spacingPips    = 250;
         g_gridSize       = g_isCentAcct ? 3 : 5;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = 30.0; g_rsiSellLvl = 70.0;
         g_trailStartPips = 100.0; g_trailStepPips = 50.0;
         g_maxProfitMult  = 4.0; g_gridSLMult = 5.0;
      }
      else if(g_isGold)
      {
         g_spacingPips    = 80;
         g_gridSize       = g_isCentAcct ? 4 : 6;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = 30.0; g_rsiSellLvl = 70.0;
         g_trailStartPips = 40.0; g_trailStepPips = 20.0;
         g_maxProfitMult  = 4.0; g_gridSLMult = g_isCentAcct ? 5.0 : 6.0;
      }
      else
      {
         g_spacingPips    = InpSpacingPips; g_gridSize = InpGridSize;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = InpRSI_BuyLvl; g_rsiSellLvl = InpRSI_SellLvl;
         g_trailStartPips = 40.0; g_trailStepPips = 20.0;
         g_maxProfitMult  = InpMaxProfitMult; g_gridSLMult = InpGridSLMult;
      }
   }
   else
   {
      g_spacingPips    = InpSpacingPips; g_gridSize = InpGridSize;
      g_lotSize        = InpLotSize;
      g_rsiBuyLvl      = InpRSI_BuyLvl; g_rsiSellLvl = InpRSI_SellLvl;
      g_trailStartPips = 40.0; g_trailStepPips = 20.0;
      g_maxProfitMult  = InpMaxProfitMult; g_gridSLMult = InpGridSLMult;
   }

   // Pip size detection
   double pipSize;
   if(_Digits==3||_Digits==2) pipSize = 0.100;
   else if(_Digits==5)        pipSize = 0.00010;
   else if(_Digits==4)        pipSize = 0.0010;
   else                       pipSize = _Point*10.0;

   g_spacingPoints    = g_spacingPips    * pipSize;
   // Use InpTrailStartPips/InpTrailStepPips from inputs — overrides preset defaults
   g_trailStartPoints = InpTrailStartPips * pipSize;
   g_trailStepPoints  = InpTrailStepPips  * pipSize;
   g_breakevenPoints  = InpBreakevenPips  * pipSize;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Create all indicator handles
   rsi_handle       = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, InpRSI_Price);
   tf_fast_handle   = iMA(_Symbol, PERIOD_CURRENT, InpTF_FastPeriod, 0, InpTF_FastMethod, InpTF_Price);
   tf_slow_handle   = iMA(_Symbol, PERIOD_CURRENT, InpTF_SlowPeriod, 0, InpTF_SlowMethod, InpTF_Price);
   exit_fast_handle = iMA(_Symbol, PERIOD_CURRENT, InpExit_FastPeriod, 0, InpExit_FastMethod, InpExit_Price);
   exit_slow_handle = iMA(_Symbol, PERIOD_CURRENT, InpExit_SlowPeriod, 0, InpExit_SlowMethod, InpExit_Price);
   atr_handle       = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
   macd_handle      = iMACD(_Symbol, PERIOD_CURRENT, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   adx_handle       = iADX(_Symbol, PERIOD_CURRENT, InpADX_Period);

   if(rsi_handle==INVALID_HANDLE || tf_fast_handle==INVALID_HANDLE ||
      tf_slow_handle==INVALID_HANDLE || exit_fast_handle==INVALID_HANDLE ||
      exit_slow_handle==INVALID_HANDLE || atr_handle==INVALID_HANDLE ||
      macd_handle==INVALID_HANDLE || adx_handle==INVALID_HANDLE)
   { Alert("EA v3.9 ERROR: Indicator handle failed!"); return INIT_FAILED; }

   g_dailyStartBalance  = safeBalance;
   g_weeklyStartBalance = safeBalance;
   g_currentDay  = GetDayStart();
   g_currentWeek = GetWeekStart();

   if(InpShowDashboard) CreateDashboard();

   Print("=== EA GRID v4.1 INITIALIZED on ", _Symbol, " ===");
   Print("v4.1: News Filter | Market Regime Detection | RSI Divergence Exit");
   Print("Account  : ", (g_isCentAcct?"CENT (USC)":"STANDARD (USD)"),
         " | Balance: ", DoubleToString(safeBalance,2), " ", g_currency);
   Print("Symbol   : ", _Symbol, " | Grid: ", g_gridSize,
         " orders | Spacing: ", g_spacingPips, " pips");
   if(InpUseDynamicLot)
      Print("Lot Mode : AUTO (", InpRiskPercent, "% risk) | Min=", InpMinLot,
            " Max=", InpMaxLot, " | Set InpUseDynamicLot=false to use manual lot");
   else
      Print("Lot Mode : MANUAL — fixed at ", InpLotSize,
            " lots | Set InpUseDynamicLot=true for auto sizing");
   Print("RSI      : BUY=", g_rsiBuyLvl, " SELL=", g_rsiSellLvl,
         " | Bypass: <", InpExtremeRSILow, " / >", InpExtremeRSIHigh);
   Print("v3.9 Upgrades: ATR=", InpUseATR, " MACD=", InpUseMACD,
         " Spread=", InpUseSpreadFilter, " ADX=", InpUseADX,
         " Breakeven=", InpUseBreakeven, " DynLot=", InpUseDynamicLot,
         " VolShield=", InpUseVolShield);

   return INIT_SUCCEEDED;
}

//==========================================================================
//  DEINIT
//==========================================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(rsi_handle);   IndicatorRelease(tf_fast_handle);
   IndicatorRelease(tf_slow_handle); IndicatorRelease(exit_fast_handle);
   IndicatorRelease(exit_slow_handle); IndicatorRelease(atr_handle);
   IndicatorRelease(macd_handle);  IndicatorRelease(adx_handle);
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
   ManageBreakevenStop();
   ManagePartialTP();
   CleanOrphanedPending();
   if(InpShowDashboard) UpdateDashboard();

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   // Load all indicator buffers
   int bars = MathMax(MathMax(InpRSI_Shift, InpTF_Shift), InpExit_Shift) + 15;

   double rsi_val[], tf_fast[], tf_slow[], exit_fast[], exit_slow[];
   double atr_val[], macd_main[], macd_sig[], adx_val[];
   ArraySetAsSeries(rsi_val,true); ArraySetAsSeries(tf_fast,true);
   ArraySetAsSeries(tf_slow,true); ArraySetAsSeries(exit_fast,true);
   ArraySetAsSeries(exit_slow,true); ArraySetAsSeries(atr_val,true);
   ArraySetAsSeries(macd_main,true); ArraySetAsSeries(macd_sig,true);
   ArraySetAsSeries(adx_val,true);

   if(CopyBuffer(rsi_handle,0,0,bars,rsi_val)<bars)
   { if(InpDebugLog) Print("DEBUG: RSI buffer not ready."); return; }
   if(CopyBuffer(tf_fast_handle,0,0,bars,tf_fast)<bars)
   { if(InpDebugLog) Print("DEBUG: TF Fast MA not ready."); return; }
   if(CopyBuffer(tf_slow_handle,0,0,bars,tf_slow)<bars)
   { if(InpDebugLog) Print("DEBUG: TF Slow MA not ready."); return; }
   if(CopyBuffer(exit_fast_handle,0,0,bars,exit_fast)<bars) return;
   if(CopyBuffer(exit_slow_handle,0,0,bars,exit_slow)<bars) return;
   if(CopyBuffer(atr_handle,0,0,bars,atr_val)<bars) return;
   if(CopyBuffer(macd_handle,0,0,bars,macd_main)<bars) return;
   if(CopyBuffer(macd_handle,1,0,bars,macd_sig)<bars) return;
   if(CopyBuffer(adx_handle,0,0,bars,adx_val)<bars) return;

   bool hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
   bool hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);

   //===================================================================
   //  v4.1 — NEWS FILTER CHECK (runs every new bar)
   //  Blocks all new entries during high-impact news windows
   //  Shows event name on dashboard and in Experts log
   //===================================================================
   g_newsActive = IsNewsTime();
   if(g_newsActive)
   {
      if(InpDebugLog) Print("📰 NEWS FILTER ACTIVE: ", g_newsEventName,
                            " — no new entries until news window clears.");
      return; // Skip all entry logic during news
   }

   //===================================================================
   //  v4.1 — MARKET REGIME DETECTION
   //  Adjusts RSI entry levels based on ADX trend strength
   //===================================================================
   double effectiveBuyLvl  = g_rsiBuyLvl;
   double effectiveSellLvl = g_rsiSellLvl;
   DetectMarketRegime(adx_val[1], effectiveBuyLvl, effectiveSellLvl);

   //===================================================================
   //  v4.1 — RSI DIVERGENCE DETECTION
   //  Load close prices for divergence check
   //===================================================================
   double close_val[];
   ArraySetAsSeries(close_val, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, InpDivLookback+5, close_val) >= InpDivLookback+5)
      DetectRSIDivergence(rsi_val, close_val);

   // If bullish divergence detected — block new SELL entries (reversal warning)
   // If bearish divergence detected — block new BUY entries (reversal warning)
   if(g_bullDivergence && hasSells)
   {
      if(InpDebugLog) Print("🟢 Divergence: Blocking SELL entries — downtrend may reverse soon.");
   }
   if(g_bearDivergence && hasBuys)
   {
      if(InpDebugLog) Print("🔴 Divergence: Blocking BUY entries — uptrend may reverse soon.");
   }

   //===================================================================
   //  IMPROVEMENT 1 — SPREAD FILTER
   //  Skip everything if spread is too wide
   //===================================================================
   if(InpUseSpreadFilter)
   {
      double spreadPips = GetCurrentSpreadPips();
      if(spreadPips > InpMaxSpreadPips)
      {
         if(InpDebugLog) Print("SPREAD FILTER: Spread=", DoubleToString(spreadPips,1),
                               " pips > limit of ", InpMaxSpreadPips, " — skipping entry.");
         return;
      }
   }

   //===================================================================
   //  IMPROVEMENT 4 — VOLATILITY SHIELD
   //  Pause if ATR is in chaos mode (2.5x above average)
   //===================================================================
   if(InpUseVolShield)
   {
      double curATR = atr_val[1];
      double avgATR = 0;
      for(int i=1; i<=14; i++) avgATR += atr_val[i];
      avgATR /= 14.0;
      if(curATR > avgATR * InpVolShieldMult)
      {
         if(InpDebugLog) Print("VOLATILITY SHIELD: Market in CHAOS mode. ATR=",
                               DoubleToString(curATR,4), " > ", InpVolShieldMult,
                               "x avg (", DoubleToString(avgATR,4), ") — pausing entries.");
         return;
      }
   }

   //===================================================================
   //  EXIT SIGNALS
   //===================================================================
   if(hasBuys || hasSells)
   {
      int s = InpExit_Shift;
      bool xBear = (exit_fast[s] < exit_slow[s] && exit_fast[s+1] >= exit_slow[s+1]);
      bool xBull = (exit_fast[s] > exit_slow[s] && exit_fast[s+1] <= exit_slow[s+1]);
      if(xBear && hasBuys)
      { ClosePositionsByType(POSITION_TYPE_BUY);  CancelPendingByComment("BUY_GRID_"); }
      if(xBull && hasSells)
      { ClosePositionsByType(POSITION_TYPE_SELL); CancelPendingByComment("SELL_GRID_"); }
      hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
      hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);
   }

   //===================================================================
   //  IMPROVEMENT 2 — ATR DYNAMIC SPACING
   //  Recalculate spacing based on current volatility
   //===================================================================
   if(InpUseATR)
   {
      double curATR = atr_val[1];
      g_spacingPoints = curATR * InpATR_SpacingMult;
      // Keep spacing within reasonable bounds
      double pipSize = (_Digits==3||_Digits==2) ? 0.100 : _Point*10.0;
      double minSpacing = 40.0 * pipSize;  // minimum 40 pips
      double maxSpacing = 200.0 * pipSize; // maximum 200 pips
      if(g_spacingPoints < minSpacing) g_spacingPoints = minSpacing;
      if(g_spacingPoints > maxSpacing) g_spacingPoints = maxSpacing;
   }

   //===================================================================
   //  IMPROVEMENT 10 — ADX ADAPTIVE GRID SIZE
   //  Adjust number of grid orders based on trend strength
   //===================================================================
   int adaptiveGridSize = g_gridSize;
   if(InpUseADX)
   {
      double curADX = adx_val[1];
      if(curADX < InpADX_Weak)
         adaptiveGridSize = 2;  // Weak trend → only 2 orders
      else if(curADX >= InpADX_Weak && curADX < InpADX_Strong)
         adaptiveGridSize = 3;  // Medium trend → 3 orders
      else
         adaptiveGridSize = g_gridSize; // Strong trend → full grid
   }

   //===================================================================
   //  IMPROVEMENT 7 — LOT SIZE CALCULATION
   //  Mode A (InpUseDynamicLot=false): uses InpLotSize EXACTLY as entered
   //  Mode B (InpUseDynamicLot=true):  auto-calculates from 1% risk
   //                                    but always respects InpMinLot/InpMaxLot
   //===================================================================
   double activeLot = InpLotSize; // Default: always start with manual lot
   if(InpUseDynamicLot)
   {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt  = balance * (InpRiskPercent / 100.0);
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double pipVal   = (tickVal/tickSize) * g_spacingPoints;
      if(pipVal > 0)
      {
         activeLot = NormalizeDouble(riskAmt / pipVal, 2);
         // Always respect user-defined min and max — manual control preserved
         activeLot = MathMax(InpMinLot, MathMin(InpMaxLot, activeLot));
         // Also never go below broker minimum lot
         double brokerMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double brokerMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         activeLot = MathMax(brokerMin, MathMin(brokerMax, activeLot));
      }
      else
         activeLot = InpLotSize; // Fallback to manual if calculation fails
   }
   // Store for dashboard display — always shows what lot will actually be used
   g_activeLot = activeLot;

   //===================================================================
   //  TREND FILTER — EMA(100) vs EMA(300)
   //===================================================================
   bool tUp = (tf_fast[InpTF_Shift] > tf_slow[InpTF_Shift]);
   bool tDn = (tf_fast[InpTF_Shift] < tf_slow[InpTF_Shift]);

   //===================================================================
   //  RSI ENTRY SIGNALS — using regime-adjusted levels
   //  Normal: 30/70 | Extreme trend: 40/60 (from regime detection)
   //===================================================================
   int rs = InpRSI_Shift;
   double currentRSI = rsi_val[rs];
   double prevRSI    = rsi_val[rs+1];

   // Use effective levels from regime detection (v4.1)
   bool rsiBuyCross  = (currentRSI >  effectiveBuyLvl  && prevRSI <= effectiveBuyLvl);
   bool rsiSellCross = (currentRSI <  effectiveSellLvl && prevRSI >= effectiveSellLvl);

   //===================================================================
   //  OPTION 1 — EXTREME RSI BYPASS FLAGS
   //  Calculated BEFORE candle confirmation and MACD
   //  so bypass can override those restrictions
   //===================================================================
   bool extremeOversold   = (prevRSI < InpExtremeRSILow);
   bool extremeOverbought = (prevRSI > InpExtremeRSIHigh);

   //===================================================================
   //  IMPROVEMENT 9 — CANDLE CONFIRMATION
   //  Normal mode: wait 2 bars to confirm signal is real
   //  Bypass mode: wait only 1 bar — extreme moves are real, not fake
   //  FIX v4.0: During bypass, 1 bar is enough — price already moved
   //  100+ pips proving the move is genuine
   //===================================================================
   int requiredBars = (extremeOversold || extremeOverbought) ? 1 : 2;

   if(InpUseCandleConfirm)
   {
      if(rsiBuyCross  && !g_buySignalPending)
      { g_buySignalPending  = true; g_signalBarsCount = 0; g_signalBarTime = currentBar; }
      if(rsiSellCross && !g_sellSignalPending)
      { g_sellSignalPending = true; g_signalBarsCount = 0; g_signalBarTime = currentBar; }

      if(g_buySignalPending  || g_sellSignalPending) g_signalBarsCount++;

      // Use effectiveBuyLvl/SellLvl (regime-adjusted) for consistency
      bool buyConfirmed  = g_buySignalPending  && g_signalBarsCount >= requiredBars && currentRSI > effectiveBuyLvl;
      bool sellConfirmed = g_sellSignalPending && g_signalBarsCount >= requiredBars && currentRSI < effectiveSellLvl;

      // Reset if RSI reverses before confirmation (use effective levels)
      if(g_buySignalPending  && currentRSI < effectiveBuyLvl  - 5)
      { g_buySignalPending  = false; g_signalBarsCount = 0; }
      if(g_sellSignalPending && currentRSI > effectiveSellLvl + 5)
      { g_sellSignalPending = false; g_signalBarsCount = 0; }

      if(buyConfirmed)  { rsiBuyCross  = true; g_buySignalPending  = false; }
      else              { rsiBuyCross  = false; }
      if(sellConfirmed) { rsiSellCross = true; g_sellSignalPending = false; }
      else              { rsiSellCross = false; }
   }

   //===================================================================
   //  IMPROVEMENT 5 — MACD CONFIRMATION
   //  Normal mode: MACD must agree with signal direction
   //  Bypass mode: MACD is IGNORED — during extreme RSI levels
   //  MACD will always be deeply negative (oversold) or positive
   //  (overbought). Requiring MACD confirmation in bypass mode
   //  is contradictory and will always block the trade.
   //  FIX v4.0: Skip MACD check entirely when bypass is active
   //===================================================================
   bool macdBullish = true, macdBearish = true;
   if(InpUseMACD && !extremeOversold && !extremeOverbought)
   {
      // Only check MACD in NORMAL mode — bypass overrides MACD
      double macdHist1 = macd_main[1] - macd_sig[1];
      double macdHist2 = macd_main[2] - macd_sig[2];
      macdBullish = (macdHist1 > 0 || macdHist1 > macdHist2);
      macdBearish = (macdHist1 < 0 || macdHist1 < macdHist2);
      if(InpDebugLog && (macdBullish==false || macdBearish==false))
         Print("  MACD filter active (normal mode): H=",DoubleToString(macdHist1,5));
   }
   else if(extremeOversold || extremeOverbought)
   {
      // Bypass mode — MACD ignored, both set to true
      macdBullish = true;
      macdBearish = true;
      if(InpDebugLog)
         Print("  MACD bypassed — extreme RSI mode (prev RSI=",DoubleToString(prevRSI,2),")");
   }

   //===================================================================
   //  IMPROVEMENT 8 — VOLUME FILTER
   //===================================================================
   bool volumeOK = true;
   if(InpUseVolFilter)
   {
      long curVol = iVolume(_Symbol, PERIOD_CURRENT, 1);
      double avgVol = 0;
      for(int i=1; i<=14; i++) avgVol += (double)iVolume(_Symbol, PERIOD_CURRENT, i);
      avgVol /= 14.0;
      volumeOK = (avgVol > 0 && curVol >= avgVol * InpMinVolMultiplier);
      if(!volumeOK && InpDebugLog)
         Print("VOLUME FILTER: Low volume — skipping entry.");
   }

   //===================================================================
   //  COMBINED ENTRY DECISION — v4.1
   //  Added: divergence block — don't open new grids against divergence
   //  Added: regime-adjusted RSI levels already in rsiBuyCross/rsiSellCross
   //===================================================================
   bool doOpenBuy  = rsiBuyCross  && macdBullish && volumeOK &&
                     (tUp || extremeOversold) && !hasBuys &&
                     !g_bearDivergence;  // v4.1: don't buy into bearish divergence
   bool doOpenSell = rsiSellCross && macdBearish && volumeOK &&
                     (tDn || extremeOverbought) && !hasSells &&
                     !g_bullDivergence;  // v4.1: don't sell into bullish divergence
                     (tDn || extremeOverbought) && !hasSells;

   //===================================================================
   //  IMPROVEMENT 12 — RE-ENTRY AFTER PROFITABLE GRID
   //  If last grid was profitable and trend still strong → re-enter
   //===================================================================
   if(InpUseReEntry && g_lastGridWasProfitable && !hasBuys && !hasSells)
   {
      datetime timeSinceClose = currentBar - g_lastGridCloseTime;
      int barsSinceClose = (int)(timeSinceClose / PeriodSeconds(PERIOD_CURRENT));

      if(barsSinceClose <= InpReEntryBars)
      {
         // Re-enter in same direction if trend still agrees
         if(g_lastGridDirection == 1 && tUp && !hasBuys)
         {
            if(InpDebugLog) Print("RE-ENTRY: Last grid was profitable. Re-entering BUY grid (trend still UP).");
            OpenBuyGrid(activeLot, adaptiveGridSize);
            g_lastGridWasProfitable = false;
            return;
         }
         if(g_lastGridDirection == -1 && tDn && !hasSells)
         {
            if(InpDebugLog) Print("RE-ENTRY: Last grid was profitable. Re-entering SELL grid (trend still DOWN).");
            OpenSellGrid(activeLot, adaptiveGridSize);
            g_lastGridWasProfitable = false;
            return;
         }
      }
      else g_lastGridWasProfitable = false; // Expired — reset
   }

   //===================================================================
   //  IMPROVEMENT 13 — GRID RECOVERY MODE
   //  After a Grid SL hit, watch for recovery opportunity
   //===================================================================
   if(InpUseRecovery && g_recoveryMode && !hasBuys && !hasSells)
   {
      double currentPrice = (g_recoveryDirection==1)
                            ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double recoveryLot = NormalizeDouble(activeLot * InpRecoveryLotMult, 2);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(recoveryLot < minLot) recoveryLot = minLot;

      // Re-enter with reduced lot after SL hit if signal confirms
      if(g_recoveryDirection == 1 && rsiBuyCross && (tUp || extremeOversold))
      {
         if(InpDebugLog) Print("RECOVERY: Opening reduced BUY grid after previous SL.");
         OpenBuyGrid(recoveryLot, 2); // only 2 orders in recovery
         g_recoveryMode = false;
         return;
      }
      if(g_recoveryDirection == -1 && rsiSellCross && (tDn || extremeOverbought))
      {
         if(InpDebugLog) Print("RECOVERY: Opening reduced SELL grid after previous SL.");
         OpenSellGrid(recoveryLot, 2);
         g_recoveryMode = false;
         return;
      }
   }

   //===================================================================
   //  DEBUG LOG
   //===================================================================
   if(InpDebugLog)
   {
      string trendStr  = tUp ? "UPTREND" : (tDn ? "DOWNTREND" : "FLAT");
      string bypassStr = extremeOversold  ? " [BYPASS:oversold<"+DoubleToString(InpExtremeRSILow,0)+"]"
                       : extremeOverbought ? " [BYPASS:overbought>"+DoubleToString(InpExtremeRSIHigh,0)+"]"
                       : "";
      double spreadNow = GetCurrentSpreadPips();
      Print("--- NEW BAR --- RSI=", DoubleToString(currentRSI,2),
            " | MACD_H=", DoubleToString(macd_main[1]-macd_sig[1],5),
            " | ADX=", DoubleToString(adx_val[1],1),
            " | Spread=", DoubleToString(spreadNow,1), "pips",
            " | Trend=", trendStr, bypassStr,
            " | Grid=", adaptiveGridSize, " orders | Lot=", DoubleToString(activeLot,3));
      if(!rsiBuyCross && !rsiSellCross)
         Print("  → Waiting: RSI=", DoubleToString(currentRSI,2),
               " (need cross of ", effectiveBuyLvl, " BUY / ", effectiveSellLvl,
               " SELL | Regime:", g_regimeName, ")");
      else if(doOpenBuy)
         Print("  → BUY ENTRY CONFIRMED: All conditions met! Opening grid.");
      else if(doOpenSell)
         Print("  → SELL ENTRY CONFIRMED: All conditions met! Opening grid.");
   }

   // OPEN GRIDS
   if(doOpenBuy)
   {
      OpenBuyGrid(activeLot, adaptiveGridSize);
      g_lastGridDirection = 1;
   }
   if(doOpenSell)
   {
      OpenSellGrid(activeLot, adaptiveGridSize);
      g_lastGridDirection = -1;
   }
}

//==========================================================================
//  OPEN BUY GRID — with dynamic lot and adaptive grid size
//==========================================================================
void OpenBuyGrid(double lot, int gridSize)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=0; i<gridSize; i++)
   {
      double price = NormalizeDouble(ask - i*g_spacingPoints, _Digits);
      // IMPROVEMENT 11: Partial TP — first target at 1x, rest runs to 2x
      double tp1 = InpTPPerTrade ? NormalizeDouble(price + InpTPMultiplier  * g_spacingPoints, _Digits) : 0;
      string cmt = "BUY_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      if(i==0) trade.Buy(lot, _Symbol, 0, 0, tp1, cmt);
      else     trade.BuyLimit(lot, price, _Symbol, 0, tp1, ORDER_TIME_GTC, 0, cmt);
   }
}

//==========================================================================
//  OPEN SELL GRID — with dynamic lot and adaptive grid size
//==========================================================================
void OpenSellGrid(double lot, int gridSize)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i=0; i<gridSize; i++)
   {
      double price = NormalizeDouble(bid + i*g_spacingPoints, _Digits);
      double tp1 = InpTPPerTrade ? NormalizeDouble(price - InpTPMultiplier  * g_spacingPoints, _Digits) : 0;
      string cmt = "SELL_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      if(i==0) trade.Sell(lot, _Symbol, 0, 0, tp1, cmt);
      else     trade.SellLimit(lot, price, _Symbol, 0, tp1, ORDER_TIME_GTC, 0, cmt);
   }
}

//==========================================================================
//  IMPROVEMENT 6 — BREAKEVEN STOP
//  Once trade is InpBreakevenPips in profit → move SL to entry price
//==========================================================================
void ManageBreakevenStop()
{
   if(!InpUseBreakeven) return;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;
      double op = posInfo.PriceOpen();
      double sl = posInfo.StopLoss();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      {
         // Move SL to entry once profit >= breakeven threshold
         if(bid - op >= g_breakevenPoints && (sl < op - _Point || sl == 0))
            trade.PositionModify(posInfo.Ticket(), op + _Point, posInfo.TakeProfit());
      }
      else if(posInfo.PositionType()==POSITION_TYPE_SELL)
      {
         if(op - ask >= g_breakevenPoints && (sl > op + _Point || sl == 0))
            trade.PositionModify(posInfo.Ticket(), op - _Point, posInfo.TakeProfit());
      }
   }
}

//==========================================================================
//  IMPROVEMENT 11 — PARTIAL TAKE PROFIT
//  Close 50% of position at 1x spacing, let rest run to 2x spacing
//==========================================================================
void ManagePartialTP()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;

      double op  = posInfo.PriceOpen();
      double lot = posInfo.Volume();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double halfLot = NormalizeDouble(lot * 0.5, 2);
      if(halfLot < minLot) continue; // can't close partial below min lot

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      {
         double firstTP = op + InpTPMultiplier  * g_spacingPoints;
         double finalTP = op + InpTP2Multiplier * g_spacingPoints;
         // If price reached first TP — close half and extend TP to 2x
         if(bid >= firstTP && lot > minLot*1.5)
         {
            trade.PositionClosePartial(posInfo.Ticket(), halfLot);
            // Update remaining position TP to 2x spacing
            Sleep(100);
            if(posInfo.SelectByTicket(posInfo.Ticket()))
               trade.PositionModify(posInfo.Ticket(), posInfo.StopLoss(), finalTP);
         }
      }
      else if(posInfo.PositionType()==POSITION_TYPE_SELL)
      {
         double firstTP = op - InpTPMultiplier  * g_spacingPoints;
         double finalTP = op - InpTP2Multiplier * g_spacingPoints;
         if(ask <= firstTP && lot > minLot*1.5)
         {
            trade.PositionClosePartial(posInfo.Ticket(), halfLot);
            Sleep(100);
            if(posInfo.SelectByTicket(posInfo.Ticket()))
               trade.PositionModify(posInfo.Ticket(), posInfo.StopLoss(), finalTP);
         }
      }
   }
}

//==========================================================================
//  TRAILING STOP
//==========================================================================
void ManageTrailingStop()
{
   if(!InpUseTrailing) return;
   if(g_trailStartPoints <= 0) return;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss();
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      { if(bid-op>=g_trailStartPoints){ double nsl=NormalizeDouble(bid-g_trailStepPoints,_Digits);
        if(nsl>sl+_Point) trade.PositionModify(posInfo.Ticket(),nsl,posInfo.TakeProfit()); } }
      else if(posInfo.PositionType()==POSITION_TYPE_SELL)
      { if(op-ask>=g_trailStartPoints){ double nsl=NormalizeDouble(ask+g_trailStepPoints,_Digits);
        if(sl==0||nsl<sl-_Point) trade.PositionModify(posInfo.Ticket(),nsl,posInfo.TakeProfit()); } }
   }
}

//==========================================================================
//  MONITOR GRID PROFIT / SL — with recovery and re-entry tracking
//==========================================================================
void MonitorGridProfit()
{
   if(CountPositions(POSITION_TYPE_BUY)==0 && CountPositions(POSITION_TYPE_SELL)==0) return;

   double totalPnL = GetTotalGridProfit();
   double tv  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // IMPROVEMENT 3 — ATR Dynamic SL value
   double atr_val2[];
   ArraySetAsSeries(atr_val2,true);
   double dynamicSLValue = 0;
   if(InpUseATR && CopyBuffer(atr_handle,0,0,3,atr_val2)>=3)
   {
      double pipVal = (tv/ts) * atr_val2[1];
      dynamicSLValue = InpATR_SLMult * pipVal * g_lotSize;
   }

   double pv   = (tv/ts) * g_spacingPoints;
   double maxP =  g_maxProfitMult * pv * g_lotSize;
   // IMPROVEMENT 14: Use ATR-based SL if available, otherwise fixed
   double maxL = (dynamicSLValue > 0) ? -dynamicSLValue : -(g_gridSLMult * pv * g_lotSize);

   if(InpCloseAtMaxProfit && totalPnL >= maxP)
   {
      Print("✅ MAX PROFIT: ", DoubleToString(totalPnL,2), " ", g_currency, " → Closing grid.");
      // Track for re-entry
      g_lastGridWasProfitable = true;
      g_lastGridProfit        = totalPnL;
      g_lastGridCloseTime     = TimeCurrent();
      g_recoveryMode          = false;
      CloseAllGridOrders();
      return;
   }

   if(totalPnL <= maxL)
   {
      Print("🛑 GRID SL: ", DoubleToString(totalPnL,2), " ", g_currency, " → Closing grid.");
      // IMPROVEMENT 13: Activate recovery mode after SL hit
      if(InpUseRecovery)
      {
         g_recoveryMode      = true;
         g_recoveryDirection = (CountPositions(POSITION_TYPE_BUY) > 0) ? 1 : -1;
      }
      g_lastGridWasProfitable = false;
      CloseAllGridOrders();
   }
}

//==========================================================================
//  SPREAD HELPER
//==========================================================================
double GetCurrentSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pipSize = (_Digits==3||_Digits==2) ? 0.100 : _Point*10.0;
   return (ask - bid) / pipSize;
}

//==========================================================================
//  v4.1 — NEWS FILTER
//  Checks if current GMT time falls within a known high-impact news window
//  All windows use GMT (Exness server time)
//  PHT = GMT + 8 hours
//
//  SCHEDULE (GMT times):
//  NFP        : 1st Friday each month  12:20–13:00 GMT = 8:20–9:00 PM PHT
//  Fed Rate   : 8x/year Wednesday      18:00–18:30 GMT = 2:00–2:30 AM PHT
//  CPI        : Monthly ~2nd Wed       12:20–13:00 GMT = 8:20–9:00 PM PHT
//  Jobless    : Every Thursday         12:20–12:50 GMT = 8:20–8:50 PM PHT
//==========================================================================
bool IsNewsTime()
{
   if(!InpUseNewsFilter) return false;

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h   = dt.hour;
   int m   = dt.min;
   int dow = dt.day_of_week; // 0=Sun,1=Mon,2=Tue,3=Wed,4=Thu,5=Fri,6=Sat
   int dom = dt.day;         // day of month 1-31
   int totalMins = h * 60 + m;
   int buf = InpNewsBufferMins;

   // --- NFP: 1st Friday of month at 12:30 GMT ---
   // 1st Friday = day <= 7 and day_of_week = 5
   if(InpBlockNFP && dow == 5 && dom <= 7)
   {
      int nfpStart = 12*60+30 - buf;  // e.g. 12:00 GMT
      int nfpEnd   = 12*60+30 + buf;  // e.g. 13:00 GMT
      if(totalMins >= nfpStart && totalMins <= nfpEnd)
      { g_newsEventName = "⚠ NFP"; return true; }
   }

   // --- Fed Rate Decision: Wednesday 18:00 GMT (8 times/year approx) ---
   // We block every Wednesday 18:00 as a safety net — Fed months are known
   if(InpBlockFed && dow == 3)
   {
      int fedStart = 18*60+0  - buf;
      int fedEnd   = 18*60+0  + buf;
      if(totalMins >= fedStart && totalMins <= fedEnd)
      { g_newsEventName = "⚠ FED"; return true; }
   }

   // --- CPI: ~2nd or 3rd Wednesday at 12:30 GMT ---
   if(InpBlockCPI && dow == 3 && dom >= 8 && dom <= 21)
   {
      int cpiStart = 12*60+30 - buf;
      int cpiEnd   = 12*60+30 + buf;
      if(totalMins >= cpiStart && totalMins <= cpiEnd)
      { g_newsEventName = "⚠ CPI"; return true; }
   }

   // --- Jobless Claims: Every Thursday 12:30 GMT ---
   if(InpBlockThursday && dow == 4)
   {
      int jcStart = 12*60+30 - buf;
      int jcEnd   = 12*60+30 + buf;
      if(totalMins >= jcStart && totalMins <= jcEnd)
      { g_newsEventName = "⚠ CLAIMS"; return true; }
   }

   g_newsEventName = "";
   return false;
}

//==========================================================================
//  v4.1 — MARKET REGIME DETECTION
//  Uses ADX to detect current market condition and adjust RSI levels
//  Returns effective BUY and SELL RSI levels for current regime
//==========================================================================
void DetectMarketRegime(double adx, double &effectiveBuy, double &effectiveSell)
{
   if(!InpUseRegime)
   {
      g_marketRegime = 0;
      g_regimeName   = "NORMAL";
      effectiveBuy   = g_rsiBuyLvl;
      effectiveSell  = g_rsiSellLvl;
      return;
   }

   if(adx < InpADX_Ranging)
   {
      // RANGING — use normal RSI levels
      g_marketRegime = 0;
      g_regimeName   = "RANGING";
      effectiveBuy   = g_rsiBuyLvl;   // 30
      effectiveSell  = g_rsiSellLvl;  // 70
   }
   else if(adx >= InpADX_Ranging && adx < InpADX_Trending)
   {
      // TRENDING — use normal levels, rely on bypass for extremes
      g_marketRegime = 1;
      g_regimeName   = "TRENDING";
      effectiveBuy   = g_rsiBuyLvl;
      effectiveSell  = g_rsiSellLvl;
   }
   else
   {
      // EXTREME TREND — relax levels so EA can catch trend continuation
      // In extreme downtrend: SELL fires at 60 (not 70) — trend still has room
      // In extreme uptrend:   BUY fires at 40 (not 30) — trend continuation
      g_marketRegime = 2;
      g_regimeName   = "EXTREME";
      effectiveBuy   = InpRSI_ExtremeBuy;   // 40 — catches trend continuation buys
      effectiveSell  = InpRSI_ExtremeSell;  // 60 — catches trend continuation sells
   }
}

//==========================================================================
//  v4.1 — RSI DIVERGENCE DETECTION
//  Detects when trend is losing momentum — early warning before reversal
//
//  Bullish divergence: Price makes LOWER LOW but RSI makes HIGHER LOW
//                      → Downtrend exhausted — stop selling, watch for reversal
//  Bearish divergence: Price makes HIGHER HIGH but RSI makes LOWER HIGH
//                      → Uptrend exhausted — stop buying, watch for reversal
//==========================================================================
void DetectRSIDivergence(double &rsi_vals[], double &close_vals[])
{
   g_bullDivergence = false;
   g_bearDivergence = false;
   if(!InpUseDivergence) return;

   int lb = InpDivLookback;
   if(ArraySize(rsi_vals) < lb+3 || ArraySize(close_vals) < lb+3) return;

   // Find recent price low and RSI low
   double recentPriceLow  = close_vals[1];
   double prevPriceLow    = close_vals[1];
   double recentRSILow    = rsi_vals[1];
   double prevRSILow      = rsi_vals[1];

   // Find recent price high and RSI high
   double recentPriceHigh = close_vals[1];
   double prevPriceHigh   = close_vals[1];
   double recentRSIHigh   = rsi_vals[1];
   double prevRSIHigh     = rsi_vals[1];

   // Scan lookback bars for swing lows and highs
   for(int i=2; i<=lb; i++)
   {
      if(close_vals[i] < recentPriceLow)
      { prevPriceLow = recentPriceLow; prevRSILow = recentRSILow;
        recentPriceLow = close_vals[i]; recentRSILow = rsi_vals[i]; }

      if(close_vals[i] > recentPriceHigh)
      { prevPriceHigh = recentPriceHigh; prevRSIHigh = recentRSIHigh;
        recentPriceHigh = close_vals[i]; recentRSIHigh = rsi_vals[i]; }
   }

   // Bullish divergence: price lower low + RSI higher low
   if(recentPriceLow < prevPriceLow && recentRSILow > prevRSILow && recentRSILow < 45)
   {
      g_bullDivergence = true;
      if(InpDebugLog) Print("🟢 BULLISH DIVERGENCE: Price lower low (",
         DoubleToString(recentPriceLow,2), "<", DoubleToString(prevPriceLow,2),
         ") but RSI higher low (", DoubleToString(recentRSILow,2), ">",
         DoubleToString(prevRSILow,2), ") — downtrend may be exhausted.");
   }

   // Bearish divergence: price higher high + RSI lower high
   if(recentPriceHigh > prevPriceHigh && recentRSIHigh < prevRSIHigh && recentRSIHigh > 55)
   {
      g_bearDivergence = true;
      if(InpDebugLog) Print("🔴 BEARISH DIVERGENCE: Price higher high (",
         DoubleToString(recentPriceHigh,2), ">", DoubleToString(prevPriceHigh,2),
         ") but RSI lower high (", DoubleToString(recentRSIHigh,2), "<",
         DoubleToString(prevRSIHigh,2), ") — uptrend may be exhausted.");
   }
}

//==========================================================================
//  CLEAN ORPHANED PENDING ORDERS
//==========================================================================
void CleanOrphanedPending()
{
   bool hasActiveBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
   bool hasActiveSells = (CountPositions(POSITION_TYPE_SELL) > 0);
   bool hasBuyPending=false, hasSellPending=false;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!ordInfo.SelectByIndex(i)) continue;
      if(ordInfo.Magic()!=InpMagicNumber || ordInfo.Symbol()!=_Symbol) continue;
      if(StringFind(ordInfo.Comment(),"BUY_GRID_") ==0) hasBuyPending  = true;
      if(StringFind(ordInfo.Comment(),"SELL_GRID_")==0) hasSellPending = true;
   }
   if(hasBuyPending  && !hasActiveBuys)  CancelPendingByComment("BUY_GRID_");
   if(hasSellPending && !hasActiveSells) CancelPendingByComment("SELL_GRID_");
}

//==========================================================================
//  DAILY / WEEKLY TRACKERS
//==========================================================================
datetime GetDayStart()
{ MqlDateTime d; TimeToStruct(TimeCurrent(),d); d.hour=0;d.min=0;d.sec=0; return StructToTime(d); }

datetime GetWeekStart()
{ MqlDateTime d; TimeToStruct(TimeCurrent(),d); datetime c=GetDayStart(); return c-d.day_of_week*86400; }

void ResetDailyTracker()
{
   datetime today=GetDayStart();
   if(today!=g_currentDay)
   { g_currentDay=today; g_dailyStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
     Print("New day — balance: ", DoubleToString(g_dailyStartBalance,2)," ",g_currency); }
   datetime week=GetWeekStart();
   if(week!=g_currentWeek)
   { g_currentWeek=week; g_weeklyStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
     Print("New week — balance: ", DoubleToString(g_weeklyStartBalance,2)," ",g_currency); }
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

//==========================================================================
//  DASHBOARD — COMPACT FIT v4.0
//  460px wide x 280px tall
//  Signal row: SAME SIZE (Mode/RSI/Status/Spread)
//  Profit/Trades/Settings: smaller, tighter — all fit on screen
//==========================================================================
void CreateDashboard()
{
   DeleteDashboard();
   int x=InpDashX, y=InpDashY, w=460, h=280;

   DashRect("BG",     x,  y,    w, h,  C'15,30,45', C'0,120,160', 2);

   // TITLE (y to y+30)
   DashRect("R_TTL",  x,  y,    w, 30, C'0,85,125', C'0,150,190', 0);
   DashLabel("TITLE", x+10,y+8, "⚡ DANE GRID EA v4.1", 11, clrWhite, true);
   // News indicator — tiny label, red when active
   DashLabel("NEWS_V",x+220,y+9, "",  8, clrRed, true);
   DashRect("ACC_BG", x+w-105,y+5,98,20,C'0,55,85',C'0,180,220',1);
   DashLabel("ACC_TYPE",x+w-101,y+9,"LOADING...", 8, clrYellow, false);

   // SIGNAL ROW — SAME SIZE (y+30 to y+98)
   DashRect("R_SIG",  x,  y+30, w, 68, C'10,25,42', C'0,100,150', 0);
   DashLabel("MD_L",  x+10,y+40,"Mode :",    10, clrSilver, false);
   DashLabel("MODE_V",x+72, y+40,"NORMAL",   11, clrLime,   true);
   DashLabel("RI_L",  x+10,y+62,"RSI  :",    10, clrSilver, false);
   DashLabel("RSI_V", x+72, y+62,"--",        13, clrWhite,  true);
   DashLabel("ST_L",  x+235,y+40,"Status :", 10, clrSilver, false);
   DashLabel("STA_V", x+310,y+40,"READY",    11, clrLime,   true);
   DashLabel("SP_L",  x+235,y+62,"Spread :", 10, clrSilver, false);
   DashLabel("S_SPRV",x+310,y+62,"--",        11, clrWhite,  false);

   DashRect("DIV1",   x,  y+98, w,  1, C'0,100,140', C'0,100,140', 0);

   // PROFIT (y+99 to y+152) — smaller
   DashRect("R_PRF",  x,  y+99, w, 53, C'12,26,40', C'0,100,140', 0);
   DashLabel("PHR",   x+10,y+104,"PROFIT TRACKER",8, C'0,200,220', true);
   DashLabel("D_L",   x+10,y+118,"Daily P/L :",   8, clrSilver,   false);
   DashLabel("D_VAL", x+90,y+118,"0.00% | 0.00",  10,clrWhite,    false);
   DashLabel("W_L",   x+10,y+136,"Weekly P/L :",  8, clrSilver,   false);
   DashLabel("W_VAL", x+90,y+136,"0.00% | 0.00",  10,clrWhite,    false);

   DashRect("DIV2",   x,  y+152,w,  1, C'0,100,140', C'0,100,140', 0);

   // LIVE TRADES (y+153 to y+205) — smaller
   DashRect("R_TRD",  x,  y+153,w, 52, C'12,26,40', C'0,100,140', 0);
   DashLabel("THR",   x+10,y+158,"LIVE TRADES",   8, C'0,200,220', true);
   DashLabel("TB_L",  x+10,y+172,"Buy Orders :",  8, clrSilver,   false);
   DashLabel("T_BUY_V",x+105,y+170,"0",           13,clrLime,     true);
   DashLabel("TS_L",  x+10,y+188,"Sell Orders :", 8, clrSilver,   false);
   DashLabel("T_SEL_V",x+105,y+186,"0",           13,clrRed,      true);
   DashLabel("PL_L",  x+210,y+172,"Float P/L :",  8, clrSilver,   false);
   DashLabel("T_PL_V",x+210,y+186,"+0.00",        11,clrLime,     true);

   DashRect("DIV3",   x,  y+205,w,  1, C'0,100,140', C'0,100,140', 0);

   // SETTINGS (y+206 to y+280) — smaller 2 lines
   DashRect("R_SET",  x,  y+206,w, 74, C'10,22,36', C'0,100,140', 0);
   DashLabel("SHR",   x+10,y+211,"SETTINGS",       8, C'0,200,220', true);
   DashLabel("S_LOT", x+10,y+225,"Lot:",            8, clrSilver,   false);
   DashLabel("S_LV",  x+40,y+225,"--",              9, clrYellow,   true);
   DashLabel("S_SP",  x+155,y+225,"Spacing:",       8, clrSilver,   false);
   DashLabel("S_SV",  x+210,y+225,"--",             9, clrYellow,   false);
   DashLabel("S_RSI", x+275,y+225,"RSI:",           8, clrSilver,   false);
   DashLabel("S_RV",  x+305,y+225,"--",             9, clrYellow,   false);
   DashLabel("S_MP",  x+10,y+245,"MaxP:",           8, clrSilver,   false);
   DashLabel("S_MV",  x+48,y+245,"--",              9, clrYellow,   false);
   DashLabel("S_SL",  x+100,y+245,"SL:",            8, clrSilver,   false);
   DashLabel("S_SLV", x+122,y+245,"--",             9, clrYellow,   false);
   DashLabel("S_ADX", x+175,y+245,"ADX:",           8, clrSilver,   false);
   DashLabel("S_ADXV",x+205,y+245,"--",             9, clrYellow,   false);
   DashLabel("S_GRD", x+270,y+245,"Grid:",          8, clrSilver,   false);
   DashLabel("S_GRV", x+305,y+245,"--",             9, clrYellow,   false);

   ChartRedraw(0);
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL  = balance - g_dailyStartBalance;
   double weeklyPnL = balance - g_weeklyStartBalance;
   double dPct=(g_dailyStartBalance >0)?(dailyPnL /g_dailyStartBalance *100.0):0;
   double wPct=(g_weeklyStartBalance>0)?(weeklyPnL/g_weeklyStartBalance*100.0):0;
   double floatPnL=GetTotalGridProfit();
   int buys=CountPositions(POSITION_TYPE_BUY);
   int sells=CountPositions(POSITION_TYPE_SELL);
   double rsiNow[]; ArraySetAsSeries(rsiNow,true);
   double adxNow[]; ArraySetAsSeries(adxNow,true);
   double curRSI=0,curADX=0;
   if(CopyBuffer(rsi_handle,0,0,3,rsiNow)>=3) curRSI=rsiNow[1];
   if(CopyBuffer(adx_handle,0,0,3,adxNow)>=3) curADX=adxNow[1];
   double spreadPips=GetCurrentSpreadPips();

   DashLabelUpdate("ACC_TYPE",g_isCentAcct?"CENT (USC)":"STANDARD (USD)",g_isCentAcct?clrYellow:clrLime);

   // News filter indicator — shows event name in red when active, blank when clear
   if(g_newsActive)
      DashLabelUpdate("NEWS_V", g_newsEventName, clrRed);
   else if(g_bullDivergence)
      DashLabelUpdate("NEWS_V", "🟢DIV", clrAqua);
   else if(g_bearDivergence)
      DashLabelUpdate("NEWS_V", "🔴DIV", clrOrange);
   else
      DashLabelUpdate("NEWS_V", "", clrRed);

   // Signal mode — now includes regime info
   bool exLow =curRSI>0&&curRSI<=InpExtremeRSILow;
   bool exHigh=curRSI>0&&curRSI>=InpExtremeRSIHigh;
   if(g_newsActive)
      DashLabelUpdate("MODE_V","📰 NEWS PAUSE", clrRed);
   else if(exLow)
      DashLabelUpdate("MODE_V","⚡ EXTREME BUY",  clrAqua);
   else if(exHigh)
      DashLabelUpdate("MODE_V","⚡ EXTREME SELL", clrOrange);
   else if(g_marketRegime==2)
      DashLabelUpdate("MODE_V","🔥 EXTREME TREND", clrOrange);
   else if(g_marketRegime==1)
      DashLabelUpdate("MODE_V","📈 TRENDING", clrYellow);
   else
      DashLabelUpdate("MODE_V","NORMAL (Trend ON)",clrLime);
   color rsiClr=curRSI<=30?clrAqua:curRSI>=70?clrOrange:clrWhite;
   DashLabelUpdate("RSI_V",DoubleToString(curRSI,1),rsiClr);
   string stTxt=g_recoveryMode?"RECOVERY":g_lastGridWasProfitable?"RE-ENTRY":"READY";
   color  stClr=g_recoveryMode?clrOrange:g_lastGridWasProfitable?clrAqua:clrLime;
   DashLabelUpdate("STA_V",stTxt,stClr);
   color sprClr=spreadPips>InpMaxSpreadPips?clrRed:clrLime;
   DashLabelUpdate("S_SPRV",DoubleToString(spreadPips,1)+" pips",sprClr);
   color dc=(dailyPnL>=0)?clrLime:clrRed; string ds=(dailyPnL>=0)?"+":"";
   DashLabelUpdate("D_VAL",ds+DoubleToString(dPct,2)+"% | "+ds+DoubleToString(dailyPnL,2)+" "+g_currency,dc);
   color wc=(weeklyPnL>=0)?clrLime:clrRed; string ws=(weeklyPnL>=0)?"+":"";
   DashLabelUpdate("W_VAL",ws+DoubleToString(wPct,2)+"% | "+ws+DoubleToString(weeklyPnL,2)+" "+g_currency,wc);
   DashLabelUpdate("T_BUY_V",IntegerToString(buys), buys>0?clrLime:clrSilver);
   DashLabelUpdate("T_SEL_V",IntegerToString(sells),sells>0?clrRed:clrSilver);
   color plc=(floatPnL>=0)?clrLime:clrRed; string pls=(floatPnL>=0)?"+":"";
   DashLabelUpdate("T_PL_V",pls+DoubleToString(floatPnL,2)+" "+g_currency,plc);
   string lotDisp=DoubleToString(g_activeLot,2)+(InpUseDynamicLot?" AUTO":" MAN");
   DashLabelUpdate("S_LV",  lotDisp,                                                    InpUseDynamicLot?clrAqua:clrYellow);
   DashLabelUpdate("S_SV",  DoubleToString(g_spacingPips,0)+"p",                        clrYellow);
   DashLabelUpdate("S_RV",  DoubleToString(g_rsiBuyLvl,0)+"/"+DoubleToString(g_rsiSellLvl,0),clrYellow);
   DashLabelUpdate("S_MV",  DoubleToString(g_maxProfitMult,0)+"x",                      clrYellow);
   DashLabelUpdate("S_SLV", DoubleToString(g_gridSLMult,0)+"x",                         clrYellow);
   color adxClr=curADX<InpADX_Weak?clrRed:curADX>InpADX_Strong?clrLime:clrYellow;
   DashLabelUpdate("S_ADXV",DoubleToString(curADX,1),                                   adxClr);
   DashLabelUpdate("S_GRV", IntegerToString(g_gridSize)+" ord",                         clrYellow);
   ChartRedraw(0);
}


void DashRect(string n,int x,int y,int w,int h,color bg,color brd,int t)
{
   string o=DASH_PREFIX+n;
   ObjectCreate(0,o,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,o,OBJPROP_XSIZE,w);     ObjectSetInteger(0,o,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,o,OBJPROP_BGCOLOR,bg);  ObjectSetInteger(0,o,OBJPROP_BORDER_COLOR,brd);
   ObjectSetInteger(0,o,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,o,OBJPROP_WIDTH,t);
   ObjectSetInteger(0,o,OBJPROP_BACK,false); ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);
}

void DashLabel(string n,int x,int y,string txt,int sz,color clr,bool bold)
{
   string o=DASH_PREFIX+n;
   ObjectCreate(0,o,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,o,OBJPROP_TEXT,txt);      ObjectSetInteger(0,o,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,o,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,o,OBJPROP_FONT,bold?"Arial Bold":"Arial");
   ObjectSetInteger(0,o,OBJPROP_BACK,false); ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);
}

void DashLabelUpdate(string n,string txt,color clr)
{
   string o=DASH_PREFIX+n;
   if(ObjectFind(0,o)>=0)
   { ObjectSetString(0,o,OBJPROP_TEXT,txt); ObjectSetInteger(0,o,OBJPROP_COLOR,clr); }
}

void DeleteDashboard()
{
   int total=ObjectsTotal(0);
   for(int i=total-1;i>=0;i--)
   { string nm=ObjectName(0,i); if(StringFind(nm,DASH_PREFIX)==0) ObjectDelete(0,nm); }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| END OF EA v3.9                                                   |
//+------------------------------------------------------------------+
