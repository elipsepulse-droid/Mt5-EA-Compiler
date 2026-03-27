//+------------------------------------------------------------------+
//|                     TuyulGoldScalper_v1.mq5                      |
//|       XAUUSD Pending-Order Breakout Straddle Scalper             |
//|       Designed for M1 or M5 | MetaTrader 5                      |
//+------------------------------------------------------------------+
#property copyright "TuyulGoldScalper v1"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
COrderInfo    orderInfo;
CPositionInfo posInfo;

//--- LOT & RISK
input double   LotSize           = 0.01;
input bool     UseAutoLot        = false;
input double   RiskPercent       = 1.0;

//--- PENDING ORDER PLACEMENT
input int      ATR_Period        = 14;
input double   ATR_Multiplier    = 0.5;
input int      MinPendingDist    = 15;
input int      MaxPendingDist    = 150;

//--- STOP LOSS & TAKE PROFIT
input int      StopLoss_Points   = 150;
input int      TakeProfit_Points = 200;
input bool     UseTrailingStop   = true;
input int      TrailStart_Points = 100;
input int      TrailStep_Points  = 50;
input bool     UseBreakEven      = true;
input int      BreakEven_Points  = 80;

//--- ORDER MANAGEMENT
input int      PendingExpiry_Min = 5;
input bool     CancelOpposite    = true;
input int      CooldownBars      = 3;

//--- SPREAD FILTER
input int      MaxSpread         = 10;
input int      MaxSlippage       = 3;

//--- SESSION FILTER
input bool     UseSessionFilter  = true;
input int      SessionStartHour  = 8;
input int      SessionEndHour    = 22;

//--- CONSOLIDATION DETECTION
input int      ConsolBars        = 5;
input double   ConsolATR_Factor  = 0.8;

//--- MISC
input long     MagicNumber       = 202503;
input bool     ShowDashboard     = true;

//--- Global variables
double   g_atr;
double   g_point;
int      g_digits;
int      g_atrHandle;
datetime g_lastBarTime    = 0;
datetime g_lastCloseTime  = 0;
int      g_barsSinceClose = 0;
int      g_totalTrades    = 0;
double   g_sessionProfit  = 0;
string   g_lastSignal     = "Waiting...";

//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(Symbol(),"XAU") < 0 && StringFind(Symbol(),"GOLD") < 0)
      Print("WARNING: EA is designed for XAUUSD. Current: ", Symbol());

   g_point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   g_atrHandle = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create ATR indicator.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetAsyncMode(false);

   Print("TuyulGoldScalper v1 ready | Symbol:", Symbol(), " TF:", EnumToString(Period()));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime = iTime(Symbol(), PERIOD_CURRENT, 0);
   bool     newBar  = (barTime != g_lastBarTime);

   ManageOpenPositions();

   if(!newBar)
   {
      if(ShowDashboard) DrawDashboard();
      return;
   }
   g_lastBarTime = barTime;

   if(g_lastCloseTime > 0)
      g_barsSinceClose++;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_atrHandle, 0, 0, 3, atrBuf) < 2) return;
   g_atr = atrBuf[1];

   int curSpread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   if(curSpread > MaxSpread)
   {
      g_lastSignal = "Spread too wide: " + IntegerToString(curSpread);
      if(ShowDashboard) DrawDashboard();
      return;
   }

   if(UseSessionFilter && !IsInSession())
   {
      g_lastSignal = "Outside session hours";
      if(ShowDashboard) DrawDashboard();
      return;
   }

   if(g_barsSinceClose < CooldownBars && g_lastCloseTime > 0)
   {
      g_lastSignal = "Cooldown: " + IntegerToString(CooldownBars - g_barsSinceClose) + " bars";
      if(ShowDashboard) DrawDashboard();
      return;
   }

   int buyPos   = CountPositions(POSITION_TYPE_BUY);
   int sellPos  = CountPositions(POSITION_TYPE_SELL);
   int buyPend  = CountPendingByType(ORDER_TYPE_BUY_STOP);
   int sellPend = CountPendingByType(ORDER_TYPE_SELL_STOP);
   int total    = buyPos + sellPos + buyPend + sellPend;

   if(total == 0)
   {
      if(IsConsolidating())
         PlaceStraddleOrders();
      else
         g_lastSignal = "No consolidation";
   }
   else
   {
      if(CancelOpposite && (buyPos > 0 || sellPos > 0) && (buyPend > 0 || sellPend > 0))
         CancelAllPending();
   }

   if(ShowDashboard) DrawDashboard();
}

//+------------------------------------------------------------------+
bool IsConsolidating()
{
   double hi = iHigh(Symbol(), PERIOD_CURRENT, 1);
   double lo = iLow(Symbol(),  PERIOD_CURRENT, 1);
   for(int i = 2; i <= ConsolBars; i++)
   {
      double h = iHigh(Symbol(), PERIOD_CURRENT, i);
      double l = iLow(Symbol(),  PERIOD_CURRENT, i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
   }
   double range = hi - lo;
   return (range < g_atr * ConsolATR_Factor);
}

//+------------------------------------------------------------------+
void PlaceStraddleOrders()
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   int distPts = (int)(g_atr * ATR_Multiplier / g_point);
   if(distPts < MinPendingDist) distPts = MinPendingDist;
   if(distPts > MaxPendingDist) distPts = MaxPendingDist;
   double dist = distPts * g_point;

   double bsPrice = NormalizeDouble(ask + dist, g_digits);
   double ssPrice = NormalizeDouble(bid - dist, g_digits);
   double slDist  = StopLoss_Points   * g_point;
   double tpDist  = TakeProfit_Points * g_point;

   double lot = UseAutoLot ? CalcAutoLot(slDist) : LotSize;
   lot = NormalizeDouble(lot, 2);

   datetime expiry = TimeCurrent() + (datetime)(PendingExpiry_Min * 60);

   //--- BUY STOP via OrderSend
   MqlTradeRequest reqBuy;
   MqlTradeResult  resBuy;
   ZeroMemory(reqBuy);
   ZeroMemory(resBuy);

   reqBuy.action     = TRADE_ACTION_PENDING;
   reqBuy.symbol     = Symbol();
   reqBuy.volume     = lot;
   reqBuy.type       = ORDER_TYPE_BUY_STOP;
   reqBuy.price      = bsPrice;
   reqBuy.sl         = NormalizeDouble(bsPrice - slDist, g_digits);
   reqBuy.tp         = NormalizeDouble(bsPrice + tpDist, g_digits);
   reqBuy.type_time  = ORDER_TIME_SPECIFIED;
   reqBuy.expiration = expiry;
   reqBuy.magic      = (ulong)MagicNumber;
   reqBuy.comment    = "TuyulBS_BUY";
   reqBuy.deviation  = (ulong)MaxSlippage;

   if(OrderSend(reqBuy, resBuy))
      Print("BUY STOP placed @ ", bsPrice, " | SL:", reqBuy.sl, " TP:", reqBuy.tp);
   else
      Print("BUY STOP FAILED retcode=", resBuy.retcode);

   //--- SELL STOP via OrderSend
   MqlTradeRequest reqSell;
   MqlTradeResult  resSell;
   ZeroMemory(reqSell);
   ZeroMemory(resSell);

   reqSell.action     = TRADE_ACTION_PENDING;
   reqSell.symbol     = Symbol();
   reqSell.volume     = lot;
   reqSell.type       = ORDER_TYPE_SELL_STOP;
   reqSell.price      = ssPrice;
   reqSell.sl         = NormalizeDouble(ssPrice + slDist, g_digits);
   reqSell.tp         = NormalizeDouble(ssPrice - tpDist, g_digits);
   reqSell.type_time  = ORDER_TIME_SPECIFIED;
   reqSell.expiration = expiry;
   reqSell.magic      = (ulong)MagicNumber;
   reqSell.comment    = "TuyulBS_SELL";
   reqSell.deviation  = (ulong)MaxSlippage;

   if(OrderSend(reqSell, resSell))
      Print("SELL STOP placed @ ", ssPrice, " | SL:", reqSell.sl, " TP:", reqSell.tp);
   else
      Print("SELL STOP FAILED retcode=", resSell.retcode);

   g_lastSignal = "Straddle set | dist=" + IntegerToString(distPts) + "pts";
   g_totalTrades++;
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))       continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != Symbol())    continue;

      ulong  ticket    = posInfo.Ticket();
      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      double curTP     = posInfo.TakeProfit();
      double curPrice  = posInfo.PriceCurrent();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double profitPts = (curPrice - openPrice) / g_point;

         if(UseBreakEven && profitPts >= (double)BreakEven_Points)
         {
            double newSL = NormalizeDouble(openPrice + g_point, g_digits);
            if(curSL < newSL)
               trade.PositionModify(ticket, newSL, curTP);
         }
         if(UseTrailingStop && profitPts >= (double)TrailStart_Points)
         {
            double newSL = NormalizeDouble(curPrice - TrailStep_Points * g_point, g_digits);
            if(newSL > curSL)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double profitPts = (openPrice - curPrice) / g_point;

         if(UseBreakEven && profitPts >= (double)BreakEven_Points)
         {
            double newSL = NormalizeDouble(openPrice - g_point, g_digits);
            if(curSL == 0.0 || curSL > newSL)
               trade.PositionModify(ticket, newSL, curTP);
         }
         if(UseTrailingStop && profitPts >= (double)TrailStart_Points)
         {
            double newSL = NormalizeDouble(curPrice + TrailStep_Points * g_point, g_digits);
            if(curSL == 0.0 || newSL < curSL)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
void CancelAllPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!orderInfo.SelectByIndex(i))      continue;
      if(orderInfo.Magic()  != MagicNumber) continue;
      if(orderInfo.Symbol() != Symbol())   continue;
      trade.OrderDelete(orderInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE ptype)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))       continue;
      if(posInfo.Magic()  != MagicNumber) continue;
      if(posInfo.Symbol() != Symbol())    continue;
      if(posInfo.PositionType() == ptype) cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
int CountPendingByType(ENUM_ORDER_TYPE otype)
{
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!orderInfo.SelectByIndex(i))        continue;
      if(orderInfo.Magic()  != MagicNumber)  continue;
      if(orderInfo.Symbol() != Symbol())     continue;
      if(orderInfo.OrderType() == otype)     cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(SessionStartHour < SessionEndHour)
      return (h >= SessionStartHour && h < SessionEndHour);
   return (h >= SessionStartHour || h < SessionEndHour);
}

//+------------------------------------------------------------------+
double CalcAutoLot(double slDist)
{
   if(slDist <= 0.0) return LotSize;
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk     = balance * RiskPercent / 100.0;
   double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0.0 || tickVal == 0.0) return LotSize;
   double lot      = risk / (slDist / tickSize * tickVal);
   double minLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double stepLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   if(stepLot > 0.0) lot = MathFloor(lot / stepLot) * stepLot;
   return MathMax(minLot, MathMin(maxLot, lot));
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT)
         {
            g_lastCloseTime  = TimeCurrent();
            g_barsSinceClose = 0;
            g_sessionProfit += HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         }
      }
   }
}

//+------------------------------------------------------------------+
void DrawDashboard()
{
   int    spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   double bid    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int    buyP   = CountPositions(POSITION_TYPE_BUY);
   int    sellP  = CountPositions(POSITION_TYPE_SELL);
   int    buyO   = CountPendingByType(ORDER_TYPE_BUY_STOP);
   int    sellO  = CountPendingByType(ORDER_TYPE_SELL_STOP);

   string dash = "=== TUYUL GOLD SCALPER v1 ===\n";
   dash += "Symbol  : " + Symbol()                           + "\n";
   dash += "Price   : " + DoubleToString(bid, g_digits)      + "\n";
   dash += "Spread  : " + IntegerToString(spread) + " pts"   + "\n";
   dash += "ATR     : " + DoubleToString(g_atr / g_point, 0) + " pts\n";
   dash += "-----------------------------\n";
   dash += "BUY  pos=" + IntegerToString(buyP)  + " pend=" + IntegerToString(buyO)  + "\n";
   dash += "SELL pos=" + IntegerToString(sellP) + " pend=" + IntegerToString(sellO) + "\n";
   dash += "-----------------------------\n";
   dash += "P/L     : " + DoubleToString(g_sessionProfit, 2) + "\n";
   dash += "Trades  : " + IntegerToString(g_totalTrades)     + "\n";
   dash += "Status  : " + g_lastSignal                       + "\n";
   Comment(dash);
}
//+------------------------------------------------------------------+
