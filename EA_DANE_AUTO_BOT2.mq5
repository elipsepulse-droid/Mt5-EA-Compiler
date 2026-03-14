//+------------------------------------------------------------------+
//| Improved Grid RSI EMA EA (MT5)                                  |
//| Warning-free version                                            |
//+------------------------------------------------------------------+
#property strict

input double LotSize=0.01;
input int GridSize=10;
input int GridSpacingPips=500;

input double TP_Multiplier=2.0;
input double SL_Multiplier=1.0;
input double MaxProfitMoney=2.0;

input int RSI_Period=14;
input double RSI_BuyLevel=40;
input double RSI_SellLevel=60;

input int EMA_Trend_Fast=100;
input int EMA_Trend_Slow=300;

input int EMA_Exit_Fast=50;
input int EMA_Exit_Slow=200;

double GridBuy[100];
double GridSell[100];

bool GridActive=false;
bool GridBuyDirection=false;

double StartPrice=0;

int rsiHandle;
int emaTrendFast;
int emaTrendSlow;
int emaExitFast;
int emaExitSlow;

//+------------------------------------------------------------------+
double Pip()
{
   if(_Digits==3 || _Digits==5)
      return _Point*10.0;
   return _Point;
}
//+------------------------------------------------------------------+
int OnInit()
{
   rsiHandle=iRSI(_Symbol,_Period,RSI_Period,PRICE_CLOSE);

   emaTrendFast=iMA(_Symbol,_Period,EMA_Trend_Fast,0,MODE_EMA,PRICE_CLOSE);
   emaTrendSlow=iMA(_Symbol,_Period,EMA_Trend_Slow,0,MODE_EMA,PRICE_CLOSE);

   emaExitFast=iMA(_Symbol,_Period,EMA_Exit_Fast,0,MODE_EMA,PRICE_CLOSE);
   emaExitSlow=iMA(_Symbol,_Period,EMA_Exit_Slow,0,MODE_EMA,PRICE_CLOSE);

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void BuildGrid()
{
   double spacing=GridSpacingPips*Pip();

   for(int i=0;i<GridSize;i++)
   {
      GridBuy[i]=StartPrice-(spacing*(i+1));
      GridSell[i]=StartPrice+(spacing*(i+1));
   }
}
//+------------------------------------------------------------------+
bool LevelUsed(double price)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            double open=PositionGetDouble(POSITION_PRICE_OPEN);

            if(MathAbs(open-price)<Pip()*5)
               return true;
         }
      }
   }

   return false;
}
//+------------------------------------------------------------------+
void OpenTrade(bool buy)
{
   MqlTradeRequest req;
   MqlTradeResult res;

   ZeroMemory(req);
   ZeroMemory(res);

   double price;
   double tp;
   double sl;

   double spacing=GridSpacingPips*Pip();

   if(buy)
   {
      price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      tp=price+(spacing*TP_Multiplier);
      sl=price-(spacing*SL_Multiplier);
      req.type=ORDER_TYPE_BUY;
   }
   else
   {
      price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      tp=price-(spacing*TP_Multiplier);
      sl=price+(spacing*SL_Multiplier);
      req.type=ORDER_TYPE_SELL;
   }

   req.action=TRADE_ACTION_DEAL;
   req.symbol=_Symbol;
   req.volume=LotSize;
   req.price=price;
   req.tp=tp;
   req.sl=sl;
   req.magic=55555;
   req.deviation=20;
   req.type_filling=ORDER_FILLING_IOC;

   bool sent=OrderSend(req,res);

   if(!sent || (res.retcode!=10009 && res.retcode!=10008))
      Print("OrderSend failed. Retcode: ",res.retcode);
}
//+------------------------------------------------------------------+
int CheckSignal()
{
   double rsi[2];
   CopyBuffer(rsiHandle,0,0,2,rsi);

   if(rsi[1]<RSI_BuyLevel && rsi[0]>RSI_BuyLevel)
      return 1;

   if(rsi[1]>RSI_SellLevel && rsi[0]<RSI_SellLevel)
      return -1;

   return 0;
}
//+------------------------------------------------------------------+
bool TrendBuy()
{
   double f[1],s[1];

   CopyBuffer(emaTrendFast,0,0,1,f);
   CopyBuffer(emaTrendSlow,0,0,1,s);

   return f[0]>s[0];
}
//+------------------------------------------------------------------+
bool TrendSell()
{
   double f[1],s[1];

   CopyBuffer(emaTrendFast,0,0,1,f);
   CopyBuffer(emaTrendSlow,0,0,1,s);

   return f[0]<s[0];
}
//+------------------------------------------------------------------+
bool ExitSignal()
{
   double f[2],s[2];

   CopyBuffer(emaExitFast,0,0,2,f);
   CopyBuffer(emaExitSlow,0,0,2,s);

   if(f[1]<s[1] && f[0]>s[0]) return true;
   if(f[1]>s[1] && f[0]<s[0]) return true;

   return false;
}
//+------------------------------------------------------------------+
void ManageGrid()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<GridSize;i++)
   {
      if(GridBuyDirection)
      {
         if(bid<=GridBuy[i] && !LevelUsed(GridBuy[i]))
            OpenTrade(true);
      }
      else
      {
         if(ask>=GridSell[i] && !LevelUsed(GridSell[i]))
            OpenTrade(false);
      }
   }
}
//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         {
            MqlTradeRequest req;
            MqlTradeResult res;

            ZeroMemory(req);
            ZeroMemory(res);

            req.action=TRADE_ACTION_DEAL;
            req.position=ticket;
            req.symbol=_Symbol;
            req.volume=PositionGetDouble(POSITION_VOLUME);
            req.deviation=20;

            if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
            {
               req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
               req.type=ORDER_TYPE_SELL;
            }
            else
            {
               req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
               req.type=ORDER_TYPE_BUY;
            }

            bool sent=OrderSend(req,res);

            if(!sent || (res.retcode!=10009 && res.retcode!=10008))
               Print("Close failed. Retcode: ",res.retcode);
         }
      }
   }

   GridActive=false;
}
//+------------------------------------------------------------------+
double GridProfit()
{
   double profit=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);

      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
            profit+=PositionGetDouble(POSITION_PROFIT);
      }
   }

   return profit;
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(!GridActive)
   {
      int signal=CheckSignal();

      if(signal==1 && TrendBuy())
      {
         GridBuyDirection=true;
         StartPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         BuildGrid();
         GridActive=true;
      }

      if(signal==-1 && TrendSell())
      {
         GridBuyDirection=false;
         StartPrice=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         BuildGrid();
         GridActive=true;
      }
   }

   if(GridActive)
   {
      ManageGrid();

      if(ExitSignal())
      {
         CloseAll();
         return;
      }

      if(GridProfit()>=MaxProfitMoney)
      {
         CloseAll();
         return;
      }
   }
}
//+------------------------------------------------------------------+
