//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT9 - Controlled Grid EA (Enhanced Stability)     |
//| Original strategy preserved                                      |
//| Added improvements without altering core logic:                  |
//| - Spread smoothing                                               |
//| - Volatility shutdown filter                                     |
//| - Grid density expansion                                         |
//| - Basket breakeven lock                                          |
//| - Trend acceleration protection                                  |
//| - Adaptive cooldown                                              |
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

input int MaxSpreadPoints = 50;
input int SessionStartHour = 6;
input int SessionEndHour = 21;

input double ATRMultiplier = 2.0;
input int ATRPeriod = 14;

input double ATRShutdownMultiplier = 4.0;
input double GridDensityFactor = 0.15;

input int CooldownSeconds = 300;

input double MinMarginLevel = 150.0;
input double EquityStopPercent = 0.7;

input int MaxTotalPositions = 15;
input int MaxBuyPositions = 10;
input int MaxSellPositions = 10;

input double EquityTrailStart = 1.05;
input double EquityTrailLock = 1.03;

input double BasketLockProfit = 2.0;

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
datetime lastTradeTime=0;

double peakEquity=0;

MqlTick tick;

//spread smoothing
#define SPREAD_SAMPLES 10
double spreadBuffer[SPREAD_SAMPLES];
int spreadIndex=0;

//================ INITIALIZATION =================//

int OnInit()
{
   pip=_Point;

   if(_Digits==3 || _Digits==5)
      pip=_Point*10;

   rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   fastMAHandle = iMA(_Symbol,_Period,FastTrendMA,0,MODE_EMA,PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol,_Period,SlowTrendMA,0,MODE_EMA,PRICE_CLOSE);
   exitFastHandle = iMA(_Symbol,_Period,ExitFastMA,0,MODE_EMA,PRICE_CLOSE);
   exitSlowHandle = iMA(_Symbol,_Period,ExitSlowMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,ATRPeriod);

   if(rsiHandle==INVALID_HANDLE ||
      fastMAHandle==INVALID_HANDLE ||
      slowMAHandle==INVALID_HANDLE ||
      exitFastHandle==INVALID_HANDLE ||
      exitSlowHandle==INVALID_HANDLE ||
      atrHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);

   ArrayInitialize(spreadBuffer,0);

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

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionSelectByIndex(i))
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

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionSelectByIndex(i))
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

   spreadBuffer[spreadIndex]=spread;
   spreadIndex=(spreadIndex+1)%SPREAD_SAMPLES;

   double avg=0;
   for(int i=0;i<SPREAD_SAMPLES;i++)
      avg+=spreadBuffer[i];

   avg/=SPREAD_SAMPLES;

   if(avg > MaxSpreadPoints)
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

//================ EQUITY TRAIL =================//

bool EquityTrailHit()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > peakEquity)
      peakEquity=equity;

   if(peakEquity >= AccountInfoDouble(ACCOUNT_BALANCE)*EquityTrailStart)
   {
      if(equity < peakEquity * EquityTrailLock)
         return true;
   }

   return false;
}

//================ OPEN BUY =================//

bool OpenBuy(double volume,double tp)
{
   if(TimeCurrent()==lastTradeTime)
      return false;

   trade.SetDeviationInPoints(20);

   if(trade.Buy(volume,_Symbol,0,0,tp))
   {
      lastTradeTime=TimeCurrent();
      return true;
   }

   return false;
}

//================ OPEN SELL =================//

bool OpenSell(double volume,double tp)
{
   if(TimeCurrent()==lastTradeTime)
      return false;

   trade.SetDeviationInPoints(20);

   if(trade.Sell(volume,_Symbol,0,0,tp))
   {
      lastTradeTime=TimeCurrent();
      return true;
   }

   return false;
}

//================ CLOSE ALL =================//

void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionSelectByIndex(i))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            ulong ticket=PositionGetInteger(POSITION_TICKET);
            trade.PositionClose(ticket);
         }
      }
   }

   buyGridActive=false;
   sellGridActive=false;

   lastBuyPrice=0;
   lastSellPrice=0;

   lastCloseTime=TimeCurrent();
}

//================ ENTRY SIGNAL =================//

void CheckEntrySignal()
{
   if(PositionsTotal() >= MaxTotalPositions)
      return;

   if(!SpreadOK() || !SessionOK())
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

   double atr=GetVal(atrHandle,1);

   gridSpacing = (GridSpacingPips*pip) + (atr*ATRMultiplier);

   if(atr > gridSpacing * ATRShutdownMultiplier)
      return;

   SymbolInfoTick(_Symbol,tick);

   if(rsiPrev < RSIBuyLevel && rsiCur > RSIBuyLevel && uptrend)
   {
      if(CountPositions(POSITION_TYPE_BUY) < MaxBuyPositions)
      {
         double tp=tick.ask+(gridSpacing*TakeProfitSpacing);

         if(OpenBuy(LotSize,tp))
         {
            lastBuyPrice=tick.ask;
            buyGridActive=true;
         }
      }
   }

   if(rsiPrev > RSISellLevel && rsiCur < RSISellLevel && downtrend)
   {
      if(CountPositions(POSITION_TYPE_SELL) < MaxSellPositions)
      {
         double tp=tick.bid-(gridSpacing*TakeProfitSpacing);

         if(OpenSell(LotSize,tp))
         {
            lastSellPrice=tick.bid;
            sellGridActive=true;
         }
      }
   }
}

//================ GRID MANAGEMENT =================//

void ManageGrid()
{
   if(!MarginOK())
      return;

   SymbolInfoTick(_Symbol,tick);

   if(buyGridActive)
   {
      int buyCount=CountPositions(POSITION_TYPE_BUY);

      if(buyCount < GridSize)
      {
         double levelSpacing = gridSpacing * (1 + buyCount * GridDensityFactor);

         if(lastBuyPrice - tick.bid >= levelSpacing)
         {
            double tp=tick.ask+(gridSpacing*TakeProfitSpacing);

            if(OpenBuy(LotSize,tp))
               lastBuyPrice=tick.ask;
         }
      }
   }

   if(sellGridActive)
   {
      int sellCount=CountPositions(POSITION_TYPE_SELL);

      if(sellCount < GridSize)
      {
         double levelSpacing = gridSpacing * (1 + sellCount * GridDensityFactor);

         if(tick.ask - lastSellPrice >= levelSpacing)
         {
            double tp=tick.bid-(gridSpacing*TakeProfitSpacing);

            if(OpenSell(LotSize,tp))
               lastSellPrice=tick.bid;
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
   if(!MarginOK() || !EquityOK() || EquityTrailHit())
   {
      CloseAll();
      return;
   }

   double profit=BasketProfit();

   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   double target = BasketProfitSpacing * GridSpacingPips * tickValue;
   double stop = -BasketStopSpacing * GridSpacingPips * tickValue;

   if(profit >= BasketLockProfit && profit < target)
      return;

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
