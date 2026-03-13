//+------------------------------------------------------------------+
//| EA SCALPING ROBOT/DANE - MT5                                     |
//+------------------------------------------------------------------+
#property strict

//---- Grid Settings
input int      GridSize = 10;
input int      SpacingPips = 500;
input double   LotSize = 0.01;
input bool     MoveGrid = true;

//---- Trade Management
input bool     TakeProfitPerTrade = true;
input int      TakeProfitMultiplier = 1;
input int      MaxProfitMultiplier = 5;
input int      GridStopLossMultiplier = 10;

//---- RSI Entry
input int      RSIPeriod = 14;
input int      RSI_BuyLevel = 40;
input int      RSI_SellLevel = 60;

//---- Moving Averages
input int      FastMA = 50;
input int      SlowMA = 200;
input int      TrendMA1 = 100;
input int      TrendMA2 = 300;

double spacing;
double tp_distance;
double sl_distance;

//+------------------------------------------------------------------+
int OnInit()
{
   spacing = SpacingPips * _Point;
   tp_distance = spacing * TakeProfitMultiplier;
   sl_distance = spacing * GridStopLossMultiplier;
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
double GetRSI()
{
   int handle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   double val[];
   CopyBuffer(handle,0,1,1,val);
   IndicatorRelease(handle);
   return val[0];
}
//+------------------------------------------------------------------+
double GetMA(int period)
{
   int handle = iMA(_Symbol,_Period,period,0,MODE_EMA,PRICE_CLOSE);
   double val[];
   CopyBuffer(handle,0,1,1,val);
   IndicatorRelease(handle);
   return val[0];
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = LotSize;
   req.type   = type;
   req.price  = price;
   req.sl     = sl;
   req.tp     = tp;
   req.deviation = 10;

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void OpenGridBuy()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      double entry = price - (i*spacing);
      double tp = entry + tp_distance;
      double sl = entry - sl_distance;

      SendOrder(ORDER_TYPE_BUY_LIMIT,entry,sl,tp);
   }
}
//+------------------------------------------------------------------+
void OpenGridSell()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   for(int i=0;i<GridSize;i++)
   {
      double entry = price + (i*spacing);
      double tp = entry - tp_distance;
      double sl = entry + sl_distance;

      SendOrder(ORDER_TYPE_SELL_LIMIT,entry,sl,tp);
   }
}
//+------------------------------------------------------------------+
bool PositionsExist()
{
   if(PositionsTotal()>0) return true;
   return false;
}
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!PositionSelectByIndex(i)) continue;

      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
      long type = PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest req;
      MqlTradeResult  res;

      ZeroMemory(req);
      ZeroMemory(res);

      req.action = TRADE_ACTION_DEAL;
      req.position = ticket;
      req.symbol = _Symbol;
      req.volume = volume;

      if(type == POSITION_TYPE_BUY)
      {
         req.type = ORDER_TYPE_SELL;
         req.price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      }
      else
      {
         req.type = ORDER_TYPE_BUY;
         req.price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      }

      OrderSend(req,res);
   }
}
//+------------------------------------------------------------------+
void CheckExitSignal()
{
   double fast = GetMA(FastMA);
   double slow = GetMA(SlowMA);

   static double prev_fast=0;
   static double prev_slow=0;

   if(prev_fast!=0)
   {
      if((prev_fast<prev_slow && fast>slow) ||
         (prev_fast>prev_slow && fast<slow))
      {
         CloseAllPositions();
      }
   }

   prev_fast=fast;
   prev_slow=slow;
}
//+------------------------------------------------------------------+
void OnTick()
{
   CheckExitSignal();

   if(PositionsExist()) return;

   double rsi = GetRSI();

   if(rsi < RSI_BuyLevel)
      OpenGridBuy();

   else if(rsi > RSI_SellLevel)
      OpenGridSell();
}
//+------------------------------------------------------------------+
