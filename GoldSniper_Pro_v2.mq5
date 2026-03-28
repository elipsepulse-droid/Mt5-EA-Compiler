//+------------------------------------------------------------------+
//|  TUYUL PO V2 — Breakout Pending Order Scalper (XAUUSD M1/M5)    |
//|  Strategy : Consolidation Range + Buy Stop / Sell Stop           |
//|  Features : ATR SL/TP, Trailing, Breakeven, Spread Filter,       |
//|             Session Filter, OCO Logic, Daily Loss Limit          |
//|  Version  : 2.1 (Bug-Fixed)                                      |
//+------------------------------------------------------------------+
// FIXES v2.1:
//  [1] Removed #property strict (MT4-only, causes MQ5 warnings)
//  [2] Filling mode auto-detected per broker instead of hardcoded IOC
//  [3] Removed unused 'balance' variable in IsDailyLossBreached()
//  [4] CloseOnNewBar input now fully implemented
//  [5] posType cast changed to ENUM_POSITION_TYPE (type safety)
//  [6] Unused ticket globals removed (g_buyStopTicket, g_sellStopTicket)
//  [7] MagicNumber type changed to long (correct for MQ5)
//  [8] Trailing/Breakeven SELL newSL=0 edge case hardened
//  [9] Added PositionSelectByTicket() before PositionModify for safety
// [10] All order loops now call OrderSelect(ticket) properly
//+------------------------------------------------------------------+

#property copyright "bs.autotrade Analysis"
#property version   "2.10"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade          Trade;
COrderInfo      OrderInfo;
CPositionInfo   PositionInfo;

//--- ═══════════════════════════════════════════════════════════════
//    INPUT PARAMETERS
//--- ═══════════════════════════════════════════════════════════════

input group "═══ TRADE SETUP ═══"
input double   LotSize              = 0.01;    // Lot Size
input int      RangeBars            = 5;       // Consolidation bars to scan
input int      EntryBufferPoints    = 50;      // Points above/below range for pending
input long     MagicNumber          = 202502;  // EA Magic Number

input group "═══ STOP LOSS & TAKE PROFIT ═══"
input bool     UseATR_SL            = true;    // Use ATR-based SL (recommended)
input double   ATR_SL_Multiplier    = 1.5;     // ATR multiplier for SL
input double   ATR_TP_Multiplier    = 2.5;     // ATR multiplier for TP
input int      FixedSL_Points       = 300;     // Fixed SL in points (if ATR off)
input int      FixedTP_Points       = 500;     // Fixed TP in points (if ATR off)
input int      ATR_Period           = 14;      // ATR period

input group "═══ TRAILING STOP & BREAKEVEN ═══"
input bool     UseTrailing          = true;    // Enable trailing stop
input int      TrailingStart_Points = 200;     // Points profit before trailing starts
input int      TrailingStep_Points  = 100;     // Trailing step in points
input bool     UseBreakeven         = true;    // Enable breakeven
input int      BreakevenActivate    = 150;     // Points profit to activate breakeven
input int      BreakevenOffset      = 10;      // Points beyond entry for breakeven SL

input group "═══ FILTERS ═══"
input int      MaxSpreadPoints      = 80;      // Max allowed spread in points (0 = off)
input bool     UseSessionFilter     = true;    // Only trade during active session
input int      SessionStartHour     = 7;       // Session start hour (broker time)
input int      SessionEndHour       = 20;      // Session end hour (broker time)
input bool     UseCancelOpposite    = true;    // Cancel opposite pending when one fills
input bool     UseVolatilityFilter  = true;    // Skip entry if ATR too low
input double   MinATR_Points        = 50.0;    // Min ATR in points to allow trading

input group "═══ RISK MANAGEMENT ═══"
input double   MaxDailyLossPct      = 3.0;     // Max daily loss % of balance (0 = off)
input int      MaxOpenOrders        = 2;       // Max simultaneous pending + open orders
input bool     CloseOnNewBar        = false;   // Close open trades on each new bar
input int      PendingExpireBars    = 3;       // Bars until pending auto-expires (0=off)

//--- ═══════════════════════════════════════════════════════════════
//    GLOBAL VARIABLES
//--- ═══════════════════════════════════════════════════════════════
datetime  g_lastBarTime     = 0;
double    g_dayStartBalance = 0.0;
datetime  g_today           = 0;
int       g_atrHandle       = INVALID_HANDLE;

//+------------------------------------------------------------------+
//  INIT
//+------------------------------------------------------------------+
int OnInit()
{
   // [FIX #2] Auto-detect the correct filling mode for this broker/symbol
   ENUM_ORDER_TYPE_FILLING fillMode = GetFillMode();
   Trade.SetTypeFilling(fillMode);
   Trade.SetExpertMagicNumber((ulong)MagicNumber);
   Trade.SetDeviationInPoints(20);

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle. EA will not start.");
      return(INIT_FAILED);
   }

   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_today           = iTime(_Symbol, PERIOD_D1, 0);

   PrintFormat("TUYUL PO v2.1 ready | %s | %s | FillMode: %s",
               _Symbol, EnumToString(Period()), EnumToString(fillMode));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//  DEINIT
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
//  MAIN TICK
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Reset daily balance snapshot each new day
   datetime todayD1 = iTime(_Symbol, PERIOD_D1, 0);
   if(todayD1 != g_today)
   {
      g_today           = todayD1;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   //--- Daily loss circuit breaker
   if(MaxDailyLossPct > 0.0 && IsDailyLossBreached())
   {
      CloseAllPositions();
      DeleteAllPending();
      return;
   }

   //--- Manage open positions every tick (trailing + breakeven)
   ManageOpenPositions();

   //--- OCO: cancel the opposite pending once one side triggers
   if(UseCancelOpposite)
      ManageOCO();

   //--- New bar detection
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   //--- [FIX #4] Close all open positions at bar open if enabled
   if(CloseOnNewBar)
      CloseAllPositions();

   //--- Auto-expire stale pending orders
   if(PendingExpireBars > 0)
      ExpireOldPendings();

   //--- Session filter
   if(UseSessionFilter && !IsSessionActive()) return;

   //--- Spread filter
   if(MaxSpreadPoints > 0 && GetSpreadPoints() > MaxSpreadPoints) return;

   //--- Max orders cap
   if(CountAllOrders() >= MaxOpenOrders) return;

   //--- Get ATR
   double atr = GetATR();
   if(atr <= 0.0) return;

   //--- Volatility filter
   if(UseVolatilityFilter && (atr / _Point) < MinATR_Points) return;

   //--- Place breakout pending orders
   PlacePendingOrders(atr);
}

//+------------------------------------------------------------------+
//  CORE: Place Buy Stop + Sell Stop around consolidation range
//+------------------------------------------------------------------+
void PlacePendingOrders(double atr)
{
   double high = GetHighest(RangeBars);
   double low  = GetLowest(RangeBars);
   if(high <= 0.0 || low <= 0.0 || high <= low) return;

   double buffer = EntryBufferPoints * _Point;
   double buyEntry  = NormalizeDouble(high + buffer, _Digits);
   double sellEntry = NormalizeDouble(low  - buffer, _Digits);

   double slDist, tpDist;
   if(UseATR_SL)
   {
      slDist = atr * ATR_SL_Multiplier;
      tpDist = atr * ATR_TP_Multiplier;
   }
   else
   {
      slDist = FixedSL_Points * _Point;
      tpDist = FixedTP_Points * _Point;
   }

   double buySL  = NormalizeDouble(buyEntry  - slDist, _Digits);
   double buyTP  = NormalizeDouble(buyEntry  + tpDist, _Digits);
   double sellSL = NormalizeDouble(sellEntry + slDist, _Digits);
   double sellTP = NormalizeDouble(sellEntry - tpDist, _Digits);

   // Basic sanity check
   if(buySL <= 0.0 || buyTP <= 0.0 || sellSL <= 0.0 || sellTP <= 0.0) return;

   // Enforce broker minimum stop distance
   long   stopLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = (stopLvl + 1) * _Point;
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buyEntry  < ask + minDist)  return;
   if(sellEntry > bid - minDist)  return;
   if(slDist < minDist || tpDist < minDist) return;

   //--- BUY STOP
   if(!HasPendingOfType(ORDER_TYPE_BUY_STOP))
   {
      if(!Trade.BuyStop(LotSize, buyEntry, _Symbol, buySL, buyTP,
                        ORDER_TIME_GTC, 0, "TUYUL_BUY"))
         PrintFormat("BuyStop FAILED | Entry:%.2f SL:%.2f TP:%.2f | %s",
                     buyEntry, buySL, buyTP, Trade.ResultRetcodeDescription());
   }

   //--- SELL STOP
   if(!HasPendingOfType(ORDER_TYPE_SELL_STOP))
   {
      if(!Trade.SellStop(LotSize, sellEntry, _Symbol, sellSL, sellTP,
                         ORDER_TIME_GTC, 0, "TUYUL_SELL"))
         PrintFormat("SellStop FAILED | Entry:%.2f SL:%.2f TP:%.2f | %s",
                     sellEntry, sellSL, sellTP, Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//  OCO: Cancel opposite pending once one side becomes a position
//+------------------------------------------------------------------+
void ManageOCO()
{
   bool hasBuyPos   = HasPositionOfType(POSITION_TYPE_BUY);
   bool hasSellPos  = HasPositionOfType(POSITION_TYPE_SELL);
   bool hasBuyPend  = HasPendingOfType(ORDER_TYPE_BUY_STOP);
   bool hasSellPend = HasPendingOfType(ORDER_TYPE_SELL_STOP);

   if(hasBuyPos  && hasSellPend) DeletePendingOfType(ORDER_TYPE_SELL_STOP);
   if(hasSellPos && hasBuyPend)  DeletePendingOfType(ORDER_TYPE_BUY_STOP);
}

//+------------------------------------------------------------------+
//  TRAILING STOP + BREAKEVEN  (runs every tick)
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)           continue;
      if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      // [FIX #5] Proper enum cast
      ENUM_POSITION_TYPE posType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = (posType == POSITION_TYPE_BUY) ? bid : ask;

      double profitPts = (posType == POSITION_TYPE_BUY)
                         ? (price - openPrice) / _Point
                         : (openPrice - price) / _Point;

      double newSL = currentSL;

      //--- Breakeven
      if(UseBreakeven && profitPts >= (double)BreakevenActivate)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            double beSL = NormalizeDouble(openPrice + BreakevenOffset * _Point, _Digits);
            if(beSL > newSL) newSL = beSL;
         }
         else
         {
            double beSL = NormalizeDouble(openPrice - BreakevenOffset * _Point, _Digits);
            // [FIX #8] Guard: if currentSL was 0, any valid beSL is an improvement
            if(newSL <= 0.0 || beSL < newSL) newSL = beSL;
         }
      }

      //--- Trailing stop
      if(UseTrailing && profitPts >= (double)TrailingStart_Points)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            double trailSL = NormalizeDouble(price - TrailingStep_Points * _Point, _Digits);
            if(trailSL > newSL) newSL = trailSL;
         }
         else
         {
            double trailSL = NormalizeDouble(price + TrailingStep_Points * _Point, _Digits);
            // [FIX #8] Guard: if currentSL was 0, any valid trailSL is better
            if(newSL <= 0.0 || trailSL < newSL) newSL = trailSL;
         }
      }

      //--- Send modify only if SL has meaningfully changed
      if(MathAbs(newSL - currentSL) > _Point)
      {
         // [FIX #9] Re-select by ticket immediately before modifying
         if(PositionSelectByTicket(ticket))
            Trade.PositionModify(ticket, newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//  HELPERS
//+------------------------------------------------------------------+

// [FIX #2] Detect broker-supported filling mode for this symbol
ENUM_ORDER_TYPE_FILLING GetFillMode()
{
   uint flags = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_FLAGS);
   if((flags & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((flags & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

double GetHighest(int bars)
{
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= bars; i++)
   {
      double hi = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(hi > h) h = hi;
   }
   return h;
}

double GetLowest(int bars)
{
   double l = iLow(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= bars; i++)
   {
      double lo = iLow(_Symbol, PERIOD_CURRENT, i);
      if(lo < l) l = lo;
   }
   return l;
}

double GetATR()
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1) return 0.0;
   return buf[0];
}

int GetSpreadPoints()
{
   return (int)MathRound(
      (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID))
      / _Point);
}

bool IsSessionActive()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= SessionStartHour && dt.hour < SessionEndHour);
}

bool IsDailyLossBreached()
{
   // [FIX #3] Removed unused 'balance' variable — only equity matters here
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double maxLoss = g_dayStartBalance * MaxDailyLossPct / 100.0;
   return((g_dayStartBalance - equity) >= maxLoss);
}

// [FIX #10] All order loops now call OrderSelect(ticket) before accessing properties
int CountAllOrders()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)           continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber) continue;
      count++;
   }
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      count++;
   }
   return count;
}

bool HasPendingOfType(ENUM_ORDER_TYPE orderType)
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)           continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == orderType) return true;
   }
   return false;
}

bool HasPositionOfType(ENUM_POSITION_TYPE posType)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == posType) return true;
   }
   return false;
}

void DeletePendingOfType(ENUM_ORDER_TYPE orderType)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)           continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == orderType)
         Trade.OrderDelete(ticket);
   }
}

void DeleteAllPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)           continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber) continue;
      Trade.OrderDelete(ticket);
   }
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      Trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET));
   }
}

void ExpireOldPendings()
{
   datetime cutoff = iTime(_Symbol, PERIOD_CURRENT, PendingExpireBars);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)           continue;
      if(OrderGetInteger(ORDER_MAGIC)  != (long)MagicNumber) continue;
      if((datetime)OrderGetInteger(ORDER_TIME_SETUP) < cutoff)
         Trade.OrderDelete(ticket);
   }
}
//+------------------------------------------------------------------+
