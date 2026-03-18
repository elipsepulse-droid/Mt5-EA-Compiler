//+------------------------------------------------------------------+
//|         EA_Scalping_Grid_GOLD_BTC_v3.mq5                         |
//|     Universal Grid Scalping Robot - XAUUSD & BTCUSD M5           |
//|                                                                  |
//|  AUTO-DETECTS symbol and applies correct settings automatically  |
//|                                                                  |
//|  XAUUSD (Gold):                                                  |
//|   - Spacing: 80 pips | Lot: 0.01 | RSI: 35/65                   |
//|   - Trades Mon–Fri (market hours)                                |
//|   - Best PHT time: 8:00 PM – 11:00 PM                           |
//|                                                                  |
//|  BTCUSD (Bitcoin):                                               |
//|   - Spacing: 250 pips | Lot: 0.001 | RSI: 30/70                 |
//|   - Trades 24/7 including weekends                               |
//|   - Best PHT time: 8:00 PM – 12:00 AM (US session overlap)      |
//|                                                                  |
//|  STRATEGY (same for both):                                       |
//|  ENTRY  : RSI crosses UP/DOWN through levels → BUY/SELL Grid    |
//|  FILTER : EMA(100) vs EMA(300) trend direction                  |
//|  EXIT   : EMA(50) crosses EMA(200) — directional exit           |
//|  TRAIL  : Trailing stop to lock in profits                       |
//|  SAFETY : Daily loss limit + Grid SL + Max Profit target         |
//+------------------------------------------------------------------+
#property copyright   "EA SCALPING ROBOT / DANE - v3.0"
#property version     "3.00"
#property description "Universal Grid EA — XAUUSD & BTCUSD M5"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//==========================================================================
//  INPUT PARAMETERS
//==========================================================================

input group "====== SYMBOL MODE ======"
input bool InpAutoDetect = true;
// If true  → EA reads the chart symbol and applies correct preset automatically
// If false → EA uses the manual settings below for everything

input group "====== GRID SETUP (Manual Override / Auto if AutoDetect=true) ======"
input int    InpGridSize       = 6;       // Grid Size (orders per side)
input double InpSpacingPips    = 80;      // Spacing in Pips
input double InpLotSize        = 0.01;    // Volume per Order (Lot)
input bool   InpMoveGrid       = true;    // Move Grid

input group "====== TRADE MANAGEMENT ======"
input bool   InpTPPerTrade       = true;  // Take Profit per Trade
input double InpTPMultiplier     = 1.0;   // TP = X x Spacing
input bool   InpCloseAtMaxProfit = true;  // Close Grid at Max Profit
input double InpMaxProfitMult    = 4.0;   // Max Profit = X x Spacing
input double InpGridSLMult       = 6.0;   // Grid SL = X x Spacing

input group "====== TRAILING STOP ======"
input bool   InpUseTrailing    = true;
input double InpTrailStartPips = 40;      // Trail activates after X pips
input double InpTrailStepPips  = 20;      // Trail step in pips

input group "====== DAILY LOSS PROTECTION ======"
input bool   InpUseDailyLoss   = true;
input double InpDailyLossUSD   = 50.0;   // Max daily loss in USD

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
input int    InpSlippage    = 50;   // Higher slippage for BTC compatibility

//==========================================================================
//  RUNTIME VARIABLES (set automatically based on symbol)
//==========================================================================
CTrade        trade;
CPositionInfo posInfo;
COrderInfo    ordInfo;

int      rsi_handle;
int      tf_fast_handle, tf_slow_handle;
int      exit_fast_handle, exit_slow_handle;

// These are the LIVE values used by the EA (auto-set or manual)
double   g_spacingPips;
int      g_gridSize;
double   g_lotSize;
double   g_rsiBuyLvl;
double   g_rsiSellLvl;
double   g_trailStartPips;
double   g_trailStepPips;
double   g_dailyLossUSD;
double   g_maxProfitMult;
double   g_gridSLMult;

// Computed point values
double   g_spacingPoints;
double   g_trailStartPoints;
double   g_trailStepPoints;

// Symbol detection
bool     g_isBTC  = false;
bool     g_isGold = false;

datetime g_lastBarTime      = 0;
datetime g_currentDay       = 0;
double   g_dailyStartBalance = 0;

//==========================================================================
//  INIT — AUTO-DETECT SYMBOL AND APPLY CORRECT PRESET
//==========================================================================
int OnInit()
{
   // --- Symbol Detection ---
   string sym = _Symbol;
   StringToUpper(sym);
   g_isBTC  = (StringFind(sym, "BTC") >= 0);
   g_isGold = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);

   if(InpAutoDetect)
   {
      if(g_isBTC)
      {
         //==============================================
         //  BTCUSD PRESET — optimized for Bitcoin M5
         //==============================================
         g_spacingPips    = 250;     // BTC moves $500-$2000/day — needs wider spacing
         g_gridSize       = 5;       // 5 orders to reduce margin exposure
         g_lotSize        = 0.001;   // Micro lot — BTC is very expensive per lot
         g_rsiBuyLvl      = 30.0;    // Deeper oversold for BTC
         g_rsiSellLvl     = 70.0;    // Deeper overbought for BTC
         g_trailStartPips = 100.0;   // BTC needs wider trail activation
         g_trailStepPips  = 50.0;    // BTC needs wider trail steps
         g_dailyLossUSD   = 100.0;   // BTC swings bigger — allow more room
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = 5.0;     // Tighter grid SL for BTC
         Print(">>> AUTO-DETECT: BTCUSD preset applied.");
         Print("    Spacing=250pips | Lot=0.001 | RSI=30/70 | GridSL=5x | DailyLoss=$100");
      }
      else if(g_isGold)
      {
         //==============================================
         //  XAUUSD PRESET — optimized for Gold M5
         //==============================================
         g_spacingPips    = 80;
         g_gridSize       = 6;
         g_lotSize        = 0.01;
         g_rsiBuyLvl      = 35.0;
         g_rsiSellLvl     = 65.0;
         g_trailStartPips = 40.0;
         g_trailStepPips  = 20.0;
         g_dailyLossUSD   = 50.0;
         g_maxProfitMult  = 4.0;
         g_gridSLMult     = 6.0;
         Print(">>> AUTO-DETECT: XAUUSD (Gold) preset applied.");
         Print("    Spacing=80pips | Lot=0.01 | RSI=35/65 | GridSL=6x | DailyLoss=$50");
      }
      else
      {
         // Unknown symbol — fall back to manual inputs
         Print(">>> AUTO-DETECT: Unknown symbol '", _Symbol, "' — using manual input values.");
         g_spacingPips    = InpSpacingPips;
         g_gridSize       = InpGridSize;
         g_lotSize        = InpLotSize;
         g_rsiBuyLvl      = InpRSI_BuyLvl;
         g_rsiSellLvl     = InpRSI_SellLvl;
         g_trailStartPips = InpTrailStartPips;
         g_trailStepPips  = InpTrailStepPips;
         g_dailyLossUSD   = InpDailyLossUSD;
         g_maxProfitMult  = InpMaxProfitMult;
         g_gridSLMult     = InpGridSLMult;
      }
   }
   else
   {
      // Manual mode — use all input values as-is
      g_spacingPips    = InpSpacingPips;
      g_gridSize       = InpGridSize;
      g_lotSize        = InpLotSize;
      g_rsiBuyLvl      = InpRSI_BuyLvl;
      g_rsiSellLvl     = InpRSI_SellLvl;
      g_trailStartPips = InpTrailStartPips;
      g_trailStepPips  = InpTrailStepPips;
      g_dailyLossUSD   = InpDailyLossUSD;
      g_maxProfitMult  = InpMaxProfitMult;
      g_gridSLMult     = InpGridSLMult;
      Print(">>> MANUAL MODE: Using all input values as-is.");
   }

   // Compute point-based distances (1 pip = 10 points for 2-decimal symbols)
   g_spacingPoints    = g_spacingPips    * 10.0 * _Point;
   g_trailStartPoints = g_trailStartPips * 10.0 * _Point;
   g_trailStepPoints  = g_trailStepPips  * 10.0 * _Point;

   // Setup trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Create indicator handles
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
      Alert("EA v3.0 ERROR: Indicator handle creation failed!");
      return INIT_FAILED;
   }

   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_currentDay        = GetDayStart();

   Print("=== EA GRID v3.0 INITIALIZED on ", _Symbol, " ===");
   Print("Grid: ", g_gridSize, " orders | Spacing: ", g_spacingPips,
         " pips | Lot: ", g_lotSize,
         " | RSI: ", g_rsiBuyLvl, "/", g_rsiSellLvl);
   Print("Trail: ", g_trailStartPips, " pip start / ", g_trailStepPips, " pip step");
   Print("Daily Loss Limit: $", g_dailyLossUSD, " | Max Profit: ", g_maxProfitMult,
         "x | Grid SL: ", g_gridSLMult, "x");

   if(g_isBTC)
      Print("NOTE: BTCUSD trades 24/7 including weekends — EA will be active always.");
   else
      Print("NOTE: XAUUSD trades Mon–Fri only. Best PHT time: 8:00PM–11:00PM.");

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

   // Daily loss guard — pauses new entries only
   if(InpUseDailyLoss && IsDailyLossBreached())
   {
      Print("DAILY LOSS LIMIT reached — no new entries today.");
      return;
   }

   // Load indicator buffers
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

   //=========================================================
   //  EXIT SIGNALS (checked only when positions are open)
   //=========================================================
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

   //=========================================================
   //  TREND FILTER — EMA(100) vs EMA(300)
   //=========================================================
   int tf = InpTF_Shift;
   bool trendBullish = (tf_fast[tf] > tf_slow[tf]);
   bool trendBearish = (tf_fast[tf] < tf_slow[tf]);

   //=========================================================
   //  ENTRY SIGNALS — RSI Crossover (auto-adjusted levels)
   //=========================================================
   int rs = InpRSI_Shift;
   bool rsiBuySignal  = (rsi_val[rs] >  g_rsiBuyLvl  && rsi_val[rs+1] <= g_rsiBuyLvl);
   bool rsiSellSignal = (rsi_val[rs] <  g_rsiSellLvl && rsi_val[rs+1] >= g_rsiSellLvl);

   //=========================================================
   //  COMBINED ENTRY + FILTER
   //=========================================================
   if(rsiBuySignal && trendBullish && !hasBuys)
   {
      Print("BUY ENTRY on ", _Symbol, ": RSI crossed UP through ", g_rsiBuyLvl,
            " | UPTREND confirmed → Opening BUY Grid (", g_gridSize, " orders).");
      OpenBuyGrid();
   }

   if(rsiSellSignal && trendBearish && !hasSells)
   {
      Print("SELL ENTRY on ", _Symbol, ": RSI crossed DOWN through ", g_rsiSellLvl,
            " | DOWNTREND confirmed → Opening SELL Grid (", g_gridSize, " orders).");
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

   double maxProfitUSD =  g_maxProfitMult * g_spacingPips * pipValue;
   double gridSL_USD   = -g_gridSLMult    * g_spacingPips * pipValue;

   if(InpCloseAtMaxProfit && totalProfit >= maxProfitUSD)
   {
      Print("MAX PROFIT HIT: $", DoubleToString(totalProfit, 2), " → Closing grid.");
      CloseAllGridOrders();
      return;
   }
   if(totalProfit <= gridSL_USD)
   {
      Print("GRID SL HIT: $", DoubleToString(totalProfit, 2), " → Closing grid.");
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
      Print("New day — balance tracker reset to $", DoubleToString(g_dailyStartBalance, 2));
   }
}

bool IsDailyLossBreached()
{
   double lost = g_dailyStartBalance - AccountInfoDouble(ACCOUNT_BALANCE);
   if(lost >= g_dailyLossUSD)
   {
      Print("DAILY LOSS LIMIT: $", DoubleToString(lost, 2),
            " lost (limit $", DoubleToString(g_dailyLossUSD, 2), ") — pausing entries.");
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
//| END OF EA v3.0                                                   |
//+------------------------------------------------------------------+
