//+------------------------------------------------------------------+
//| Grid RSI EMA EA (MT5)                                           |
//| Controlled execution / single signal entry                      |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//================ INPUT PARAMETERS =================//

input double   LotSize = 0.01;
input int      GridSize = 10;
input int      GridSpacingPips = 500;

input int      RSIPeriod = 14;
input double   RSIBuyLevel = 40;
input double   RSISellLevel = 60;

input int      FastTrendMA = 100;
input int      SlowTrendMA = 300;

input int      ExitFastMA = 50;
input int      ExitSlowMA = 200;

input double   TakeProfitSpacing = 1.0;
input double   BasketProfitSpacing = 5.0;
input double   BasketStopSpacing = 10.0;

input bool     MoveGrid = true;

//================ GLOBAL VARIABLES =================//

int rsiHandle;
int fastMAHandle;
int slowMAHandle;
int exitFastHandle;
int exitSlowHandle;

double pip;
double gridSpacing;

double lastBuyPrice = 0;
double lastSellPrice = 0;

bool buyGridActive=false;
bool sellGridActive=false;

datetime lastSignalBar=0;

//================ INITIALIZATION =================//

int OnInit()
{
   pip = _Point;
   if(_Digits==3 || _Digits==5)
      pip = _Point*10;

   gridSpacing = GridSpacingPips * pip;

   rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);

   fastMAHandle = iMA(_Symbol,_Period,FastTrendMA,0,MODE_EMA,PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol,_Period,SlowTrendMA,0,MODE_EMA,PRICE_CLOSE);

   exitFastHandle = iMA(_Symbol,_Period,ExitFastMA,0,MODE_EMA,PRICE_CLOSE);
   exitSlowHandle = iMA(_Symbol,_Period,ExitSlowMA,0,MODE_EMA,PRICE_CLOSE);

   return(INIT_SUCCEEDED);
}

//================ DATA ACCESS =================//

double GetBufferValue(int handle,int shift)
{
   double val[];
   CopyBuffer(handle,0,shift,1,val);
   return val[0];
}

//================ POSITION COUNT =================//

int CountPositions(int type)
{
   int total=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionGetString(POSITION_SYMBOL)==_Symbol)
      {
         if(PositionGetInteger(POSITION_TYPE)==type)
            total++;
      }
   }
   return total;
}

//================ BASKET PROFIT =================//

double BasketProfit()
{
   double profit=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
            profit+=PositionGetDouble(POSITION_PROFIT);
      }
   }

   return profit;
}

//================ CLOSE ALL =================//

void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionGetString(POSITION_SYMBOL)==_Symbol)
      {
         trade.PositionClose(ticket);
      }
   }

   buyGridActive=false;
   sellGridActive=false;
}

//================ ENTRY SIGNAL =================//

void CheckEntrySignal()
{
   datetime bar=iTime(_Symbol,_Period,1);

   if(bar==lastSignalBar)
      return;

   lastSignalBar=bar;

   double rsiPrev=GetBufferValue(rsiHandle,2);
   double rsiCur=GetBufferValue(rsiHandle,1);

   double fastMA=GetBufferValue(fastMAHandle,1);
   double slowMA=GetBufferValue(slowMAHandle,1);

   bool uptrend = fastMA > slowMA;
   bool downtrend = fastMA < slowMA;

   if(rsiPrev < RSIBuyLevel && rsiCur > RSIBuyLevel && uptrend)
   {
      if(CountPositions(POSITION_TYPE_BUY)==0)
      {
         double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

         trade.Buy(LotSize,_Symbol,price,0,price+(gridSpacing*TakeProfitSpacing));

         lastBuyPrice=price;
         buyGridActive=true;
      }
   }

   if(rsiPrev > RSISellLevel && rsiCur < RSISellLevel && downtrend)
   {
      if(CountPositions(POSITION_TYPE_SELL)==0)
      {
         double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

         trade.Sell(LotSize,_Symbol,price,0,price-(gridSpacing*TakeProfitSpacing));

         lastSellPrice=price;
         sellGridActive=true;
      }
   }
}

//================ GRID LOGIC =================//

void ManageGrid()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   if(buyGridActive)
   {
      int buyCount=CountPositions(POSITION_TYPE_BUY);

      if(buyCount < GridSize)
      {
         if(lastBuyPrice - bid >= gridSpacing)
         {
            trade.Buy(LotSize,_Symbol,ask,0,ask+(gridSpacing*TakeProfitSpacing));

            lastBuyPrice=ask;
         }
      }
   }

   if(sellGridActive)
   {
      int sellCount=CountPositions(POSITION_TYPE_SELL);

      if(sellCount < GridSize)
      {
         if(ask - lastSellPrice >= gridSpacing)
         {
            trade.Sell(LotSize,_Symbol,bid,0,bid-(gridSpacing*TakeProfitSpacing));

            lastSellPrice=bid;
         }
      }
   }
}

//================ EXIT SIGNAL =================//

void CheckExitSignal()
{
   double fastPrev=GetBufferValue(exitFastHandle,2);
   double fastCur=GetBufferValue(exitFastHandle,1);

   double slowPrev=GetBufferValue(exitSlowHandle,2);
   double slowCur=GetBufferValue(exitSlowHandle,1);

   bool crossUp = fastPrev < slowPrev && fastCur > slowCur;
   bool crossDown = fastPrev > slowPrev && fastCur < slowCur;

   if(crossUp || crossDown)
      CloseAll();
}

//================ BASKET MANAGEMENT =================//

void ManageBasket()
{
   double profit=BasketProfit();

   double spacingValue = gridSpacing / _Point * SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   double target = BasketProfitSpacing * spacingValue;
   double stop = -BasketStopSpacing * spacingValue;

   if(profit >= target || profit <= stop)
      CloseAll();
}

//================ MAIN LOOP =================//

void OnTick()
{
   CheckEntrySignal();
   ManageGrid();
   CheckExitSignal();
   ManageBasket();
}
