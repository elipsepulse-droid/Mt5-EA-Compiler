//+------------------------------------------------------------------+
//| XAUUSD AGGRESSIVE SCALPER PRO v4 (HIGH FREQUENCY)               |
//| Designed for M1–M5, Exness-compatible, no Trade.mqh             |
//+------------------------------------------------------------------+
#property strict
#property version "4.0"

//================ INPUTS =================//

input double RiskPercent = 0.5;
input int ATR_Period = 14;
input int RSI_Period = 7;

input int MaxTrades = 10;
input int SpreadLimit = 60;

input int ScoreThreshold = 50;     // main entries
input int AggressiveScore = 40;    // fallback entries

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
   return rsi[0] > 52;
}

bool MomentumSell()
{
   double rsi[];
   if(CopyBuffer(rsiHandle,0,0,1,rsi)<=0) return false;
   return rsi[0] < 48;
}

//+------------------------------------------------------------------+
bool FastTrendBuy()
{
   double maFast = iMA(_Symbol, PERIOD_M1, 5, 0, MODE_EMA, PRICE_CLOSE, 0);
   double maSlow = iMA(_Symbol, PERIOD_M1, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
   return maFast > maSlow;
}

bool FastTrendSell()
{
   double maFast = iMA(_Symbol, PERIOD_M1, 5, 0, MODE_EMA, PRICE_CLOSE, 0);
   double maSlow = iMA(_Symbol, PERIOD_M1, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
   return maFast < maSlow;
}

//+------------------------------------------------------------------+
bool BreakUp()
{
   return iHigh(_Symbol, PERIOD_M1, 0) > iHigh(_Symbol, PERIOD_M1, 1);
}

bool BreakDown()
{
   return iLow(_Symbol, PERIOD_M1, 0) < iLow(_Symbol, PERIOD_M1, 1);
}

//+------------------------------------------------------------------+
int SignalScore(bool buy)
{
   int s=0;

   if(buy)
   {
      if(FastTrendBuy()) s+=20;
      if(BreakUp()) s+=20;
      if(MomentumBuy()) s+=15;
   }
   else
   {
      if(FastTrendSell()) s+=20;
      if(BreakDown()) s+=20;
      if(MomentumSell()) s+=15;
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

   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = NormalizeDouble(lot,2);

   return lot;
}

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
   req.deviation= 20;
   req.magic    = 777;

   if(!OrderSend(req,res))
      return false;

   return (res.retcode == TRADE_RETCODE_DONE);
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
   if(CountPositions() >= MaxTrades) return;

   double atr = GetATRPoints();
   if(atr <= 0) return;

   int buyScore  = SignalScore(true);
   int sellScore = SignalScore(false);

   double slPoints = atr * 1.0;
   double tpPoints = slPoints * 1.2;

   double lot = LotSize(slPoints);

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   //================ MAIN ENTRIES =================//

   if(buyScore >= ScoreThreshold)
   {
      double sl = bid - slPoints*_Point;
      double tp = bid + tpPoints*_Point;
      OpenTrade(true,lot,sl,tp);
   }

   if(sellScore >= ScoreThreshold)
   {
      double sl = ask + slPoints*_Point;
      double tp = ask - tpPoints*_Point;
      OpenTrade(false,lot,sl,tp);
   }

   //================ AGGRESSIVE ENTRIES =================//

   if(buyScore >= AggressiveScore && MomentumBuy())
   {
      double sl = bid - slPoints*_Point;
      double tp = bid + (slPoints*1.0)*_Point;
      OpenTrade(true,lot,sl,tp);
   }

   if(sellScore >= AggressiveScore && MomentumSell())
   {
      double sl = ask + slPoints*_Point;
      double tp = ask - (slPoints*1.0)*_Point;
      OpenTrade(false,lot,sl,tp);
   }

   //================ FORCED SCALPING =================//

   static int force=0;
   force++;

   if(force >= 8) // ensures frequent trades
   {
      double sl = bid - slPoints*_Point;
      double tp = bid + (slPoints*0.8)*_Point;
      OpenTrade(true,lot,sl,tp);
      force=0;
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar=0;
   datetime current=iTime(_Symbol,PERIOD_M1,0);

   if(current == lastBar) return;
   lastBar = current;

   CheckTrade();
}
//+------------------------------------------------------------------+
