//+------------------------------------------------------------------+
//| CTelegramNotifier.mqh  - XAUUSD Scalper EA Phase 3              |
//| Telegram stub: logs to Print(); HTTP deferred to Phase 4+ (DLL) |
//+------------------------------------------------------------------+
#property strict

#include "CNotificationBase.mqh"

class CTelegramNotifier : public CNotificationBase
{
private:
   string m_token;
   string m_chatId;

public:
   void Init(string token, string chatId);
   virtual bool Send(string event, string detail);
};

void CTelegramNotifier::Init(string token, string chatId)
{
   m_token  = token;
   m_chatId = chatId;
}

//--- Stub: logs to Experts log; replace with WinInet HTTP POST in Phase 4+
bool CTelegramNotifier::Send(string event, string detail)
{
   // TODO Phase 4+: POST https://api.telegram.org/bot<token>/sendMessage
   //   body: chat_id=m_chatId, text=event+"|"+detail via WinInet.dll
   PrintFormat("[Telegram] %s | %s", event, detail);
   return true;
}
//+------------------------------------------------------------------+
