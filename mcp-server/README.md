# Wave MCP Server

Stdio MCP server that exposes the Wave WebSocket extension's HTTP API as tools to AI agents (Claude Code, Cursor, Claude Desktop).

## Setup

```bash
cd mcp-server
npm install
```

That's it. No build step, no global install needed.

## Register with Claude Code

Either run:

```bash
claude mcp add wave node "C:\\projects\\Wave-Websocket-Execution\\mcp-server\\index.js"
```

Or edit `~/.claude.json` (or the platform equivalent) and add under `mcpServers`:

```json
{
  "mcpServers": {
    "wave": {
      "command": "node",
      "args": ["C:\\projects\\Wave-Websocket-Execution\\mcp-server\\index.js"]
    }
  }
}
```

Restart Claude Code, then run `/mcp` to verify the `wave` server is connected.

## Register with Cursor

Edit `~/.cursor/mcp.json` (project-local: `.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "wave": {
      "command": "node",
      "args": ["C:\\projects\\Wave-Websocket-Execution\\mcp-server\\index.js"]
    }
  }
}
```

## Configuration

The MCP server proxies to `http://127.0.0.1:61418` by default (the Wave extension's agent API). Override with env:

```json
{
  "mcpServers": {
    "wave": {
      "command": "node",
      "args": ["C:\\projects\\Wave-Websocket-Execution\\mcp-server\\index.js"],
      "env": {
        "WAVE_API_URL": "http://127.0.0.1:61418",
        "WAVE_REQUEST_TIMEOUT_MS": "60000"
      }
    }
  }
}
```

## Tools

| Tool | Purpose |
|---|---|
| `wave_status` | Server state, sessions, connected clients. Call first to confirm a client is connected. |
| `wave_list_clients` | All connected Roblox clients with identity. |
| `wave_get_logs` | Recent logs with filters (level, sinceId, clientId, sessionId, playerId). |
| `wave_clear_logs` | Wipe in-memory and JSONL log buffer. |
| `wave_execute_text` | Send Lua to clients (fire-and-forget). |
| `wave_execute_file` | Execute a workspace `.lua` file (fire-and-forget). |
| `wave_execute_and_wait` | Send Lua, wrap in pcall + completion marker, wait for output. Use for one-shot debugging. |
| `wave_list_sessions` | All tracked sessions with generation counter. |
| `wave_wait_for_reload` | Long-poll until a fresh session arrives (after teleport reconnect). |
| `wave_get_session_logs` | Logs scoped to one session. |

## Workflow recipes

### Quick debug snippet

```
wave_execute_and_wait(text="print('hello')")
```

Returns `{ ok, markerSeen, logs: [...] }` synchronously.

### Watch-reload loop (autoexec workflow)

1. `wave_list_sessions` → grab current `generation` for your `playerId`
2. Edit your source files
3. Run your build command (via the agent's Bash, not via this MCP)
4. Build pushes new code → user's script server emits `script_updated` → `websocket_client.lua` reconnects with new session
5. `wave_wait_for_reload(playerId, sinceGeneration)` → returns new `sessionId`
6. `wave_get_session_logs(sessionId)` → read clean logs from the fresh session only
