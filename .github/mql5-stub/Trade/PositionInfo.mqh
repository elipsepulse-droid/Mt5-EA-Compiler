//+------------------------------------------------------------------+
//| PositionInfo.mqh — CPositionInfo stub for CI compilation        |
//| Compatible with all EAs: v2, v3, GoldSniper Pro v2              |
//+------------------------------------------------------------------+
#ifndef __POSITION_INFO_MQH__
#define __POSITION_INFO_MQH__

class CPositionInfo
{
public:
   bool SelectByIndex(int index)
   {
      ulong ticket = PositionGetTicket(index);
      return (ticket > 0) && PositionSelectByTicket(ticket);
   }

   bool SelectByTicket(ulong ticket) { return PositionSelectByTicket(ticket); }

   ulong  Ticket()        { return PositionGetInteger(POSITION_TICKET);       }
   ulong  Magic()         { return PositionGetInteger(POSITION_MAGIC);        }
   string Symbol()        { return PositionGetString(POSITION_SYMBOL);        }
   string Comment()       { return PositionGetString(POSITION_COMMENT);       }
   double PriceOpen()     { return PositionGetDouble(POSITION_PRICE_OPEN);    }
   double StopLoss()      { return PositionGetDouble(POSITION_SL);            }
   double TakeProfit()    { return PositionGetDouble(POSITION_TP);            }
   double Volume()        { return PositionGetDouble(POSITION_VOLUME);        }
   double Profit()        { return PositionGetDouble(POSITION_PROFIT);        }
   double Swap()          { return PositionGetDouble(POSITION_SWAP);          }
   double PriceCurrent()  { return PositionGetDouble(POSITION_PRICE_CURRENT); }

   ENUM_POSITION_TYPE PositionType()
   { return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); }
};

#endif
