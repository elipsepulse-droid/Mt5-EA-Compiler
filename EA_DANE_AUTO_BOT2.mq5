//+------------------------------------------------------------------+
//| EA SCALPING ROBOT/DANE FIXED (NO Trade.mqh)                     |
//+------------------------------------------------------------------+
#property strict

input int GridSize=10;
input int SpacingPips=500;
input double LotSize=0.01;

input int RSIPeriod=14;
input int RSI_BuyLevel=40;
input int RSI_SellLevel=60;

input int FastMA=50;
input int SlowMA=200;

input int TakeProfitMultiplier=1;
input int StopLossMultiplier=10;

input ulong Magic=3613;

double spacing;
double tp_dist;
double sl_dist;

//+------------------------------------------------------------------+
int OnInit()
{
   spacing = SpacingPips * _Point;
   tp_dist = spacing * TakeProfitMultiplier;
   sl_dist = spacing * StopLossMultiplier;

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
bool GridExists()
{
   for(int i=0;i<OrdersTotal();i++)
   {
      ulong ticket=OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC)==Magic &&
            OrderGetString(ORDER_SYMBOL)==_Symbol)
            return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
double GetRSI()
{
   int h=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   double r[];
   CopyBuffer(h,0,1,1,r);
   IndicatorRelease(h);
   return r[0];
}
//+------------------------------------------------------------------+
double GetMA(int p)
{
   int h=iMA(_Symbol,_Period,p,0,MODE_EMA,PRICE_CLOSE);
   double r[];
   CopyBuffer(h,0,1,1,r);
   IndicatorRelease(h);
   return r[0];
}
//+------------------------------------------------------------------+
void SendPending(ENUM_ORDER_TYPE type,double entry,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_PENDING;
   req.symbol=_Symbol;
   req.volume=LotSize;
   req.type=type;
   req.price=entry;
   req.sl=sl;
   req.tp=tp;
   req.magic=Magic;

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void OpenGridSell()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   for(int i=0;i<GridSize;i++)
   {
      double entry=price+(i*spacing);
      double tp=entry-tp_dist;
      double sl=entry+sl_dist;

      SendPending(ORDER_TYPE_SELL_LIMIT,entry,sl,tp);
   }
}
//+------------------------------------------------------------------+
void OpenGridBuy()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      double entry=price-(i*spacing);
      double tp=entry+tp_dist;
      double sl=entry-sl_dist;

      SendPending(ORDER_TYPE_BUY_LIMIT,entry,sl,tp);
   }
}
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket,long type,double volume)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.position=ticket;
   req.symbol=_Symbol;
   req.volume=volume;
   req.magic=Magic;

   if(type==POSITION_TYPE_BUY)
   {
      req.type=ORDER_TYPE_SELL;
      req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   }
   else
   {
      req.type=ORDER_TYPE_BUY;
      req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   }

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void CheckExit()
{
   static double pf=0;
   static double ps=0;

   double f=GetMA(FastMA);
   double s=GetMA(SlowMA);

   if(pf!=0)
   {
      if((pf<s && f>s) || (pf>s && f<s))
      {
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong ticket=PositionGetTicket(i);
            string sym=PositionGetString(POSITION_SYMBOL);

            if(sym!=_Symbol)
               continue;

            if(PositionGetInteger(POSITION_MAGIC)!=Magic)
               continue;

            long type=PositionGetInteger(POSITION_TYPE);
            double vol=PositionGetDouble(POSITION_VOLUME);

            ClosePosition(ticket,type,vol);
         }
      }
   }

   pf=f;
   ps=s;
}
//+------------------------------------------------------------------+
void OnTick()
{
   CheckExit();

   if(GridExists())
      return;

   double rsi=GetRSI();

   if(rsi>RSI_SellLevel)
      OpenGridSell();

   if(rsi<RSI_BuyLevel)
      OpenGridBuy();
}
//+------------------------------------------------------------------+
