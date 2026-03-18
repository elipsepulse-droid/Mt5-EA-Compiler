//+------------------------------------------------------------------+
//|         EA_Scalping_Grid_GOLD_BTC_v3.2.mq5                       |
//|     Universal Grid Scalping Robot - XAUUSD & BTCUSD M5           |
//|                                                                  |
//|  v3.2 CHANGES:                                                   |
//|  - Full Exness Cent Account support (XAUUSDc, BTCUSDc)           |
//|  - Auto-detects cent account & adjusts money values to USC       |
//|  - Safe preset for 2000 USC ($20 USD) small capital              |
//|  - Daily loss limit in account currency (USC or USD auto)        |
//|  - Grid reduced to 4 orders for cent account safety              |
//|                                                                  |
//|  SYMBOL SUPPORT (auto-detected):                                 |
//|  XAUUSD, XAUUSDm, XAUUSDc — Gold standard / cent / raw          |
//|  BTCUSD, BTCUSDm, BTCUSDc — BTC  standard / cent / raw          |
//|                                                                  |
//|  CENT ACCOUNT NOTE:                                              |
//|  2000 USC = $20.00 USD real money (USC = US Cents)               |
//|  All money values (profit/loss/balance) shown in USC on MT5      |
//|                                                                  |
//|  STRATEGY:                                                       |
//|  ENTRY  : RSI crosses UP/DOWN through levels → BUY/SELL Grid    |
//|  FILTER : EMA(100) vs EMA(300) trend direction                  |
//|  EXIT   : EMA(50) crosses EMA(200) — directional exit           |
//|  TRAIL  : Trailing stop to lock in profits                       |
//|  SAFETY : Daily loss limit + Grid SL + Max Profit target         |
//|  Best PHT time: 8:00 PM – 11:00 PM (London + NY overlap)        |
//+------------------------------------------------------------------+
#property copyright   "EA SCALPING ROBOT / DANE - v3.2"
#property version     "3.20"
#property description "Universal Grid EA — XAUUSD/BTCUSD — Cent & Standard Account"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//==========================================================================
//  INPUT PARAMETERS
//==========================================================================

input group "====== SYMBOL MODE ======"
input bool InpAutoDetect = true;
// true  = EA auto-detects symbol & account type, applies correct preset
// false = EA uses manual values below

input group "====== GRID SETUP (Manual / Auto-overridden if AutoDetect=true) ======"
input int    InpGridSize       = 4;       // Grid Size (orders per side)
input double InpSpacingPips    = 80;      // Spacing in Pips
input double InpLotSize        = 0.01;    // Volume per Order (Lot)
input bool   InpMoveGrid       = true;    // Move Grid

input group "====== TRADE MANAGEMENT ======"
input bool   InpTPPerTrade       = true;  // Take Profit per Trade
input double InpTPMultiplier     = 1.0;   // TP = X x Spacing
input bool   InpCloseAtMaxProfit = true;  // Close Grid at Max Profit
input double InpMaxProfitMult    = 4.0;   // Max Profit = X x Spacing
input double InpGridSLMult       = 5.0;   // Grid SL = X x Spacing

input group "====== TRAILING STOP ======"
input bool   InpUseTrailing    = true;
input double InpTrailStartPips = 40;      // Trail activates after X pips
input double InpTrailStepPips  = 20;      // Trail step in pips

input group "====== DAILY LOSS PROTECTION ======"
// IMPORTANT: Enter this value in YOUR account currency
// USC (Cent account) : 500 = 500 USC = $5.00 USD (25% of 2000 USC)
// USD (Real account) : 50  = $50 USD
input bool   InpUseDailyLoss   = true;
input double InpDailyLossAmt   = 500.0;  // Daily loss limit in account currency

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

input group "====== GENERAL ======"
input ulong  InpMagicNumber = 654321;
input int    InpSlippage    = 50;

//==========================================================================
//  GLOBAL VARIABLES
//==========================================================================
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    ordInfo;

int      rsi_handle;
int      tf_fast_handle, tf_slow_handle;
int      exit_fast_handle, exit_slow_handle;

// Live runtime values (auto-set or manual)
double   g_spacingPips;
int      g_gridSize;
double   g_lotSize;
double   g_rsiBuyLvl;
double   g_rsiSellLvl;
double   g_trailStartPips;
double   g_trailStepPips;
double   g_dailyLossAmt;     // In account currency (USC or USD)
double   g_maxProfitMult;
double   g_gridSLMult;

// Computed distances
double   g_spacingPoints;
double   g_trailStartPoints;
double   g_trailStepPoints;

// Symbol & account flags
bool     g_isBTC        = false;
bool     g_isGold       = false;
bool     g_isCentAcct   = false;   // true = USC cent account

datetime g_lastBarTime       = 0;
datetime g_currentDay        = 0;
double   g_dailyStartBalance = 0;

//==========================================================================
//  INIT
//==========================================================================
int OnInit()
{
   //--- Symbol Detection
   // Supports all Exness variants:
   // XAUUSDc (cent), XAUUSDm (micro), XAUUSD (standard), XAUUSD. (raw)
   // BTCUSDc (cent), BTCUSDm (micro), BTCUSD (standard)
   string sym = _Symbol;
   StringToUpper(sym);
   g_isBTC  = (StringFind(sym, "BTC")  >= 0);
   g_isGold = (StringFind(sym, "XAU")  >= 0 || StringFind(sym, "GOLD") >= 0);

   //--- Account Currency Detection
   // Exness cent accounts use "USC" as account currency
   string accCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   StringToUpper(accCurrency);
   g_isCentAcct = (StringFind(accCurrency, "USC") >= 0 ||
                   StringFind(accCurrency, "CENT") >= 0 ||
                   StringFind(sym, "C") == StringLen(sym)-1); // symbol ends in 'C'

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpAutoDetect)
   {
      if(g_isBTC)
      {
         //==============================================
         //  BTCUSD / BTCUSDc PRESET
         //==============================================
         g_spacingPips    = 250;
         g_gridSize       = g_isCentAcct ? 3    : 5;
         g_lotSize        = g_isCentAcct ? 0.01 : 0.001;
         g_rsiBuyLvl      = 30.0;
         g_rsiSellLvl     = 70.0;
         g_trailStartPips = 100.0;
         g_trailStepPips  = 50.0;
         // Daily loss: 25% of balance, capped reasonably
         g_dailyLossAmt   = g_isCentAcct ? MathMin(balance * 0.25, 500.0) : 100.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = 5.0;

         Print(">>> AUTO-DETECT: ", (g_isCentAcct ? "BTCUSDc CENT" : "BTCUSD STANDARD"), " preset applied.");
      }
      else if(g_isGold)
      {
         //==============================================
         //  XAUUSD / XAUUSDc PRESET
         //==============================================
         g_spacingPips    = 80;
         g_gridSize       = g_isCentAcct ? 4    : 6;      // 4 orders on cent (safer)
         g_lotSize        = g_isCentAcct ? 0.01 : 0.01;   // same lot — cent scales value down
         g_rsiBuyLvl      = 35.0;
         g_rsiSellLvl     = 65.0;
         g_trailStartPips = 40.0;
         g_trailStepPips  = 20.0;
         // Daily loss: 25% of balance for cent, $50 for standard
         // For 2000 USC account: 25% = 500 USC max daily loss
         g_dailyLossAmt   = g_isCentAcct ? MathMin(balance * 0.25, 500.0) : 50.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = g_isCentAcct ? 5.0 : 6.0;    // tighter SL for cent

         Print(">>> AUTO-DETECT: ", (g_isCentAcct ? "XAUUSDc CENT ACCOUNT" : "XAUUSD STANDARD"), " preset applied.");
      }
      else
      {
         Print(">>> AUTO-DETECT: Unknown symbol '", _Symbol, "' — using manual values.");
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
      Print(">>> MANUAL MODE: Using all input values as-is.");
   }

   // Compute point distances
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

   if(rsi_handle       == INVALID_HANDLE ||
      tf_fast_handle   == INVALID_HANDLE ||
      tf_slow_handle   == INVALID_HANDLE ||
      exit_fast_handle == INVALID_HANDLE ||
      exit_slow_handle == INVALID_HANDLE)
   {
      Alert("EA v3.2 ERROR: Indicator handle creation failed!");
      return INIT_FAILED;
   }

   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_currentDay        = GetDayStart();

   // Print full account and settings summary
   Print("=== EA GRID v3.2 INITIALIZED on ", _Symbol, " ===");
   Print("Account Type : ", (g_isCentAcct ? "CENT ACCOUNT (USC)" : "STANDARD ACCOUNT (USD)"));
   Print("Balance      : ", DoubleToString(balance, 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
         (g_isCentAcct ? " = $" + DoubleToString(balance/100.0, 2) + " USD real" : ""));
   Print("Grid         : ", g_gridSize, " orders | Spacing: ", g_spacingPips, " pips | Lot: ", g_lotSize);
   Print("RSI Levels   : BUY ", g_rsiBuyLvl, " / SELL ", g_rsiSellLvl);
   Print("Daily Loss   : ", g_dailyLossAmt, " ", AccountInfoString(ACCOUNT_CURRENCY),
         (g_isCentAcct ? " = $" + DoubleToString(g_dailyLossAmt/100.0, 2) + " USD" : ""));
   Print("Max Profit   : ", g_maxProfitMult, "x | Grid SL: ", g_gridSLMult, "x");
   Print("Trail        : Activates at ", g_trailStartPips, " pips | Step: ", g_trailStepPips, " pips");

   if(g_isCentAcct)
   {
      Print("⚠ CENT ACCOUNT WARNING: 2000 USC = $20 USD real money.");
      Print("  EA is configured conservatively to protect your capital.");
      Print("  Max risk per grid cycle: ~", DoubleToString(g_gridSLMult * g_spacingPips * 0.1, 1),
            " USC per lot");
   }

   if(g_isGold)
      Print("Best PHT monitoring time: 8:00 PM – 11:00 PM (London + NY overlap)");
   if(g_isBTC)
      Print("BTCUSD trades 24/7 — monitor anytime, best 8:00 PM – 12:00 AM PHT");

   return INIT_SUCCEEDED;
}

//==========================================================================
//  DEINIT
//==========================================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(rsi_handle);
   IndicatorRelease(tf_fast_handle);
   IndicatorRelease(tf_slow_handle);
   IndicatorRelease(exit_fast_handle);
   IndicatorRelease(exit_slow_handle);
}

//==========================================================================
//  MAIN TICK
//==========================================================================
void OnTick()
{
   ResetDailyTracker();
   MonitorGridProfit();
   ManageTrailingStop();

   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   if(InpUseDailyLoss && IsDailyLossBreached())
   {
      Print("DAILY LOSS LIMIT reached — no new entries today.");
      return;
   }

   int bars = MathMax(MathMax(InpRSI_Shift, InpTF_Shift), InpExit_Shift) + 3;

   double rsi_val[], tf_fast[], tf_slow[], exit_fast[], exit_slow[];
   ArraySetAsSeries(rsi_val,   true);
   ArraySetAsSeries(tf_fast,   true);
   ArraySetAsSeries(tf_slow,   true);
   ArraySetAsSeries(exit_fast, true);
   ArraySetAsSeries(exit_slow, true);

   if(CopyBuffer(rsi_handle,       0, 0, bars, rsi_val)   < bars) return;
   if(CopyBuffer(tf_fast_handle,   0, 0, bars, tf_fast)   < bars) return;
   if(CopyBuffer(tf_slow_handle,   0, 0, bars, tf_slow)   < bars) return;
   if(CopyBuffer(exit_fast_handle, 0, 0, bars, exit_fast) < bars) return;
   if(CopyBuffer(exit_slow_handle, 0, 0, bars, exit_slow) < bars) return;

   bool hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
   bool hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);

   //--- Exit signals (only when positions open)
   if(hasBuys || hasSells)
   {
      int s = InpExit_Shift;
      bool exitBearish = (exit_fast[s]   <  exit_slow[s]   && exit_fast[s+1] >= exit_slow[s+1]);
      bool exitBullish = (exit_fast[s]   >  exit_slow[s]   && exit_fast[s+1] <= exit_slow[s+1]);

      if(exitBearish && hasBuys)
      {
         Print("EXIT: EMA(50) bearish cross — closing BUY grid.");
         ClosePositionsByType(POSITION_TYPE_BUY);
         CancelPendingByComment("BUY_GRID_");
      }
      if(exitBullish && hasSells)
      {
         Print("EXIT: EMA(50) bullish cross — closing SELL grid.");
         ClosePositionsByType(POSITION_TYPE_SELL);
         CancelPendingByComment("SELL_GRID_");
      }

      hasBuys  = (CountPositions(POSITION_TYPE_BUY)  > 0);
      hasSells = (CountPositions(POSITION_TYPE_SELL) > 0);
   }

   //--- Trend filter
   int tf = InpTF_Shift;
   bool trendBullish = (tf_fast[tf] > tf_slow[tf]);
   bool trendBearish = (tf_fast[tf] < tf_slow[tf]);

   //--- Entry signals
   int rs = InpRSI_Shift;
   bool rsiBuySignal  = (rsi_val[rs] >  g_rsiBuyLvl  && rsi_val[rs+1] <= g_rsiBuyLvl);
   bool rsiSellSignal = (rsi_val[rs] <  g_rsiSellLvl && rsi_val[rs+1] >= g_rsiSellLvl);

   //--- Combined entry
   if(rsiBuySignal && trendBullish && !hasBuys)
   {
      Print("BUY ENTRY: RSI crossed UP through ", g_rsiBuyLvl,
            " | UPTREND | Opening BUY Grid (", g_gridSize, " orders).");
      OpenBuyGrid();
   }
   if(rsiSellSignal && trendBearish && !hasSells)
   {
      Print("SELL ENTRY: RSI crossed DOWN through ", g_rsiSellLvl,
            " | DOWNTREND | Opening SELL Grid (", g_gridSize, " orders).");
      OpenSellGrid();
   }
}

//==========================================================================
//  OPEN BUY GRID
//==========================================================================
void OpenBuyGrid()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = 0; i < g_gridSize; i++)
   {
      double price   = NormalizeDouble(ask - i * g_spacingPoints, _Digits);
      double tp      = InpTPPerTrade
                       ? NormalizeDouble(price + InpTPMultiplier * g_spacingPoints, _Digits)
                       : 0.0;
      string comment = "BUY_GRID_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString(i);

      if(i == 0)
      { if(!trade.Buy(g_lotSize, _Symbol, 0, 0, tp, comment))
           Print("BUY Market FAILED: ", trade.ResultRetcodeDescription()); }
      else
      { if(!trade.BuyLimit(g_lotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, comment))
           Print("BUY Limit #", i, " FAILED: ", trade.ResultRetcodeDescription()); }
   }
}

//==========================================================================
//  OPEN SELL GRID
//==========================================================================
void OpenSellGrid()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 0; i < g_gridSize; i++)
   {
      double price   = NormalizeDouble(bid + i * g_spacingPoints, _Digits);
      double tp      = InpTPPerTrade
                       ? NormalizeDouble(price - InpTPMultiplier * g_spacingPoints, _Digits)
                       : 0.0;
      string comment = "SELL_GRID_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString(i);

      if(i == 0)
      { if(!trade.Sell(g_lotSize, _Symbol, 0, 0, tp, comment))
           Print("SELL Market FAILED: ", trade.ResultRetcodeDescription()); }
      else
      { if(!trade.SellLimit(g_lotSize, price, _Symbol, 0, tp, ORDER_TIME_GTC, 0, comment))
           Print("SELL Limit #", i, " FAILED: ", trade.ResultRetcodeDescription()); }
   }
}

//==========================================================================
//  TRAILING STOP (every tick)
//==========================================================================
void ManageTrailingStop()
{
   if(!InpUseTrailing) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))          continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)        continue;

      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         if(bid - openPrice >= g_trailStartPoints)
         {
            double newSL = NormalizeDouble(bid - g_trailStepPoints, _Digits);
            if(newSL > currentSL + _Point)
               trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
         }
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         if(openPrice - ask >= g_trailStartPoints)
         {
            double newSL = NormalizeDouble(ask + g_trailStepPoints, _Digits);
            if(currentSL == 0 || newSL < currentSL - _Point)
               trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
         }
      }
   }
}

//==========================================================================
//  MONITOR GRID PROFIT / SL (every tick)
//==========================================================================
void MonitorGridProfit()
{
   if(CountPositions(POSITION_TYPE_BUY)  == 0 &&
      CountPositions(POSITION_TYPE_SELL) == 0) return;

   double totalProfit = GetTotalGridProfit();
   double tickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pipValue    = (tickValue / tickSize) * (_Point * 10.0) * g_lotSize;

   double maxProfitAmt =  g_maxProfitMult * g_spacingPips * pipValue;
   double gridSL_Amt   = -g_gridSLMult    * g_spacingPips * pipValue;

   if(InpCloseAtMaxProfit && totalProfit >= maxProfitAmt)
   {
      Print("MAX PROFIT HIT: ", DoubleToString(totalProfit,2),
            " ", AccountInfoString(ACCOUNT_CURRENCY), " → Closing grid.");
      CloseAllGridOrders();
      return;
   }
   if(totalProfit <= gridSL_Amt)
   {
      Print("GRID SL HIT: ", DoubleToString(totalProfit,2),
            " ", AccountInfoString(ACCOUNT_CURRENCY), " → Closing grid.");
      CloseAllGridOrders();
   }
}

//==========================================================================
//  DAILY LOSS TRACKER
//==========================================================================
datetime GetDayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

void ResetDailyTracker()
{
   datetime today = GetDayStart();
   if(today != g_currentDay)
   {
      g_currentDay        = today;
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("New trading day — balance reset to ",
            DoubleToString(g_dailyStartBalance, 2), " ",
            AccountInfoString(ACCOUNT_CURRENCY));
   }
}

bool IsDailyLossBreached()
{
   double lost = g_dailyStartBalance - AccountInfoDouble(ACCOUNT_BALANCE);
   if(lost >= g_dailyLossAmt)
   {
      Print("DAILY LOSS LIMIT: Lost ", DoubleToString(lost,2),
            " ", AccountInfoString(ACCOUNT_CURRENCY),
            " (limit: ", DoubleToString(g_dailyLossAmt,2), ") — pausing entries.");
      return true;
   }
   return false;
}

//==========================================================================
//  HELPERS
//==========================================================================
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber && posInfo.Symbol()==_Symbol &&
            posInfo.PositionType()==type) count++;
   return count;
}

double GetTotalGridProfit()
{
   double p = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber && posInfo.Symbol()==_Symbol)
            p += posInfo.Profit() + posInfo.Swap();
   return p;
}

void ClosePositionsByType(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==InpMagicNumber && posInfo.Symbol()==_Symbol &&
            posInfo.PositionType()==type)
            trade.PositionClose(posInfo.Ticket());
}

void CancelPendingByComment(string prefix)
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
      if(ordInfo.SelectByIndex(i))
         if(ordInfo.Magic()==InpMagicNumber && ordInfo.Symbol()==_Symbol &&
            StringFind(ordInfo.Comment(), prefix)==0)
            trade.OrderDelete(ordInfo.Ticket());
}

void CloseAllGridOrders()
{
   ClosePositionsByType(POSITION_TYPE_BUY);
   ClosePositionsByType(POSITION_TYPE_SELL);
   for(int i = OrdersTotal()-1; i >= 0; i--)
      if(ordInfo.SelectByIndex(i))
         if(ordInfo.Magic()==InpMagicNumber && ordInfo.Symbol()==_Symbol)
            trade.OrderDelete(ordInfo.Ticket());
}

//+------------------------------------------------------------------+
//| END OF EA v3.2                                                   |
//+------------------------------------------------------------------+
