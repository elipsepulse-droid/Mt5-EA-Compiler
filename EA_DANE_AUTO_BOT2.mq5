//+------------------------------------------------------------------+
//| EA_DANE_AUTO_BOT14 - Full Architecture Version (Library-Free)    |
//| Compatible with MT5 / GitHub / Winlator                          |
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
double gridSpacing;
double smoothedATR=0;
double atrLongAvg=0;

double lastBuyPrice=0;
double lastSellPrice=0;

bool buyGridActive=false;
bool sellGridActive=false;

datetime lastTradeTime=0;
double peakEquity=0;
double avgSpread=0;

double prevTick=0;

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

bool UpdateIndicators(double &rsiPrev,double &rsiCur,
                      double &fastMA,double &slowMA,
                      double &adx,double &atr,double &fastHTF)
{
   double buf[3];

   if(CopyBuffer(rsiHandle,0,1,2,buf)<=0) return false;
   rsiCur=buf[0];
   rsiPrev=buf[1];

   if(CopyBuffer(fastMAHandle,0,0,1,buf)<=0) return false;
   fastMA=buf[0];

   if(CopyBuffer(slowMAHandle,0,0,1,buf)<=0) return false;
   slowMA=buf[0];

   if(CopyBuffer(adxHandle,0,0,1,buf)<=0) return false;
   adx=buf[0];

   if(CopyBuffer(atrHandle,0,0,1,buf)<=0) return false;
   atr=buf[0];

   if(CopyBuffer(fastMA_HTF,0,0,1,buf)<=0) return false;
   fastHTF=buf[0];

   return true;
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

   double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   if(spread > avgSpread*1.5) lot*=0.6;
   if(spread > avgSpread*2) lot*=0.4;

   return NormalizeLot(lot);
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

double TotalExposure()
{
   double exposure=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         exposure+=PositionGetDouble(POSITION_VOLUME);
      }
   }

   return exposure;
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

            OrderSend(request,result);
         }
      }
   }

   buyGridActive=false;
   sellGridActive=false;
}

//+------------------------------------------------------------------+

void BasketBreakEven()
{
   double totalProfit=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         totalProfit+=PositionGetDouble(POSITION_PROFIT);
      }
   }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);

   if(totalProfit > balance*0.002)
      CloseAll();
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

bool SpreadOK()
{
   double spread=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-
                  SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   avgSpread=(avgSpread*0.9)+(spread*0.1);

   if(spread>MaxSpreadPoints) return false;
   if(spread>avgSpread*SpreadSpikeMultiplier) return false;

   return true;
}

//+------------------------------------------------------------------+

bool MarginSafe()
{
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(margin/equity>MarginExposureLimit)
      return false;

   return true;
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

      if(OrderSend(request,result))
         if(result.retcode==TRADE_RETCODE_DONE)
            return true;
   }

   return false;
}

//+------------------------------------------------------------------+

void ManagePositions()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

         datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);

         if(TimeCurrent()-openTime > MaxTradeSeconds &&
            PositionGetDouble(POSITION_PROFIT)<0)
         {
            CloseAll();
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+

void OnTick()
{
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double rsiPrev,rsiCur,fastMA,slowMA,adx,atr,fastHTF;

   if(!UpdateIndicators(rsiPrev,rsiCur,fastMA,slowMA,adx,atr,fastHTF))
      return;

   if(!SpreadOK()) return;
   if(!MarginSafe()) return;

   if(!FloatingDrawdownSafe())
   {
      CloseAll();
      return;
   }

   BasketBreakEven();

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity<peakEquity*EquityProtection)
      return;

   if(equity>peakEquity)
      peakEquity=equity;

   bool uptrend = fastMA>slowMA && tick.bid>fastHTF && adx>25;
   bool downtrend = fastMA<slowMA && tick.bid<fastHTF && adx>25;

   if(TimeCurrent()-lastTradeTime < CooldownSeconds) return;

   int totalPositions=PositionsTotal();
   if(totalPositions>=MaxTotalPositions) return;

   double exposure=TotalExposure();
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);

   if(exposure > balance*ExposureHardCap)
      return;

   double dynamicTP = TP_ATR;
   double dynamicSL = EmergencySL_ATR;

   if(rsiPrev<RSIBuyLevel && rsiCur>RSIBuyLevel && uptrend && !sellGridActive)
   {
      int depth=CountPositions(POSITION_TYPE_BUY);

      if(depth<MaxBuyPositions)
      {
         double lot=GetLotSize(depth,atr);

         double sl=tick.ask-(atr*dynamicSL);
         double tp=tick.ask+(atr*dynamicTP);

         if(ExecuteTrade(ORDER_TYPE_BUY,lot,sl,tp))
         {
            lastBuyPrice=tick.ask;
            buyGridActive=true;
            lastTradeTime=TimeCurrent();
         }
      }
   }

   if(rsiPrev>RSISellLevel && rsiCur<RSISellLevel && downtrend && !buyGridActive)
   {
      int depth=CountPositions(POSITION_TYPE_SELL);

      if(depth<MaxSellPositions)
      {
         double lot=GetLotSize(depth,atr);

         double sl=tick.bid+(atr*dynamicSL);
         double tp=tick.bid-(atr*dynamicTP);

         if(ExecuteTrade(ORDER_TYPE_SELL,lot,sl,tp))
         {
            lastSellPrice=tick.bid;
            sellGridActive=true;
            lastTradeTime=TimeCurrent();
         }
      }
   }

   ManagePositions();
}
