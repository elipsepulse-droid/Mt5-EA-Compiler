//+------------------------------------------------------------------+
//| AccountInfo.mqh — CAccountInfo stub for CI compilation          |
//| Covers all methods used by GoldSniper Pro v2                    |
//+------------------------------------------------------------------+
#ifndef __ACCOUNT_INFO_MQH__
#define __ACCOUNT_INFO_MQH__

class CAccountInfo
{
public:
   double Balance()  { return AccountInfoDouble(ACCOUNT_BALANCE);  }
   double Equity()   { return AccountInfoDouble(ACCOUNT_EQUITY);   }
   double Margin()   { return AccountInfoDouble(ACCOUNT_MARGIN);   }
   double FreeMargin(){ return AccountInfoDouble(ACCOUNT_FREEMARGIN); }
   double Profit()   { return AccountInfoDouble(ACCOUNT_PROFIT);   }

   string Currency() { return AccountInfoString(ACCOUNT_CURRENCY); }
   string Company()  { return AccountInfoString(ACCOUNT_COMPANY);  }
   string Name()     { return AccountInfoString(ACCOUNT_NAME);     }
   string Server()   { return AccountInfoString(ACCOUNT_SERVER);   }

   long   Login()    { return AccountInfoInteger(ACCOUNT_LOGIN);    }
   long   Leverage() { return AccountInfoInteger(ACCOUNT_LEVERAGE); }

   ENUM_ACCOUNT_TRADE_MODE TradeMode()
   { return (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE); }

   bool TradeAllowed()
   { return (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED); }
};

#endif
