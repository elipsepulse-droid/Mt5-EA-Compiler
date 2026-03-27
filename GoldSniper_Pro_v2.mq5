//+------------------------------------------------------------------+
//|                         TuyulGoldScalper_v1.mq5                  |
//|          XAUUSD Pending-Order Breakout Straddle Scalper           |
//|      Based on strategy analysis of TUYUL PO V2 / bs.autotrade    |
//|         Designed for M1 or M5 | MetaTrader 5                     |
//+------------------------------------------------------------------+
#property copyright   "Tuyul Gold Scalper v1 - Strategy Reverse-Engineered"
#property version     "1.00"
#property description "Breakout straddle scalper for XAUUSD M1/M5"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
COrderInfo     orderInfo;
CPositionInfo  posInfo;

//==========================================================================
// INPUT PARAMETERS
//==========================================================================

input group "=== LOT & RISK ==="
input double   LotSize           = 0.01;    // Fixed Lot Size
input bool     UseAutoLot        = false;   // Use Auto Lot (based on balance)
input double   RiskPercent       = 1.0;     // Risk % per trade (if AutoLot)

input group "=== PENDING ORDER PLACEMENT ==="
input int      ATR_Period        = 14;      // ATR Period for distance calc
input double   ATR_Multiplier    = 0.5;     // ATR Multiplier for BUY/SELL STOP offset
input int      MinPendingDist    = 15;      // Minimum distance from price (points)
input int      MaxPendingDist    = 150;     // Maximum distance from price (points)

input group "=== STOP LOSS & TAKE PROFIT ==="
input int      StopLoss_Points   = 150;     // Stop Loss in points (15 pips for gold)
input int      TakeProfit_Points = 200;     // Take Profit in points (20 pips for gold)
input bool     UseTrailingStop   = true;    // Enable Trailing Stop
input int      TrailStart_Points = 100;     // Trail activates after X points profit
input int      TrailStep_Points  = 50;      // Trail step size in points
input bool     UseBreakEven      = true;    // Enable Break-Even
input int      BreakEven_Points  = 80;      // Move SL to BE after X points profit

input group "=== ORDER EXPIRY & MANAGEMENT ==="
input int      PendingExpiry_Min = 5;       // Pending order expiry in minutes
input bool     CancelOpposite    = true;    // Cancel opposite pending when one triggers
input int      MaxTrades         = 1;       // Max simultaneous trades (per direction)
input int      CooldownBars      = 3;       // Bars to wait after close before new trade

input group "=== SPREAD & EXECUTION FILTER ==="
input int      MaxSpread         = 10;      // Max allowed spread in points (10 = 1.0 pip gold)
input int      MaxSlippage       = 3;       // Max slippage in points

input group "=== SESSION FILTER ==="
input bool     UseSessionFilter  = true;    // Enable session time filter
input int      SessionStartHour  = 8;       // Session start hour (server time)
input int      SessionEndHour    = 22;      // Session end hour (server time)

input group "=== CONSOLIDATION DETECTION ==="
input int      ConsolBars        = 5;       // Bars to look back for consolidation range
input double   ConsolATR_Factor  = 0.8;     // Range must be < ATR * this factor

input group "=== MAGIC & DISPLAY ==="
input long     MagicNumber       = 202503;  // EA Magic Number
input bool     ShowDashboard     = true;    // Show info panel on chart

//==========================================================================
// GLOBAL VARIABLES
//==========================================================================
double   _atr;
double   _point;
int      _digits;
int      _atrHandle;
datetime _lastBarTime    = 0;
datetime _lastCloseTime  = 0;
int      _barsSinceClose = 0;
int      _totalTrades    = 0;
double   _sessionProfit  = 0;
string   _lastSignal     = "None";

//+------------------------------------------------------------------+
//| EA Initialization                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(StringFind(Symbol(), "XAU") < 0 && StringFind(Symbol(), "GOLD") < 0)
   {
      Print("WARNING: This EA is optimized for XAUUSD/GOLD. Current symbol: ", Symbol());
   }

   _point   = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   _digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   // ATR indicator
   _atrHandle = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   if(_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print("TuyulGoldScalper v1 initialized. Symbol: ", Symbol(),
         " | TF: ", EnumToString(Period()),
         " | Lot: ", LotSize);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(_atrHandle != INVALID_HANDLE)
      IndicatorRelease(_atrHandle);
   Comment("");
}

//+------------------------------------------------------------------+
//| Main OnTick                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only process on new bar
   datetime currentBarTime = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(currentBarTime == _lastBarTime) 
   {
      // Between bars: manage trailing stop and BE
      ManageOpenPositions();
      if(ShowDashboard) DrawDashboard();
      return;
   }
   _lastBarTime = currentBarTime;

   // Update cooldown counter
   if(_lastCloseTime > 0)
      _barsSinceClose++;

   // Get ATR
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(_atrHandle, 0, 0, 3, atrBuf) < 2)
      return;
   _atr = atrBuf[1]; // confirmed closed bar ATR

   // Check spread
   double spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _point;
   if((int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) > MaxSpread)
   {
      _lastSignal = "Spread too wide: " + IntegerToString((int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD));
      if(ShowDashboard) DrawDashboard();
      return;
   }

   // Session filter
   if(UseSessionFilter && !IsInSession())
   {
      _lastSignal = "Outside session";
      if(ShowDashboard) DrawDashboard();
      return;
   }

   // Cooldown filter
   if(_barsSinceClose < CooldownBars && _lastCloseTime > 0)
   {
      _lastSignal = "Cooldown: " + IntegerToString(CooldownBars - _barsSinceClose) + " bars left";
      if(ShowDashboard) DrawDashboard();
      return;
   }

   // Count current positions and pending orders
   int buyPos    = CountPositions(POSITION_TYPE_BUY);
   int sellPos   = CountPositions(POSITION_TYPE_SELL);
   int buyStop   = CountPendingOrders(ORDER_TYPE_BUY_STOP);
   int sellStop  = CountPendingOrders(ORDER_TYPE_SELL_STOP);

   int totalActive = buyPos + sellPos + buyStop + sellStop;

   // If no pending orders and no open positions → check for setup
   if(totalActive == 0)
   {
      if(IsConsolidating())
         PlaceStraddleOrders();
   }
   else
   {
      // Check if one side triggered → cancel opposite pending
      if(CancelOpposite)
      {
         if((buyPos > 0 || sellPos > 0) && (buyStop > 0 || sellStop > 0))
         {
            CancelAllPendingOrders();
         }
      }
   }

   ManageOpenPositions();
   if(ShowDashboard) DrawDashboard();
}

//+------------------------------------------------------------------+
//| Check if price is in consolidation zone                          |
//+------------------------------------------------------------------+
bool IsConsolidating()
{
   double high = iHigh(Symbol(), PERIOD_CURRENT, 1);
   double low  = iLow(Symbol(), PERIOD_CURRENT, 1);

   for(int i = 2; i <= ConsolBars; i++)
   {
      double h = iHigh(Symbol(), PERIOD_CURRENT, i);
      double l = iLow(Symbol(), PERIOD_CURRENT, i);
      if(h > high) high = h;
      if(l < low)  low  = l;
   }

   double range = high - low;
   return (range < _atr * ConsolATR_Factor);
}

//+------------------------------------------------------------------+
//| Place both BUY STOP and SELL STOP orders                         |
//+------------------------------------------------------------------+
void PlaceStraddleOrders()
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   // Calculate distance using ATR
   double rawDist = _atr * ATR_Multiplier;
   int    distPoints = (int)(rawDist / _point);

   // Clamp to min/max
   distPoints = MathMax(distPoints, MinPendingDist);
   distPoints = MathMin(distPoints, MaxPendingDist);

   double distPrice = distPoints * _point;

   double buyStopPrice  = NormalizeDouble(ask + distPrice, _digits);
   double sellStopPrice = NormalizeDouble(bid - distPrice, _digits);

   double sl_dist = StopLoss_Points  * _point;
   double tp_dist = TakeProfit_Points * _point;

   double buySL  = NormalizeDouble(buyStopPrice  - sl_dist, _digits);
   double buyTP  = NormalizeDouble(buyStopPrice  + tp_dist, _digits);
   double sellSL = NormalizeDouble(sellStopPrice + sl_dist, _digits);
   double sellTP = NormalizeDouble(sellStopPrice - tp_dist, _digits);

   // Expiry time
   datetime expiry = TimeCurrent() + PendingExpiry_Min * 60;

   // Calculate lot size
   double lot = UseAutoLot ? CalcAutoLot(sl_dist) : LotSize;
   lot = NormalizeDouble(lot, 2);

   // Place BUY STOP
   bool buyOk = trade.BuyStop(lot, buyStopPrice, Symbol(), buySL, buyTP,
                               ORDER_TIME_SPECIFIED, expiry,
                               "TuyulBS_BUY");
   if(buyOk)
      Print("BUY STOP placed @ ", buyStopPrice, " SL:", buySL, " TP:", buyTP);
   else
      Print("BUY STOP FAILED: ", trade.ResultRetcodeDescription());

   // Place SELL STOP
   bool sellOk = trade.SellStop(lot, sellStopPrice, Symbol(), sellSL, sellTP,
                                 ORDER_TIME_SPECIFIED, expiry,
                                 "TuyulBS_SELL");
   if(sellOk)
      Print("SELL STOP placed @ ", sellStopPrice, " SL:", sellSL, " TP:", sellTP);
   else
      Print("SELL STOP FAILED: ", trade.ResultRetcodeDescription());

   if(buyOk || sellOk)
   {
      _lastSignal = "Straddle placed | Dist: " + IntegerToString(distPoints) + "pts";
      _totalTrades++;
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (BreakEven + TrailingStop)                 |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != MagicNumber) continue;
      if(posInfo.Symbol() != Symbol()) continue;

      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      double curTP     = posInfo.TakeProfit();
      double curPrice  = posInfo.PriceCurrent();
      ulong  ticket    = posInfo.Ticket();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double profitPts = (curPrice - openPrice) / _point;

         // Break-Even
         if(UseBreakEven && profitPts >= BreakEven_Points)
         {
            double newSL = NormalizeDouble(openPrice + (_point * 2), _digits);
            if(curSL < newSL)
               trade.PositionModify(ticket, newSL, curTP);
         }

         // Trailing Stop
         if(UseTrailingStop && profitPts >= TrailStart_Points)
         {
            double newSL = NormalizeDouble(curPrice - (TrailStep_Points * _point), _digits);
            if(newSL > curSL)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double profitPts = (openPrice - curPrice) / _point;

         // Break-Even
         if(UseBreakEven && profitPts >= BreakEven_Points)
         {
            double newSL = NormalizeDouble(openPrice - (_point * 2), _digits);
            if(curSL > newSL || curSL == 0)
               trade.PositionModify(ticket, newSL, curTP);
         }

         // Trailing Stop
         if(UseTrailingStop && profitPts >= TrailStart_Points)
         {
            double newSL = NormalizeDouble(curPrice + (TrailStep_Points * _point), _digits);
            if(newSL < curSL || curSL == 0)
               trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                            |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!orderInfo.SelectByIndex(i)) continue;
      if(orderInfo.Magic() != MagicNumber) continue;
      if(orderInfo.Symbol() != Symbol()) continue;
      trade.OrderDelete(orderInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Count open positions by type                                     |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != MagicNumber) continue;
      if(posInfo.Symbol() != Symbol()) continue;
      if(posInfo.PositionType() == type) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count pending orders by type                                     |
//+------------------------------------------------------------------+
int CountPendingOrders(ENUM_ORDER_TYPE type)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!orderInfo.SelectByIndex(i)) continue;
      if(orderInfo.Magic() != MagicNumber) continue;
      if(orderInfo.Symbol() != Symbol()) continue;
      if(orderInfo.OrderType() == type) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Session time check                                               |
//+------------------------------------------------------------------+
bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   if(SessionStartHour < SessionEndHour)
      return (hour >= SessionStartHour && hour < SessionEndHour);
   else
      return (hour >= SessionStartHour || hour < SessionEndHour);
}

//+------------------------------------------------------------------+
//| Auto lot calculation based on risk %                             |
//+------------------------------------------------------------------+
double CalcAutoLot(double slDistance)
{
   if(slDistance <= 0) return LotSize;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double lotRisk    = (riskAmount / (slDistance / tickSize * tickValue));
   double minLot     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double stepLot    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   lotRisk           = MathFloor(lotRisk / stepLot) * stepLot;
   return MathMax(minLot, MathMin(maxLot, lotRisk));
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: detect when trade closes                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
      {
         // If position is being closed
         if(HistoryDealSelect(trans.deal))
         {
            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               _lastCloseTime  = TimeCurrent();
               _barsSinceClose = 0;
               _sessionProfit += HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw info dashboard                                              |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   double bid    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int    spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   int    buyP   = CountPositions(POSITION_TYPE_BUY);
   int    sellP  = CountPositions(POSITION_TYPE_SELL);
   int    buyO   = CountPendingOrders(ORDER_TYPE_BUY_STOP);
   int    sellO  = CountPendingOrders(ORDER_TYPE_SELL_STOP);

   string info = "";
   info += "╔══════════════════════════╗\n";
   info += "║  TUYUL GOLD SCALPER v1   ║\n";
   info += "╠══════════════════════════╣\n";
   info += "║ Symbol  : " + Symbol() + "          \n";
   info += "║ TF      : " + EnumToString(Period()) + "              \n";
   info += "║ Price   : " + DoubleToString(bid, _digits) + "   \n";
   info += "║ Spread  : " + IntegerToString(spread) + " pts         \n";
   info += "║ ATR     : " + DoubleToString(_atr / _point, 0) + " pts  \n";
   info += "╠══════════════════════════╣\n";
   info += "║ BUY pos : " + IntegerToString(buyP) + " | pending: " + IntegerToString(buyO) + "\n";
   info += "║ SELL pos: " + IntegerToString(sellP) + " | pending: " + IntegerToString(sellO) + "\n";
   info += "╠══════════════════════════╣\n";
   info += "║ Session P/L: " + DoubleToString(_sessionProfit, 2) + "       \n";
   info += "║ Total trades: " + IntegerToString(_totalTrades) + "          \n";
   info += "║ Signal: " + _lastSignal + "   \n";
   info += "╚══════════════════════════╝";
   Comment(info);
}

//+------------------------------------------------------------------+
//| END OF EA                                                        |
//+------------------------------------------------------------------+
