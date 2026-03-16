//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT2_FINAL                                          |
//+------------------------------------------------------------------+
#property strict

//================ INPUT PARAMETERS =================//

input double LotSize = 0.01;
input int RSIPeriod = 14;
input int FastEMA = 9;
input int SlowEMA = 21;
input int ATRPeriod = 14;

input double SL_ATR = 1.5;
input double TP_ATR = 1.0;

input double MaxSpread = 300;
input int MaxTrades = 5;

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
   rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   fastHandle = iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   slowHandle = iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,ATRPeriod);

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
   if(PositionsTotal() >= MaxTrades) return;

   int signal = Signal();

   if(signal == 1) OpenBuy();
   if(signal == -1) OpenSell();
}

//+------------------------------------------------------------------+

bool SpreadOK()
{
   double spread = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(spread > MaxSpread)
      return false;

   return true;
}

//+------------------------------------------------------------------+

int Signal()
{
   CopyBuffer(rsiHandle,0,0,2,rsi);
   CopyBuffer(fastHandle,0,0,2,fast);
   CopyBuffer(slowHandle,0,0,2,slow);

   if(rsi[0] > 55 && fast[0] > slow[0])
      return 1;

   if(rsi[0] < 45 && fast[0] < slow[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+

void OpenBuy()
{
   CopyBuffer(atrHandle,0,0,1,atr);

   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl = price - atr[0] * SL_ATR;
   double tp = price + atr[0] * TP_ATR;

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_BUY;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request,result))
   {
      Print("BUY OrderSend failed: ",GetLastError());
   }
   else
   {
      if(result.retcode != TRADE_RETCODE_DONE)
         Print("BUY trade rejected: ",result.retcode);
   }
}

//+------------------------------------------------------------------+

void OpenSell()
{
   CopyBuffer(atrHandle,0,0,1,atr);

   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = price + atr[0] * SL_ATR;
   double tp = price - atr[0] * TP_ATR;

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.type = ORDER_TYPE_SELL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request,result))
   {
      Print("SELL OrderSend failed: ",GetLastError());
   }
   else
   {
      if(result.retcode != TRADE_RETCODE_DONE)
         Print("SELL trade rejected: ",result.retcode);
   }
}
