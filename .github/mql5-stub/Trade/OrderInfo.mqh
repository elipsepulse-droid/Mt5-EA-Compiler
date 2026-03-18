//+------------------------------------------------------------------+
//| OrderInfo.mqh — COrderInfo stub for CI compilation              |
//| Compatible with all EAs: v2, v3, GoldSniper Pro v2              |
//+------------------------------------------------------------------+
#ifndef __ORDER_INFO_MQH__
#define __ORDER_INFO_MQH__

class COrderInfo
{
public:
   bool SelectByIndex(int index)
   {
      ulong ticket = OrderGetTicket(index);
      return (ticket > 0) && OrderSelect(ticket);
   }

   bool SelectByTicket(ulong ticket) { return OrderSelect(ticket); }

   ulong  Ticket()  { return OrderGetInteger(ORDER_TICKET);        }
   ulong  Magic()   { return OrderGetInteger(ORDER_MAGIC);         }
   string Symbol()  { return OrderGetString(ORDER_SYMBOL);         }
   string Comment() { return OrderGetString(ORDER_COMMENT);        }
   double Volume()  { return OrderGetDouble(ORDER_VOLUME_CURRENT); }
   double Price()   { return OrderGetDouble(ORDER_PRICE_OPEN);     }
   double SL()      { return OrderGetDouble(ORDER_SL);             }
   double TP()      { return OrderGetDouble(ORDER_TP);             }

   ENUM_ORDER_TYPE Type()
   { return (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE); }
};

#endif
