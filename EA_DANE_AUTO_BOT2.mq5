//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT2_FIXED                                          |
//| Clean compile version                                            |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//================ INPUT PARAMETERS =================//

input double FixedLot = 0.01;
input bool   UseDynamicLot = true;
input double RiskPercent = 1.0;

input int RSIPeriod = 14;
input int FastEMA = 9;
input int SlowEMA = 21;

input int ATRPeriod = 14;
input double SL_ATR_Multiplier = 1.5;
input double TP_ATR_Multiplier = 1.0;

input double MaxSpreadPoints = 300;
input int MaxOpenTrades = 5;

input double BreakevenTrigger = 200;
input double TrailingDistance = 150;

input double MaxDrawdownPercent = 20;

//================ GLOBAL VARIABLES =================//

int rsiHandle;
int emaFastHandle;
int emaSlowHandle;
int atrHandle;

double rsiBuffer[];
double emaFastBuffer[];
double emaSlowBuffer[];
double atrBuffer[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+

int OnInit()
{
   rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   emaFastHandle = iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,ATRPeriod);

   ArraySetAsSeries(rsiBuffer,true);
   ArraySetAsSeries(emaFastBuffer,true);
   ArraySetAsSeries(emaSlowBuffer,true);
   ArraySetAsSeries(atrBuffer,true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick Engine                                                      |
//+------------------------------------------------------------------+

void OnTick()
{
   if(!MarketFilters())
      return;

   ManagePositions();

   if(PositionsTotal() >= MaxOpenTrades)
      return;

   int signal = GetSignal();

   if(signal == 1)
      OpenBuy();

   if(signal == -1)
      OpenSell();
}

//+------------------------------------------------------------------+
//| Market Filters                                                   |
//+------------------------------------------------------------------+

bool MarketFilters()
{
   if(!SpreadCheck()) return false;
   if(!DrawdownCheck()) return false;

   return true;
}

bool SpreadCheck()
{
   double spread = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(spread > MaxSpreadPoints)
      return false;

   return true;
}

bool DrawdownCheck()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   double dd = (balance-equity)/balance*100.0;

   if(dd > MaxDrawdownPercent)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Signal Engine                                                    |
//+------------------------------------------------------------------+

int GetSignal()
{
   CopyBuffer(rsiHandle,0,0,2,rsiBuffer);
   CopyBuffer(emaFastHandle,0,0,2,emaFastBuffer);
   CopyBuffer(emaSlowHandle,0,0,2,emaSlowBuffer);

   if(rsiBuffer[0] > 55 && emaFastBuffer[0] > emaSlowBuffer[0])
      return 1;

   if(rsiBuffer[0] < 45 && emaFastBuffer[0] < emaSlowBuffer[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Risk Management                                                  |
//+------------------------------------------------------------------+

double CalculateLot(double sl_points)
{
   if(!UseDynamicLot)
      return FixedLot;

   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;

   double tickvalue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   double lot = risk / (sl_points * tickvalue);

   double minlot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

   if(lot < minlot) lot = minlot;
   if(lot > maxlot) lot = maxlot;

   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
//| Order Execution                                                  |
//+------------------------------------------------------------------+

void OpenBuy()
{
   CopyBuffer(atrHandle,0,0,1,atrBuffer);

   double atr = atrBuffer[0];

   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double sl = price - atr * SL_ATR_Multiplier;
   double tp = price + atr * TP_ATR_Multiplier;

   double sl_points = (price - sl)/_Point;

   double lot = CalculateLot(sl_points);

   trade.Buy(lot,_Symbol,price,sl,tp);
}

void OpenSell()
{
   CopyBuffer(atrHandle,0,0,1,atrBuffer);

   double atr = atrBuffer[0];

   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double sl = price + atr * SL_ATR_Multiplier;
   double tp = price - atr * TP_ATR_Multiplier;

   double sl_points = (sl - price)/_Point;

   double lot = CalculateLot(sl_points);

   trade.Sell(lot,_Symbol,price,sl,tp);
}

//+------------------------------------------------------------------+
//| Position Management                                              |
//+------------------------------------------------------------------+

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      ManageBreakeven(ticket);
      ManageTrailing(ticket);
   }
}

//+------------------------------------------------------------------+
//| Breakeven                                                        |
//+------------------------------------------------------------------+

void ManageBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double profit = PositionGetDouble(POSITION_PROFIT);

   if(profit > BreakevenTrigger && sl != open)
      trade.PositionModify(ticket,open,tp);
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//+------------------------------------------------------------------+

void ManageTrailing(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   double newSL = price - TrailingDistance * _Point;

   if(newSL > sl)
      trade.PositionModify(ticket,newSL,tp);
}
