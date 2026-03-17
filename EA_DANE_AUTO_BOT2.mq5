//+------------------------------------------------------------------+
//| XAUUSD PRO SCALPER EA v2.1 - COMPILATION SAFE VERSION            |
//| Fixed: includes, position handling, type casting, stability      |
//+------------------------------------------------------------------+
#property strict
#property version   "2.1"
#property description "XAUUSD PRO SCALPER FIXED BUILD"

#include <Trade\Trade.mqh>
CTrade trade;

//================ INPUTS =================//

input double RiskPercent        = 0.5;
input int    ATR_Period         = 14;
input int    RSI_Period         = 7;

input double RR_Min             = 1.2;
input double RR_Max             = 2.0;

input int    MaxTrades          = 3;

input double MaxDrawdownPercent = 10;
input double DailyLossPercent   = 5;
input double DailyProfitTarget  = 3;

input int    SpreadLimit        = 30;
input int    ScoreThreshold     = 70;

//================ GLOBAL =================//

int atrHandle, rsiHandle;

double peakEquity=0, dailyStartEquity=0;
datetime lastDay=0;
int lossStreak=0;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_M1, ATR_Period);
   rsiHandle = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);

   trade.SetDeviationInPoints(10);

   peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyStartEquity = peakEquity;
   lastDay = TimeDay(TimeCurrent());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// RISK CONTROL
//+------------------------------------------------------------------+
bool RiskOK()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > peakEquity)
      peakEquity = equity;

   double dd = (peakEquity - equity)/peakEquity*100.0;
   if(dd > MaxDrawdownPercent)
      return false;

   if(TimeDay(TimeCurrent()) != lastDay)
   {
      dailyStartEquity = equity;
      lastDay = TimeDay(TimeCurrent());
   }

   double dailyLoss = (dailyStartEquity - equity)/dailyStartEquity*100.0;
   if(dailyLoss > DailyLossPercent)
      return false;

   double dailyProfit = (equity - dailyStartEquity)/dailyStartEquity*100.0;
   if(dailyProfit > DailyProfitTarget)
      return false;

   return true;
}

//+------------------------------------------------------------------+
// LOT SIZE
//+------------------------------------------------------------------+
double LotSize(double slPoints)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * (RiskPercent/100.0);

   if(lossStreak >= 2)
      risk *= 0.5;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double valuePerPoint = tickValue / tickSize;
   double lot = risk / (slPoints * valuePerPoint);

   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
// SPREAD CHECK
//+------------------------------------------------------------------+
bool SpreadOK()
{
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   return spread <= SpreadLimit;
}

//+------------------------------------------------------------------+
// STRUCTURE (BOS)
//+------------------------------------------------------------------+
bool BreakStructureUp()
{
   double prevHigh = iHigh(_Symbol,PERIOD_M5,1);
   double currHigh = iHigh(_Symbol,PERIOD_M5,0);
   return currHigh > prevHigh;
}

bool BreakStructureDown()
{
   double prevLow = iLow(_Symbol,PERIOD_M5,1);
   double currLow = iLow(_Symbol,PERIOD_M5,0);
   return currLow < prevLow;
}

//+------------------------------------------------------------------+
// LIQUIDITY SWEEP
//+------------------------------------------------------------------+
bool SweepLow()
{
   double low1=iLow(_Symbol,PERIOD_M1,1);
   double low2=iLow(_Symbol,PERIOD_M1,2);
   double close=iClose(_Symbol,PERIOD_M1,1);
   return (low1 < low2 && close > low2);
}

bool SweepHigh()
{
   double high1=iHigh(_Symbol,PERIOD_M1,1);
   double high2=iHigh(_Symbol,PERIOD_M1,2);
   double close=iClose(_Symbol,PERIOD_M1,1);
   return (high1 > high2 && close < high2);
}

//+------------------------------------------------------------------+
// MOMENTUM
//+------------------------------------------------------------------+
bool MomentumBuy()
{
   double rsi[];
   if(CopyBuffer(rsiHandle,0,0,1,rsi) <= 0) return false;
   return rsi[0] > 55;
}

bool MomentumSell()
{
   double rsi[];
   if(CopyBuffer(rsiHandle,0,0,1,rsi) <= 0) return false;
   return rsi[0] < 45;
}

//+------------------------------------------------------------------+
// VOLUME SPIKE
//+------------------------------------------------------------------+
bool VolumeSpike()
{
   double v1 = (double)iVolume(_Symbol,PERIOD_M1,1);
   double avg=0;

   for(int i=2;i<10;i++)
      avg += (double)iVolume(_Symbol,PERIOD_M1,i);

   avg /= 8.0;

   return v1 > avg*1.5;
}

//+------------------------------------------------------------------+
// ATR
//+------------------------------------------------------------------+
double GetATRPoints()
{
   double atr[];
   if(CopyBuffer(atrHandle,0,0,1,atr) <= 0) return 0;
   return atr[0]/_Point;
}

//+------------------------------------------------------------------+
// SIGNAL SCORE
//+------------------------------------------------------------------+
int SignalScore(bool buy)
{
   int score=0;

   if(buy)
   {
      if(SweepLow()) score+=20;
      if(BreakStructureUp()) score+=25;
      if(MomentumBuy()) score+=15;
      if(VolumeSpike()) score+=10;
   }
   else
   {
      if(SweepHigh()) score+=20;
      if(BreakStructureDown()) score+=25;
      if(MomentumSell()) score+=15;
      if(VolumeSpike()) score+=10;
   }

   if(GetATRPoints() > 0) score+=20;

   return score;
}

//+------------------------------------------------------------------+
// MANAGE TRADES
//+------------------------------------------------------------------+
void ManageTrades(double atrPoints)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double price= PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      long type   = PositionGetInteger(POSITION_TYPE);

      double profit = (type==POSITION_TYPE_BUY)?
         (price-open)/_Point:(open-price)/_Point;

      double BE = atrPoints;

      if(profit >= BE)
         trade.PositionModify(ticket, open, tp);

      double trail = atrPoints * 1.5;

      if(type==POSITION_TYPE_BUY)
      {
         double newSL = price - trail*_Point;
         if(newSL > sl)
            trade.PositionModify(ticket, newSL, tp);
      }
      else
      {
         double newSL = price + trail*_Point;
         if(newSL < sl)
            trade.PositionModify(ticket, newSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
// ENTRY
//+------------------------------------------------------------------+
void CheckTrade()
{
   if(!RiskOK()) return;
   if(!SpreadOK()) return;
   if(PositionsTotal() >= MaxTrades) return;

   double atrPoints = GetATRPoints();
   if(atrPoints <= 0) return;

   int buyScore = SignalScore(true);
   int sellScore= SignalScore(false);

   double slPoints = atrPoints * 1.2;
   double RR = (buyScore > sellScore) ? RR_Max : RR_Min;
   double tpPoints = slPoints * RR;

   double lot = LotSize(slPoints);

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(buyScore >= ScoreThreshold)
   {
      double sl = bid - slPoints*_Point;
      double tp = bid + tpPoints*_Point;

      if(trade.Buy(lot,_Symbol,ask,sl,tp))
         lossStreak = 0;
      else
         lossStreak++;
   }

   if(sellScore >= ScoreThreshold)
   {
      double sl = ask + slPoints*_Point;
      double tp = ask - tpPoints*_Point;

      if(trade.Sell(lot,_Symbol,bid,sl,tp))
         lossStreak = 0;
      else
         lossStreak++;
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar=0;
   datetime currentBar=iTime(_Symbol,PERIOD_M1,0);

   double atrPoints = GetATRPoints();

   ManageTrades(atrPoints);

   if(currentBar == lastBar) return;
   lastBar = currentBar;

   CheckTrade();
}
//+------------------------------------------------------------------+
