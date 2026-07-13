//+------------------------------------------------------------------+
//| TradingDeskGuardEA.mq5                                           |
//| Contract skeleton for TradingDesk Block Trade                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.000"
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
input int    HeartbeatIntervalMs = 1000;
input string AuditFileName = "ea_mt5_demo_audit.jsonl";

#define TD_DECISION_ALLOW "ALLOW"
#define TD_DECISION_DENY  "DENY"

CTrade trade;
ulong lastEnforcementTickMs = 0;
ulong lastHeartbeatTickMs = 0;
ulong lastConfigCheckTickMs = 0;
ulong lastCommandCheckTickMs = 0;
bool  lastObservedBlockedState = false;
bool  lastObservedBlockStateKnown = false;
string lastCommandId = "";

string runtimeBackendBaseUrl = "";
int    runtimeAccountId = 0;
int    runtimeTimeoutMs = 0;
string runtimeSharedFileName = "";
bool   runtimeClosePositionsWhenBlocked = true;
bool   runtimeDeletePendingOrdersWhenBlocked = true;
int    runtimeEnforcementTimerMs = 0;
int    runtimeEnforcementThrottleMs = 0;
int    runtimeHeartbeatIntervalMs = 0;
string runtimeAuditFileName = "";

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
   InitializeRuntimeDefaults();
   LoadRuntimeConfig(true);
   int timerMs = MathMax(10, runtimeEnforcementTimerMs);
   EventSetMillisecondTimer(timerMs);
   LogInfo("Initialization started. Backend=" + runtimeBackendBaseUrl
           + " timerMs=" + IntegerToString(timerMs)
           + " throttleMs=" + IntegerToString(runtimeEnforcementThrottleMs)
           + " heartbeatMs=" + IntegerToString(MathMax(100, runtimeHeartbeatIntervalMs)));
   LogInfo("Communication directory=" + CommonFilesDirectory());
   LogInfo("EA status file=" + StatusFilePath());
   LogInfo("EA timing audit file=" + AuditFilePath());
   LogInfo("AccountId runtime=" + IntegerToString(runtimeAccountId)
            + " terminal_login=" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)));
   AppendAuditEvent("initialization",
                    "\"communication_directory\":\"" + JsonEscape(CommonFilesDirectory()) + "\","
                    + "\"status_file\":\"" + JsonEscape(StatusFilePath()) + "\","
                    + "\"audit_file\":\"" + JsonEscape(AuditFilePath()) + "\","
                    + "\"terminal_login\":" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)));
   WriteHeartbeat(true, "");
   EnforceBlockState(true);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   LogInfo("Deinitializing. reason=" + IntegerToString(reason));
   WriteHeartbeat(false, "EA stopped");
}

void OnTick()
{
   EnforceBlockState(false);
}

void OnTimer()
{
   MaybeReloadRuntimeConfig();
   MaybeProcessCommandFile();
   MaybeWriteHeartbeat();
   EnforceBlockState(false);
}

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   AppendAuditEvent("ea_transaction_received",
                    "\"transaction_type\":" + IntegerToString((int)trans.type) + ","
                    + "\"order\":" + IntegerToString((int)trans.order) + ","
                    + "\"deal\":" + IntegerToString((int)trans.deal) + ","
                    + "\"position\":" + IntegerToString((int)trans.position) + ","
                    + "\"retcode\":" + IntegerToString((int)result.retcode));
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
   string url = runtimeBackendBaseUrl + "/guardrails/pre-trade/validate";
   string headers = "Content-Type: application/json\r\n";
   string resultHeaders = "";
   char requestBody[];
   char resultBody[];

   string body = "{"
               + "\"account_id\":" + IntegerToString(runtimeAccountId) + ","
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
      runtimeTimeoutMs,
      requestBody,
      resultBody,
      resultHeaders
   );

   if(httpStatus == -1)
   {
      int errorCode = GetLastError();
      Print("TradingDesk Guard WebRequest failed. error=", errorCode,
            ". Add backend URL to MT5 allowed WebRequest list: ", runtimeBackendBaseUrl);
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
   string fileName = "block_" + IntegerToString(runtimeAccountId) + ".json";
   int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      LogInfo("Block file read skipped. path=" + BlockFilePath()
              + " error=" + IntegerToString(GetLastError()));
      return false;
   }

   string payload = FileReadString(handle, (int)FileSize(handle));
   FileClose(handle);

   bool hasBlockedField = StringFind(payload, "\"blocked\"") >= 0;
   bool blockedTrue = StringFind(payload, "\"blocked\":true") >= 0
                   || StringFind(payload, "\"blocked\": true") >= 0;
   if(!lastObservedBlockStateKnown || lastObservedBlockedState != (hasBlockedField && blockedTrue))
   {
      AppendAuditEvent("block_file_read",
                       "\"path\":\"" + JsonEscape(BlockFilePath()) + "\","
                       + "\"bytes\":" + IntegerToString(StringLen(payload)) + ","
                       + "\"blocked\":" + BoolText(hasBlockedField && blockedTrue));
      lastObservedBlockedState = (hasBlockedField && blockedTrue);
      lastObservedBlockStateKnown = true;
   }
   LogInfo("Block file read. path=" + BlockFilePath()
            + " bytes=" + IntegerToString(StringLen(payload))
            + " blocked=" + BoolText(hasBlockedField && blockedTrue));
   return hasBlockedField && blockedTrue;
}

void EnforceBlockState(const bool force)
{
   ulong nowMs = GetTickCount64();
   if(!force && lastEnforcementTickMs > 0)
   {
      ulong elapsed = nowMs - lastEnforcementTickMs;
      if(elapsed < (ulong)MathMax(0, runtimeEnforcementThrottleMs))
         return;
   }
   lastEnforcementTickMs = nowMs;

   if(!IsBackendBlocked())
      return;

   if(runtimeDeletePendingOrdersWhenBlocked)
      DeleteAllPendingOrders();

   if(runtimeClosePositionsWhenBlocked)
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

      LogInfo("Delete pending order attempt. ticket=" + IntegerToString((int)ticket)
              + " type=" + IntegerToString((int)type));
      if(!trade.OrderDelete(ticket))
         LogError("Delete pending order failed. ticket=" + IntegerToString((int)ticket)
                  + " retcode=" + IntegerToString((int)trade.ResultRetcode())
                  + " description=" + trade.ResultRetcodeDescription());
      else
         LogInfo("Delete pending order success. ticket=" + IntegerToString((int)ticket)
                 + " retcode=" + IntegerToString((int)trade.ResultRetcode())
                 + " description=" + trade.ResultRetcodeDescription());
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
      LogInfo("Close position attempt. ticket=" + IntegerToString((int)ticket)
              + " symbol=" + symbol);
      AppendAuditEvent("close_request_sent",
                       "\"ticket\":" + IntegerToString((int)ticket) + ","
                       + "\"symbol\":\"" + JsonEscape(symbol) + "\"");
      if(!trade.PositionClose(ticket))
         LogError("Close position failed. ticket=" + IntegerToString((int)ticket)
                  + " symbol=" + symbol
                  + " retcode=" + IntegerToString((int)trade.ResultRetcode())
                  + " description=" + trade.ResultRetcodeDescription());
      else
      {
         AppendAuditEvent("close_confirmed",
                          "\"ticket\":" + IntegerToString((int)ticket) + ","
                          + "\"symbol\":\"" + JsonEscape(symbol) + "\","
                          + "\"retcode\":" + IntegerToString((int)trade.ResultRetcode()));
         LogInfo("Close position success. ticket=" + IntegerToString((int)ticket)
                  + " symbol=" + symbol
                  + " retcode=" + IntegerToString((int)trade.ResultRetcode())
                  + " description=" + trade.ResultRetcodeDescription());
      }
   }
}

void WriteHeartbeat(const bool connected, const string error)
{
   string payload = "{"
                  + "\"connected\":" + (connected ? "true" : "false") + ","
                  + "\"last_heartbeat\":\"" + IsoUtcNow() + "\"," 
                  + "\"version\":\"1.000\"," 
                  + "\"account_id\":" + IntegerToString(runtimeAccountId) + ","
                  + "\"error\":\"" + JsonEscape(error) + "\""
                  + "}";

   int handle = FileOpen(runtimeSharedFileName, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      LogError("Heartbeat write failed. path=" + StatusFilePath()
               + " error=" + IntegerToString(GetLastError()));
      return;
   }
   FileWriteString(handle, payload);
   FileClose(handle);
   lastHeartbeatTickMs = GetTickCount64();
   LogInfo("Heartbeat written. path=" + StatusFilePath()
           + " connected=" + BoolText(connected)
           + " error=" + error);
}

void MaybeWriteHeartbeat()
{
   ulong nowMs = GetTickCount64();
   int intervalMs = MathMax(100, runtimeHeartbeatIntervalMs);
   if(lastHeartbeatTickMs == 0 || (nowMs - lastHeartbeatTickMs) >= (ulong)intervalMs)
      WriteHeartbeat(true, "");
}

void InitializeRuntimeDefaults()
{
   runtimeBackendBaseUrl = BackendBaseUrl;
   runtimeAccountId = AccountId;
   runtimeTimeoutMs = TimeoutMs;
   runtimeSharedFileName = SharedFileName;
   runtimeClosePositionsWhenBlocked = ClosePositionsWhenBlocked;
   runtimeDeletePendingOrdersWhenBlocked = DeletePendingOrdersWhenBlocked;
   runtimeEnforcementTimerMs = EnforcementTimerMs;
   runtimeEnforcementThrottleMs = EnforcementThrottleMs;
   runtimeHeartbeatIntervalMs = HeartbeatIntervalMs;
   runtimeAuditFileName = AuditFileName;
}

void MaybeReloadRuntimeConfig()
{
   ulong nowMs = GetTickCount64();
   if(lastConfigCheckTickMs > 0 && (nowMs - lastConfigCheckTickMs) < 2000)
      return;
   LoadRuntimeConfig(false);
}

bool LoadRuntimeConfig(const bool logMissing)
{
   string payload = "";
   if(!ReadCommonTextFile("ea_config.json", payload))
   {
      lastConfigCheckTickMs = GetTickCount64();
      if(logMissing)
         LogInfo("Runtime config not found. Using EA input defaults. path=" + CommonFilesDirectory() + "\\ea_config.json");
      return false;
   }

   int oldTimerMs = runtimeEnforcementTimerMs;
   runtimeBackendBaseUrl = JsonStringValue(payload, "backend_base_url", runtimeBackendBaseUrl);
   runtimeAccountId = JsonIntValue(payload, "account_id", runtimeAccountId);
   runtimeTimeoutMs = JsonIntValue(payload, "timeout_ms", runtimeTimeoutMs);
   runtimeHeartbeatIntervalMs = JsonIntValue(payload, "heartbeat_interval_ms", runtimeHeartbeatIntervalMs);
   runtimeEnforcementTimerMs = JsonIntValue(payload, "enforcement_timer_ms", runtimeEnforcementTimerMs);
   runtimeEnforcementThrottleMs = JsonIntValue(payload, "enforcement_throttle_ms", runtimeEnforcementThrottleMs);
   runtimeClosePositionsWhenBlocked = JsonBoolValue(payload, "close_positions_when_blocked", runtimeClosePositionsWhenBlocked);
   runtimeDeletePendingOrdersWhenBlocked = JsonBoolValue(payload, "delete_pending_orders_when_blocked", runtimeDeletePendingOrdersWhenBlocked);
   runtimeSharedFileName = JsonStringValue(payload, "status_file_name", runtimeSharedFileName);
   runtimeAuditFileName = JsonStringValue(payload, "audit_file_name", runtimeAuditFileName);
   lastConfigCheckTickMs = GetTickCount64();

   int timerMs = MathMax(10, runtimeEnforcementTimerMs);
   if(oldTimerMs != runtimeEnforcementTimerMs)
      EventSetMillisecondTimer(timerMs);

   LogInfo("Runtime config loaded. path=" + CommonFilesDirectory() + "\\ea_config.json"
           + " account_id=" + IntegerToString(runtimeAccountId)
           + " backend=" + runtimeBackendBaseUrl
           + " timerMs=" + IntegerToString(timerMs));
   AppendAuditEvent("config_loaded",
                    "\"path\":\"" + JsonEscape(CommonFilesDirectory() + "\\ea_config.json") + "\","
                    + "\"account_id\":" + IntegerToString(runtimeAccountId) + ","
                    + "\"backend_base_url\":\"" + JsonEscape(runtimeBackendBaseUrl) + "\"");
   return true;
}

void MaybeProcessCommandFile()
{
   ulong nowMs = GetTickCount64();
   if(lastCommandCheckTickMs > 0 && (nowMs - lastCommandCheckTickMs) < 250)
      return;
   lastCommandCheckTickMs = nowMs;
   ProcessCommandFile();
}

bool ProcessCommandFile()
{
   string payload = "";
   if(!ReadCommonTextFile("ea_command.json", payload))
      return false;

   string commandId = JsonStringValue(payload, "command_id", "");
   string commandType = JsonStringValue(payload, "command_type", "");
   if(StringLen(commandId) <= 0 || StringLen(commandType) <= 0)
      return false;
   if(commandId == lastCommandId)
      return false;

   lastCommandId = commandId;
   LogInfo("EA command received. id=" + commandId + " type=" + commandType);
   AppendAuditEvent("command_received",
                    "\"command_id\":\"" + JsonEscape(commandId) + "\","
                    + "\"command_type\":\"" + JsonEscape(commandType) + "\"");

   if(commandType == "reload_config")
   {
      LoadRuntimeConfig(true);
      WriteHeartbeat(true, "");
      return true;
   }
   if(commandType == "ping")
   {
      WriteHeartbeat(true, "");
      return true;
   }
   if(commandType == "clear_command")
   {
      ClearCommandFile();
      return true;
   }

   LogInfo("Unknown EA command ignored. id=" + commandId + " type=" + commandType);
   return false;
}

bool ClearCommandFile()
{
   ResetLastError();
   if(FileDelete("ea_command.json", FILE_COMMON))
   {
      LogInfo("EA command file cleared. path=" + CommonFilesDirectory() + "\\ea_command.json");
      return true;
   }
   LogError("EA command file clear failed. path=" + CommonFilesDirectory() + "\\ea_command.json"
            + " error=" + IntegerToString(GetLastError()));
   return false;
}

bool ReadCommonTextFile(const string fileName, string &payload)
{
   int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      payload = "";
      return false;
   }
   payload = FileReadString(handle, (int)FileSize(handle));
   FileClose(handle);
   return true;
}

string JsonStringValue(const string payload, const string key, const string fallback)
{
   int keyIndex = StringFind(payload, "\"" + key + "\"");
   if(keyIndex < 0)
      return fallback;
   int colonIndex = StringFind(payload, ":", keyIndex);
   if(colonIndex < 0)
      return fallback;
   int startQuote = StringFind(payload, "\"", colonIndex + 1);
   if(startQuote < 0)
      return fallback;
   int endQuote = StringFind(payload, "\"", startQuote + 1);
   if(endQuote < 0)
      return fallback;
   return StringSubstr(payload, startQuote + 1, endQuote - startQuote - 1);
}

int JsonIntValue(const string payload, const string key, const int fallback)
{
   int keyIndex = StringFind(payload, "\"" + key + "\"");
   if(keyIndex < 0)
      return fallback;
   int colonIndex = StringFind(payload, ":", keyIndex);
   if(colonIndex < 0)
      return fallback;
   string valueText = StringSubstr(payload, colonIndex + 1, 32);
   StringTrimLeft(valueText);
   if(StringLen(valueText) <= 0 || StringFind(valueText, "null") == 0)
      return fallback;
   int parsed = (int)StringToInteger(valueText);
   return parsed;
}

bool JsonBoolValue(const string payload, const string key, const bool fallback)
{
   int keyIndex = StringFind(payload, "\"" + key + "\"");
   if(keyIndex < 0)
      return fallback;
   int colonIndex = StringFind(payload, ":", keyIndex);
   if(colonIndex < 0)
      return fallback;
   string valueText = StringSubstr(payload, colonIndex + 1, 8);
   StringTrimLeft(valueText);
   if(StringFind(valueText, "true") == 0)
      return true;
   if(StringFind(valueText, "false") == 0)
      return false;
   return fallback;
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

string BoolText(const bool value)
{
   return value ? "true" : "false";
}

string CommonFilesDirectory()
{
   return TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files";
}

string StatusFilePath()
{
   return CommonFilesDirectory() + "\\" + runtimeSharedFileName;
}

string BlockFilePath()
{
   return CommonFilesDirectory() + "\\block_" + IntegerToString(runtimeAccountId) + ".json";
}

string AuditFilePath()
{
   return CommonFilesDirectory() + "\\" + runtimeAuditFileName;
}

void AppendAuditEvent(const string eventType, const string metadataJson)
{
   string payload = "{"
                  + "\"source\":\"ea\","
                  + "\"event_type\":\"" + JsonEscape(eventType) + "\","
                  + "\"occurred_at\":\"" + IsoUtcNow() + "\","
                  + "\"account_id\":" + IntegerToString(runtimeAccountId) + ","
                  + "\"metadata\":{";
   if(StringLen(metadataJson) > 0)
      payload += metadataJson;
   payload += "}";

   int handle = FileOpen(runtimeAuditFileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      handle = FileOpen(runtimeAuditFileName, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      LogError("Audit write failed. path=" + AuditFilePath()
               + " error=" + IntegerToString(GetLastError()));
      return;
   }
   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, payload + "\r\n");
   FileClose(handle);
}

void LogInfo(const string message)
{
   Print("TradingDeskGuardEA | INFO | ", message);
}

void LogError(const string message)
{
   Print("TradingDeskGuardEA | ERROR | ", message);
}
