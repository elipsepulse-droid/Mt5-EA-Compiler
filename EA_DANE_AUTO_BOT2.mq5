//+------------------------------------------------------------------+
//| Grid RSI EMA EA (MT5)                                           |
//| Strategy based on provided configuration                         |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//================ INPUT PARAMETERS =================//

input double   LotSize            = 0.01;     // Volume per order
input int      GridSize           = 10;       // Max grid levels
input int      GridSpacingPips    = 500;      // Grid spacing
input double   TP_Multiplier      = 1.0;      // Take profit = spacing * multiplier
input double   MaxProfitMulti     = 5.0;      // Close grid at profit
input double   StopLossMulti      = 10.0;     // Grid stop loss

// RSI
input int      RSI_Period         = 14;
input double   RSI_BuyLevel       = 40;
input double   RSI_SellLevel      = 60;

// Trend Filter
input int      EMA_Trend_Fast     = 100;
input int      EMA_Trend_Slow     = 300;

// Exit Rule
input int      EMA_Exit_Fast      = 50;
input int      EMA_Exit_Slow      = 200;

//================ GLOBAL VARIABLES =================//

double GridLevelsBuy[100];
double GridLevelsSell[100];

bool   GridActive=false;
bool   GridDirectionBuy=false;

double StartPrice=0;

int rsiHandle;
int emaTrendFast;
int emaTrendSlow;
int emaExitFast;
int emaExitSlow;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   rsiHandle=iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);

   emaTrendFast=iMA(_Symbol,_Period,EMA_Trend_Fast,0,MODE_EMA,PRICE_CLOSE);
   emaTrendSlow=iMA(_Symbol,_Period,EMA_Trend_Slow,0,MODE_EMA,PRICE_CLOSE);

   emaExitFast=iMA(_Symbol,_Period,EMA_Exit_Fast,0,MODE_EMA,PRICE_CLOSE);
   emaExitSlow=iMA(_Symbol,_Period,EMA_Exit_Slow,0,MODE_EMA,PRICE_CLOSE);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get Pip Value                                                    |
//+------------------------------------------------------------------+
double PipValue()
{
   if(_Digits==3 || _Digits==5)
      return(_Point*10);
   return(_Point);
}

//+------------------------------------------------------------------+
//| Check if level already traded                                    |
//+------------------------------------------------------------------+
bool LevelUsed(double price)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            double open=PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(open-price)<PipValue()*10)
               return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Build Grid Levels                                                |
//+------------------------------------------------------------------+
void BuildGrid()
{
   double pip=PipValue();
   double spacing=GridSpacingPips*pip;

   for(int i=0;i<GridSize;i++)
   {
      GridLevelsBuy[i]=StartPrice-(spacing*(i+1));
      GridLevelsSell[i]=StartPrice+(spacing*(i+1));
   }
}

//+------------------------------------------------------------------+
//| Check RSI Signal                                                 |
//+------------------------------------------------------------------+
int CheckSignal()
{
   double rsi[2];
   CopyBuffer(rsiHandle,0,0,2,rsi);

   if(rsi[1]<RSI_BuyLevel && rsi[0]>RSI_BuyLevel)
      return 1;

   if(rsi[1]>RSI_SellLevel && rsi[0]<RSI_SellLevel)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Trend Filter                                                     |
//+------------------------------------------------------------------+
bool TrendBuy()
{
   double f[1],s[1];
   CopyBuffer(emaTrendFast,0,0,1,f);
   CopyBuffer(emaTrendSlow,0,0,1,s);

   return f[0]>s[0];
}

bool TrendSell()
{
   double f[1],s[1];
   CopyBuffer(emaTrendFast,0,0,1,f);
   CopyBuffer(emaTrendSlow,0,0,1,s);

   return f[0]<s[0];
}

//+------------------------------------------------------------------+
//| Exit Rule                                                        |
//+------------------------------------------------------------------+
bool ExitSignal()
{
   double f[2],s[2];
   CopyBuffer(emaExitFast,0,0,2,f);
   CopyBuffer(emaExitSlow,0,0,2,s);

   if(f[1]<s[1] && f[0]>s[0]) return true;
   if(f[1]>s[1] && f[0]<s[0]) return true;

   return false;
}

//+------------------------------------------------------------------+
//| Open Trade                                                       |
//+------------------------------------------------------------------+
void OpenTrade(bool buy)
{
   double pip=PipValue();
   double spacing=GridSpacingPips*pip;

   double price=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double tp;

   if(buy)
      tp=price+(spacing*TP_Multiplier);
   else
      tp=price-(spacing*TP_Multiplier);

   if(buy)
      trade.Buy(LotSize,_Symbol,price,0,tp);
   else
      trade.Sell(LotSize,_Symbol,price,0,tp);
}

//+------------------------------------------------------------------+
//| Manage Grid                                                      |
//+------------------------------------------------------------------+
void ManageGrid()
{
   double priceBid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double priceAsk=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      if(GridDirectionBuy)
      {
         if(priceBid<=GridLevelsBuy[i] && !LevelUsed(GridLevelsBuy[i]))
         {
            OpenTrade(true);
         }
      }
      else
      {
         if(priceAsk>=GridLevelsSell[i] && !LevelUsed(GridLevelsSell[i]))
         {
            OpenTrade(false);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close All Positions                                              |
//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            trade.PositionClose(ticket);
         }
      }
   }

   GridActive=false;
}

//+------------------------------------------------------------------+
//| Calculate Profit                                                 |
//+------------------------------------------------------------------+
double GridProfit()
{
   double profit=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            profit+=PositionGetDouble(POSITION_PROFIT);
         }
      }
   }

   return profit;
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   double pip=PipValue();
   double spacing=GridSpacingPips*pip;

   if(!GridActive)
   {
      int signal=CheckSignal();

      if(signal==1 && TrendBuy())
      {
         GridDirectionBuy=true;
         StartPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         BuildGrid();
         GridActive=true;
      }

      if(signal==-1 && TrendSell())
      {
         GridDirectionBuy=false;
         StartPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         BuildGrid();
         GridActive=true;
      }
   }

   if(GridActive)
   {
      ManageGrid();

      if(ExitSignal())
      {
         CloseAll();
         return;
      }

      double target=spacing*MaxProfitMulti;

      if(GridProfit()>=target)
      {
         CloseAll();
         return;
      }
   }
}
//+------------------------------------------------------------------+
