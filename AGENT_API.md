# Wave WebSocket Agent API

This extension exposes a local HTTP API so an AI agent can read Roblox client logs and execute Lua scripts through the existing WebSocket bridge.

Default base URL:

```text
http://127.0.0.1:61418
```

Structured logs are also written as newline-delimited JSON:

```text
.wave/logs/current.ndjson
```

## Agent Workflow

1. Call `GET /status` and make sure `websocket.connectedClients` is greater than `0`.
2. Execute a script with `POST /scripts/execute-file` or `POST /scripts/execute-text`.
3. Poll `GET /logs?sinceId=<lastId>&limit=100` to read new output.
4. Treat `ERROR`, `WARNING`, compiler errors, and authentication errors as failures to investigate.

## Endpoints

### `GET /status`

Returns server state, connected clients, selected clients, API URL, and log file information.

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
- `clientId`: filter by client id

```bash
curl "http://127.0.0.1:61418/logs?limit=100"
curl "http://127.0.0.1:61418/logs?sinceId=25"
curl "http://127.0.0.1:61418/logs?level=ERROR"
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
  "player": "PlayerName",
  "playerId": "123",
  "game": "GameName"
}
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
  "path": "C:\\project\\scripts\\test.lua"
}
```

### `POST /scripts/execute-text`

Sends raw Lua text to the currently targeted clients.

```bash
curl -X POST http://127.0.0.1:61418/scripts/execute-text \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"agent-check.lua\",\"text\":\"print('agent check')\"}"
```

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

