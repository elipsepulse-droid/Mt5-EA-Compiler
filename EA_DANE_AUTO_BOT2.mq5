//+------------------------------------------------------------------+
//| XAUUSD PRO SCALPER EA - UPGRADED COMPETITIVE VERSION             |
//| Includes: Structure + Session + Risk + Filters + Smart Logic     |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//================ INPUT PARAMETERS =================//

input double RiskPercent        = 0.5;
input int    FastEMA            = 20;
input int    SlowEMA            = 50;
input int    RSIPeriod          = 14;
input int    ADX_Period         = 14;
input double ADX_Min            = 25;

input int    ATR_Period         = 14;
input double ATR_Min            = 30;
input double ATR_Max            = 500;

input double RR_Ratio           = 1.5;

input int    MaxSpreadPoints    = 30;
input int    MaxTrades          = 1;

input int    BreakevenPoints    = 80;
input int    TrailATR_Mult      = 1;

input double MaxDrawdownPercent = 10;
input double DailyLossPercent   = 5;

input bool   UseSessionFilter   = true;
input bool   UseNewsFilter      = false; // manual placeholder

//================ GLOBAL =================//

int emaFast_M1, emaSlow_M1;
int emaFast_M5, emaSlow_M5;
int emaFast_H1, emaSlow_H1;

int rsiHandle, atrHandle, adxHandle;

double peakEquity = 0;
double dailyStartEquity = 0;
datetime lastDay = 0;

//+------------------------------------------------------------------+
// INIT
//+------------------------------------------------------------------+
int OnInit()
{
   emaFast_M1 = iMA(_Symbol, PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   emaSlow_M1 = iMA(_Symbol, PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   emaFast_M5 = iMA(_Symbol, PERIOD_M5, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   emaSlow_M5 = iMA(_Symbol, PERIOD_M5, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   emaFast_H1 = iMA(_Symbol, PERIOD_H1, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   emaSlow_H1 = iMA(_Symbol, PERIOD_H1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   rsiHandle = iRSI(_Symbol, PERIOD_M1, RSIPeriod, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_M1, ATR_Period);
   adxHandle = iADX(_Symbol, PERIOD_M1, ADX_Period);

   peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyStartEquity = peakEquity;
   lastDay = TimeDay(TimeCurrent());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// SESSION FILTER
//+------------------------------------------------------------------+
bool SessionOK()
{
   if(!UseSessionFilter) return true;

   int hour = TimeHour(TimeCurrent());

   if(hour >= 7 && hour <= 17) return true;   // London
   if(hour >= 13 && hour <= 22) return true;  // NY

   return false;
}

//+------------------------------------------------------------------+
// SPREAD FILTER
//+------------------------------------------------------------------+
bool SpreadOK()
{
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   return spread <= MaxSpreadPoints;
}

//+------------------------------------------------------------------+
// DRAW DOWN CONTROL
//+------------------------------------------------------------------+
bool RiskOK()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > peakEquity) peakEquity = equity;

   double dd = (peakEquity - equity)/peakEquity*100.0;
   if(dd > MaxDrawdownPercent) return false;

   // Daily reset
   if(TimeDay(TimeCurrent()) != lastDay)
   {
      dailyStartEquity = equity;
      lastDay = TimeDay(TimeCurrent());
   }

   double dailyLoss = (dailyStartEquity - equity)/dailyStartEquity*100.0;
   if(dailyLoss > DailyLossPercent) return false;

   return true;
}

//+------------------------------------------------------------------+
// LOT SIZE (RISK BASED)
//+------------------------------------------------------------------+
double LotSize(double slPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (RiskPercent/100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = risk / (slPoints * tickValue);

   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
// POSITION COUNT
//+------------------------------------------------------------------+
int CountPositions()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
      if(PositionGetSymbol(i)==_Symbol) c++;
   return c;
}

//+------------------------------------------------------------------+
// TRADE MANAGEMENT
//+------------------------------------------------------------------+
void ManageTrades(double atrPoints)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetSymbol(i)!=_Symbol) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double price= PositionGetDouble(POSITION_PRICE_CURRENT);

      long type = PositionGetInteger(POSITION_TYPE);

      double profitPoints = (type==POSITION_TYPE_BUY)?
         (price-open)/_Point:(open-price)/_Point;

      // Breakeven
      if(profitPoints >= BreakevenPoints)
         trade.PositionModify(PositionGetTicket(i), open, tp);

      // ATR trailing
      double trail = atrPoints * TrailATR_Mult;

      if(type==POSITION_TYPE_BUY)
      {
         double newSL = price - trail*_Point;
         if(newSL > sl)
            trade.PositionModify(PositionGetTicket(i), newSL, tp);
      }
      else
      {
         double newSL = price + trail*_Point;
         if(newSL < sl)
            trade.PositionModify(PositionGetTicket(i), newSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
// SIMPLE CANDLE CONFIRMATION
//+------------------------------------------------------------------+
bool BullishEngulfing()
{
   double o1=iOpen(_Symbol,PERIOD_M1,1);
   double c1=iClose(_Symbol,PERIOD_M1,1);
   double o2=iOpen(_Symbol,PERIOD_M1,2);
   double c2=iClose(_Symbol,PERIOD_M1,2);

   return (c1>o1 && c2<o2 && c1>o2 && o1<c2);
}

bool BearishEngulfing()
{
   double o1=iOpen(_Symbol,PERIOD_M1,1);
   double c1=iClose(_Symbol,PERIOD_M1,1);
   double o2=iOpen(_Symbol,PERIOD_M1,2);
   double c2=iClose(_Symbol,PERIOD_M1,2);

   return (c1<o1 && c2>o2 && c1<o2 && o1>c2);
}

//+------------------------------------------------------------------+
// MAIN LOGIC
//+------------------------------------------------------------------+
void CheckTrade()
{
   if(!SessionOK()) return;
   if(!SpreadOK()) return;
   if(!RiskOK()) return;
   if(CountPositions() >= MaxTrades) return;

   double emaF_M1[], emaS_M1[];
   double emaF_M5[], emaS_M5[];
   double emaF_H1[], emaS_H1[];
   double rsi[], atr[], adx[];

   CopyBuffer(emaFast_M1,0,0,2,emaF_M1);
   CopyBuffer(emaSlow_M1,0,0,2,emaS_M1);

   CopyBuffer(emaFast_M5,0,0,2,emaF_M5);
   CopyBuffer(emaSlow_M5,0,0,2,emaS_M5);

   CopyBuffer(emaFast_H1,0,0,2,emaF_H1);
   CopyBuffer(emaSlow_H1,0,0,2,emaS_H1);

   CopyBuffer(rsiHandle,0,0,2,rsi);
   CopyBuffer(atrHandle,0,0,2,atr);
   CopyBuffer(adxHandle,0,0,2,adx);

   double atrPoints = atr[0]/_Point;

   if(atrPoints < ATR_Min || atrPoints > ATR_Max) return;
   if(adx[0] < ADX_Min) return;

   bool upTrend =
      emaF_H1[0]>emaS_H1[0] &&
      emaF_M5[0]>emaS_M5[0];

   bool downTrend =
      emaF_H1[0]<emaS_H1[0] &&
      emaF_M5[0]<emaS_M5[0];

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double slPoints = atrPoints * 1.2;
   double tpPoints = slPoints * RR_Ratio;

   double lot = LotSize(slPoints);

   // BUY
   if(upTrend &&
      emaF_M1[0]>emaS_M1[0] &&
      rsi[0]>55 &&
      BullishEngulfing())
   {
      double sl = bid - slPoints*_Point;
      double tp = bid + tpPoints*_Point;
      trade.Buy(lot,_Symbol,ask,sl,tp);
   }

   // SELL
   if(downTrend &&
      emaF_M1[0]<emaS_M1[0] &&
      rsi[0]<45 &&
      BearishEngulfing())
   {
      double sl = ask + slPoints*_Point;
      double tp = ask - tpPoints*_Point;
      trade.Sell(lot,_Symbol,bid,sl,tp);
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar=0;
   datetime currentBar = iTime(_Symbol,PERIOD_M1,0);

   double atr[];
   CopyBuffer(atrHandle,0,0,1,atr);
   double atrPoints = atr[0]/_Point;

   ManageTrades(atrPoints);

   if(currentBar == lastBar) return;
   lastBar = currentBar;

   CheckTrade();
}
//+------------------------------------------------------------------+
