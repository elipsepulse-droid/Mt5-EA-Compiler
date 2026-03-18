//+------------------------------------------------------------------+
//| XAUUSD PRO SCALPER v2 (MQL5 Fixed + Aggressive Improvements)    |
//| Fixes: MQL5 API, ManageTrade direction, handle leak,            |
//|        daily loss limit, magic number, equity-based risk,       |
//|        breakout logic, RSI thresholds, trailing for shorts      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//---- Inputs
input group "== Risk Management =="
input double   RiskPercent      = 1.5;     // Risk % per trade (of equity)
input double   DailyLossLimit   = 4.0;     // Max daily loss % before EA stops
input int      MaxTradesPerDay  = 6;       // Max entries per day
input int      MagicNumber      = 20240101;

input group "== Indicators =="
input int      EMA_Fast         = 9;
input int      EMA_Slow         = 21;
input int      EMA_Trend        = 50;      // Higher TF trend filter
input int      RSI_Period       = 7;
input int      ATR_Period       = 14;

input group "== Entry Settings =="
input double   ATR_SL_Mult      = 1.3;
input double   ATR_TP_Mult      = 2.0;    // Raised for better R:R
input int      Lookback         = 10;
input int      MaxSpread        = 180;
input double   RSI_Bull         = 58.0;   // Raised from 55 for quality entries
input double   RSI_Bear         = 42.0;   // Lowered from 45

input group "== Session Filter =="
input bool     UseSessionFilter = true;
input int      SessionStartHour = 7;      // UTC - London open
input int      SessionEndHour   = 20;     // UTC - NY close

input group "== Trade Management =="
input bool     UseTrailing      = true;
input double   TrailATR         = 1.0;
input double   BE_ATR           = 0.7;    // Move to BE sooner
input bool     UsePartialClose  = true;   // Close 50% at 1R
input double   PartialATR       = 1.0;    // ATR mult to trigger partial

//---- Indicator Handles (created once in OnInit)
int handleATR;
int handleEMAFast;
int handleEMASlow;
int handleEMATrend;
int handleRSI;

//---- Globals
double   lotSize;
double   dayStartEquity   = 0;
int      tradesToday      = 0;
datetime lastTradeDay     = 0;
bool     partialDone      = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Create all handles once
   handleATR      = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   handleEMAFast  = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   handleEMASlow  = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   handleEMATrend = iMA(_Symbol, PERIOD_CURRENT, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI      = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);

   if(handleATR == INVALID_HANDLE || handleEMAFast == INVALID_HANDLE ||
      handleEMASlow == INVALID_HANDLE || handleEMATrend == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles. EA will not run.");
      return INIT_FAILED;
   }

   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("XAUUSD PRO SCALPER v2 initialized. MagicNumber=", MagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleATR);
   IndicatorRelease(handleEMAFast);
   IndicatorRelease(handleEMASlow);
   IndicatorRelease(handleEMATrend);
   IndicatorRelease(handleRSI);
}

//+------------------------------------------------------------------+
// Safely read a single value from an indicator buffer
double GetIndicatorValue(int handle, int bufferIndex, int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, bufferIndex, shift, 1, buf) <= 0)
   {
      Print("WARNING: CopyBuffer failed for handle ", handle);
      return 0.0;
   }
   return buf[0];
}

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step) * step;
   return MathMax(minLot, MathMin(lot, maxLot));
}

//+------------------------------------------------------------------+
double CalculateLot(double slPoints)
{
   // Use EQUITY not BALANCE — safer during open drawdown
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || slPoints <= 0) return 0.01;

   double costPerLot = (slPoints * tickValue) / tickSize;
   if(costPerLot <= 0) return 0.01;

   return NormalizeLot(riskMoney / costPerLot);
}

//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!UseSessionFilter) return true;
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   return (tm.hour >= SessionStartHour && tm.hour < SessionEndHour);
}

//+------------------------------------------------------------------+
bool IsSpreadOK(double atr)
{
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   return (spread <= MaxSpread && spread < (atr / _Point) * 0.2);
}

//+------------------------------------------------------------------+
// Reset daily counters at the start of a new day
void CheckDayReset()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", tm.year, tm.mon, tm.day));

   if(today != lastTradeDay)
   {
      lastTradeDay   = today;
      tradesToday    = 0;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("New trading day. Equity reset to ", dayStartEquity);
   }
}

//+------------------------------------------------------------------+
bool IsDailyLimitReached()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double loss = (dayStartEquity - currentEquity) / dayStartEquity * 100.0;
   if(loss >= DailyLossLimit)
   {
      Print("Daily loss limit hit (", DoubleToString(loss, 2), "%). EA paused for today.");
      return true;
   }
   if(tradesToday >= MaxTradesPerDay)
   {
      Print("Max trades per day (", MaxTradesPerDay, ") reached.");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Lookback high/low — starts from bar 2 to avoid competing with entry bar
double GetHigh()
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, 2);
   for(int i = 3; i <= Lookback + 1; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(h > high) high = h;
   }
   return high;
}

double GetLow()
{
   double low = iLow(_Symbol, PERIOD_CURRENT, 2);
   for(int i = 3; i <= Lookback + 1; i++)
   {
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      if(l < low) low = l;
   }
   return low;
}

//+------------------------------------------------------------------+
// Checks if price just closed above/below a level (momentum confirmation)
bool IsMomentumBar()
{
   double body = MathAbs(iClose(_Symbol, PERIOD_CURRENT, 1) - iOpen(_Symbol, PERIOD_CURRENT, 1));
   double range = iHigh(_Symbol, PERIOD_CURRENT, 1) - iLow(_Symbol, PERIOD_CURRENT, 1);
   if(range <= 0) return false;
   // Require body to be at least 40% of the candle range — avoids indecision bars
   return (body / range >= 0.40);
}

//+------------------------------------------------------------------+
void ManageTrade(double atr)
{
   if(!PositionSelect(_Symbol)) return;
   if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) return;

   long   posType = PositionGetInteger(POSITION_TYPE);
   double open    = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl      = PositionGetDouble(POSITION_SL);
   double tp      = PositionGetDouble(POSITION_TP);
   double volume  = PositionGetDouble(POSITION_VOLUME);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(posType == POSITION_TYPE_BUY)
   {
      double price = bid;

      // Partial close at 1R for buys
      if(UsePartialClose && !partialDone && (price - open) >= atr * PartialATR)
      {
         double closeVol = NormalizeLot(volume * 0.5);
         if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            trade.PositionClosePartial(_Symbol, closeVol);
            partialDone = true;
            Print("Partial close (BUY) at ", price);
         }
      }

      // Breakeven
      if((price - open) > atr * BE_ATR && sl < open)
      {
         double newSL = open + _Point; // 1 point above entry
         trade.PositionModify(_Symbol, NormalizeDouble(newSL, _Digits), tp);
      }

      // Trailing stop
      if(UseTrailing)
      {
         double newSL = NormalizeDouble(price - atr * TrailATR, _Digits);
         if(newSL > sl && newSL < price)
            trade.PositionModify(_Symbol, newSL, tp);
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double price = ask;

      // Partial close at 1R for sells
      if(UsePartialClose && !partialDone && (open - price) >= atr * PartialATR)
      {
         double closeVol = NormalizeLot(volume * 0.5);
         if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            trade.PositionClosePartial(_Symbol, closeVol);
            partialDone = true;
            Print("Partial close (SELL) at ", price);
         }
      }

      // Breakeven
      if((open - price) > atr * BE_ATR && sl > open)
      {
         double newSL = open - _Point;
         trade.PositionModify(_Symbol, NormalizeDouble(newSL, _Digits), tp);
      }

      // Trailing stop
      if(UseTrailing)
      {
         double newSL = NormalizeDouble(price + atr * TrailATR, _Digits);
         if(newSL < sl && newSL > price)
            trade.PositionModify(_Symbol, newSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckDayReset();

   double atr = GetIndicatorValue(handleATR, 0, 1);
   if(atr <= 0) return;

   ManageTrade(atr);

   // Don't look for entries if a position is already open
   if(PositionSelect(_Symbol)) return;

   if(IsDailyLimitReached()) return;
   if(!IsTradingTime())      return;
   if(!IsSpreadOK(atr))      return;
   if(!IsMomentumBar())      return;

   // Read all indicators from bar 1 (closed candle — no repainting)
   double emaFast  = GetIndicatorValue(handleEMAFast,  0, 1);
   double emaSlow  = GetIndicatorValue(handleEMASlow,  0, 1);
   double emaTrend = GetIndicatorValue(handleEMATrend, 0, 1);
   double rsi      = GetIndicatorValue(handleRSI,      0, 1);
   double close1   = iClose(_Symbol, PERIOD_CURRENT, 1);

   if(emaFast <= 0 || emaSlow <= 0 || emaTrend <= 0 || rsi <= 0) return;

   double high = GetHigh();
   double low  = GetLow();
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slPoints = (atr * ATR_SL_Mult) / _Point;
   lotSize = CalculateLot(slPoints);
   if(lotSize <= 0) return;

   // ---- BUY SIGNAL ----
   // Fast EMA > Slow EMA (short term bullish)
   // Price above 50 EMA (trend filter)
   // Closed above recent high (breakout confirmed)
   // RSI confirms momentum without being overbought
   bool buySignal = (emaFast > emaSlow)
                 && (close1  > emaTrend)
                 && (close1  > high)
                 && (rsi     > RSI_Bull && rsi < 75.0);

   // ---- SELL SIGNAL ----
   bool sellSignal = (emaFast < emaSlow)
                  && (close1  < emaTrend)
                  && (close1  < low)
                  && (rsi     < RSI_Bear && rsi > 25.0);

   // Only one direction per tick
   if(buySignal && !sellSignal)
   {
      double sl = NormalizeDouble(ask - atr * ATR_SL_Mult, _Digits);
      double tp = NormalizeDouble(ask + atr * ATR_TP_Mult, _Digits);
      partialDone = false;

      if(trade.Buy(lotSize, _Symbol, ask, sl, tp))
      {
         tradesToday++;
         Print("BUY | Lot=", lotSize, " SL=", sl, " TP=", tp, " ATR=", atr);
      }
   }
   else if(sellSignal && !buySignal)
   {
      double sl = NormalizeDouble(bid + atr * ATR_SL_Mult, _Digits);
      double tp = NormalizeDouble(bid - atr * ATR_TP_Mult, _Digits);
      partialDone = false;

      if(trade.Sell(lotSize, _Symbol, bid, sl, tp))
      {
         tradesToday++;
         Print("SELL | Lot=", lotSize, " SL=", sl, " TP=", tp, " ATR=", atr);
      }
   }
}
//+------------------------------------------------------------------+
