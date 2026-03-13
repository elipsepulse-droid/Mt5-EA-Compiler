//+------------------------------------------------------------------+
//| EA SCALPING ROBOT/DANE - MT5                                     |
//+------------------------------------------------------------------+
#property strict

input int GridSize = 10;
input int SpacingPips = 500;
input double LotSize = 0.01;

input int TakeProfitMultiplier = 1;
input int GridStopLossMultiplier = 10;

input int RSIPeriod = 14;
input int RSI_BuyLevel = 40;
input int RSI_SellLevel = 60;

input int FastMA = 50;
input int SlowMA = 200;

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
   int h = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   double v[];
   CopyBuffer(h,0,1,1,v);
   IndicatorRelease(h);
   return v[0];
}
//+------------------------------------------------------------------+
double GetMA(int p)
{
   int h = iMA(_Symbol,_Period,p,0,MODE_EMA,PRICE_CLOSE);
   double v[];
   CopyBuffer(h,0,1,1,v);
   IndicatorRelease(h);
   return v[0];
}
//+------------------------------------------------------------------+
void SendOrder(ENUM_ORDER_TYPE type,double price,double sl,double tp)
{
   MqlTradeRequest r;
   MqlTradeResult res;

   ZeroMemory(r);
   ZeroMemory(res);

   r.action=TRADE_ACTION_PENDING;
   r.symbol=_Symbol;
   r.volume=LotSize;
   r.type=type;
   r.price=price;
   r.sl=sl;
   r.tp=tp;

   OrderSend(r,res);
}
//+------------------------------------------------------------------+
void OpenGridBuy()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      double entry = price-(i*spacing);
      double tp = entry+tp_distance;
      double sl = entry-sl_distance;

      SendOrder(ORDER_TYPE_BUY_LIMIT,entry,sl,tp);
   }
}
//+------------------------------------------------------------------+
void OpenGridSell()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   for(int i=0;i<GridSize;i++)
   {
      double entry = price+(i*spacing);
      double tp = entry-tp_distance;
      double sl = entry+sl_distance;

      SendOrder(ORDER_TYPE_SELL_LIMIT,entry,sl,tp);
   }
}
//+------------------------------------------------------------------+
bool PositionsExist()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket>0)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket==0)
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      if(sym!=_Symbol)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);
      long type = PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest r;
      MqlTradeResult res;

      ZeroMemory(r);
      ZeroMemory(res);

      r.action=TRADE_ACTION_DEAL;
      r.position=ticket;
      r.symbol=_Symbol;
      r.volume=volume;

      if(type==POSITION_TYPE_BUY)
      {
         r.type=ORDER_TYPE_SELL;
         r.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      }
      else
      {
         r.type=ORDER_TYPE_BUY;
         r.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      }

      OrderSend(r,res);
   }
}
//+------------------------------------------------------------------+
void CheckExit()
{
   double fast = GetMA(FastMA);
   double slow = GetMA(SlowMA);

   static double pf=0;
   static double ps=0;

   if(pf!=0)
   {
      if((pf<ps && fast>slow) || (pf>ps && fast<slow))
         CloseAllPositions();
   }

   pf=fast;
   ps=slow;
}
//+------------------------------------------------------------------+
void OnTick()
{
   CheckExit();

   if(PositionsExist())
      return;

   double rsi = GetRSI();

   if(rsi < RSI_BuyLevel)
      OpenGridBuy();

   if(rsi > RSI_SellLevel)
      OpenGridSell();
}
//+------------------------------------------------------------------+
