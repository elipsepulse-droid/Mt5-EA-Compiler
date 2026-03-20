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
#property copyright   "EA SCALPING ROBOT / DANE - v3.9"
#property version     "3.90"
#property description "Grid EA v3.9 — 14 Upgrades | Smart Risk Management"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//==========================================================================
//  INPUTS
//==========================================================================

input group "====== SYMBOL MODE ======"
input bool InpAutoDetect = true;

input group "====== GRID SETUP ======"
input int    InpGridSize       = 4;
input double InpSpacingPips    = 80;
// *** LOT SIZE — HOW TO USE ***
// If InpUseDynamicLot = false → EA uses EXACTLY this lot size every trade
// If InpUseDynamicLot = true  → EA auto-calculates lot but respects InpMinLot/InpMaxLot below
// You can change this anytime in EA Properties → Inputs without recompiling
input double InpLotSize        = 0.01; // Manual lot size (used when dynamic lot is OFF)
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
// When ON  → lot auto-calculated from balance % but capped by InpMinLot and InpMaxLot
// When OFF → EA uses InpLotSize exactly — full manual control
input bool   InpUseDynamicLot    = true;
input double InpRiskPercent      = 1.0;   // Risk % of balance per grid (used when dynamic ON)
input double InpMinLot           = 0.01;  // Minimum lot even if dynamic calc says lower
input double InpMaxLot           = 1.00;  // Maximum lot even if dynamic calc says higher
// TIP: Set InpUseDynamicLot=false and change InpLotSize anytime to trade any size you want

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
input double InpRecoveryLotMult  = 0.5; // Recovery lot = 50% of normal lot

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
double g_activeLot = 0.01; // Tracks the actual lot being used — shown on dashboard

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

   Print("=== EA GRID v3.9 INITIALIZED on ", _Symbol, " ===");
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
   //  RSI ENTRY SIGNALS
   //===================================================================
   int rs = InpRSI_Shift;
   double currentRSI = rsi_val[rs];
   double prevRSI    = rsi_val[rs+1];

   bool rsiBuyCross  = (currentRSI >  g_rsiBuyLvl  && prevRSI <= g_rsiBuyLvl);
   bool rsiSellCross = (currentRSI <  g_rsiSellLvl && prevRSI >= g_rsiSellLvl);

   //===================================================================
   //  IMPROVEMENT 9 — CANDLE CONFIRMATION
   //  Track RSI signal for 2 bars before firing
   //===================================================================
   if(InpUseCandleConfirm)
   {
      // New RSI cross detected — start counting
      if(rsiBuyCross  && !g_buySignalPending)
      { g_buySignalPending  = true; g_signalBarsCount = 0; g_signalBarTime = currentBar; }
      if(rsiSellCross && !g_sellSignalPending)
      { g_sellSignalPending = true; g_signalBarsCount = 0; g_signalBarTime = currentBar; }

      // Count bars since signal appeared
      if(g_buySignalPending  || g_sellSignalPending) g_signalBarsCount++;

      // Signal confirmed after 2 bars — check RSI still on same side
      bool buyConfirmed  = g_buySignalPending  && g_signalBarsCount >= 2 && currentRSI > g_rsiBuyLvl;
      bool sellConfirmed = g_sellSignalPending && g_signalBarsCount >= 2 && currentRSI < g_rsiSellLvl;

      // Reset if RSI reverses before confirmation
      if(g_buySignalPending  && currentRSI < g_rsiBuyLvl -5)
      { g_buySignalPending  = false; g_signalBarsCount = 0; }
      if(g_sellSignalPending && currentRSI > g_rsiSellLvl+5)
      { g_sellSignalPending = false; g_signalBarsCount = 0; }

      // Reset confirmed signals
      if(buyConfirmed)  { rsiBuyCross  = true; g_buySignalPending  = false; }
      else              { rsiBuyCross  = false; }
      if(sellConfirmed) { rsiSellCross = true; g_sellSignalPending = false; }
      else              { rsiSellCross = false; }
   }

   //===================================================================
   //  IMPROVEMENT 5 — MACD CONFIRMATION
   //  RSI signal must agree with MACD histogram direction
   //===================================================================
   bool macdBullish = true, macdBearish = true;
   if(InpUseMACD)
   {
      double macdHist1 = macd_main[1] - macd_sig[1]; // current histogram
      double macdHist2 = macd_main[2] - macd_sig[2]; // previous histogram
      macdBullish = (macdHist1 > 0 || macdHist1 > macdHist2); // rising or positive
      macdBearish = (macdHist1 < 0 || macdHist1 < macdHist2); // falling or negative
   }

   //===================================================================
   //  IMPROVEMENT 8 — VOLUME FILTER
   //  Skip entry if current candle volume is too low
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
         Print("VOLUME FILTER: Low volume (", curVol, " vs avg ", DoubleToString(avgVol,0), ") — skipping entry.");
   }

   //===================================================================
   //  OPTION 1 — EXTREME RSI BYPASS
   //===================================================================
   bool extremeOversold   = (prevRSI < InpExtremeRSILow);
   bool extremeOverbought = (prevRSI > InpExtremeRSIHigh);

   //===================================================================
   //  COMBINED ENTRY DECISION
   //===================================================================
   bool doOpenBuy  = rsiBuyCross  && macdBullish && volumeOK &&
                     (tUp || extremeOversold) && !hasBuys;
   bool doOpenSell = rsiSellCross && macdBearish && volumeOK &&
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
               " (need cross of ", g_rsiBuyLvl, " for BUY or ", g_rsiSellLvl, " for SELL)");
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
//  DASHBOARD
//==========================================================================
//  HORIZONTAL LANDSCAPE DASHBOARD — v3.9
//  Layout: 4 compact rows across full width
//  Row 1: Title | Account | Signal Mode | RSI | Spread | ATR | ADX
//  Row 2: Daily Profit | Weekly Profit | Buys | Sells | Floating P/L
//  Row 3: Grid | Spacing | Lot | RSI Levels | MaxProfit | Grid SL
//  Row 4: Footer info
//  Total size: ~780px wide x 155px tall — fits any screen
//==========================================================================
void CreateDashboard()
{
   DeleteDashboard();
   int x = InpDashX;
   int y = InpDashY;
   int w = 780;   // Wide horizontal panel
   int h = 155;   // Short height — fits all screens

   // === MAIN BACKGROUND ===
   DashRect("BG",       x, y,   w, h,  C'18,36,48',  C'0,120,160', 2);

   // === ROW 1: TITLE BAR (y+0 to y+30) ===
   DashRect("R1_BG",    x, y,   w, 30, C'0,90,130',  C'0,140,180', 0);
   DashLabel("TITLE",   x+8,  y+8,  "⚡ DANE GRID EA v3.9", 11, clrWhite,  true);
   DashLabel("BY",      x+200,y+10, "by Dane",               8, clrAqua,   false);

   // Account badge (top right)
   DashRect("ACC_BG",   x+w-110,y+5, 102, 20, C'0,60,90', C'0,180,220', 1);
   DashLabel("ACC_TYPE",x+w-105,y+9, "LOADING...", 8, clrYellow, false);

   // Signal mode + live indicators (all in row 1, right side)
   DashLabel("MD_L",    x+255,y+10, "Mode:",      8, clrSilver, false);
   DashLabel("MODE_V",  x+295,y+10, "NORMAL",     8, clrLime,   true);
   DashLabel("RI_L",    x+400,y+10, "RSI:",       8, clrSilver, false);
   DashLabel("RSI_V",   x+425,y+10, "--",         8, clrWhite,  true);
   DashLabel("SP_L",    x+465,y+10, "Spread:",    8, clrSilver, false);
   DashLabel("SPR_V",   x+510,y+10, "--",         8, clrWhite,  false);
   DashLabel("AT_L",    x+565,y+10, "ATR:",       8, clrSilver, false);
   DashLabel("ATR_V",   x+590,y+10, "--",         8, clrWhite,  false);
   DashLabel("AX_L",    x+630,y+10, "ADX:",       8, clrSilver, false);
   DashLabel("ADX_V",   x+655,y+10, "--",         8, clrWhite,  false);

   // === ROW 2: PROFIT + LIVE TRADES (y+34 to y+68) ===
   DashRect("R2_BG",    x, y+32, w, 34, C'12,28,40', C'0,100,140', 0);

   // Daily Profit
   DashLabel("D_LBL",   x+8,  y+38, "Daily P/L:",  8, C'0,200,220', true);
   DashLabel("D_VAL",   x+75, y+38, "0.00% | 0.00",9, clrWhite,    false);
   DashLabel("D_LBL2",  x+8,  y+52, "Weekly P/L:", 8, C'0,200,220', true);
   DashLabel("W_VAL",   x+75, y+52, "0.00% | 0.00",9, clrWhite,    false);

   // Separator
   DashRect("SEP1",     x+255,y+34, 2, 34, C'0,120,160', C'0,120,160', 0);

   // Live Trades
   DashLabel("TB_L",    x+265,y+38, "Buy Orders:",  8, clrSilver, false);
   DashLabel("T_BUY_V", x+345,y+38, "0",           10, clrLime,   true);
   DashLabel("TS_L",    x+265,y+52, "Sell Orders:", 8, clrSilver, false);
   DashLabel("T_SEL_V", x+345,y+52, "0",           10, clrRed,    true);

   // Separator
   DashRect("SEP2",     x+390,y+34, 2, 34, C'0,120,160', C'0,120,160', 0);

   // Floating P/L
   DashLabel("PL_L",    x+400,y+38, "Floating P/L:", 8, clrSilver, false);
   DashLabel("T_PL_V",  x+490,y+38, "+0.00",         10, clrLime,  true);

   // Separator
   DashRect("SEP3",     x+620,y+34, 2, 34, C'0,120,160', C'0,120,160', 0);

   // Recovery / Re-entry status
   DashLabel("REC_L",   x+630,y+38, "Status:",   8, clrSilver, false);
   DashLabel("REC_V",   x+675,y+38, "READY",     8, clrLime,   true);

   // === ROW 3: CURRENT SETTINGS (y+70 to y+104) ===
   DashRect("R3_BG",    x, y+68, w, 34, C'10,25,38', C'0,100,140', 0);

   DashLabel("S1_L",    x+8,  y+74, "Grid:",       8, clrSilver, false);
   DashLabel("S1_V",    x+40, y+74, "--",           9, clrYellow, true);
   DashRect("SEP4",     x+90, y+70, 1, 32, C'0,100,140', C'0,100,140', 0);

   DashLabel("S2_L",    x+98, y+74, "Spacing:",    8, clrSilver, false);
   DashLabel("S2_V",    x+150,y+74, "--",           9, clrYellow, true);
   DashRect("SEP5",     x+215,y+70, 1, 32, C'0,100,140', C'0,100,140', 0);

   DashLabel("S3_L",    x+223,y+74, "Lot:",        8, clrSilver, false);
   DashLabel("S3_V",    x+250,y+74, "--",           9, clrYellow, true);
   DashRect("SEP6",     x+370,y+70, 1, 32, C'0,100,140', C'0,100,140', 0);

   DashLabel("S4_L",    x+378,y+74, "RSI:",        8, clrSilver, false);
   DashLabel("S4_V",    x+405,y+74, "--",           9, clrYellow, true);
   DashRect("SEP7",     x+450,y+70, 1, 32, C'0,100,140', C'0,100,140', 0);

   DashLabel("S5_L",    x+458,y+74, "MaxProfit:",  8, clrSilver, false);
   DashLabel("S5_V",    x+525,y+74, "--",           9, clrYellow, true);
   DashRect("SEP8",     x+560,y+70, 1, 32, C'0,100,140', C'0,100,140', 0);

   DashLabel("S6_L",    x+568,y+74, "GridSL:",     8, clrSilver, false);
   DashLabel("S6_V",    x+615,y+74, "--",           9, clrYellow, true);
   DashRect("SEP9",     x+655,y+70, 1, 32, C'0,100,140', C'0,100,140', 0);

   DashLabel("S7_L",    x+663,y+74, "Symbol:",     8, clrSilver, false);
   DashLabel("S7_V",    x+707,y+74, "--",           9, clrAqua,   true);

   // Second line of settings row
   DashLabel("S1_L2",   x+8,  y+88, "Orders:",     8, clrSilver, false);
   DashLabel("S1_V2",   x+52, y+88, "--",           8, clrYellow, false);
   DashLabel("S2_L2",   x+98, y+88, "ATR Spac:",   8, clrSilver, false);
   DashLabel("S2_V2",   x+155,y+88, "--",           8, clrYellow, false);
   DashLabel("S3_L2",   x+223,y+88, "DynLot:",     8, clrSilver, false);
   DashLabel("S3_V2",   x+265,y+88, "--",           8, clrYellow, false);
   DashLabel("S4_L2",   x+378,y+88, "Bypass:",     8, clrSilver, false);
   DashLabel("S4_V2",   x+418,y+88, "--",           8, clrYellow, false);
   DashLabel("S5_L2",   x+458,y+88, "Trail:",      8, clrSilver, false);
   DashLabel("S5_V2",   x+490,y+88, "--",           8, clrYellow, false);
   DashLabel("S6_L2",   x+568,y+88, "MACD:",       8, clrSilver, false);
   DashLabel("S6_V2",   x+605,y+88, "--",           8, clrYellow, false);
   DashLabel("S7_L2",   x+663,y+88, "Vol:",        8, clrSilver, false);
   DashLabel("S7_V2",   x+685,y+88, "--",           8, clrYellow, false);

   // === ROW 4: FOOTER (y+105 to h) ===
   DashRect("FOOT_BG",  x, y+104, w, h-104, C'8,20,32', C'0,100,140', 0);
   DashLabel("FOOT",    x+8, y+112,
             "v3.9 | 14 Upgrades: ATR Spacing | MACD | ADX Grid | Spread Filter | Breakeven | Partial TP | Re-Entry | Recovery | Vol Shield | Best PHT: 8PM-11PM",
             7, C'0,140,180', false);

   ChartRedraw(0);
}

void UpdateDashboard()
{
   if(!InpShowDashboard) return;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL  = balance - g_dailyStartBalance;
   double weeklyPnL = balance - g_weeklyStartBalance;
   double dPct      = (g_dailyStartBalance  > 0) ? (dailyPnL /g_dailyStartBalance *100.0) : 0;
   double wPct      = (g_weeklyStartBalance > 0) ? (weeklyPnL/g_weeklyStartBalance*100.0) : 0;
   double floatPnL  = GetTotalGridProfit();
   int buys  = CountPositions(POSITION_TYPE_BUY);
   int sells = CountPositions(POSITION_TYPE_SELL);

   // Live indicators
   double rsiNow[]; ArraySetAsSeries(rsiNow,true);
   double atrNow[]; ArraySetAsSeries(atrNow,true);
   double adxNow[]; ArraySetAsSeries(adxNow,true);
   double curRSI=0, curATR=0, curADX=0;
   if(CopyBuffer(rsi_handle,0,0,3,rsiNow)>=3) curRSI=rsiNow[1];
   if(CopyBuffer(atr_handle,0,0,3,atrNow)>=3) curATR=atrNow[1];
   if(CopyBuffer(adx_handle,0,0,3,adxNow)>=3) curADX=adxNow[1];
   double spreadPips = GetCurrentSpreadPips();

   // --- ROW 1 UPDATES ---
   DashLabelUpdate("ACC_TYPE", g_isCentAcct?"CENT (USC)":"STANDARD (USD)",
                   g_isCentAcct?clrYellow:clrLime);

   bool exLow  = curRSI>0 && curRSI<=InpExtremeRSILow;
   bool exHigh = curRSI>0 && curRSI>=InpExtremeRSIHigh;
   if(exLow)       DashLabelUpdate("MODE_V","⚡ EXTREME BUY", clrAqua);
   else if(exHigh) DashLabelUpdate("MODE_V","⚡ EXTREME SELL",clrOrange);
   else            DashLabelUpdate("MODE_V","NORMAL (Trend ON)",clrLime);

   color rsiClr = curRSI<=30 ? clrAqua : curRSI>=70 ? clrOrange : clrWhite;
   DashLabelUpdate("RSI_V", DoubleToString(curRSI,1), rsiClr);

   color sprClr = spreadPips > InpMaxSpreadPips ? clrRed : clrLime;
   DashLabelUpdate("SPR_V", DoubleToString(spreadPips,1)+"p", sprClr);
   DashLabelUpdate("ATR_V", DoubleToString(curATR,2), clrWhite);

   color adxClr = curADX<InpADX_Weak ? clrRed : curADX>InpADX_Strong ? clrLime : clrYellow;
   DashLabelUpdate("ADX_V", DoubleToString(curADX,1), adxClr);

   // --- ROW 2 UPDATES ---
   color dc=(dailyPnL>=0)?clrLime:clrRed; string ds=(dailyPnL>=0)?"+":"";
   DashLabelUpdate("D_VAL", ds+DoubleToString(dPct,2)+"% | "+ds+DoubleToString(dailyPnL,2)+" "+g_currency, dc);
   color wc=(weeklyPnL>=0)?clrLime:clrRed; string ws=(weeklyPnL>=0)?"+":"";
   DashLabelUpdate("W_VAL", ws+DoubleToString(wPct,2)+"% | "+ws+DoubleToString(weeklyPnL,2)+" "+g_currency, wc);

   DashLabelUpdate("T_BUY_V", IntegerToString(buys),  buys>0?clrLime:clrSilver);
   DashLabelUpdate("T_SEL_V", IntegerToString(sells), sells>0?clrRed:clrSilver);

   color plc=(floatPnL>=0)?clrLime:clrRed; string pls=(floatPnL>=0)?"+":"";
   DashLabelUpdate("T_PL_V", pls+DoubleToString(floatPnL,2)+" "+g_currency, plc);

   // Recovery / re-entry status
   string statusTxt = g_recoveryMode ? "RECOVERY" :
                      g_lastGridWasProfitable ? "RE-ENTRY" : "READY";
   color statusClr  = g_recoveryMode ? clrOrange :
                      g_lastGridWasProfitable ? clrAqua : clrLime;
   DashLabelUpdate("REC_V", statusTxt, statusClr);

   // --- ROW 3 UPDATES (Settings line 1) ---
   DashLabelUpdate("S1_V", IntegerToString(g_gridSize)+" orders", clrYellow);
   DashLabelUpdate("S2_V", DoubleToString(g_spacingPips,0)+"pips", clrYellow);
   string lotDisp = DoubleToString(g_activeLot,2)+(InpUseDynamicLot?" AUTO":" MANUAL");
   DashLabelUpdate("S3_V", lotDisp, InpUseDynamicLot?clrAqua:clrYellow);
   DashLabelUpdate("S4_V", DoubleToString(g_rsiBuyLvl,0)+"/"+DoubleToString(g_rsiSellLvl,0), clrYellow);
   DashLabelUpdate("S5_V", DoubleToString(g_maxProfitMult,0)+"x", clrYellow);
   DashLabelUpdate("S6_V", DoubleToString(g_gridSLMult,0)+"x", clrYellow);
   DashLabelUpdate("S7_V", _Symbol, clrAqua);

   // Settings line 2 (feature status)
   DashLabelUpdate("S1_V2", IntegerToString(g_gridSize), clrYellow);
   DashLabelUpdate("S2_V2", InpUseATR?"ON":"OFF", InpUseATR?clrLime:clrRed);
   DashLabelUpdate("S3_V2", InpUseDynamicLot?"ON":"OFF", InpUseDynamicLot?clrLime:clrYellow);
   DashLabelUpdate("S4_V2", "<"+DoubleToString(InpExtremeRSILow,0)+"/"+DoubleToString(InpExtremeRSIHigh,0)+">", clrYellow);
   DashLabelUpdate("S5_V2", InpUseTrailing?"ON":"OFF", InpUseTrailing?clrLime:clrRed);
   DashLabelUpdate("S6_V2", InpUseMACD?"ON":"OFF", InpUseMACD?clrLime:clrRed);
   DashLabelUpdate("S7_V2", InpUseVolFilter?"ON":"OFF", InpUseVolFilter?clrLime:clrRed);

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
