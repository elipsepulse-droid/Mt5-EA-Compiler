//+------------------------------------------------------------------+
//| EA SCALPING ROBOT/DANE - MT5                                     |
//| Settings copied from provided configuration                      |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

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
   int rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   double rsi[];
   CopyBuffer(rsiHandle,0,1,1,rsi);
   IndicatorRelease(rsiHandle);
   return rsi[0];
}
//+------------------------------------------------------------------+
double GetMA(int period)
{
   int maHandle = iMA(_Symbol,_Period,period,0,MODE_EMA,PRICE_CLOSE);
   double ma[];
   CopyBuffer(maHandle,0,1,1,ma);
   IndicatorRelease(maHandle);
   return ma[0];
}
//+------------------------------------------------------------------+
void OpenGridBuy()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      double entry = price - (i*spacing);
      double tp = entry + tp_distance;
      double sl = entry - sl_distance;

      trade.BuyLimit(LotSize,entry,_Symbol,sl,tp);
   }
}
//+------------------------------------------------------------------+
void OpenGridSell()
{
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   for(int i=0;i<GridSize;i++)
   {
      double entry = price + (i*spacing);
      double tp = entry - tp_distance;
      double sl = entry + sl_distance;

      trade.SellLimit(LotSize,entry,_Symbol,sl,tp);
   }
}
//+------------------------------------------------------------------+
bool PositionsExist()
{
   if(PositionsTotal()>0) return true;
   return false;
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
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong ticket=PositionGetTicket(i);
            trade.PositionClose(ticket);
         }
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
   {
      OpenGridBuy();
   }
   else if(rsi > RSI_SellLevel)
   {
      OpenGridSell();
   }
}
//+------------------------------------------------------------------+
