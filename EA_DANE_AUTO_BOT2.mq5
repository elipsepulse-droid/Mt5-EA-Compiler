//+------------------------------------------------------------------+
//| XAUUSD PRO SCALPER EA v3 - NO INCLUDE (CI SAFE)                  |
//+------------------------------------------------------------------+
#property strict
#property version "3.0"

//================ INPUTS =================//

input double RiskPercent = 0.5;
input int ATR_Period = 14;
input int RSI_Period = 7;
input int MaxTrades = 3;
input int SpreadLimit = 30;
input int ScoreThreshold = 70;

//================ GLOBAL =================//

int atrHandle, rsiHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_M1, ATR_Period);
   rsiHandle = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
double GetATRPoints()
{
   double atr[];
   if(CopyBuffer(atrHandle,0,0,1,atr)<=0) return 0;
   return atr[0]/_Point;
}

//+------------------------------------------------------------------+
bool SpreadOK()
{
   double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-
                  SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   return spread<=SpreadLimit;
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
bool SweepLow()
{
   double low1=iLow(_Symbol,PERIOD_M1,1);
   double low2=iLow(_Symbol,PERIOD_M1,2);
   double close=iClose(_Symbol,PERIOD_M1,1);
   return (low1<low2 && close>low2);
}

bool SweepHigh()
{
   double high1=iHigh(_Symbol,PERIOD_M1,1);
   double high2=iHigh(_Symbol,PERIOD_M1,2);
   double close=iClose(_Symbol,PERIOD_M1,1);
   return (high1>high2 && close<high2);
}

//+------------------------------------------------------------------+
bool BreakUp()
{
   return iHigh(_Symbol,PERIOD_M5,0) > iHigh(_Symbol,PERIOD_M5,1);
}

bool BreakDown()
{
   return iLow(_Symbol,PERIOD_M5,0) < iLow(_Symbol,PERIOD_M5,1);
}

//+------------------------------------------------------------------+
int SignalScore(bool buy)
{
   int s=0;

   if(buy)
   {
      if(SweepLow()) s+=25;
      if(BreakUp()) s+=25;
      if(MomentumBuy()) s+=20;
   }
   else
   {
      if(SweepHigh()) s+=25;
      if(BreakDown()) s+=25;
      if(MomentumSell()) s+=20;
   }

   if(GetATRPoints()>0) s+=20;

   return s;
}

//+------------------------------------------------------------------+
double LotSize(double slPoints)
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=balance*(RiskPercent/100.0);

   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);

   double valuePerPoint=tickValue/tickSize;

   double lot=risk/(slPoints*valuePerPoint);
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
// EXECUTION (NO CTRADE)
//+------------------------------------------------------------------+
bool OpenTrade(bool buy,double lot,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;

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
int CountPositions()
{
   int count=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
void CheckTrade()
{
   if(!SpreadOK()) return;
   if(CountPositions()>=MaxTrades) return;

   double atr=GetATRPoints();
   if(atr<=0) return;

   int buyScore=SignalScore(true);
   int sellScore=SignalScore(false);

   double slPoints=atr*1.2;
   double tpPoints=slPoints*1.6;

   double lot=LotSize(slPoints);

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(buyScore>=ScoreThreshold)
   {
      double sl=bid-slPoints*_Point;
      double tp=bid+tpPoints*_Point;
      OpenTrade(true,lot,sl,tp);
   }

   if(sellScore>=ScoreThreshold)
   {
      double sl=ask+slPoints*_Point;
      double tp=ask-tpPoints*_Point;
      OpenTrade(false,lot,sl,tp);
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar=0;
   datetime current=iTime(_Symbol,PERIOD_M1,0);

   if(current==lastBar) return;
   lastBar=current;

   CheckTrade();
}
//+------------------------------------------------------------------+
