//+------------------------------------------------------------------+
//| Minimal CTrade stub — used by CI when official MT5 lib missing  |
//| Covers all methods used by XAUUSD Pro Scalper EA                |
//+------------------------------------------------------------------+
#ifndef __TRADE_TRADE_MQH__
#define __TRADE_TRADE_MQH__

class CTrade
{
private:
   ulong  m_magic;
   ulong  m_deviation;
   ENUM_ORDER_TYPE_FILLING m_filling;

public:
   CTrade()
   {
      m_magic     = 0;
      m_deviation = 10;
      m_filling   = ORDER_FILLING_IOC;
   }

   void SetExpertMagicNumber(ulong magic)             { m_magic     = magic;     }
   void SetDeviationInPoints(ulong deviation)         { m_deviation = deviation; }
   void SetTypeFilling(ENUM_ORDER_TYPE_FILLING fill)  { m_filling   = fill;      }

   bool Buy(double volume, string symbol=NULL, double price=0,
            double sl=0, double tp=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      if(price  == 0)    price  = SymbolInfoDouble(symbol, SYMBOL_ASK);
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
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
      return OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
   }

   bool Sell(double volume, string symbol=NULL, double price=0,
             double sl=0, double tp=0, string comment=NULL)
   {
      if(symbol == NULL) symbol = _Symbol;
      if(price  == 0)    price  = SymbolInfoDouble(symbol, SYMBOL_BID);
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
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
      return OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
   }

   bool PositionModify(string symbol, double sl, double tp)
   {
      if(!PositionSelect(symbol)) return false;
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = symbol;
      req.sl       = sl;
      req.tp       = tp;
      req.magic    = m_magic;
      req.position = PositionGetInteger(POSITION_TICKET);
      return OrderSend(req, res) &&
             (res.retcode == TRADE_RETCODE_DONE ||
              res.retcode == TRADE_RETCODE_PLACED);
   }

   bool PositionClose(string symbol, ulong deviation=ULONG_MAX)
   {
      if(!PositionSelect(symbol)) return false;
      long   type   = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action      = TRADE_ACTION_DEAL;
      req.symbol      = symbol;
      req.volume      = volume;
      req.magic       = m_magic;
      req.deviation   = (deviation == ULONG_MAX) ? m_deviation : deviation;
      req.type_filling= m_filling;
      req.position    = PositionGetInteger(POSITION_TICKET);
      if(type == POSITION_TYPE_BUY)
      {
         req.type  = ORDER_TYPE_SELL;
         req.price = SymbolInfoDouble(symbol, SYMBOL_BID);
      }
      else
      {
         req.type  = ORDER_TYPE_BUY;
         req.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      }
      return OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
   }

   bool PositionClosePartial(string symbol, double volume)
   {
      if(!PositionSelect(symbol)) return false;
      long type = PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = symbol;
      req.volume       = volume;
      req.magic        = m_magic;
      req.deviation    = m_deviation;
      req.type_filling = m_filling;
      req.position     = PositionGetInteger(POSITION_TICKET);
      if(type == POSITION_TYPE_BUY)
      {
         req.type  = ORDER_TYPE_SELL;
         req.price = SymbolInfoDouble(symbol, SYMBOL_BID);
      }
      else
      {
         req.type  = ORDER_TYPE_BUY;
         req.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      }
      return OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
   }
};

#endif
