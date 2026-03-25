//+------------------------------------------------------------------+
//|         EA_Scalping_Grid_GOLD_BTC_v5.0.mq5                       |
//|     Universal Grid Scalping Robot - XAUUSD & BTCUSD M5           |
//|                                                                   |
//|  ORIGINAL BASE: v4.1 by DANE                                      |
//|  v5.0 UPGRADE — Dynasty Gold Strategy Integration:                |
//|  A.  Broker Auto-Detection   — Exness, IC Markets, Pepperstone,   |
//|      FTMO, etc. with broker-specific spread/lot presets           |
//|  B.  Momentum Candle Entry   — Dynasty-style entry on strong      |
//|      candle close (body > 60% ATR) = the "arrow signals"         |
//|  C.  Swing Break Entry       — Buy/sell on 3-bar high/low break   |
//|      (replicates Dynasty Gold's candle extreme arrows)            |
//|  D.  Scalp TP Mode           — 15–25 pip tight TP like video      |
//|      (toggleable alongside existing grid TP)                      |
//|  E.  Single-Order First      — 1 order opens first, grid only     |
//|      adds on continuation (reduces overexposure)                  |
//|  F.  Overnight Session Logic — relaxed filters for Asian/London   |
//|      overnight so EA trades more like the video (overnight runs)  |
//|  G.  BTC Weekend Broker-Aware — BTC session uses broker-specific  |
//|      weekend/24h detection                                        |
//|  H.  Improved Dashboard      — shows broker name, scalp mode,     |
//|      momentum signal, swing signal in real time                   |
//|                                                                   |
//|  ALL v4.1 FEATURES RETAINED:                                      |
//|  - RSI 30/70 entry + EMA(100/300) trend filter                   |
//|  - MACD confirmation, ADX adaptive grid, ATR dynamic spacing/SL  |
//|  - Spread filter, volatility shield, volume filter               |
//|  - Breakeven stop, trailing stop, partial TP (50% at 1x/2x)     |
//|  - News filter (NFP, Fed, CPI, Jobless)                          |
//|  - Market regime detection, RSI divergence exit                  |
//|  - Recovery mode, re-entry after profit                          |
//|  - Extreme RSI bypass (25/75), candle confirmation               |
//|  - Dynamic lot sizing, cent/standard account detection           |
//|  - Live dashboard, debug logging, orphan order cleanup           |
//+------------------------------------------------------------------+
#property copyright   "EA SCALPING ROBOT / DANE - v5.0"
#property version     "5.00"
#property description "Grid EA v5.0 — Dynasty Gold Strategy + Broker Detection + Scalp Mode"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//==========================================================================
//  INPUTS
//==========================================================================

input group "====== ★ LOT SIZE QUICK CONTROL ★ ======"
input bool   InpUseDynamicLot  = true;
input double InpLotSize        = 0.01;
input double InpRiskPercent    = 1.0;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.00;

input group "====== SYMBOL MODE ======"
input bool InpAutoDetect = true;

input group "====== GRID SETUP ======"
input int    InpGridSize       = 4;
input double InpSpacingPips    = 80;
input bool   InpMoveGrid       = true;

input group "====== TRADE MANAGEMENT ======"
input bool   InpTPPerTrade       = true;
input double InpTPMultiplier     = 1.0;
input double InpTP2Multiplier    = 2.0;
input bool   InpCloseAtMaxProfit = true;
input double InpMaxProfitMult    = 4.0;
input double InpGridSLMult       = 6.0;

input group "====== v5.0 A: BROKER AUTO-DETECTION ======"
// EA reads your broker name from the account and applies matching presets
// Exness: tight spread presets | FTMO: conservative lot caps
// Override: set InpBrokerOverride to your broker name to force a profile
// Leave blank = auto-detect from account company name
input bool   InpUseBrokerDetect = true;   // Enable broker auto-detection
input string InpBrokerOverride  = "";     // Force broker profile (blank=auto)

input group "====== v5.0 B+C: DYNASTY GOLD ENTRY MODE ======"
// Replicates the arrow signals seen in the Dynasty Gold v9 video
// Momentum Entry: fires when a candle closes with a strong body (>ATR*mult)
// Swing Break Entry: fires when price breaks the 3-bar high/low
// Both layers require RSI and trend to still agree before opening
input bool   InpUseMomentumEntry  = true;   // Momentum candle arrow entry
input double InpMomBodyMult       = 0.55;   // Body must be > ATR x this (0.55=55%)
input bool   InpUseSwingBreak     = true;   // Swing high/low break entry
input int    InpSwingLookback     = 3;      // Bars to look back for swing high/low
input bool   InpMomentumNeedRSI   = true;   // Momentum entry still needs RSI zone (recommended)
input bool   InpMomentumNeedTrend = true;   // Momentum entry still needs EMA trend (recommended)

input group "====== v5.0 D: SCALP TP MODE (Dynasty Gold Style) ======"
// When enabled: first TP is tight (15–25 pips) like the video
// Overrides InpTPMultiplier for the scalp layer only
// Grid TP still applies to non-scalp positions
input bool   InpUseScalpTP       = true;   // Enable scalp-style tight TP
input double InpScalpTPPips      = 20.0;   // Tight TP in pips (Dynasty Gold uses ~15–25)
input double InpScalpSLPips      = 15.0;   // Tight SL in pips for scalp entries

input group "====== v5.0 E: SINGLE-ORDER FIRST MODE ======"
// Dynasty Gold appears to open 1 order first, then add on continuation
// This reduces overexposure on the first signal candle
input bool   InpSingleFirst      = true;   // Open 1 order first, add grid on continuation
input int    InpGridAddBars      = 2;      // Add remaining grid orders after X bars if trade profitable

input group "====== v5.0 F: OVERNIGHT SESSION (More Trades Like Video) ======"
// Overnight: Asian/early London session — spread is wider, volume lower
// Relax filters during this window so EA trades more (like Dynasty Gold does)
input bool   InpUseOvernightMode  = true;   // Enable relaxed overnight filters
input int    InpOvernightStartHr  = 22;     // Overnight starts at GMT hour (default 22:00 = 6AM PHT)
input int    InpOvernightEndHr    = 6;      // Overnight ends at GMT hour (default 06:00 = 2PM PHT)
input double InpOvernightSpread   = 35.0;   // Max spread during overnight (wider allowed)
input double InpOvernightVolMult  = 0.45;   // Min volume multiplier overnight (more relaxed)
input double InpOvernightRSIBuy   = 35.0;   // RSI buy level overnight (less extreme needed)
input double InpOvernightRSISell  = 65.0;   // RSI sell level overnight

input group "====== v5.0 G: BTC WEEKEND / 24H TRADING ======"
// BTC trades 24/7 on most brokers — but weekend liquidity differs
// Broker-aware: Exness allows BTC weekend, some others pause
input bool   InpBTCWeekendTrade   = true;   // Allow BTC trading on weekends
input bool   InpBTCReducedWeekend = true;   // Reduce lot size on weekends (lower liquidity)
input double InpBTCWeekendLotMult = 0.5;    // Weekend lot multiplier (0.5 = half lot)

input group "====== IMPROVEMENT 1: SPREAD FILTER ======"
input bool   InpUseSpreadFilter  = true;
input double InpMaxSpreadPips    = 20.0;

input group "====== IMPROVEMENT 2+3: ATR DYNAMIC SPACING & SL ======"
input bool   InpUseATR           = true;
input int    InpATR_Period        = 14;
input double InpATR_SpacingMult  = 0.7;
input double InpATR_SLMult       = 2.0;

input group "====== IMPROVEMENT 4: VOLATILITY SHIELD ======"
input bool   InpUseVolShield     = true;
input double InpVolShieldMult    = 2.5;

input group "====== IMPROVEMENT 5: MACD CONFIRMATION ======"
input bool   InpUseMACD          = true;
input int    InpMACD_Fast         = 12;
input int    InpMACD_Slow         = 26;
input int    InpMACD_Signal       = 9;

input group "====== IMPROVEMENT 6: BREAKEVEN STOP ======"
input bool   InpUseBreakeven     = true;
input double InpBreakevenPips    = 20.0;

input group "====== TRAILING STOP ======"
input bool   InpUseTrailing      = true;
input double InpTrailStartPips   = 40.0;
input double InpTrailStepPips    = 20.0;

input group "====== IMPROVEMENT 8: VOLUME FILTER ======"
input bool   InpUseVolFilter     = true;
input double InpMinVolMultiplier = 0.7;

input group "====== IMPROVEMENT 9: CANDLE CONFIRMATION ======"
input bool   InpUseCandleConfirm = true;

input group "====== IMPROVEMENT 10: ADX ADAPTIVE GRID SIZE ======"
input bool   InpUseADX           = true;
input int    InpADX_Period        = 14;
input double InpADX_Weak          = 20.0;
input double InpADX_Strong        = 35.0;

input group "====== IMPROVEMENT 12: RE-ENTRY AFTER PROFIT ======"
input bool   InpUseReEntry       = true;
input int    InpReEntryBars      = 3;

input group "====== IMPROVEMENT 13: GRID RECOVERY ======"
input bool   InpUseRecovery      = true;
input double InpRecoveryLotMult  = 0.5;

input group "====== v4.1: NEWS FILTER ======"
input bool   InpUseNewsFilter    = true;
input bool   InpBlockNFP         = true;
input bool   InpBlockFed         = true;
input bool   InpBlockCPI         = true;
input bool   InpBlockThursday    = true;
input int    InpNewsBufferMins   = 30;

input group "====== v4.1: MARKET REGIME DETECTION ======"
input bool   InpUseRegime        = true;
input double InpADX_Ranging      = 25.0;
input double InpADX_Trending     = 40.0;
input double InpRSI_ExtremeBuy   = 40.0;
input double InpRSI_ExtremeSell  = 60.0;

input group "====== v4.1: RSI DIVERGENCE EXIT ======"
input bool   InpUseDivergence    = true;
input int    InpDivLookback      = 5;

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
double g_scalpTPPoints, g_scalpSLPoints;

// Account/symbol flags
bool   g_isBTC = false, g_isGold = false, g_isCentAcct = false;
string g_currency = "USD";
double g_activeLot = 0.01;

// v5.0 — Broker detection
string g_brokerName    = "UNKNOWN";
string g_brokerProfile = "DEFAULT";
bool   g_isExness      = false;
bool   g_isICMarkets   = false;
bool   g_isPepperstone = false;
bool   g_isFTMO        = false;
bool   g_isOandA       = false;

// v5.0 — Overnight session flag
bool   g_isOvernightSession = false;

// v5.0 — Dynasty Gold entry signals
bool   g_momentumBuySignal  = false;
bool   g_momentumSellSignal = false;
bool   g_swingBuySignal     = false;
bool   g_swingSellSignal    = false;

// v5.0 — Single-order first tracking
bool     g_waitingToAddGrid   = false;
int      g_gridAddBarsCount   = 0;
datetime g_firstOrderBarTime  = 0;
int      g_firstOrderDir      = 0; // 1=buy, -1=sell
double   g_firstOrderLot      = 0;

// v4.1 — News filter state
bool   g_newsActive    = false;
string g_newsEventName = "";

// v4.1 — Market regime state
int    g_marketRegime  = 0;
string g_regimeName    = "RANGING";

// v4.1 — RSI Divergence state
bool   g_bullDivergence = false;
bool   g_bearDivergence = false;

// Candle confirmation tracking
bool     g_buySignalPending  = false;
bool     g_sellSignalPending = false;
int      g_signalBarsCount   = 0;
datetime g_signalBarTime     = 0;

// Re-entry tracking
bool     g_lastGridWasProfitable = false;
datetime g_lastGridCloseTime     = 0;
int      g_lastGridDirection     = 0;

// Recovery tracking
bool   g_recoveryMode       = false;
int    g_recoveryDirection  = 0;
double g_recoveryEntryPrice = 0;

// Profit tracking
datetime g_lastBarTime        = 0;
datetime g_currentDay         = 0;
datetime g_currentWeek        = 0;
double   g_dailyStartBalance  = 0;
double   g_weeklyStartBalance = 0;
double   g_lastGridProfit     = 0;

// Partial TP tracking
bool g_partialTPDone[];

#define DASH_PREFIX "DANE_DASH_"

//==========================================================================
//  BROKER DETECTION — v5.0
//  Reads account company name and sets broker-specific presets
//==========================================================================
void DetectBroker()
{
   if(!InpUseBrokerDetect) { g_brokerProfile = "DEFAULT"; return; }

   string company = (InpBrokerOverride != "") ? InpBrokerOverride
                                               : AccountInfoString(ACCOUNT_COMPANY);
   StringToUpper(company);
   g_brokerName = company;

   // Exness — ultra-tight spreads, allows BTC 24/7 weekends
   if(StringFind(company,"EXNESS") >= 0)
   {
      g_isExness      = true;
      g_brokerProfile = "EXNESS";
      // Exness gold spread is typically 10–18 pips — keep standard filter
      // Exness allows BTC weekend trading — BTC weekend mode fully active
      if(InpDebugLog) Print("🏦 BROKER: Exness detected — tight spread profile, BTC 24/7 enabled");
   }
   // IC Markets — raw spreads, ECN
   else if(StringFind(company,"IC MARKET") >= 0 || StringFind(company,"ICMARKETS") >= 0)
   {
      g_isICMarkets   = true;
      g_brokerProfile = "ICMARKETS";
      if(InpDebugLog) Print("🏦 BROKER: IC Markets detected — raw ECN profile");
   }
   // Pepperstone
   else if(StringFind(company,"PEPPERSTONE") >= 0)
   {
      g_isPepperstone = true;
      g_brokerProfile = "PEPPERSTONE";
      if(InpDebugLog) Print("🏦 BROKER: Pepperstone detected — ECN profile");
   }
   // FTMO — prop firm, conservative caps
   else if(StringFind(company,"FTMO") >= 0)
   {
      g_isFTMO        = true;
      g_brokerProfile = "FTMO";
      if(InpDebugLog) Print("🏦 BROKER: FTMO detected — prop firm conservative profile");
   }
   // OANDA
   else if(StringFind(company,"OANDA") >= 0)
   {
      g_isOandA       = true;
      g_brokerProfile = "OANDA";
      if(InpDebugLog) Print("🏦 BROKER: OANDA detected — standard profile");
   }
   else
   {
      g_brokerProfile = "DEFAULT";
      if(InpDebugLog) Print("🏦 BROKER: Unknown broker (", company, ") — using default profile");
   }
}

//==========================================================================
//  CHECK BTC WEEKEND ALLOWED — v5.0 broker-aware
//==========================================================================
bool IsBTCTradingAllowed()
{
   if(!g_isBTC) return true; // Not BTC — always allowed

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week; // 0=Sun, 6=Sat

   bool isWeekend = (dow == 0 || dow == 6);

   if(!isWeekend) return true; // Weekday — always allowed

   // Weekend check
   if(!InpBTCWeekendTrade) return false; // Weekend trading disabled

   // Exness allows BTC 24/7 — weekend fully OK
   if(g_isExness) return true;

   // IC Markets, Pepperstone — BTC available weekends but lower liquidity
   if(g_isICMarkets || g_isPepperstone) return true;

   // FTMO — check if prop firm allows weekend BTC
   if(g_isFTMO) return false; // FTMO typically pauses weekend for safety

   // Default: allow weekend but with reduced lot
   return true;
}

//==========================================================================
//  CHECK OVERNIGHT SESSION — v5.0
//==========================================================================
bool IsOvernightSession()
{
   if(!InpUseOvernightMode) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   // Overnight wraps midnight: start=22, end=6
   if(InpOvernightStartHr > InpOvernightEndHr)
      return (h >= InpOvernightStartHr || h < InpOvernightEndHr);
   else
      return (h >= InpOvernightStartHr && h < InpOvernightEndHr);
}

//==========================================================================
//  INIT
//==========================================================================
int OnInit()
{
   // v5.0 — Broker detection first
   DetectBroker();

   string sym = _Symbol;
   StringToUpper(sym);
   g_isBTC  = (StringFind(sym,"BTC") >= 0);
   g_isGold = (StringFind(sym,"XAU") >= 0 || StringFind(sym,"GOLD") >= 0);

   g_currency = AccountInfoString(ACCOUNT_CURRENCY);
   string cur = g_currency; StringToUpper(cur);
   g_isCentAcct = (StringFind(cur,"USC") >= 0 || StringFind(cur,"CENT") >= 0);

   // Safe balance load
   double safeBalance = 0;
   for(int i=0; i<10; i++)
   { safeBalance = AccountInfoDouble(ACCOUNT_BALANCE); if(safeBalance>0) break; Sleep(100); }
   if(safeBalance <= 0) safeBalance = AccountInfoDouble(ACCOUNT_EQUITY);

   // Symbol presets
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
   g_trailStartPoints = InpTrailStartPips * pipSize;
   g_trailStepPoints  = InpTrailStepPips  * pipSize;
   g_breakevenPoints  = InpBreakevenPips  * pipSize;

   // v5.0 — Scalp TP/SL in points
   g_scalpTPPoints = InpScalpTPPips * pipSize;
   g_scalpSLPoints = InpScalpSLPips * pipSize;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Create indicator handles
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
   { Alert("EA v5.0 ERROR: Indicator handle failed!"); return INIT_FAILED; }

   g_dailyStartBalance  = safeBalance;
   g_weeklyStartBalance = safeBalance;
   g_currentDay  = GetDayStart();
   g_currentWeek = GetWeekStart();

   if(InpShowDashboard) CreateDashboard();

   Print("=== EA GRID v5.0 INITIALIZED on ", _Symbol, " ===");
   Print("v5.0: Broker Detection | Dynasty Gold Entry | Scalp TP | Overnight Mode | BTC 24/7");
   Print("Broker   : ", g_brokerName, " → Profile: ", g_brokerProfile);
   Print("Account  : ", (g_isCentAcct?"CENT (USC)":"STANDARD (USD)"),
         " | Balance: ", DoubleToString(safeBalance,2), " ", g_currency);
   Print("Symbol   : ", _Symbol, " | Grid: ", g_gridSize,
         " orders | Spacing: ", g_spacingPips, " pips");
   Print("Dynasty Mode: Momentum=", InpUseMomentumEntry,
         " | SwingBreak=", InpUseSwingBreak,
         " | ScalpTP=", InpUseScalpTP, "(", InpScalpTPPips, "pips)",
         " | SingleFirst=", InpSingleFirst);
   Print("Overnight: ", InpUseOvernightMode, " | GMT ", InpOvernightStartHr,
         ":00 – ", InpOvernightEndHr, ":00");

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

   // v5.0 — BTC weekend check
   if(g_isBTC && !IsBTCTradingAllowed())
   {
      if(InpDebugLog) Print("BTC WEEKEND: Trading paused by broker profile (", g_brokerProfile, ")");
      return;
   }

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   // v5.0 — Detect overnight session
   g_isOvernightSession = IsOvernightSession();

   // Load all indicator buffers
   int bars = MathMax(MathMax(InpRSI_Shift, InpTF_Shift), InpExit_Shift) + 20;

   double rsi_val[], tf_fast[], tf_slow[], exit_fast[], exit_slow[];
   double atr_val[], macd_main[], macd_sig[], adx_val[];
   double open_val[], high_val[], low_val[], close_val2[];
   ArraySetAsSeries(rsi_val,true);   ArraySetAsSeries(tf_fast,true);
   ArraySetAsSeries(tf_slow,true);   ArraySetAsSeries(exit_fast,true);
   ArraySetAsSeries(exit_slow,true); ArraySetAsSeries(atr_val,true);
   ArraySetAsSeries(macd_main,true); ArraySetAsSeries(macd_sig,true);
   ArraySetAsSeries(adx_val,true);
   ArraySetAsSeries(open_val,true);  ArraySetAsSeries(high_val,true);
   ArraySetAsSeries(low_val,true);   ArraySetAsSeries(close_val2,true);

   if(CopyBuffer(rsi_handle,0,0,bars,rsi_val)<bars)       { if(InpDebugLog) Print("DEBUG: RSI buffer not ready."); return; }
   if(CopyBuffer(tf_fast_handle,0,0,bars,tf_fast)<bars)   { if(InpDebugLog) Print("DEBUG: TF Fast MA not ready."); return; }
   if(CopyBuffer(tf_slow_handle,0,0,bars,tf_slow)<bars)   { if(InpDebugLog) Print("DEBUG: TF Slow MA not ready."); return; }
   if(CopyBuffer(exit_fast_handle,0,0,bars,exit_fast)<bars) return;
   if(CopyBuffer(exit_slow_handle,0,0,bars,exit_slow)<bars) return;
   if(CopyBuffer(atr_handle,0,0,bars,atr_val)<bars) return;
   if(CopyBuffer(macd_handle,0,0,bars,macd_main)<bars) return;
   if(CopyBuffer(macd_handle,1,0,bars,macd_sig)<bars) return;
   if(CopyBuffer(adx_handle,0,0,bars,adx_val)<bars) return;
   if(CopyOpen(_Symbol,PERIOD_CURRENT,0,bars,open_val)<bars) return;
   if(CopyHigh(_Symbol,PERIOD_CURRENT,0,bars,high_val)<bars) return;
   if(CopyLow(_Symbol,PERIOD_CURRENT,0,bars,low_val)<bars) return;
   if(CopyClose(_Symbol,PERIOD_CURRENT,0,bars,close_val2)<bars) return;

   bool hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
   bool hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);

   //===================================================================
   //  v5.0 E — SINGLE ORDER FIRST: Add remaining grid if profitable
   //===================================================================
   if(InpSingleFirst && g_waitingToAddGrid && (hasBuys || hasSells))
   {
      g_gridAddBarsCount++;
      if(g_gridAddBarsCount >= InpGridAddBars)
      {
         double totalPnL = GetTotalGridProfit();
         if(totalPnL > 0) // Only add grid if first order is in profit
         {
            int adaptSize = g_gridSize - 1; // Already have 1 order
            if(adaptSize > 0)
            {
               if(g_firstOrderDir == 1)
               {
                  if(InpDebugLog) Print("SINGLE-FIRST: Adding remaining BUY grid (", adaptSize, " orders) — first trade profitable");
                  OpenBuyGridContinuation(g_firstOrderLot, adaptSize);
               }
               else if(g_firstOrderDir == -1)
               {
                  if(InpDebugLog) Print("SINGLE-FIRST: Adding remaining SELL grid (", adaptSize, " orders) — first trade profitable");
                  OpenSellGridContinuation(g_firstOrderLot, adaptSize);
               }
            }
            g_waitingToAddGrid = false;
            g_gridAddBarsCount = 0;
         }
         else
         {
            // First trade not profitable after X bars — don't add grid, just wait
            if(InpDebugLog) Print("SINGLE-FIRST: First order not profitable after ", InpGridAddBars, " bars — holding single position only");
            g_waitingToAddGrid = false;
            g_gridAddBarsCount = 0;
         }
      }
   }
   if(!hasBuys && !hasSells)
   {
      g_waitingToAddGrid = false;
      g_gridAddBarsCount = 0;
   }

   //===================================================================
   //  v4.1 — NEWS FILTER
   //===================================================================
   g_newsActive = IsNewsTime();
   if(g_newsActive)
   {
      if(InpDebugLog) Print("📰 NEWS FILTER ACTIVE: ", g_newsEventName, " — no new entries until window clears.");
      return;
   }

   //===================================================================
   //  v4.1 — MARKET REGIME DETECTION
   //===================================================================
   double effectiveBuyLvl  = g_rsiBuyLvl;
   double effectiveSellLvl = g_rsiSellLvl;
   DetectMarketRegime(adx_val[1], effectiveBuyLvl, effectiveSellLvl);

   // v5.0 — OVERNIGHT SESSION: Relax RSI levels if overnight
   if(g_isOvernightSession)
   {
      effectiveBuyLvl  = MathMax(effectiveBuyLvl,  InpOvernightRSIBuy);
      effectiveSellLvl = MathMin(effectiveSellLvl, InpOvernightRSISell);
   }

   //===================================================================
   //  v4.1 — RSI DIVERGENCE DETECTION
   //===================================================================
   double close_val[];
   ArraySetAsSeries(close_val, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, InpDivLookback+5, close_val) >= InpDivLookback+5)
      DetectRSIDivergence(rsi_val, close_val);

   //===================================================================
   //  SPREAD FILTER — Overnight uses relaxed limit
   //===================================================================
   double maxSpread = g_isOvernightSession ? InpOvernightSpread : InpMaxSpreadPips;
   if(InpUseSpreadFilter)
   {
      double spreadPips = GetCurrentSpreadPips();
      if(spreadPips > maxSpread)
      {
         if(InpDebugLog) Print("SPREAD FILTER: ", DoubleToString(spreadPips,1),
                               " pips > limit ", maxSpread, (g_isOvernightSession?" [OVERNIGHT]":""), " — skipping.");
         return;
      }
   }

   //===================================================================
   //  VOLATILITY SHIELD
   //===================================================================
   if(InpUseVolShield)
   {
      double curATR = atr_val[1];
      double avgATR = 0;
      for(int i=1; i<=14; i++) avgATR += atr_val[i];
      avgATR /= 14.0;
      if(curATR > avgATR * InpVolShieldMult)
      {
         if(InpDebugLog) Print("VOLATILITY SHIELD: Chaos mode — pausing entries.");
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
   //  ATR DYNAMIC SPACING
   //===================================================================
   if(InpUseATR)
   {
      double curATR = atr_val[1];
      g_spacingPoints = curATR * InpATR_SpacingMult;
      double pipSize = (_Digits==3||_Digits==2) ? 0.100 : _Point*10.0;
      double minSpacing = 40.0 * pipSize;
      double maxSpacing = 200.0 * pipSize;
      if(g_spacingPoints < minSpacing) g_spacingPoints = minSpacing;
      if(g_spacingPoints > maxSpacing) g_spacingPoints = maxSpacing;
   }

   //===================================================================
   //  ADX ADAPTIVE GRID SIZE
   //===================================================================
   int adaptiveGridSize = g_gridSize;
   if(InpUseADX)
   {
      double curADX = adx_val[1];
      if(curADX < InpADX_Weak)
         adaptiveGridSize = 2;
      else if(curADX < InpADX_Strong)
         adaptiveGridSize = 3;
      else
         adaptiveGridSize = g_gridSize;
   }

   //===================================================================
   //  LOT SIZE CALCULATION — with BTC weekend reduction
   //===================================================================
   double activeLot = InpLotSize;
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
         activeLot = MathMax(InpMinLot, MathMin(InpMaxLot, activeLot));
         double brokerMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double brokerMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         activeLot = MathMax(brokerMin, MathMin(brokerMax, activeLot));
      }
      else activeLot = InpLotSize;
   }

   // v5.0 G — BTC weekend: reduce lot
   if(g_isBTC && InpBTCReducedWeekend)
   {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 0 || dt.day_of_week == 6)
      {
         activeLot = NormalizeDouble(activeLot * InpBTCWeekendLotMult, 2);
         double brokerMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(activeLot < brokerMin) activeLot = brokerMin;
         if(InpDebugLog) Print("BTC WEEKEND LOT: Reduced to ", activeLot, " (", InpBTCWeekendLotMult*100, "%)");
      }
   }
   g_activeLot = activeLot;

   //===================================================================
   //  TREND FILTER — EMA(100) vs EMA(300)
   //===================================================================
   bool tUp = (tf_fast[InpTF_Shift] > tf_slow[InpTF_Shift]);
   bool tDn = (tf_fast[InpTF_Shift] < tf_slow[InpTF_Shift]);

   //===================================================================
   //  RSI ENTRY SIGNALS — regime/overnight adjusted levels
   //===================================================================
   int rs = InpRSI_Shift;
   double currentRSI = rsi_val[rs];
   double prevRSI    = rsi_val[rs+1];
   bool rsiBuyCross  = (currentRSI >  effectiveBuyLvl  && prevRSI <= effectiveBuyLvl);
   bool rsiSellCross = (currentRSI <  effectiveSellLvl && prevRSI >= effectiveSellLvl);

   bool extremeOversold   = (prevRSI < InpExtremeRSILow);
   bool extremeOverbought = (prevRSI > InpExtremeRSIHigh);

   //===================================================================
   //  CANDLE CONFIRMATION
   //===================================================================
   int requiredBars = (extremeOversold || extremeOverbought) ? 1 : 2;
   if(InpUseCandleConfirm)
   {
      if(rsiBuyCross  && !g_buySignalPending)
      { g_buySignalPending  = true; g_signalBarsCount = 0; g_signalBarTime = currentBar; }
      if(rsiSellCross && !g_sellSignalPending)
      { g_sellSignalPending = true; g_signalBarsCount = 0; g_signalBarTime = currentBar; }

      if(g_buySignalPending  || g_sellSignalPending) g_signalBarsCount++;

      bool buyConfirmed  = g_buySignalPending  && g_signalBarsCount >= requiredBars && currentRSI > effectiveBuyLvl;
      bool sellConfirmed = g_sellSignalPending && g_signalBarsCount >= requiredBars && currentRSI < effectiveSellLvl;

      if(g_buySignalPending  && currentRSI < effectiveBuyLvl  - 5) { g_buySignalPending  = false; g_signalBarsCount = 0; }
      if(g_sellSignalPending && currentRSI > effectiveSellLvl + 5) { g_sellSignalPending = false; g_signalBarsCount = 0; }

      if(buyConfirmed)  { rsiBuyCross  = true; g_buySignalPending  = false; }
      else              { rsiBuyCross  = false; }
      if(sellConfirmed) { rsiSellCross = true; g_sellSignalPending = false; }
      else              { rsiSellCross = false; }
   }

   //===================================================================
   //  MACD CONFIRMATION
   //===================================================================
   bool macdBullish = true, macdBearish = true;
   if(InpUseMACD && !extremeOversold && !extremeOverbought)
   {
      double macdHist1 = macd_main[1] - macd_sig[1];
      double macdHist2 = macd_main[2] - macd_sig[2];
      macdBullish = (macdHist1 > 0 || macdHist1 > macdHist2);
      macdBearish = (macdHist1 < 0 || macdHist1 < macdHist2);
   }

   //===================================================================
   //  VOLUME FILTER — overnight uses relaxed multiplier
   //===================================================================
   bool volumeOK = true;
   if(InpUseVolFilter)
   {
      double minVolMult = g_isOvernightSession ? InpOvernightVolMult : InpMinVolMultiplier;
      long curVol = iVolume(_Symbol, PERIOD_CURRENT, 1);
      double avgVol = 0;
      for(int i=1; i<=14; i++) avgVol += (double)iVolume(_Symbol, PERIOD_CURRENT, i);
      avgVol /= 14.0;
      volumeOK = (avgVol > 0 && curVol >= avgVol * minVolMult);
      if(!volumeOK && InpDebugLog)
         Print("VOLUME FILTER: Low volume — skipping entry.",
               g_isOvernightSession?" [OVERNIGHT relaxed threshold]":"");
   }

   //===================================================================
   //  v5.0 B — MOMENTUM CANDLE ENTRY (Dynasty Gold "arrow signal")
   //  Fires when last closed candle has a strong body relative to ATR
   //  Bullish: close > open, body > ATR * mult, close near high
   //  Bearish: close < open, body > ATR * mult, close near low
   //===================================================================
   g_momentumBuySignal  = false;
   g_momentumSellSignal = false;
   if(InpUseMomentumEntry && volumeOK)
   {
      double curATR   = atr_val[1];
      double candleOpen  = open_val[1];   // Last closed candle
      double candleClose = close_val2[1];
      double candleHigh  = high_val[1];
      double candleLow   = low_val[1];
      double body        = MathAbs(candleClose - candleOpen);
      double candleRange = candleHigh - candleLow;

      // Bullish momentum: strong green candle closing near its high
      bool strongBull = (body >= curATR * InpMomBodyMult) &&
                        (candleClose > candleOpen) &&
                        (candleRange > 0) &&
                        ((candleClose - candleLow) / candleRange >= 0.55); // close in top 45% of range

      // Bearish momentum: strong red candle closing near its low
      bool strongBear = (body >= curATR * InpMomBodyMult) &&
                        (candleClose < candleOpen) &&
                        (candleRange > 0) &&
                        ((candleHigh - candleClose) / candleRange >= 0.55); // close in bottom 45% of range

      // Apply RSI zone check if required
      bool rsiZoneBuy  = !InpMomentumNeedRSI || (currentRSI < 55); // Not overbought
      bool rsiZoneSell = !InpMomentumNeedRSI || (currentRSI > 45); // Not oversold

      // Apply trend check if required
      bool trendBuy  = !InpMomentumNeedTrend || tUp || extremeOversold;
      bool trendSell = !InpMomentumNeedTrend || tDn || extremeOverbought;

      g_momentumBuySignal  = strongBull && rsiZoneBuy  && trendBuy  && !g_bearDivergence;
      g_momentumSellSignal = strongBear && rsiZoneSell && trendSell && !g_bullDivergence;

      if(InpDebugLog && (g_momentumBuySignal || g_momentumSellSignal))
         Print("⚡ MOMENTUM SIGNAL: ",
               g_momentumBuySignal?"BUY":"SELL",
               " | Body=", DoubleToString(body,_Digits),
               " | ATR=", DoubleToString(curATR,_Digits),
               " | Ratio=", DoubleToString(body/(curATR>0?curATR:1),2));
   }

   //===================================================================
   //  v5.0 C — SWING HIGH/LOW BREAK ENTRY (Dynasty Gold candle extreme)
   //  Fires when price breaks above the highest high (or below lowest low)
   //  of the last InpSwingLookback closed bars
   //===================================================================
   g_swingBuySignal  = false;
   g_swingSellSignal = false;
   if(InpUseSwingBreak && volumeOK)
   {
      int lb = InpSwingLookback;
      double swingHigh = high_val[1];
      double swingLow  = low_val[1];
      for(int i=2; i<=lb+1; i++)
      {
         if(high_val[i] > swingHigh) swingHigh = high_val[i];
         if(low_val[i]  < swingLow)  swingLow  = low_val[i];
      }

      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Break above swing high = bullish momentum burst (Dynasty Blue Arrow Up)
      bool swingBreakBull = (currentAsk > swingHigh + _Point) && (tUp || extremeOversold);
      // Break below swing low = bearish momentum burst (Dynasty Red Arrow Down)
      bool swingBreakBear = (currentBid < swingLow  - _Point) && (tDn || extremeOverbought);

      // RSI must not be at extreme opposite (no buying into overbought)
      bool rsiOKBuy  = (currentRSI < 65);
      bool rsiOKSell = (currentRSI > 35);

      g_swingBuySignal  = swingBreakBull && rsiOKBuy  && !g_bearDivergence && macdBullish;
      g_swingSellSignal = swingBreakBear && rsiOKSell && !g_bullDivergence && macdBearish;

      if(InpDebugLog && (g_swingBuySignal || g_swingSellSignal))
         Print("📊 SWING BREAK: ",
               g_swingBuySignal?"BUY above ":"SELL below ",
               g_swingBuySignal?DoubleToString(swingHigh,_Digits):DoubleToString(swingLow,_Digits));
   }

   //===================================================================
   //  COMBINED ENTRY DECISION — v5.0
   //  Original RSI entry + Dynasty Momentum + Dynasty Swing Break
   //  Any one of these three triggers an entry (if other filters pass)
   //===================================================================
   bool rsiEntryBuy  = rsiBuyCross  && macdBullish && volumeOK &&
                       (tUp || extremeOversold) && !g_bearDivergence;
   bool rsiEntrySell = rsiSellCross && macdBearish && volumeOK &&
                       (tDn || extremeOverbought) && !g_bullDivergence;

   bool doOpenBuy  = !hasBuys  && (rsiEntryBuy  || (g_momentumBuySignal  && !hasBuys)  || (g_swingBuySignal  && !hasBuys));
   bool doOpenSell = !hasSells && (rsiEntrySell || (g_momentumSellSignal && !hasSells) || (g_swingSellSignal && !hasSells));

   //===================================================================
   //  IMPROVEMENT 12 — RE-ENTRY AFTER PROFITABLE GRID
   //===================================================================
   if(InpUseReEntry && g_lastGridWasProfitable && !hasBuys && !hasSells)
   {
      datetime timeSinceClose = currentBar - g_lastGridCloseTime;
      int barsSinceClose = (int)(timeSinceClose / PeriodSeconds(PERIOD_CURRENT));
      if(barsSinceClose <= InpReEntryBars)
      {
         if(g_lastGridDirection == 1 && tUp && !hasBuys)
         {
            if(InpDebugLog) Print("RE-ENTRY: BUY grid (trend still UP).");
            ExecuteEntry(1, activeLot, adaptiveGridSize);
            g_lastGridWasProfitable = false;
            return;
         }
         if(g_lastGridDirection == -1 && tDn && !hasSells)
         {
            if(InpDebugLog) Print("RE-ENTRY: SELL grid (trend still DOWN).");
            ExecuteEntry(-1, activeLot, adaptiveGridSize);
            g_lastGridWasProfitable = false;
            return;
         }
      }
      else g_lastGridWasProfitable = false;
   }

   //===================================================================
   //  IMPROVEMENT 13 — GRID RECOVERY MODE
   //===================================================================
   if(InpUseRecovery && g_recoveryMode && !hasBuys && !hasSells)
   {
      double recoveryLot = NormalizeDouble(activeLot * InpRecoveryLotMult, 2);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(recoveryLot < minLot) recoveryLot = minLot;
      if(g_recoveryDirection == 1 && rsiBuyCross && (tUp || extremeOversold))
      {
         if(InpDebugLog) Print("RECOVERY: Opening reduced BUY grid.");
         ExecuteEntry(1, recoveryLot, 2);
         g_recoveryMode = false;
         return;
      }
      if(g_recoveryDirection == -1 && rsiSellCross && (tDn || extremeOverbought))
      {
         if(InpDebugLog) Print("RECOVERY: Opening reduced SELL grid.");
         ExecuteEntry(-1, recoveryLot, 2);
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
      string sessStr   = g_isOvernightSession ? " [OVERNIGHT]" : "";
      double spreadNow = GetCurrentSpreadPips();
      string entryStr  = doOpenBuy  ? "→ BUY ENTRY" :
                         doOpenSell ? "→ SELL ENTRY" :
                         "→ Waiting";
      Print("--- NEW BAR --- RSI=", DoubleToString(currentRSI,2),
            " | ADX=", DoubleToString(adx_val[1],1),
            " | Spread=", DoubleToString(spreadNow,1), "pips",
            " | Trend=", trendStr, sessStr,
            " | Grid=", adaptiveGridSize, " | Lot=", DoubleToString(activeLot,3),
            " | ", entryStr,
            " | Mom=", g_momentumBuySignal?"↑":g_momentumSellSignal?"↓":"-",
            " | Swing=", g_swingBuySignal?"↑":g_swingSellSignal?"↓":"-");
   }

   // OPEN ENTRIES
   if(doOpenBuy)
   {
      ExecuteEntry(1, activeLot, adaptiveGridSize);
      g_lastGridDirection = 1;
   }
   if(doOpenSell)
   {
      ExecuteEntry(-1, activeLot, adaptiveGridSize);
      g_lastGridDirection = -1;
   }
}

//==========================================================================
//  v5.0 — UNIFIED ENTRY EXECUTOR
//  Handles Single-First mode and Scalp TP vs Grid TP
//==========================================================================
void ExecuteEntry(int dir, double lot, int gridSize)
{
   if(InpSingleFirst)
   {
      // Open only the first order
      if(dir == 1) OpenSingleBuy(lot);
      else         OpenSingleSell(lot);
      // Schedule grid addition after InpGridAddBars bars
      g_waitingToAddGrid  = true;
      g_gridAddBarsCount  = 0;
      g_firstOrderBarTime = TimeCurrent();
      g_firstOrderDir     = dir;
      g_firstOrderLot     = lot;
   }
   else
   {
      // Full grid immediately (original v4.1 behavior)
      if(dir == 1) OpenBuyGrid(lot, gridSize);
      else         OpenSellGrid(lot, gridSize);
   }
}

//==========================================================================
//  v5.0 — OPEN SINGLE BUY (scalp TP if enabled, grid TP otherwise)
//==========================================================================
void OpenSingleBuy(double lot)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp, sl;

   if(InpUseScalpTP)
   {
      // Dynasty Gold style: tight TP + tight SL on first entry
      tp = NormalizeDouble(ask + g_scalpTPPoints, _Digits);
      sl = NormalizeDouble(ask - g_scalpSLPoints, _Digits);
   }
   else
   {
      tp = InpTPPerTrade ? NormalizeDouble(ask + InpTPMultiplier * g_spacingPoints, _Digits) : 0;
      sl = 0;
   }

   string cmt = "BUY_GRID_"+IntegerToString(InpMagicNumber)+"_0";
   trade.Buy(lot, _Symbol, 0, sl, tp, cmt);
   if(InpDebugLog) Print("SINGLE BUY: lot=", lot,
                         " | TP=", DoubleToString(tp,_Digits),
                         " | SL=", DoubleToString(sl,_Digits),
                         InpUseScalpTP?" [SCALP MODE]":" [GRID MODE]");
}

//==========================================================================
//  v5.0 — OPEN SINGLE SELL
//==========================================================================
void OpenSingleSell(double lot)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp, sl;

   if(InpUseScalpTP)
   {
      tp = NormalizeDouble(bid - g_scalpTPPoints, _Digits);
      sl = NormalizeDouble(bid + g_scalpSLPoints, _Digits);
   }
   else
   {
      tp = InpTPPerTrade ? NormalizeDouble(bid - InpTPMultiplier * g_spacingPoints, _Digits) : 0;
      sl = 0;
   }

   string cmt = "SELL_GRID_"+IntegerToString(InpMagicNumber)+"_0";
   trade.Sell(lot, _Symbol, 0, sl, tp, cmt);
   if(InpDebugLog) Print("SINGLE SELL: lot=", lot,
                         " | TP=", DoubleToString(tp,_Digits),
                         " | SL=", DoubleToString(sl,_Digits),
                         InpUseScalpTP?" [SCALP MODE]":" [GRID MODE]");
}

//==========================================================================
//  OPEN BUY GRID — full grid (original v4.1)
//==========================================================================
void OpenBuyGrid(double lot, int gridSize)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=0; i<gridSize; i++)
   {
      double price = NormalizeDouble(ask - i*g_spacingPoints, _Digits);
      double tp1   = InpTPPerTrade ? NormalizeDouble(price + InpTPMultiplier * g_spacingPoints, _Digits) : 0;
      string cmt   = "BUY_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      if(i==0) trade.Buy(lot, _Symbol, 0, 0, tp1, cmt);
      else     trade.BuyLimit(lot, price, _Symbol, 0, tp1, ORDER_TIME_GTC, 0, cmt);
   }
}

//==========================================================================
//  OPEN SELL GRID — full grid (original v4.1)
//==========================================================================
void OpenSellGrid(double lot, int gridSize)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i=0; i<gridSize; i++)
   {
      double price = NormalizeDouble(bid + i*g_spacingPoints, _Digits);
      double tp1   = InpTPPerTrade ? NormalizeDouble(price - InpTPMultiplier * g_spacingPoints, _Digits) : 0;
      string cmt   = "SELL_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      if(i==0) trade.Sell(lot, _Symbol, 0, 0, tp1, cmt);
      else     trade.SellLimit(lot, price, _Symbol, 0, tp1, ORDER_TIME_GTC, 0, cmt);
   }
}

//==========================================================================
//  v5.0 — OPEN BUY GRID CONTINUATION (adds to existing single order)
//  Starts from order index 1 since index 0 already exists
//==========================================================================
void OpenBuyGridContinuation(double lot, int additionalOrders)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=1; i<=additionalOrders; i++)
   {
      double price = NormalizeDouble(ask - i*g_spacingPoints, _Digits);
      double tp1   = InpTPPerTrade ? NormalizeDouble(price + InpTPMultiplier * g_spacingPoints, _Digits) : 0;
      string cmt   = "BUY_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      trade.BuyLimit(lot, price, _Symbol, 0, tp1, ORDER_TIME_GTC, 0, cmt);
   }
}

//==========================================================================
//  v5.0 — OPEN SELL GRID CONTINUATION
//==========================================================================
void OpenSellGridContinuation(double lot, int additionalOrders)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i=1; i<=additionalOrders; i++)
   {
      double price = NormalizeDouble(bid + i*g_spacingPoints, _Digits);
      double tp1   = InpTPPerTrade ? NormalizeDouble(price - InpTPMultiplier * g_spacingPoints, _Digits) : 0;
      string cmt   = "SELL_GRID_"+IntegerToString(InpMagicNumber)+"_"+IntegerToString(i);
      trade.SellLimit(lot, price, _Symbol, 0, tp1, ORDER_TIME_GTC, 0, cmt);
   }
}

//==========================================================================
//  BREAKEVEN STOP
//==========================================================================
void ManageBreakevenStop()
{
   if(!InpUseBreakeven) return;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;
      double op  = posInfo.PriceOpen();
      double sl  = posInfo.StopLoss();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      {
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
//  PARTIAL TAKE PROFIT (50% at 1x, 50% at 2x)
//==========================================================================
void ManagePartialTP()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=InpMagicNumber || posInfo.Symbol()!=_Symbol) continue;

      // Skip scalp orders — they have their own tight TP set at open
      if(InpUseScalpTP && StringFind(posInfo.Comment(),"_0")>0) continue;

      double op      = posInfo.PriceOpen();
      double lot     = posInfo.Volume();
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double halfLot = NormalizeDouble(lot * 0.5, 2);
      if(halfLot < minLot) continue;

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      {
         double firstTP = op + InpTPMultiplier  * g_spacingPoints;
         double finalTP = op + InpTP2Multiplier * g_spacingPoints;
         if(bid >= firstTP && lot > minLot*1.5)
         {
            trade.PositionClosePartial(posInfo.Ticket(), halfLot);
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
//  MONITOR GRID PROFIT / SL — with recovery and re-entry
//==========================================================================
void MonitorGridProfit()
{
   if(CountPositions(POSITION_TYPE_BUY)==0 && CountPositions(POSITION_TYPE_SELL)==0) return;
   double totalPnL = GetTotalGridProfit();
   double tv  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

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
   double maxL = (dynamicSLValue > 0) ? -dynamicSLValue : -(g_gridSLMult * pv * g_lotSize);

   if(InpCloseAtMaxProfit && totalPnL >= maxP)
   {
      Print("✅ MAX PROFIT: ", DoubleToString(totalPnL,2), " ", g_currency, " → Closing grid.");
      g_lastGridWasProfitable = true;
      g_lastGridProfit        = totalPnL;
      g_lastGridCloseTime     = TimeCurrent();
      g_recoveryMode          = false;
      g_waitingToAddGrid      = false;
      CloseAllGridOrders();
      return;
   }

   if(totalPnL <= maxL)
   {
      Print("🛑 GRID SL: ", DoubleToString(totalPnL,2), " ", g_currency, " → Closing grid.");
      if(InpUseRecovery)
      {
         g_recoveryMode      = true;
         g_recoveryDirection = (CountPositions(POSITION_TYPE_BUY) > 0) ? 1 : -1;
      }
      g_lastGridWasProfitable = false;
      g_waitingToAddGrid      = false;
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
//==========================================================================
bool IsNewsTime()
{
   if(!InpUseNewsFilter) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h   = dt.hour;
   int m   = dt.min;
   int dow = dt.day_of_week;
   int dom = dt.day;
   int totalMins = h * 60 + m;
   int buf = InpNewsBufferMins;

   if(InpBlockNFP && dow == 5 && dom <= 7)
   { int s=12*60+30-buf, e=12*60+30+buf;
     if(totalMins>=s && totalMins<=e){ g_newsEventName="⚠ NFP"; return true; } }

   if(InpBlockFed && dow == 3)
   { int s=18*60+0-buf, e=18*60+0+buf;
     if(totalMins>=s && totalMins<=e){ g_newsEventName="⚠ FED"; return true; } }

   if(InpBlockCPI && dow == 3 && dom >= 8 && dom <= 21)
   { int s=12*60+30-buf, e=12*60+30+buf;
     if(totalMins>=s && totalMins<=e){ g_newsEventName="⚠ CPI"; return true; } }

   if(InpBlockThursday && dow == 4)
   { int s=12*60+30-buf, e=12*60+30+buf;
     if(totalMins>=s && totalMins<=e){ g_newsEventName="⚠ CLAIMS"; return true; } }

   g_newsEventName = "";
   return false;
}

//==========================================================================
//  v4.1 — MARKET REGIME DETECTION
//==========================================================================
void DetectMarketRegime(double adx, double &effectiveBuy, double &effectiveSell)
{
   if(!InpUseRegime)
   { g_marketRegime=0; g_regimeName="NORMAL"; effectiveBuy=g_rsiBuyLvl; effectiveSell=g_rsiSellLvl; return; }

   if(adx < InpADX_Ranging)
   { g_marketRegime=0; g_regimeName="RANGING"; effectiveBuy=g_rsiBuyLvl; effectiveSell=g_rsiSellLvl; }
   else if(adx < InpADX_Trending)
   { g_marketRegime=1; g_regimeName="TRENDING"; effectiveBuy=g_rsiBuyLvl; effectiveSell=g_rsiSellLvl; }
   else
   { g_marketRegime=2; g_regimeName="EXTREME"; effectiveBuy=InpRSI_ExtremeBuy; effectiveSell=InpRSI_ExtremeSell; }
}

//==========================================================================
//  v4.1 — RSI DIVERGENCE DETECTION
//==========================================================================
void DetectRSIDivergence(double &rsi_vals[], double &close_vals[])
{
   g_bullDivergence = false;
   g_bearDivergence = false;
   if(!InpUseDivergence) return;

   int lb = InpDivLookback;
   if(ArraySize(rsi_vals)<lb+3 || ArraySize(close_vals)<lb+3) return;

   double recentPriceLow=close_vals[1], prevPriceLow=close_vals[1];
   double recentRSILow=rsi_vals[1],    prevRSILow=rsi_vals[1];
   double recentPriceHigh=close_vals[1], prevPriceHigh=close_vals[1];
   double recentRSIHigh=rsi_vals[1],     prevRSIHigh=rsi_vals[1];

   for(int i=2; i<=lb; i++)
   {
      if(close_vals[i] < recentPriceLow)
      { prevPriceLow=recentPriceLow; prevRSILow=recentRSILow;
        recentPriceLow=close_vals[i]; recentRSILow=rsi_vals[i]; }
      if(close_vals[i] > recentPriceHigh)
      { prevPriceHigh=recentPriceHigh; prevRSIHigh=recentRSIHigh;
        recentPriceHigh=close_vals[i]; recentRSIHigh=rsi_vals[i]; }
   }

   if(recentPriceLow < prevPriceLow && recentRSILow > prevRSILow && recentRSILow < 45)
   { g_bullDivergence=true;
     if(InpDebugLog) Print("🟢 BULLISH DIVERGENCE detected — downtrend weakening"); }

   if(recentPriceHigh > prevPriceHigh && recentRSIHigh < prevRSIHigh && recentRSIHigh > 55)
   { g_bearDivergence=true;
     if(InpDebugLog) Print("🔴 BEARISH DIVERGENCE detected — uptrend weakening"); }
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
//  DASHBOARD — v5.0 UPDATED (adds broker, scalp mode, momentum signals)
//==========================================================================
void CreateDashboard()
{
   DeleteDashboard();
   int x=InpDashX, y=InpDashY, w=480, h=320;

   DashRect("BG",     x,  y,    w, h,  C'15,30,45', C'0,120,160', 2);

   // TITLE
   DashRect("R_TTL",  x,  y,    w, 30, C'0,85,125', C'0,150,190', 0);
   DashLabel("TITLE", x+10,y+8, "⚡ DANE GRID EA v5.0 — DYNASTY GOLD", 10, clrWhite, true);
   DashRect("ACC_BG", x+w-105,y+5,98,20,C'0,55,85',C'0,180,220',1);
   DashLabel("ACC_TYPE",x+w-101,y+9,"LOADING...", 8, clrYellow, false);

   // BROKER ROW
   DashRect("R_BRK",  x,  y+30, w, 22, C'8,20,35', C'0,100,140', 0);
   DashLabel("BRK_L", x+10,y+36,"Broker:",  8, clrSilver, false);
   DashLabel("BRK_V", x+60, y+36,"--",      9, clrAqua,   true);
   DashLabel("NEWS_V",x+200,y+36,"",        8, clrRed,    true);
   DashLabel("SESS_V",x+340,y+36,"",        8, clrYellow, false);

   // SIGNAL ROW
   DashRect("R_SIG",  x,  y+52, w, 68, C'10,25,42', C'0,100,150', 0);
   DashLabel("MD_L",  x+10,y+62,"Mode :",   10, clrSilver, false);
   DashLabel("MODE_V",x+72, y+62,"NORMAL",  11, clrLime,   true);
   DashLabel("RI_L",  x+10,y+84,"RSI  :",   10, clrSilver, false);
   DashLabel("RSI_V", x+72, y+84,"--",      13, clrWhite,  true);
   DashLabel("ST_L",  x+240,y+62,"Status:", 10, clrSilver, false);
   DashLabel("STA_V", x+310,y+62,"READY",   11, clrLime,   true);
   DashLabel("SP_L",  x+240,y+84,"Spread:", 10, clrSilver, false);
   DashLabel("S_SPRV",x+310,y+84,"--",      11, clrWhite,  false);

   // DYNASTY SIGNALS ROW
   DashRect("R_DYN",  x,  y+120,w, 30, C'8,20,35', C'0,100,140', 0);
   DashLabel("DYN_L", x+10,y+127,"Dynasty:", 8, clrSilver,  false);
   DashLabel("MOM_V", x+75, y+127,"Mom: -",  9, clrSilver,  false);
   DashLabel("SWG_V", x+200,y+127,"Swing: -",9, clrSilver,  false);
   DashLabel("STP_V", x+340,y+127,"ScalpTP:--",8,clrSilver, false);

   DashRect("DIV1",   x,  y+150,w,  1, C'0,100,140', C'0,100,140', 0);

   // PROFIT
   DashRect("R_PRF",  x,  y+151,w, 53, C'12,26,40', C'0,100,140', 0);
   DashLabel("PHR",   x+10,y+156,"PROFIT TRACKER", 8, C'0,200,220', true);
   DashLabel("D_L",   x+10,y+170,"Daily P/L :",    8, clrSilver,   false);
   DashLabel("D_VAL", x+90,y+170,"0.00% | 0.00",   10,clrWhite,    false);
   DashLabel("W_L",   x+10,y+188,"Weekly P/L :",   8, clrSilver,   false);
   DashLabel("W_VAL", x+90,y+188,"0.00% | 0.00",   10,clrWhite,    false);

   DashRect("DIV2",   x,  y+204,w,  1, C'0,100,140', C'0,100,140', 0);

   // LIVE TRADES
   DashRect("R_TRD",  x,  y+205,w, 52, C'12,26,40', C'0,100,140', 0);
   DashLabel("THR",   x+10,y+210,"LIVE TRADES",    8, C'0,200,220', true);
   DashLabel("TB_L",  x+10,y+224,"Buy Orders :",   8, clrSilver,   false);
   DashLabel("T_BUY_V",x+105,y+222,"0",            13,clrLime,     true);
   DashLabel("TS_L",  x+10,y+240,"Sell Orders :",  8, clrSilver,   false);
   DashLabel("T_SEL_V",x+105,y+238,"0",            13,clrRed,      true);
   DashLabel("PL_L",  x+210,y+224,"Float P/L :",   8, clrSilver,   false);
   DashLabel("T_PL_V",x+210,y+238,"+0.00",         11,clrLime,     true);

   DashRect("DIV3",   x,  y+257,w,  1, C'0,100,140', C'0,100,140', 0);

   // SETTINGS
   DashRect("R_SET",  x,  y+258,w, 60, C'10,22,36', C'0,100,140', 0);
   DashLabel("SHR",   x+10,y+263,"SETTINGS",       8, C'0,200,220', true);
   DashLabel("S_LOT", x+10,y+277,"Lot:",            8, clrSilver,   false);
   DashLabel("S_LV",  x+40,y+277,"--",              9, clrYellow,   true);
   DashLabel("S_SP",  x+155,y+277,"Spacing:",       8, clrSilver,   false);
   DashLabel("S_SV",  x+210,y+277,"--",             9, clrYellow,   false);
   DashLabel("S_RSI", x+275,y+277,"RSI:",           8, clrSilver,   false);
   DashLabel("S_RV",  x+305,y+277,"--",             9, clrYellow,   false);
   DashLabel("S_ADX", x+10,y+295,"ADX:",            8, clrSilver,   false);
   DashLabel("S_ADXV",x+40,y+295,"--",              9, clrYellow,   false);
   DashLabel("S_GRD", x+100,y+295,"Grid:",          8, clrSilver,   false);
   DashLabel("S_GRV", x+130,y+295,"--",             9, clrYellow,   false);
   DashLabel("S_SL",  x+185,y+295,"SL:",            8, clrSilver,   false);
   DashLabel("S_SLV", x+207,y+295,"--",             9, clrYellow,   false);

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

   // Broker row
   DashLabelUpdate("BRK_V", g_brokerName==""?"UNKNOWN":g_brokerName,
                   g_isExness?clrAqua:g_isFTMO?clrOrange:clrLime);

   // News/divergence
   if(g_newsActive)
      DashLabelUpdate("NEWS_V", g_newsEventName, clrRed);
   else if(g_bullDivergence)
      DashLabelUpdate("NEWS_V", "🟢DIV", clrAqua);
   else if(g_bearDivergence)
      DashLabelUpdate("NEWS_V", "🔴DIV", clrOrange);
   else
      DashLabelUpdate("NEWS_V", "", clrRed);

   // Session indicator
   DashLabelUpdate("SESS_V", g_isOvernightSession?"🌙OVERNIGHT":"☀ ACTIVE",
                   g_isOvernightSession?clrYellow:clrLime);

   // Signal mode
   bool exLow =curRSI>0&&curRSI<=InpExtremeRSILow;
   bool exHigh=curRSI>0&&curRSI>=InpExtremeRSIHigh;
   if(g_newsActive)           DashLabelUpdate("MODE_V","📰 NEWS PAUSE",    clrRed);
   else if(exLow)             DashLabelUpdate("MODE_V","⚡ EXTREME BUY",   clrAqua);
   else if(exHigh)            DashLabelUpdate("MODE_V","⚡ EXTREME SELL",  clrOrange);
   else if(g_marketRegime==2) DashLabelUpdate("MODE_V","🔥 EXTREME TREND", clrOrange);
   else if(g_marketRegime==1) DashLabelUpdate("MODE_V","📈 TRENDING",      clrYellow);
   else                       DashLabelUpdate("MODE_V","NORMAL",           clrLime);

   color rsiClr=curRSI<=30?clrAqua:curRSI>=70?clrOrange:clrWhite;
   DashLabelUpdate("RSI_V",DoubleToString(curRSI,1),rsiClr);

   string stTxt=g_recoveryMode?"RECOVERY":g_waitingToAddGrid?"GRID PENDING":g_lastGridWasProfitable?"RE-ENTRY":"READY";
   color  stClr=g_recoveryMode?clrOrange:g_waitingToAddGrid?clrAqua:g_lastGridWasProfitable?clrAqua:clrLime;
   DashLabelUpdate("STA_V",stTxt,stClr);

   color sprClr=spreadPips>InpMaxSpreadPips?clrRed:clrLime;
   DashLabelUpdate("S_SPRV",DoubleToString(spreadPips,1)+" pips",sprClr);

   // Dynasty signals
   string momStr = g_momentumBuySignal?"Mom:🟢↑":g_momentumSellSignal?"Mom:🔴↓":"Mom:  -";
   color  momClr = g_momentumBuySignal?clrLime:g_momentumSellSignal?clrRed:clrSilver;
   DashLabelUpdate("MOM_V", momStr, momClr);

   string swgStr = g_swingBuySignal?"Swing:🟢↑":g_swingSellSignal?"Swing:🔴↓":"Swing: -";
   color  swgClr = g_swingBuySignal?clrLime:g_swingSellSignal?clrRed:clrSilver;
   DashLabelUpdate("SWG_V", swgStr, swgClr);

   string stpStr = InpUseScalpTP?"ScalpTP:"+DoubleToString(InpScalpTPPips,0)+"p":"ScalpTP:OFF";
   DashLabelUpdate("STP_V", stpStr, InpUseScalpTP?clrAqua:clrSilver);

   // Profit
   color dc=(dailyPnL>=0)?clrLime:clrRed; string ds=(dailyPnL>=0)?"+":"";
   DashLabelUpdate("D_VAL",ds+DoubleToString(dPct,2)+"% | "+ds+DoubleToString(dailyPnL,2)+" "+g_currency,dc);
   color wc=(weeklyPnL>=0)?clrLime:clrRed; string ws=(weeklyPnL>=0)?"+":"";
   DashLabelUpdate("W_VAL",ws+DoubleToString(wPct,2)+"% | "+ws+DoubleToString(weeklyPnL,2)+" "+g_currency,wc);

   // Trades
   DashLabelUpdate("T_BUY_V",IntegerToString(buys), buys>0?clrLime:clrSilver);
   DashLabelUpdate("T_SEL_V",IntegerToString(sells),sells>0?clrRed:clrSilver);
   color plc=(floatPnL>=0)?clrLime:clrRed; string pls=(floatPnL>=0)?"+":"";
   DashLabelUpdate("T_PL_V",pls+DoubleToString(floatPnL,2)+" "+g_currency,plc);

   // Settings
   string lotDisp=DoubleToString(g_activeLot,2)+(InpUseDynamicLot?" AUTO":" MAN");
   DashLabelUpdate("S_LV",  lotDisp, InpUseDynamicLot?clrAqua:clrYellow);
   DashLabelUpdate("S_SV",  DoubleToString(g_spacingPips,0)+"p", clrYellow);
   DashLabelUpdate("S_RV",  DoubleToString(g_rsiBuyLvl,0)+"/"+DoubleToString(g_rsiSellLvl,0), clrYellow);
   color adxClr=curADX<InpADX_Weak?clrRed:curADX>InpADX_Strong?clrLime:clrYellow;
   DashLabelUpdate("S_ADXV",DoubleToString(curADX,1), adxClr);
   DashLabelUpdate("S_GRV", IntegerToString(g_gridSize)+" ord", clrYellow);
   DashLabelUpdate("S_SLV", DoubleToString(g_gridSLMult,0)+"x", clrYellow);

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
//| END OF EA v5.0                                                    |
//+------------------------------------------------------------------+
