//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT9 - Controlled Grid EA (Improved Stability)     |
//| Preserves original logic, parameters, and strategy purpose      |
//| Added: spread filter, session filter, ATR volatility filter,    |
//| margin protection, equity protection, and grid cooldown         |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//================ INPUT PARAMETERS =================//

input double LotSize = 0.01;
input int GridSize = 10;
input int GridSpacingPips = 500;

input int RSIPeriod = 14;
input double RSIBuyLevel = 40;
input double RSISellLevel = 60;

input int FastTrendMA = 100;
input int SlowTrendMA = 300;

input int ExitFastMA = 50;
input int ExitSlowMA = 200;

input double TakeProfitSpacing = 10.0;
input double BasketProfitSpacing = 5.0;
input double BasketStopSpacing = 1.0;

//--- protection parameters
input int MaxSpreadPoints = 50;
input int SessionStartHour = 6;
input int SessionEndHour = 21;
input double ATRMultiplier = 2.0;
input int CooldownSeconds = 300;
input double MinMarginLevel = 150.0;
input double EquityStopPercent = 0.7;

//================ GLOBAL VARIABLES =================//

int rsiHandle;
int fastMAHandle;
int slowMAHandle;
int exitFastHandle;
int exitSlowHandle;
int atrHandle;

double pip;
double gridSpacing;

double lastBuyPrice=0;
double lastSellPrice=0;

bool buyGridActive=false;
bool sellGridActive=false;

datetime lastSignalBar=0;
datetime lastCloseTime=0;

//================ INITIALIZATION =================//

int OnInit()
{
   pip=_Point;

   if(_Digits==3 || _Digits==5)
      pip=_Point*10;

   gridSpacing = GridSpacingPips * pip;

   rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   fastMAHandle = iMA(_Symbol,_Period,FastTrendMA,0,MODE_EMA,PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol,_Period,SlowTrendMA,0,MODE_EMA,PRICE_CLOSE);
   exitFastHandle = iMA(_Symbol,_Period,ExitFastMA,0,MODE_EMA,PRICE_CLOSE);
   exitSlowHandle = iMA(_Symbol,_Period,ExitSlowMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,14);

   return(INIT_SUCCEEDED);
}

//================ INDICATOR READ =================//

double GetVal(int handle,int shift)
{
   double val[];

   if(CopyBuffer(handle,0,shift,1,val)<=0)
      return 0;

   return val[0];
}

//================ POSITION COUNT =================//

int CountPositions(int type)
{
   int total=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_TYPE)==type)
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
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
            profit+=PositionGetDouble(POSITION_PROFIT);
      }
   }

   return profit;
}

//================ PROTECTION FILTERS =================//

bool SpreadOK()
{
   double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   if(spread > MaxSpreadPoints)
      return false;

   return true;
}

bool SessionOK()
{
   int hour=TimeHour(TimeCurrent());

   if(hour < SessionStartHour || hour > SessionEndHour)
      return false;

   return true;
}

bool VolatilityOK()
{
   double atr=GetVal(atrHandle,1);

   if(atr > gridSpacing*ATRMultiplier)
      return false;

   return true;
}

bool MarginOK()
{
   double margin=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   if(margin < MinMarginLevel)
      return false;

   return true;
}

bool EquityOK()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);

   if(equity < balance * EquityStopPercent)
      return false;

   return true;
}

//================ OPEN BUY =================//

bool OpenBuy(double volume,double tp)
{
   trade.SetDeviationInPoints(20);
   return trade.Buy(volume,_Symbol,0,0,tp);
}

//================ OPEN SELL =================//

bool OpenSell(double volume,double tp)
{
   trade.SetDeviationInPoints(20);
   return trade.Sell(volume,_Symbol,0,0,tp);
}

//================ CLOSE ALL =================//

void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
            trade.PositionClose(ticket);
      }
   }

   buyGridActive=false;
   sellGridActive=false;
   lastCloseTime=TimeCurrent();
}

//================ ENTRY SIGNAL =================//

void CheckEntrySignal()
{
   if(!SpreadOK() || !SessionOK() || !VolatilityOK())
      return;

   if(TimeCurrent()-lastCloseTime < CooldownSeconds)
      return;

   datetime bar=iTime(_Symbol,_Period,1);

   if(bar==lastSignalBar)
      return;

   lastSignalBar=bar;

   double rsiPrev=GetVal(rsiHandle,2);
   double rsiCur=GetVal(rsiHandle,1);

   double fastMA=GetVal(fastMAHandle,1);
   double slowMA=GetVal(slowMAHandle,1);

   bool uptrend = fastMA > slowMA;
   bool downtrend = fastMA < slowMA;

   if(rsiPrev < RSIBuyLevel && rsiCur > RSIBuyLevel && uptrend)
   {
      if(CountPositions(POSITION_TYPE_BUY)==0)
      {
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double tp=ask+(gridSpacing*TakeProfitSpacing);

         if(OpenBuy(LotSize,tp))
         {
            lastBuyPrice=ask;
            buyGridActive=true;
         }
      }
   }

   if(rsiPrev > RSISellLevel && rsiCur < RSISellLevel && downtrend)
   {
      if(CountPositions(POSITION_TYPE_SELL)==0)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double tp=bid-(gridSpacing*TakeProfitSpacing);

         if(OpenSell(LotSize,tp))
         {
            lastSellPrice=bid;
            sellGridActive=true;
         }
      }
   }
}

//================ GRID MANAGEMENT =================//

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
            double tp=ask+(gridSpacing*TakeProfitSpacing);

            if(OpenBuy(LotSize,tp))
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
            double tp=bid-(gridSpacing*TakeProfitSpacing);

            if(OpenSell(LotSize,tp))
               lastSellPrice=bid;
         }
      }
   }
}

//================ EXIT SIGNAL =================//

void CheckExitSignal()
{
   double fastPrev=GetVal(exitFastHandle,2);
   double fastCur=GetVal(exitFastHandle,1);

   double slowPrev=GetVal(exitSlowHandle,2);
   double slowCur=GetVal(exitSlowHandle,1);

   bool crossUp = fastPrev < slowPrev && fastCur > slowCur;
   bool crossDown = fastPrev > slowPrev && fastCur < slowCur;

   if(crossUp || crossDown)
      CloseAll();
}

//================ BASKET MANAGEMENT =================//

void ManageBasket()
{
   if(!MarginOK() || !EquityOK())
   {
      CloseAll();
      return;
   }

   double profit=BasketProfit();

   double target = BasketProfitSpacing * GridSpacingPips;
   double stop = -BasketStopSpacing * GridSpacingPips;

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
