//+------------------------------------------------------------------+
//| XAUUSD_M1_PRO_SCALPER_STRUCTURE                                  |
//| Modular EA Architecture                                          |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//================ INPUT PARAMETERS =================//

input double FixedLot              = 0.01;
input bool   UseDynamicLot         = true;
input double RiskPercent           = 1.0;

input int    RSIPeriod             = 14;
input int    FastEMA               = 9;
input int    SlowEMA               = 21;

input int    ATRPeriod             = 14;
input double SL_ATR_Multiplier     = 1.5;
input double TP_ATR_Multiplier     = 1.0;

input double MaxSpreadPoints       = 300;
input int    MaxOpenTrades         = 5;

input double BreakevenTrigger      = 200;
input double TrailingDistance      = 150;

input double MaxDrawdownPercent    = 20;

//================ GLOBAL VARIABLES =================//

int rsiHandle;
int emaFastHandle;
int emaSlowHandle;
int atrHandle;

double rsiBuffer[];
double emaFastBuffer[];
double emaSlowBuffer[];
double atrBuffer[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+

int OnInit()
{
   rsiHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
   emaFastHandle = iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   atrHandle = iATR(_Symbol,_Period,ATRPeriod);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Tick Engine                                                      |
//+------------------------------------------------------------------+

void OnTick()
{
   if(!MarketConditionFilter()) return;

   TradeManager();

   if(PositionTotalCheck()) return;

   int signal = SignalEngine();

   if(signal == 1)
      OpenBuy();

   if(signal == -1)
      OpenSell();
}

//+------------------------------------------------------------------+
//| Market Filters                                                   |
//+------------------------------------------------------------------+

bool MarketConditionFilter()
{
   if(SpreadCheck()==false) return false;
   if(VolatilityCheck()==false) return false;
   if(DrawdownProtection()==false) return false;

   return true;
}

bool SpreadCheck()
{
   double spread = SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   if(spread > MaxSpreadPoints)
      return false;

   return true;
}

bool VolatilityCheck()
{
   CopyBuffer(atrHandle,0,0,2,atrBuffer);

   if(atrBuffer[0] <= 0)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Signal Engine                                                    |
//+------------------------------------------------------------------+

int SignalEngine()
{
   CopyBuffer(rsiHandle,0,0,2,rsiBuffer);
   CopyBuffer(emaFastHandle,0,0,2,emaFastBuffer);
   CopyBuffer(emaSlowHandle,0,0,2,emaSlowBuffer);

   if(rsiBuffer[0] > 55 && emaFastBuffer[0] > emaSlowBuffer[0])
      return 1;

   if(rsiBuffer[0] < 45 && emaFastBuffer[0] < emaSlowBuffer[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Position Control                                                 |
//+------------------------------------------------------------------+

bool PositionTotalCheck()
{
   if(PositionsTotal() >= MaxOpenTrades)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Risk Management                                                  |
//+------------------------------------------------------------------+

double CalculateLot(double stoploss_points)
{
   if(!UseDynamicLot)
      return FixedLot;

   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;

   double tickvalue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   double lot = risk / (stoploss_points * tickvalue);

   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
//| Order Execution                                                  |
//+------------------------------------------------------------------+

void OpenBuy()
{
   CopyBuffer(atrHandle,0,0,2,atrBuffer);

   double atr = atrBuffer[0];

   double sl = SymbolInfoDouble(_Symbol,SYMBOL_BID) - atr * SL_ATR_Multiplier;
   double tp = SymbolInfoDouble(_Symbol,SYMBOL_BID) + atr * TP_ATR_Multiplier;

   double sl_points = (SymbolInfoDouble(_Symbol,SYMBOL_BID)-sl)/_Point;

   double lot = CalculateLot(sl_points);

   trade.Buy(lot,_Symbol,0,sl,tp);
}

void OpenSell()
{
   CopyBuffer(atrHandle,0,0,2,atrBuffer);

   double atr = atrBuffer[0];

   double sl = SymbolInfoDouble(_Symbol,SYMBOL_ASK) + atr * SL_ATR_Multiplier;
   double tp = SymbolInfoDouble(_Symbol,SYMBOL_ASK) - atr * TP_ATR_Multiplier;

   double sl_points = (sl-SymbolInfoDouble(_Symbol,SYMBOL_ASK))/_Point;

   double lot = CalculateLot(sl_points);

   trade.Sell(lot,_Symbol,0,sl,tp);
}

//+------------------------------------------------------------------+
//| Trade Manager                                                    |
//+------------------------------------------------------------------+

void TradeManager()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         ManageBreakeven(ticket);
         ManageTrailing(ticket);
      }
   }
}

void ManageBreakeven(ulong ticket)
{
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double profit = PositionGetDouble(POSITION_PROFIT);

   if(profit > BreakevenTrigger)
   {
      trade.PositionModify(ticket,open,PositionGetDouble(POSITION_TP));
   }
}

void ManageTrailing(ulong ticket)
{
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double newSL = price - TrailingDistance * _Point;

   trade.PositionModify(ticket,newSL,PositionGetDouble(POSITION_TP));
}

//+------------------------------------------------------------------+
//| Equity Protection                                                |
//+------------------------------------------------------------------+

bool DrawdownProtection()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   double dd = (balance-equity)/balance*100;

   if(dd > MaxDrawdownPercent)
      return false;

   return true;
}
