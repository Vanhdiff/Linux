//+------------------------------------------------------------------+
//| TradingDeskGuardEA.mq5                                           |
//| Contract skeleton for TradingDesk Block Trade                    |
//+------------------------------------------------------------------+
#property strict
#property version   "0.12"
#property description "TradingDesk Block Trade EA contract skeleton"

#include <Trade/Trade.mqh>

input string BackendBaseUrl = "http://127.0.0.1:8000";
input int    AccountId      = 1;
input int    TimeoutMs      = 750;
input string SharedFileName = "ea_status.json";
input bool   ClosePositionsWhenBlocked = true;
input bool   DeletePendingOrdersWhenBlocked = true;
input int    EnforcementTimerMs = 20;
input int    EnforcementThrottleMs = 10;

#define TD_DECISION_ALLOW "ALLOW"
#define TD_DECISION_DENY  "DENY"

CTrade trade;
ulong lastEnforcementTickMs = 0;

// -------------------------------------------------------------------
// Mandatory fail-safe policy
// -------------------------------------------------------------------
// Only allow a trade when backend response is explicitly valid:
// - HTTP 200
// - valid JSON
// - required fields exist
// - decision == "ALLOW"
// - allowed == true
//
// DENY locally on:
// - backend down
// - timeout
// - connection error
// - non-200 response
// - invalid JSON
// - missing required field
// - decision != "ALLOW"
// - allowed != true
// -------------------------------------------------------------------

int OnInit()
{
   int timerMs = MathMax(10, EnforcementTimerMs);
   EventSetMillisecondTimer(timerMs);
   Print("TradingDesk Guard EA initialized. Backend=", BackendBaseUrl,
         " timerMs=", timerMs,
         " throttleMs=", EnforcementThrottleMs);
   WriteHeartbeat(true, "");
   EnforceBlockState(true);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   WriteHeartbeat(false, "EA stopped");
}

void OnTick()
{
   WriteHeartbeat(true, "");
   EnforceBlockState(false);
}

void OnTimer()
{
   EnforceBlockState(false);
}

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   EnforceBlockState(true);
}

bool ValidateBeforeTrade(const string symbol, const string direction, const double volume)
{
   string response = "";
   int httpStatus = 0;

   bool requestOk = PostPreTradeValidation(symbol, direction, volume, response, httpStatus);
   if(!requestOk)
   {
      Print("TradingDesk Guard DENY: backend request failed");
      return false;
   }

   if(!ShouldAllowBackendResponse(response, httpStatus))
   {
      Print("TradingDesk Guard DENY: backend response not explicitly ALLOW");
      return false;
   }

   return true;
}

bool PostPreTradeValidation(
   const string symbol,
   const string direction,
   const double volume,
   string &response,
   int &httpStatus
)
{
   string url = BackendBaseUrl + "/guardrails/pre-trade/validate";
   string headers = "Content-Type: application/json\r\n";
   string resultHeaders = "";
   char requestBody[];
   char resultBody[];

   string body = "{"
               + "\"account_id\":" + IntegerToString(AccountId) + ","
               + "\"symbol\":\"" + JsonEscape(symbol) + "\"," 
               + "\"direction\":\"" + JsonEscape(direction) + "\"," 
               + "\"volume\":" + DoubleToString(volume, 2) + ","
               + "\"source\":\"mt5_ea\""
               + "}";

   StringToCharArray(body, requestBody, 0, WHOLE_ARRAY, CP_UTF8);
   ResetLastError();
   httpStatus = WebRequest(
      "POST",
      url,
      headers,
      TimeoutMs,
      requestBody,
      resultBody,
      resultHeaders
   );

   if(httpStatus == -1)
   {
      int errorCode = GetLastError();
      Print("TradingDesk Guard WebRequest failed. error=", errorCode,
            ". Add backend URL to MT5 allowed WebRequest list: ", BackendBaseUrl);
      response = "";
      return false;
   }

   response = CharArrayToString(resultBody, 0, -1, CP_UTF8);
   return true;
}

bool ShouldAllowBackendResponse(const string response, const int httpStatus)
{
   if(httpStatus != 200)
      return false;

   if(StringLen(response) <= 0)
      return false;

   // Minimal defensive checks. Full JSON parsing can be added later, but this
   // remains fail-safe because any ambiguous response returns false.
   bool hasDecision = StringFind(response, "\"decision\"") >= 0;
   bool hasAllowed  = StringFind(response, "\"allowed\"") >= 0;
   bool isAllow     = StringFind(response, "\"decision\":\"ALLOW\"") >= 0
                   || StringFind(response, "\"decision\": \"ALLOW\"") >= 0;
   bool allowedTrue = StringFind(response, "\"allowed\":true") >= 0
                   || StringFind(response, "\"allowed\": true") >= 0;

   return hasDecision && hasAllowed && isAllow && allowedTrue;
}

bool IsBackendBlocked()
{
   string fileName = "block_" + IntegerToString(AccountId) + ".json";
   int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   string payload = FileReadString(handle, (int)FileSize(handle));
   FileClose(handle);

   bool hasBlockedField = StringFind(payload, "\"blocked\"") >= 0;
   bool blockedTrue = StringFind(payload, "\"blocked\":true") >= 0
                   || StringFind(payload, "\"blocked\": true") >= 0;
   return hasBlockedField && blockedTrue;
}

void EnforceBlockState(const bool force)
{
   ulong nowMs = GetTickCount64();
   if(!force && lastEnforcementTickMs > 0)
   {
      ulong elapsed = nowMs - lastEnforcementTickMs;
      if(elapsed < (ulong)MathMax(0, EnforcementThrottleMs))
         return;
   }
   lastEnforcementTickMs = nowMs;

   if(!IsBackendBlocked())
      return;

   if(DeletePendingOrdersWhenBlocked)
      DeleteAllPendingOrders();

   if(ClosePositionsWhenBlocked)
      CloseAllOpenPositions();
}

void DeleteAllPendingOrders()
{
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      ulong ticket = OrderGetTicket(index);
      if(ticket == 0)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool pending = type == ORDER_TYPE_BUY_LIMIT
                  || type == ORDER_TYPE_SELL_LIMIT
                  || type == ORDER_TYPE_BUY_STOP
                  || type == ORDER_TYPE_SELL_STOP
                  || type == ORDER_TYPE_BUY_STOP_LIMIT
                  || type == ORDER_TYPE_SELL_STOP_LIMIT;
      if(!pending)
         continue;

      if(!trade.OrderDelete(ticket))
         Print("TradingDesk Guard failed to delete pending order ", ticket,
               ". retcode=", trade.ResultRetcode());
      else
         Print("TradingDesk Guard deleted pending order while blocked: ", ticket);
   }
}

void CloseAllOpenPositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!trade.PositionClose(ticket))
         Print("TradingDesk Guard failed to close blocked position ", ticket,
               " symbol=", symbol,
               " retcode=", trade.ResultRetcode());
      else
         Print("TradingDesk Guard closed blocked position: ", ticket,
               " symbol=", symbol);
   }
}

void WriteHeartbeat(const bool connected, const string error)
{
   string payload = "{"
                  + "\"connected\":" + (connected ? "true" : "false") + ","
                  + "\"last_heartbeat\":\"" + IsoUtcNow() + "\"," 
                  + "\"version\":\"0.12\"," 
                  + "\"account_id\":" + IntegerToString(AccountId) + ","
                  + "\"error\":\"" + JsonEscape(error) + "\""
                  + "}";

   int handle = FileOpen(SharedFileName, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("TradingDesk Guard failed to write heartbeat file. error=", GetLastError());
      return;
   }
   FileWriteString(handle, payload);
   FileClose(handle);
}

string IsoUtcNow()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d+00:00",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

string JsonEscape(const string value)
{
   string escaped = value;
   StringReplace(escaped, "\\", "\\\\");
   StringReplace(escaped, "\"", "\\\"");
   return escaped;
}
