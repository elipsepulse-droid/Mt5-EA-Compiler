//+------------------------------------------------------------------+
//| Trade.mqh — CTrade stub for CI compilation                      |
//| Compatible with all EAs: v2, v3, GoldSniper Pro v2              |
//+------------------------------------------------------------------+
#ifndef __TRADE_TRADE_MQH__
#define __TRADE_TRADE_MQH__

class CTrade
{
private:
   ulong                   m_magic;
   ulong                   m_deviation;
   ENUM_ORDER_TYPE_FILLING m_filling;
   bool                    m_async;
   uint                    m_last_retcode;
   ulong                   m_last_order;

   bool SendOrder(MqlTradeRequest &req)
   {
      MqlTradeResult res;
      ZeroMemory(res);
      bool ok = OrderSend(req, res);
      m_last_retcode = res.retcode;
      m_last_order   = res.order;
      return ok && (res.retcode == TRADE_RETCODE_DONE ||
                    res.retcode == TRADE_RETCODE_PLACED);
   }

public:
   CTrade()
   {
      m_magic        = 0;
      m_deviation    = 10;
      m_filling      = ORDER_FILLING_IOC;
      m_async        = false;
      m_last_retcode = 0;
      m_last_order   = 0;
   }

   void SetExpertMagicNumber(ulong magic)             { m_magic     = magic;     }
   void SetDeviationInPoints(ulong deviation)         { m_deviation = deviation; }
   void SetTypeFilling(ENUM_ORDER_TYPE_FILLING fill)  { m_filling   = fill;      }
   void SetAsyncMode(bool async)                      { m_async     = async;     }

   // Result accessors
   ulong  ResultOrder()                { return m_last_order;   }
   uint   ResultRetcode()              { return m_last_retcode; }
   string ResultRetcodeDescription()  { return "retcode=" + IntegerToString(m_last_retcode); }

   bool Buy(double volume, string symbol=NULL, double price=0,
            double sl=0, double tp=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      if(price  == 0)    price  = SymbolInfoDouble(symbol, SYMBOL_ASK);
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_BUY;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_filling = m_filling;
      if(comment != NULL) req.comment = comment;
      return SendOrder(req);
   }

   bool Sell(double volume, string symbol=NULL, double price=0,
             double sl=0, double tp=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      if(price  == 0)    price  = SymbolInfoDouble(symbol, SYMBOL_BID);
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_SELL;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_filling = m_filling;
      if(comment != NULL) req.comment = comment;
      return SendOrder(req);
   }

   bool BuyStop(double volume, double price, string symbol=NULL,
               double sl=0, double tp=0,
               ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,
               datetime expiration=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_BUY_STOP;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_time    = type_time;
      req.expiration   = expiration;
      req.type_filling = m_filling;
      if(comment != NULL) req.comment = comment;
      return SendOrder(req);
   }

   bool SellStop(double volume, double price, string symbol=NULL,
                 double sl=0, double tp=0,
                 ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,
                 datetime expiration=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_SELL_STOP;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_time    = type_time;
      req.expiration   = expiration;
      req.type_filling = m_filling;
      if(comment != NULL) req.comment = comment;
      return SendOrder(req);
   }

   bool BuyLimit(double volume, double price, string symbol=NULL,
                 double sl=0, double tp=0,
                 ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,
                 datetime expiration=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_BUY_LIMIT;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_time    = type_time;
      req.expiration   = expiration;
      req.type_filling = m_filling;
      if(comment != NULL) req.comment = comment;
      return SendOrder(req);
   }

   bool SellLimit(double volume, double price, string symbol=NULL,
                  double sl=0, double tp=0,
                  ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,
                  datetime expiration=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_SELL_LIMIT;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_time    = type_time;
      req.expiration   = expiration;
      req.type_filling = m_filling;
      if(comment != NULL) req.comment = comment;
      return SendOrder(req);
   }

   // Modify by ticket (used by GoldSniper v2)
   bool PositionModify(ulong ticket, double sl, double tp)
   {
      MqlTradeRequest req; ZeroMemory(req);
      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.sl       = sl;
      req.tp       = tp;
      req.magic    = m_magic;
      return SendOrder(req);
   }

   // Modify by symbol (used by grid EA v3)
   bool PositionModify(string symbol, double sl, double tp)
   {
      if(!PositionSelect(symbol)) return false;
      return PositionModify((ulong)PositionGetInteger(POSITION_TICKET), sl, tp);
   }

   // Close by ticket (used by GoldSniper v2)
   bool PositionClose(ulong ticket, ulong deviation=ULONG_MAX)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      string symbol = PositionGetString(POSITION_SYMBOL);
      long   type   = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_DEAL;
      req.position     = ticket;
      req.symbol       = symbol;
      req.volume       = volume;
      req.deviation    = (deviation == ULONG_MAX) ? m_deviation : deviation;
      req.magic        = m_magic;
      req.type_filling = m_filling;
      if(type == POSITION_TYPE_BUY)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(symbol, SYMBOL_BID); }
      else
      { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(symbol, SYMBOL_ASK); }
      return SendOrder(req);
   }

   // Partial close by ticket (used by GoldSniper v2)
   bool PositionClosePartial(ulong ticket, double volume)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      string symbol = PositionGetString(POSITION_SYMBOL);
      long   type   = PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest req; ZeroMemory(req);
      req.action       = TRADE_ACTION_DEAL;
      req.position     = ticket;
      req.symbol       = symbol;
      req.volume       = volume;
      req.deviation    = m_deviation;
      req.magic        = m_magic;
      req.type_filling = m_filling;
      if(type == POSITION_TYPE_BUY)
      { req.type = ORDER_TYPE_SELL; req.price = SymbolInfoDouble(symbol, SYMBOL_BID); }
      else
      { req.type = ORDER_TYPE_BUY;  req.price = SymbolInfoDouble(symbol, SYMBOL_ASK); }
      return SendOrder(req);
   }

   // Partial close by symbol (used by grid EA v3)
   bool PositionClosePartial(string symbol, double volume)
   {
      if(!PositionSelect(symbol)) return false;
      return PositionClosePartial((ulong)PositionGetInteger(POSITION_TICKET), volume);
   }

   bool OrderDelete(ulong ticket)
   {
      MqlTradeRequest req; ZeroMemory(req);
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      return SendOrder(req);
   }
};

#endif
