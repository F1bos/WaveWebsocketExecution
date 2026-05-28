# Wave WebSocket Agent API

This extension exposes a local HTTP API so an AI agent can read Roblox client logs and execute Lua scripts through the existing WebSocket bridge.

For Claude Code / Cursor / Claude Desktop integration, see `mcp-server/README.md` — it wraps every endpoint here as an MCP tool. This file documents the raw HTTP API for curl, scripts, and any non-MCP client.

Default base URL:

```text
http://127.0.0.1:61418
```

Structured logs are also written as newline-delimited JSON:

```text
.wave/logs/current.ndjson
```

## Workflows

### A. One-shot debug

1. `GET /status` — confirm `websocket.connectedClients > 0`.
2. `POST /scripts/execute-and-wait` with `{ "text": "print(2+2)" }` — script is wrapped in `pcall` plus a unique completion marker. Returns `markerSeen`, `durationMs`, `logs[]` collected during the run, and `errors[]` if `pcall` failed.

### B. Watch-reload (autoexec development)

1. `GET /sessions` — note the current `generation` for your `playerId`.
2. Edit your source files. Run your build command — your script server pushes `script_updated` to the Roblox client, which calls `TeleportReconnect()`. The autoexec re-runs in a fresh session.
3. `GET /sessions/wait-reload?playerId=...&sinceGeneration=N&timeoutMs=60000` — long-poll until the new session arrives.
4. `GET /logs/since-session?sessionId=...` — read only the logs of the new session, without noise from the old one.

### C. Polling

`GET /logs?sinceId=<lastId>` — agent polls for new entries. Treat `ERROR`, `WARNING`, compiler errors, and authentication errors as failures to investigate.

## Endpoints

### `GET /status`

Returns server state, connected clients, sessions, selected clients, API URL, and log file information.

```bash
curl http://127.0.0.1:61418/status
```

### `GET /clients`

Returns all currently identified Roblox clients.

```bash
curl http://127.0.0.1:61418/clients
```

Each client includes:

- `id`
- `selected`
- `ready`
- `displayName`
- `player`
- `process`
- `game`

### `GET /logs`

Returns recent in-memory log entries.

Query parameters:

- `limit`: number of entries, default `100`
- `sinceId`: only entries after this log id
- `level`: filter by level, for example `ERROR`
- `clientId`: filter by client id (Wave-internal UUID)
- `sessionId`: filter by session id (one Roblox lifecycle)
- `playerId`: filter by Roblox player UserId

```bash
curl "http://127.0.0.1:61418/logs?limit=100"
curl "http://127.0.0.1:61418/logs?sinceId=25"
curl "http://127.0.0.1:61418/logs?level=ERROR"
curl "http://127.0.0.1:61418/logs?sessionId=8c2e..."
```

Log entries look like this:

```json
{
  "id": 42,
  "time": "2026-05-02T13:30:00.000Z",
  "displayTime": "16:30:00",
  "level": "ERROR",
  "message": "attempt to index nil",
  "type": "client/console/error",
  "clientId": "5f2c...",
  "sessionId": "8c2e...",
  "player": "PlayerName",
  "playerId": "123",
  "game": "GameName"
}
```

### `GET /logs/since-session`

Sugar over `/logs` that requires `sessionId`. Same query parameters as `/logs`.

```bash
curl "http://127.0.0.1:61418/logs/since-session?sessionId=8c2e...&limit=200"
```

### `GET /sessions`

Returns all tracked sessions keyed by `playerId`. A session is created on every `client/identify` from a client and gets an incremented `generation` counter when the same player reconnects (e.g. after `TeleportReconnect()`).

```bash
curl http://127.0.0.1:61418/sessions
```

Response:

```json
{
  "ok": true,
  "sessions": [
    {
      "playerId": "123456",
      "sessionId": "8c2e...",
      "generation": 4,
      "clientId": "5f2c...",
      "identity": { "player": { ... }, "game": { ... }, "process": { ... } },
      "firstSeenAt": "2026-05-28T12:00:00.000Z",
      "lastSeenAt": "2026-05-28T12:00:00.000Z",
      "closed": false
    }
  ]
}
```

### `GET /sessions/wait-reload`

Long-poll. Resolves when a fresh session appears that satisfies the filters, or when the timeout expires.

Query parameters:

- `playerId`: optional, wait for a specific player
- `sinceGeneration`: optional, only return when generation > this value
- `timeoutMs`: optional, default `30000`, max `600000`

```bash
curl "http://127.0.0.1:61418/sessions/wait-reload?playerId=123456&sinceGeneration=4&timeoutMs=60000"
```

Response on success:

```json
{
  "ok": true,
  "timedOut": false,
  "sessionId": "9f1a...",
  "playerId": "123456",
  "generation": 5,
  "clientId": "...",
  "identity": { ... },
  "firstSeenAt": "..."
}
```

Response on timeout:

```json
{ "ok": true, "timedOut": true, "playerId": "123456", "sinceGeneration": 4 }
```

### `POST /scripts/execute-file`

Reads a Lua file and sends it to the currently targeted clients. Relative paths are resolved from the VS Code workspace root.

```bash
curl -X POST http://127.0.0.1:61418/scripts/execute-file \
  -H "Content-Type: application/json" \
  -d "{\"path\":\"scripts/test.lua\"}"
```

Response:

```json
{
  "ok": true,
  "sent": 1,
  "failed": 0,
  "selectionMode": "all",
  "scriptName": "test.lua",
  "chars": 120,
  "path": "C:\\project\\scripts\\test.lua",
  "targets": [ { "clientId": "...", "sessionId": "...", "playerId": "..." } ]
}
```

### `POST /scripts/execute-text`

Sends raw Lua text to the currently targeted clients. Fire-and-forget.

```bash
curl -X POST http://127.0.0.1:61418/scripts/execute-text \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"agent-check.lua\",\"text\":\"print('agent check')\"}"
```

### `POST /scripts/execute-and-wait`

Wraps the script in `pcall` plus a unique completion marker, sends it, and blocks until the marker comes back through the log stream (or the timeout expires).

Body: `{ "text": "...", "name": "...", "timeoutMs": 15000 }`

```bash
curl -X POST http://127.0.0.1:61418/scripts/execute-and-wait \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"print(2+2)\"}"
```

Response:

```json
{
  "ok": true,
  "executionId": "f3a1...",
  "markerSeen": true,
  "timedOut": false,
  "durationMs": 184,
  "sent": 1,
  "failed": 0,
  "scriptName": "Agent Script",
  "chars": 11,
  "targets": [ ... ],
  "logs": [
    { "id": 51, "level": "PRINT", "message": "4", ... },
    { "id": 52, "level": "PRINT", "message": "__WAVE_DONE_f3a1...__", ... }
  ],
  "errors": []
}
```

If the user code throws, `errors[]` contains the `pcall` message:

```json
{
  "ok": true,
  "markerSeen": true,
  "errors": [
    { "id": 60, "message": "boom", "clientId": "...", "sessionId": "..." }
  ]
}
```

`execute-and-wait` is for one-shot scripts that complete. Use `execute-text` plus `wait-reload` for scripts that never return (UI loops, long-running autoexec).

### `POST /scripts/execute-specific`

Executes the configured `luaWebSocket.specificScriptPath`.

```bash
curl -X POST http://127.0.0.1:61418/scripts/execute-specific
```

### `POST /commands/execute-current`

Executes the currently active VS Code editor document.

```bash
curl -X POST http://127.0.0.1:61418/commands/execute-current
```

### `POST /logs/clear`

Clears the in-memory log buffer and truncates the JSONL log file.

```bash
curl -X POST http://127.0.0.1:61418/logs/clear
```

### `GET /config`

Returns effective agent-related settings.

```bash
curl http://127.0.0.1:61418/config
```

## Settings

- `luaWebSocket.agentApiEnabled`: enable the local HTTP API, default `true`
- `luaWebSocket.agentApiPort`: API port, default `61418`
- `luaWebSocket.agentLogEnabled`: enable JSONL log writing, default `true`
- `luaWebSocket.agentLogFilePath`: log path, default `.wave/logs/current.ndjson`
- `luaWebSocket.agentLogMaxEntries`: in-memory log tail size, default `1000`
- `luaWebSocket.executeAndWaitTimeoutMs`: default timeout for `/scripts/execute-and-wait`, default `15000`
- `luaWebSocket.waitForReloadTimeoutMs`: default timeout for `/sessions/wait-reload`, default `30000`


