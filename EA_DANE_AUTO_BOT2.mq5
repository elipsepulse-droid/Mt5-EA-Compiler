//+------------------------------------------------------------------+
//| EA SCALPING ROBOT/DANE - GITHUB COMPATIBLE                      |
//+------------------------------------------------------------------+
#property strict

//--- Grid Setup
input int      GridSize=10;
input int      SpacingPips=500;
input double   LotSize=0.01;

//--- Trade Management
input int      TakeProfitMultiplier=1;
input int      MaxGridProfitMultiplier=5;
input int      GridStopLossMultiplier=10;

//--- RSI Entry
input int      RSIPeriod=14;
input double   RSI_BuyLevel=40;
input double   RSI_SellLevel=60;

//--- Exit Signal
input int      ExitMAFast=50;
input int      ExitMASlow=200;

//--- General
input ulong    MagicNumber=3613;

double spacing;
double tp_distance;
double sl_distance;

bool grid_active=false;

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
   int handle=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);

   double val[];
   CopyBuffer(handle,0,1,1,val);

   IndicatorRelease(handle);

   return val[0];
}
//+------------------------------------------------------------------+
double GetMA(int period)
{
   int handle=iMA(_Symbol,_Period,period,0,MODE_EMA,PRICE_CLOSE);

   double val[];
   CopyBuffer(handle,0,1,1,val);

   IndicatorRelease(handle);

   return val[0];
}
//+------------------------------------------------------------------+
void SendPending(ENUM_ORDER_TYPE type,double price,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_PENDING;
   req.symbol = _Symbol;
   req.volume = LotSize;
   req.type = type;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.magic = MagicNumber;

   OrderSend(req,res);
}
//+------------------------------------------------------------------+
void OpenBuyGrid()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      double entry=price-(i*spacing);
      double tp=entry+tp_distance;
      double sl=entry-sl_distance;

      SendPending(ORDER_TYPE_BUY_LIMIT,entry,sl,tp);
   }

   grid_active=true;
}
//+------------------------------------------------------------------+
void OpenSellGrid()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   for(int i=0;i<GridSize;i++)
   {
      double entry=price+(i*spacing);
      double tp=entry-tp_distance;
      double sl=entry+sl_distance;

      SendPending(ORDER_TYPE_SELL_LIMIT,entry,sl,tp);
   }

   grid_active=true;
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
   req.magic=MagicNumber;

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
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double vol=PositionGetDouble(POSITION_VOLUME);

      ClosePosition(ticket,type,vol);
   }
}
//+------------------------------------------------------------------+
double CalculateGridProfit()
{
   double profit=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      profit+=PositionGetDouble(POSITION_PROFIT);
   }

   return profit;
}
//+------------------------------------------------------------------+
void CheckExitSignal()
{
   static double prev_fast=0;
   static double prev_slow=0;

   double fast=GetMA(ExitMAFast);
   double slow=GetMA(ExitMASlow);

   if(prev_fast!=0)
   {
      if((prev_fast<prev_slow && fast>slow) ||
         (prev_fast>prev_slow && fast<slow))
      {
         CloseAllPositions();
         grid_active=false;
      }
   }

   prev_fast=fast;
   prev_slow=slow;
}
//+------------------------------------------------------------------+
int CountEAOrders()
{
   int total=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         if(PositionGetInteger(POSITION_MAGIC)==MagicNumber &&
            PositionGetString(POSITION_SYMBOL)==_Symbol)
            total++;
      }
   }

   return total;
}
//+------------------------------------------------------------------+
void OnTick()
{
   CheckExitSignal();

   if(CountEAOrders()==0)
      grid_active=false;

   double profit=CalculateGridProfit();
   double target_profit=MaxGridProfitMultiplier*spacing;

   if(profit>=target_profit)
   {
      CloseAllPositions();
      grid_active=false;
      return;
   }

   if(grid_active)
      return;

   double rsi=GetRSI();

   if(rsi<=RSI_BuyLevel)
      OpenBuyGrid();

   if(rsi>=RSI_SellLevel)
      OpenSellGrid();
}
//+------------------------------------------------------------------+
