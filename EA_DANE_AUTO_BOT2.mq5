//+------------------------------------------------------------------+
//| XAUUSD_M1_AGGRESSIVE_SCALPER.mq5                                 |
//| Platform: MetaTrader 5                                           |
//| Language: MQL5                                                   |
//| Target Symbol: XAUUSD                                            |
//| Timeframe: M1                                                    |
//| Purpose: Extremely aggressive high-frequency scalping EA         |
//+------------------------------------------------------------------+
#property strict

//================ USER INPUT PARAMETERS =================//

input string  TradeSymbol        = "XAUUSD";
input ENUM_TIMEFRAMES TradeTF    = PERIOD_M1;

input double  LotSize            = 0.01;
input int     StopLossPoints     = 150;
input int     TakeProfitPoints   = 120;
input int     TrailingStopPoints = 80;

input int     MaxSpread          = 300;
input int     MaxPositions       = 3;

input int     FastEMA            = 5;
input int     SlowEMA            = 20;
input int     RSI_Period         = 7;

input int     TradeCooldownSec   = 5;

//================ GLOBAL VARIABLES =================//

int fastEMAHandle;
int slowEMAHandle;
int rsiHandle;

double fastEMA[];
double slowEMA[];
double rsi[];

datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+

int OnInit()
{
   if(_Symbol != TradeSymbol)
   {
      Print("EA designed only for XAUUSD.");
      return(INIT_FAILED);
   }

   if(_Period != TradeTF)
   {
      Print("EA designed only for M1 timeframe.");
      return(INIT_FAILED);
   }

   fastEMAHandle = iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   slowEMAHandle = iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   rsiHandle     = iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);

   ArraySetAsSeries(fastEMA,true);
   ArraySetAsSeries(slowEMA,true);
   ArraySetAsSeries(rsi,true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main tick function                                               |
//+------------------------------------------------------------------+

void OnTick()
{
   if(!SpreadOK()) return;

   ManageTrailingStops();

   if(PositionsTotal() >= MaxPositions) return;

   if(TimeCurrent() - lastTradeTime < TradeCooldownSec) return;

   int signal = GetSignal();

   if(signal == 1)
   {
      OpenBuy();
      lastTradeTime = TimeCurrent();
   }

   if(signal == -1)
   {
      OpenSell();
      lastTradeTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+

bool SpreadOK()
{
   double spread = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(spread > MaxSpread)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Signal generation logic                                          |
//| Combines EMA momentum + RSI impulse                              |
//+------------------------------------------------------------------+

int GetSignal()
{
   CopyBuffer(fastEMAHandle,0,0,3,fastEMA);
   CopyBuffer(slowEMAHandle,0,0,3,slowEMA);
   CopyBuffer(rsiHandle,0,0,3,rsi);

   if(fastEMA[0] > slowEMA[0] && rsi[0] > 55)
      return 1;

   if(fastEMA[0] < slowEMA[0] && rsi[0] < 45)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Open Buy Position                                                |
//+------------------------------------------------------------------+

void OpenBuy()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double sl = price - StopLossPoints * _Point;
   double tp = price + TakeProfitPoints * _Point;

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action       = TRADE_ACTION_DEAL;
   request.type         = ORDER_TYPE_BUY;
   request.symbol       = _Symbol;
   request.volume       = LotSize;
   request.price        = price;
   request.sl           = sl;
   request.tp           = tp;
   request.deviation    = 10;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request,result))
      Print("BUY OrderSend failed: ",GetLastError());
}

//+------------------------------------------------------------------+
//| Open Sell Position                                               |
//+------------------------------------------------------------------+

void OpenSell()
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double sl = price + StopLossPoints * _Point;
   double tp = price - TakeProfitPoints * _Point;

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action       = TRADE_ACTION_DEAL;
   request.type         = ORDER_TYPE_SELL;
   request.symbol       = _Symbol;
   request.volume       = LotSize;
   request.price        = price;
   request.sl           = sl;
   request.tp           = tp;
   request.deviation    = 10;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request,result))
      Print("SELL OrderSend failed: ",GetLastError());
}

//+------------------------------------------------------------------+
//| Trailing Stop Management                                         |
//+------------------------------------------------------------------+

void ManageTrailingStops()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);

      int type = (int)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
      {
         double newSL = price - TrailingStopPoints * _Point;

         if(newSL > sl && newSL > open)
         {
            ModifyPosition(ticket,newSL,tp);
         }
      }

      if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

         double newSL = ask + TrailingStopPoints * _Point;

         if(newSL < sl || sl == 0)
         {
            ModifyPosition(ticket,newSL,tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify Position                                                  |
//+------------------------------------------------------------------+

void ModifyPosition(ulong ticket,double newSL,double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action  = TRADE_ACTION_SLTP;
   request.symbol  = _Symbol;
   request.position= ticket;
   request.sl      = newSL;
   request.tp      = tp;

   if(!OrderSend(request,result))
      Print("Modify failed: ",GetLastError());
}
