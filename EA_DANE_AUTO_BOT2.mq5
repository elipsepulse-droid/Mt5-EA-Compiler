//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT14 - Corrected Compilation Version               |
//| OrderSend return values fully validated                          |
//+------------------------------------------------------------------+
#property strict

//================ INPUT PARAMETERS =================//

input double LotSize = 0.01;
input bool UseDynamicLot = true;
input double RiskPercent = 0.5;

input int GridSize = 10;
input int GridSpacingPips = 500;

input int RSIPeriod = 14;
input double RSIBuyLevel = 40;
input double RSISellLevel = 60;

input int FastTrendMA = 100;
input int SlowTrendMA = 300;

input int ExitFastMA = 50;
input int ExitSlowMA = 200;

input int ADXPeriod = 14;
input double MinADX = 20;

input int ATRPeriod = 14;
input double ATRMultiplier = 2.0;

input int MaxSpreadPoints = 50;

input double FloatingDDLimit = 0.03;

input int MaxTotalPositions = 15;
input int MaxBuyPositions = 10;
input int MaxSellPositions = 10;

input int CooldownSeconds = 300;
input int MaxSlippage = 20;

input double MarginExposureLimit = 0.35;
input double ExposureHardCap = 0.002;

input int RetryAttempts = 3;

input double EmergencySL_ATR = 6.0;
input double TP_ATR = 1.5;
input int MaxTradeSeconds = 900;
input double SpreadSpikeMultiplier = 2.5;
input double EquityProtection = 0.92;

//================ GLOBAL VARIABLES =================//

int rsiHandle;
int fastMAHandle;
int slowMAHandle;
int exitFastHandle;
int exitSlowHandle;
int atrHandle;
int adxHandle;
int fastMA_HTF;

double pip;

double lastBuyPrice=0;
double lastSellPrice=0;

bool buyGridActive=false;
bool sellGridActive=false;

datetime lastTradeTime=0;

double peakEquity=0;
double avgSpread=0;

MqlTick tick;
MqlTradeRequest request;
MqlTradeResult result;

//+------------------------------------------------------------------+

int OnInit()
{
   pip=_Point;
   if(_Digits==3 || _Digits==5) pip=_Point*10;

   rsiHandle=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   fastMAHandle=iMA(_Symbol,_Period,FastTrendMA,0,MODE_EMA,PRICE_CLOSE);
   slowMAHandle=iMA(_Symbol,_Period,SlowTrendMA,0,MODE_EMA,PRICE_CLOSE);

   exitFastHandle=iMA(_Symbol,_Period,ExitFastMA,0,MODE_EMA,PRICE_CLOSE);
   exitSlowHandle=iMA(_Symbol,_Period,ExitSlowMA,0,MODE_EMA,PRICE_CLOSE);

   atrHandle=iATR(_Symbol,_Period,ATRPeriod);
   adxHandle=iADX(_Symbol,_Period,ADXPeriod);

   fastMA_HTF=iMA(_Symbol,PERIOD_M15,FastTrendMA,0,MODE_EMA,PRICE_CLOSE);

   peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+

bool SpreadOK()
{
   double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   avgSpread=(avgSpread*0.9)+(spread*0.1);

   if(spread>MaxSpreadPoints) return false;
   if(spread>avgSpread*SpreadSpikeMultiplier) return false;

   return true;
}

//+------------------------------------------------------------------+

bool FloatingDrawdownSafe()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);

   double dd=(balance-equity)/balance;

   if(dd>=FloatingDDLimit)
      return false;

   return true;
}

//+------------------------------------------------------------------+

int CountPositions(int type)
{
   int total=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_TYPE)==type)
            total++;
      }
   }

   return total;
}

//+------------------------------------------------------------------+

double NormalizeLot(double lot)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   lot=MathMax(minLot,lot);
   lot=MathMin(maxLot,lot);

   lot=MathFloor(lot/step)*step;

   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+

double GetLotSize(int depth,double atr)
{
   double lot=LotSize;

   if(UseDynamicLot)
   {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney=balance*(RiskPercent/100.0);

      double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double safeATR=MathMax(atr,_Point*50);

      lot=riskMoney/(safeATR*tickValue*10);

      if(lot<LotSize) lot=LotSize;
   }

   lot = lot/(1+(depth*0.45));

   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+

bool ExecuteTrade(int type,double lot,double sl,double tp)
{
   for(int i=0;i<RetryAttempts;i++)
   {
      ZeroMemory(request);
      ZeroMemory(result);

      request.action=TRADE_ACTION_DEAL;
      request.symbol=_Symbol;
      request.volume=lot;
      request.deviation=MaxSlippage;

      if(type==ORDER_TYPE_BUY)
      {
         request.type=ORDER_TYPE_BUY;
         request.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      }
      else
      {
         request.type=ORDER_TYPE_SELL;
         request.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      }

      request.sl=sl;
      request.tp=tp;

      bool sent = OrderSend(request,result);

      if(sent && result.retcode==TRADE_RETCODE_DONE)
         return true;

      Print("Trade attempt failed. Retcode: ",result.retcode);
   }

   return false;
}

//+------------------------------------------------------------------+

void CloseAll()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            ZeroMemory(request);
            ZeroMemory(result);

            request.action=TRADE_ACTION_DEAL;
            request.position=ticket;
            request.symbol=_Symbol;
            request.volume=PositionGetDouble(POSITION_VOLUME);
            request.deviation=MaxSlippage;

            if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
            {
               request.type=ORDER_TYPE_SELL;
               request.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
            }
            else
            {
               request.type=ORDER_TYPE_BUY;
               request.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
            }

            bool sent = OrderSend(request,result);

            if(!sent || result.retcode!=TRADE_RETCODE_DONE)
               Print("Close failed. Retcode:",result.retcode);
         }
      }
   }

   buyGridActive=false;
   sellGridActive=false;
}

//+------------------------------------------------------------------+

void OnTick()
{
   if(!SymbolInfoTick(_Symbol,tick)) return;

   if(!SpreadOK()) return;

   if(!FloatingDrawdownSafe())
   {
      CloseAll();
      return;
   }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity<peakEquity*EquityProtection)
      return;

   if(equity>peakEquity)
      peakEquity=equity;

   if(TimeCurrent()-lastTradeTime < CooldownSeconds) return;

   int totalPositions=PositionsTotal();
   if(totalPositions>=MaxTotalPositions) return;

   double rsi[2];
   double atr[1];

   if(CopyBuffer(rsiHandle,0,0,2,rsi)<=0) return;
   if(CopyBuffer(atrHandle,0,0,1,atr)<=0) return;

   double atrValue=atr[0];

   if(rsi[1]<RSIBuyLevel && rsi[0]>RSIBuyLevel && !sellGridActive)
   {
      int depth=CountPositions(POSITION_TYPE_BUY);

      if(depth<MaxBuyPositions)
      {
         double lot=GetLotSize(depth,atrValue);

         double sl=tick.ask-(atrValue*EmergencySL_ATR);
         double tp=tick.ask+(atrValue*TP_ATR);

         if(ExecuteTrade(ORDER_TYPE_BUY,lot,sl,tp))
         {
            lastBuyPrice=tick.ask;
            buyGridActive=true;
            lastTradeTime=TimeCurrent();
         }
      }
   }

   if(rsi[1]>RSISellLevel && rsi[0]<RSISellLevel && !buyGridActive)
   {
      int depth=CountPositions(POSITION_TYPE_SELL);

      if(depth<MaxSellPositions)
      {
         double lot=GetLotSize(depth,atrValue);

         double sl=tick.bid+(atrValue*EmergencySL_ATR);
         double tp=tick.bid-(atrValue*TP_ATR);

         if(ExecuteTrade(ORDER_TYPE_SELL,lot,sl,tp))
         {
            lastSellPrice=tick.bid;
            sellGridActive=true;
            lastTradeTime=TimeCurrent();
         }
      }
   }
}
