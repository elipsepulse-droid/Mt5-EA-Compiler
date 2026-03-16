//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT14 - MT5 Compatible Version                      |
//+------------------------------------------------------------------+
#property strict

//---- Inputs
input double LotSize = 0.01;
input int RSIPeriod = 14;
input double RSIBuyLevel = 40;
input double RSISellLevel = 60;

input int FastTrendMA = 100;
input int SlowTrendMA = 300;

input int ATRPeriod = 14;
input double TP_ATR = 1.5;
input double SL_ATR = 6.0;

input int MaxSpreadPoints = 50;
input int CooldownSeconds = 300;
input int MaxPositions = 10;
input int MaxSlippage = 20;

//---- Indicators
int rsiHandle;
int fastMAHandle;
int slowMAHandle;
int atrHandle;

//---- Variables
datetime lastTradeTime=0;
MqlTick tick;

//+------------------------------------------------------------------+

int OnInit()
{
   rsiHandle=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   fastMAHandle=iMA(_Symbol,_Period,FastTrendMA,0,MODE_EMA,PRICE_CLOSE);
   slowMAHandle=iMA(_Symbol,_Period,SlowTrendMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle=iATR(_Symbol,_Period,ATRPeriod);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+

bool GetIndicators(double &rsiPrev,double &rsiCur,double &fastMA,double &slowMA,double &atr)
{
   double buf[3];

   if(CopyBuffer(rsiHandle,0,1,2,buf)<=0) return false;
   rsiCur=buf[0];
   rsiPrev=buf[1];

   if(CopyBuffer(fastMAHandle,0,0,1,buf)<=0) return false;
   fastMA=buf[0];

   if(CopyBuffer(slowMAHandle,0,0,1,buf)<=0) return false;
   slowMA=buf[0];

   if(CopyBuffer(atrHandle,0,0,1,buf)<=0) return false;
   atr=buf[0];

   return true;
}

//+------------------------------------------------------------------+

int CountPositions()
{
   int total=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
            total++;
      }
   }

   return total;
}

//+------------------------------------------------------------------+

bool ExecuteBuy(double lot,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.symbol=_Symbol;
   req.type=ORDER_TYPE_BUY;
   req.volume=lot;
   req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   req.sl=sl;
   req.tp=tp;
   req.deviation=MaxSlippage;
   req.type_filling=ORDER_FILLING_IOC;

   if(!OrderSend(req,res))
      return false;

   if(res.retcode!=TRADE_RETCODE_DONE)
      return false;

   return true;
}

//+------------------------------------------------------------------+

bool ExecuteSell(double lot,double sl,double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.symbol=_Symbol;
   req.type=ORDER_TYPE_SELL;
   req.volume=lot;
   req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.sl=sl;
   req.tp=tp;
   req.deviation=MaxSlippage;
   req.type_filling=ORDER_FILLING_IOC;

   if(!OrderSend(req,res))
      return false;

   if(res.retcode!=TRADE_RETCODE_DONE)
      return false;

   return true;
}

//+------------------------------------------------------------------+

bool SpreadOK()
{
   double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-
                  SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   if(spread>MaxSpreadPoints)
      return false;

   return true;
}

//+------------------------------------------------------------------+

void OnTick()
{
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   if(!SpreadOK())
      return;

   if(TimeCurrent()-lastTradeTime<CooldownSeconds)
      return;

   if(CountPositions()>=MaxPositions)
      return;

   double rsiPrev,rsiCur,fastMA,slowMA,atr;

   if(!GetIndicators(rsiPrev,rsiCur,fastMA,slowMA,atr))
      return;

   bool uptrend=fastMA>slowMA;
   bool downtrend=fastMA<slowMA;

   // BUY condition
   if(rsiPrev<RSIBuyLevel && rsiCur>RSIBuyLevel && uptrend)
   {
      double sl=tick.ask-(atr*SL_ATR);
      double tp=tick.ask+(atr*TP_ATR);

      if(ExecuteBuy(LotSize,sl,tp))
         lastTradeTime=TimeCurrent();
   }

   // SELL condition
   if(rsiPrev>RSISellLevel && rsiCur<RSISellLevel && downtrend)
   {
      double sl=tick.bid+(atr*SL_ATR);
      double tp=tick.bid-(atr*TP_ATR);

      if(ExecuteSell(LotSize,sl,tp))
         lastTradeTime=TimeCurrent();
   }
}
