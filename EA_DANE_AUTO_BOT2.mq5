//+------------------------------------------------------------------+
//| EA DANE GRID BOT - MARKET ENTRY ONLY (CI COMPATIBLE)            |
//+------------------------------------------------------------------+
#property strict

// GRID SETTINGS
input int GridSize=10;
input int SpacingPips=500;
input double LotSize=0.01;

// RSI ENTRY
input int RSIPeriod=14;
input int RSI_BuyLevel=40;
input int RSI_SellLevel=60;

// TREND FILTER
input int FastMA=100;
input int SlowMA=300;

// EXIT FILTER
input int ExitFastMA=50;
input int ExitSlowMA=200;

input ulong Magic=3613;

// GLOBAL VARIABLES
double spacing;
double lastPrice=0;
int direction=0;
int tradeCount=0;

//+------------------------------------------------------------------+
int OnInit()
{
 spacing = SpacingPips * _Point;
 return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
double GetRSI()
{
 int h=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);
 double b[];
 CopyBuffer(h,0,0,1,b);
 IndicatorRelease(h);
 return b[0];
}

//+------------------------------------------------------------------+
double GetMA(int p)
{
 int h=iMA(_Symbol,_Period,p,0,MODE_EMA,PRICE_CLOSE);
 double b[];
 CopyBuffer(h,0,0,1,b);
 IndicatorRelease(h);
 return b[0];
}

//+------------------------------------------------------------------+
int CountPositions()
{
 int c=0;

 for(int i=0;i<PositionsTotal();i++)
 {
  if(PositionGetTicket(i))
  {
   if(PositionGetInteger(POSITION_MAGIC)==Magic &&
      PositionGetString(POSITION_SYMBOL)==_Symbol)
      c++;
  }
 }

 return c;
}

//+------------------------------------------------------------------+
void SendMarketOrder(int dir)
{
 MqlTradeRequest req;
 MqlTradeResult res;

 ZeroMemory(req);
 ZeroMemory(res);

 req.action=TRADE_ACTION_DEAL;
 req.symbol=_Symbol;
 req.volume=LotSize;
 req.magic=Magic;

 if(dir==1)
 {
  req.type=ORDER_TYPE_BUY;
  req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
 }
 else
 {
  req.type=ORDER_TYPE_SELL;
  req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
 }

 OrderSend(req,res);
}

//+------------------------------------------------------------------+
void OpenFirstTrade(int dir)
{
 double price;

 if(dir==1)
  price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
 else
  price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

 SendMarketOrder(dir);

 lastPrice=price;
 direction=dir;
 tradeCount=1;
}

//+------------------------------------------------------------------+
void ManageGrid()
{
 if(tradeCount>=GridSize)
  return;

 double price;

 if(direction==1)
  price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
 else
  price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

 if(MathAbs(price-lastPrice)>=spacing)
 {
  SendMarketOrder(direction);

  lastPrice=price;
  tradeCount++;
 }
}

//+------------------------------------------------------------------+
void ClosePosition(ulong ticket,long type,double volume)
{
 MqlTradeRequest req;
 MqlTradeResult res;

 ZeroMemory(req);
 ZeroMemory(res);

 req.action=TRADE_ACTION_DEAL;
 req.position=ticket;
 req.symbol=_Symbol;
 req.volume=volume;
 req.magic=Magic;

 if(type==POSITION_TYPE_BUY)
 {
  req.type=ORDER_TYPE_SELL;
  req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
 }
 else
 {
  req.type=ORDER_TYPE_BUY;
  req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
 }

 OrderSend(req,res);
}

//+------------------------------------------------------------------+
void CloseAll()
{
 for(int i=PositionsTotal()-1;i>=0;i--)
 {
  ulong ticket=PositionGetTicket(i);

  if(PositionGetInteger(POSITION_MAGIC)!=Magic)
   continue;

  if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
   continue;

  long type=PositionGetInteger(POSITION_TYPE);
  double vol=PositionGetDouble(POSITION_VOLUME);

  ClosePosition(ticket,type,vol);
 }

 tradeCount=0;
 direction=0;
}

//+------------------------------------------------------------------+
void CheckExitSignal()
{
 static double prevF=0;
 static double prevS=0;

 double f=GetMA(ExitFastMA);
 double s=GetMA(ExitSlowMA);

 if(prevF!=0)
 {
  if((prevF<prevS && f>s) || (prevF>prevS && f<s))
   CloseAll();
 }

 prevF=f;
 prevS=s;
}

//+------------------------------------------------------------------+
void OnTick()
{
 CheckExitSignal();

 if(CountPositions()==0)
 {
  tradeCount=0;
  direction=0;
 }

 if(direction!=0)
 {
  ManageGrid();
  return;
 }

 double rsi=GetRSI();

 if(rsi<=RSI_BuyLevel)
  OpenFirstTrade(1);

 if(rsi>=RSI_SellLevel)
  OpenFirstTrade(-1);
}
//+------------------------------------------------------------------+
