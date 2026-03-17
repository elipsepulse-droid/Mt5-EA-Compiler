//+------------------------------------------------------------------+
//| XAUUSD PRO SCALPER EA v2.2 - NO INCLUDE VERSION (CI SAFE)         |
//+------------------------------------------------------------------+
#property strict
#property version   "2.2"

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
// BASIC TRADE FUNCTION (NO CTrade)
//+------------------------------------------------------------------+
bool OpenTrade(bool buy,double lot,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.volume   = lot;
   req.type     = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price    = buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                      : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.sl       = sl;
   req.tp       = tp;
   req.deviation= 10;
   req.magic    = 123456;

   return OrderSend(req,res);
}

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_M1, ATR_Period);
   rsiHandle = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);

   peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyStartEquity = peakEquity;
   lastDay = TimeDay(TimeCurrent());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
bool RiskOK()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity > peakEquity)
      peakEquity = equity;

   double dd = (peakEquity - equity)/peakEquity*100.0;
   if(dd > MaxDrawdownPercent) return false;

   if(TimeDay(TimeCurrent()) != lastDay)
   {
      dailyStartEquity = equity;
      lastDay = TimeDay(TimeCurrent());
   }

   double dailyLoss = (dailyStartEquity - equity)/dailyStartEquity*100.0;
   if(dailyLoss > DailyLossPercent) return false;

   double dailyProfit = (equity - dailyStartEquity)/dailyStartEquity*100.0;
   if(dailyProfit > DailyProfitTarget) return false;

   return true;
}

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
bool SpreadOK()
{
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   return spread <= SpreadLimit;
}

//+------------------------------------------------------------------+
bool BreakStructureUp()
{
   return iHigh(_Symbol,PERIOD_M5,0) > iHigh(_Symbol,PERIOD_M5,1);
}

bool BreakStructureDown()
{
   return iLow(_Symbol,PERIOD_M5,0) < iLow(_Symbol,PERIOD_M5,1);
}

//+------------------------------------------------------------------+
bool SweepLow()
{
   double l1=iLow(_Symbol,PERIOD_M1,1);
   double l2=iLow(_Symbol,PERIOD_M1,2);
   double c=iClose(_Symbol,PERIOD_M1,1);
   return (l1<l2 && c>l2);
}

bool SweepHigh()
{
   double h1=iHigh(_Symbol,PERIOD_M1,1);
   double h2=iHigh(_Symbol,PERIOD_M1,2);
   double c=iClose(_Symbol,PERIOD_M1,1);
   return (h1>h2 && c<h2);
}

//+------------------------------------------------------------------+
bool MomentumBuy()
{
   double rsi[];
   if(CopyBuffer(rsiHandle,0,0,1,rsi)<=0) return false;
   return rsi[0]>55;
}

bool MomentumSell()
{
   double rsi[];
   if(CopyBuffer(rsiHandle,0,0,1,rsi)<=0) return false;
   return rsi[0]<45;
}

//+------------------------------------------------------------------+
bool VolumeSpike()
{
   double v1=(double)iVolume(_Symbol,PERIOD_M1,1);
   double avg=0;

   for(int i=2;i<10;i++)
      avg+=(double)iVolume(_Symbol,PERIOD_M1,i);

   avg/=8.0;

   return v1>avg*1.5;
}

//+------------------------------------------------------------------+
double GetATRPoints()
{
   double atr[];
   if(CopyBuffer(atrHandle,0,0,1,atr)<=0) return 0;
   return atr[0]/_Point;
}

//+------------------------------------------------------------------+
int SignalScore(bool buy)
{
   int s=0;

   if(buy)
   {
      if(SweepLow()) s+=20;
      if(BreakStructureUp()) s+=25;
      if(MomentumBuy()) s+=15;
      if(VolumeSpike()) s+=10;
   }
   else
   {
      if(SweepHigh()) s+=20;
      if(BreakStructureDown()) s+=25;
      if(MomentumSell()) s+=15;
      if(VolumeSpike()) s+=10;
   }

   if(GetATRPoints()>0) s+=20;

   return s;
}

//+------------------------------------------------------------------+
void CheckTrade()
{
   if(!RiskOK()) return;
   if(!SpreadOK()) return;
   if(PositionsTotal()>=MaxTrades) return;

   double atrPoints = GetATRPoints();
   if(atrPoints<=0) return;

   int buyScore = SignalScore(true);
   int sellScore= SignalScore(false);

   double slPoints = atrPoints*1.2;
   double RR = (buyScore>sellScore)?RR_Max:RR_Min;
   double tpPoints = slPoints*RR;

   double lot = LotSize(slPoints);

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(buyScore>=ScoreThreshold)
   {
      double sl=bid-slPoints*_Point;
      double tp=bid+tpPoints*_Point;

      if(OpenTrade(true,lot,sl,tp))
         lossStreak=0;
      else
         lossStreak++;
   }

   if(sellScore>=ScoreThreshold)
   {
      double sl=ask+slPoints*_Point;
      double tp=ask-tpPoints*_Point;

      if(OpenTrade(false,lot,sl,tp))
         lossStreak=0;
      else
         lossStreak++;
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar=0;
   datetime currentBar=iTime(_Symbol,PERIOD_M1,0);

   if(currentBar==lastBar) return;
   lastBar=currentBar;

   CheckTrade();
}
//+------------------------------------------------------------------+
