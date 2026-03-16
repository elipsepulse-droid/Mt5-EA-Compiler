//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT2_NO_LIBRARY                                    |
//+------------------------------------------------------------------+
#property strict

//================ INPUT PARAMETERS =================//

input double LotSize=0.01;
input int RSIPeriod=14;
input int FastEMA=9;
input int SlowEMA=21;
input int ATRPeriod=14;

input double SL_ATR=1.5;
input double TP_ATR=1.0;

input double MaxSpread=300;
input int MaxTrades=5;

//================ INDICATORS =================//

int rsiHandle;
int fastHandle;
int slowHandle;
int atrHandle;

double rsi[];
double fast[];
double slow[];
double atr[];

//+------------------------------------------------------------------+

int OnInit()
{
   rsiHandle=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   fastHandle=iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   slowHandle=iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle=iATR(_Symbol,_Period,ATRPeriod);

   ArraySetAsSeries(rsi,true);
   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);
   ArraySetAsSeries(atr,true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+

void OnTick()
{
   if(!SpreadOK()) return;
   if(PositionsTotal()>=MaxTrades) return;

   int signal=Signal();

   if(signal==1) OpenBuy();
   if(signal==-1) OpenSell();
}

//+------------------------------------------------------------------+

bool SpreadOK()
{
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(spread>MaxSpread)
      return false;

   return true;
}

//+------------------------------------------------------------------+

int Signal()
{
   CopyBuffer(rsiHandle,0,0,2,rsi);
   CopyBuffer(fastHandle,0,0,2,fast);
   CopyBuffer(slowHandle,0,0,2,slow);

   if(rsi[0]>55 && fast[0]>slow[0])
      return 1;

   if(rsi[0]<45 && fast[0]<slow[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+

void OpenBuy()
{
   CopyBuffer(atrHandle,0,0,1,atr);

   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double sl=price-atr[0]*SL_ATR;
   double tp=price+atr[0]*TP_ATR;

   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.type=ORDER_TYPE_BUY;
   req.symbol=_Symbol;
   req.volume=LotSize;
   req.price=price;
   req.sl=sl;
   req.tp=tp;
   req.deviation=10;
   req.type_filling=ORDER_FILLING_IOC;

   OrderSend(req,res);
}

//+------------------------------------------------------------------+

void OpenSell()
{
   CopyBuffer(atrHandle,0,0,1,atr);

   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double sl=price+atr[0]*SL_ATR;
   double tp=price-atr[0]*TP_ATR;

   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   req.action=TRADE_ACTION_DEAL;
   req.type=ORDER_TYPE_SELL;
   req.symbol=_Symbol;
   req.volume=LotSize;
   req.price=price;
   req.sl=sl;
   req.tp=tp;
   req.deviation=10;
   req.type_filling=ORDER_FILLING_IOC;

   OrderSend(req,res);
}
