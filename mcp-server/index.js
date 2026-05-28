#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
    CallToolRequestSchema,
    ListToolsRequestSchema
} from '@modelcontextprotocol/sdk/types.js';

const API_BASE = (process.env.WAVE_API_URL || 'http://127.0.0.1:61418').replace(/\/+$/, '');
const DEFAULT_TIMEOUT_MS = parseInt(process.env.WAVE_REQUEST_TIMEOUT_MS || '60000', 10);

async function callApi(method, path, { query, body, timeoutMs } = {}) {
    const url = new URL(API_BASE + path);
    if (query) {
        for (const [key, value] of Object.entries(query)) {
            if (value === undefined || value === null || value === '') continue;
            url.searchParams.set(key, String(value));
        }
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs || DEFAULT_TIMEOUT_MS);

    try {
        const response = await fetch(url, {
            method,
            headers: body ? { 'Content-Type': 'application/json' } : undefined,
            body: body ? JSON.stringify(body) : undefined,
            signal: controller.signal
        });
        const text = await response.text();
        let parsed;
        try {
            parsed = text ? JSON.parse(text) : {};
        } catch {
            parsed = { ok: false, error: `Non-JSON response (${response.status}): ${text.slice(0, 500)}` };
        }
        if (!response.ok && parsed && parsed.ok !== false) {
            parsed.ok = false;
            parsed.httpStatus = response.status;
        }
        return parsed;
    } catch (error) {
        if (error.name === 'AbortError') {
            return { ok: false, error: `Request to ${url.pathname} timed out after ${timeoutMs || DEFAULT_TIMEOUT_MS}ms` };
        }
        return { ok: false, error: `HTTP error: ${error.message}. Is the Wave VS Code extension running and listening at ${API_BASE}?` };
    } finally {
        clearTimeout(timer);
    }
}

function asToolResult(payload) {
    return {
        content: [
            {
                type: 'text',
                text: JSON.stringify(payload, null, 2)
            }
        ],
        isError: payload && payload.ok === false
    };
}

const TOOLS = [
    {
        name: 'wave_status',
        description: 'Show overall Wave server state: WebSocket port, connected Roblox clients, active sessions, last log id, and selection mode. Use this first to confirm at least one client is connected before executing scripts.',
        inputSchema: { type: 'object', properties: {}, additionalProperties: false }
    },
    {
        name: 'wave_list_clients',
        description: 'List all currently connected Roblox clients with their identity (player, game, process). Each client has an `id`, `selected` flag, and `ready` boolean.',
        inputSchema: { type: 'object', properties: {}, additionalProperties: false }
    },
    {
        name: 'wave_get_logs',
        description: 'Fetch recent in-memory log entries (player prints, warnings, errors, server events). Supports filters. Use `sinceId` from a previous response to only fetch new entries.',
        inputSchema: {
            type: 'object',
            properties: {
                limit: { type: 'integer', minimum: 1, maximum: 1000, description: 'Max entries (default 100).' },
                sinceId: { type: 'integer', description: 'Only return entries with id greater than this value.' },
                level: { type: 'string', description: 'Filter by level e.g. ERROR, WARNING, PRINT, INFO, DEBUG, CLIENT, AGENT, SERVER.' },
                clientId: { type: 'string', description: 'Filter by Wave-internal client id (UUID).' },
                sessionId: { type: 'string', description: 'Filter by session id (one Roblox lifecycle, see wave_wait_for_reload).' },
                playerId: { type: 'string', description: 'Filter by Roblox player id (UserId).' }
            },
            additionalProperties: false
        }
    },
    {
        name: 'wave_clear_logs',
        description: 'Wipe the in-memory log buffer and truncate the JSONL log file. Useful before running a fresh test to keep output focused.',
        inputSchema: { type: 'object', properties: {}, additionalProperties: false }
    },
    {
        name: 'wave_execute_text',
        description: 'Send a Lua script to the targeted Roblox clients (fire-and-forget). Returns immediately after dispatch — does NOT wait for output. Prefer wave_execute_and_wait when you need to verify a script ran successfully.',
        inputSchema: {
            type: 'object',
            properties: {
                text: { type: 'string', description: 'Lua source code to execute.' },
                name: { type: 'string', description: 'Optional display name for logs/notifications.' }
            },
            required: ['text'],
            additionalProperties: false
        }
    },
    {
        name: 'wave_execute_file',
        description: 'Execute a Lua file from the VS Code workspace. Path is resolved against the workspace root unless absolute. Fire-and-forget like wave_execute_text.',
        inputSchema: {
            type: 'object',
            properties: {
                path: { type: 'string', description: 'Relative or absolute path to a .lua file.' }
            },
            required: ['path'],
            additionalProperties: false
        }
    },
    {
        name: 'wave_execute_and_wait',
        description: 'Send a Lua script and synchronously wait until it completes. The script is wrapped in pcall and a unique completion marker. Returns logs captured during execution plus any pcall errors. Use this for one-shot scripts where you need the result. NOT suitable for long-running scripts that never return (UI loops, autoexec) — use wave_execute_text + wave_wait_for_reload for those.',
        inputSchema: {
            type: 'object',
            properties: {
                text: { type: 'string', description: 'Lua source code to execute.' },
                name: { type: 'string', description: 'Optional display name.' },
                timeoutMs: { type: 'integer', minimum: 500, maximum: 600000, description: 'Override default timeout (ms).' }
            },
            required: ['text'],
            additionalProperties: false
        }
    },
    {
        name: 'wave_list_sessions',
        description: 'List tracked Roblox sessions (one per player.id). Each session has a `generation` counter that increments every time the same player reconnects (e.g. after TeleportReconnect from a script reload). Use the current generation as `sinceGeneration` for wave_wait_for_reload.',
        inputSchema: { type: 'object', properties: {}, additionalProperties: false }
    },
    {
        name: 'wave_wait_for_reload',
        description: 'Long-poll until a Roblox client reconnects with a fresh session (generation > sinceGeneration). Designed for the autoexec workflow: you change source, the user-side script server pushes script_updated, the Roblox client TeleportReconnect()s, the autoexec re-runs — this tool returns when the new session arrives. Returns the new sessionId, which you can pass to wave_get_session_logs to read only the new sessions output.',
        inputSchema: {
            type: 'object',
            properties: {
                playerId: { type: 'string', description: 'Optional Roblox player id (UserId) to wait for. If omitted, returns on any reconnect.' },
                sinceGeneration: { type: 'integer', description: 'Only return sessions with generation strictly greater than this. Pass current generation from wave_list_sessions.' },
                timeoutMs: { type: 'integer', minimum: 1000, maximum: 600000, description: 'Override default long-poll timeout (ms).' }
            },
            additionalProperties: false
        }
    },
    {
        name: 'wave_get_session_logs',
        description: 'Read all logs belonging to a specific session (one Roblox lifecycle). Pair with wave_wait_for_reload to inspect output of the freshly reloaded autoexec script without noise from the previous session.',
        inputSchema: {
            type: 'object',
            properties: {
                sessionId: { type: 'string', description: 'Session id from wave_wait_for_reload or wave_list_sessions.' },
                limit: { type: 'integer', minimum: 1, maximum: 1000, description: 'Max entries (default 200).' },
                sinceId: { type: 'integer', description: 'Only entries with id greater than this.' },
                level: { type: 'string', description: 'Filter by level.' }
            },
            required: ['sessionId'],
            additionalProperties: false
        }
    }
];

const server = new Server(
    { name: 'wave-mcp', version: '0.1.0' },
    { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args = {} } = request.params;

    switch (name) {
        case 'wave_status':
            return asToolResult(await callApi('GET', '/status'));

        case 'wave_list_clients':
            return asToolResult(await callApi('GET', '/clients'));

        case 'wave_get_logs':
            return asToolResult(await callApi('GET', '/logs', { query: args }));

        case 'wave_clear_logs':
            return asToolResult(await callApi('POST', '/logs/clear'));

        case 'wave_execute_text':
            return asToolResult(await callApi('POST', '/scripts/execute-text', {
                body: { text: args.text, name: args.name }
            }));

        case 'wave_execute_file':
            return asToolResult(await callApi('POST', '/scripts/execute-file', {
                body: { path: args.path }
            }));

        case 'wave_execute_and_wait': {
            const timeoutMs = args.timeoutMs;
            const requestTimeoutMs = timeoutMs ? timeoutMs + 5000 : DEFAULT_TIMEOUT_MS;
            return asToolResult(await callApi('POST', '/scripts/execute-and-wait', {
                body: { text: args.text, name: args.name, timeoutMs },
                timeoutMs: requestTimeoutMs
            }));
        }

        case 'wave_list_sessions':
            return asToolResult(await callApi('GET', '/sessions'));

        case 'wave_wait_for_reload': {
            const timeoutMs = args.timeoutMs || 30000;
            return asToolResult(await callApi('GET', '/sessions/wait-reload', {
                query: {
                    playerId: args.playerId,
                    sinceGeneration: args.sinceGeneration,
                    timeoutMs
                },
                timeoutMs: timeoutMs + 5000
            }));
        }

        case 'wave_get_session_logs':
            return asToolResult(await callApi('GET', '/logs/since-session', {
                query: {
                    sessionId: args.sessionId,
                    limit: args.limit ?? 200,
                    sinceId: args.sinceId,
                    level: args.level
                }
            }));

        default:
            return asToolResult({ ok: false, error: `Unknown tool: ${name}` });
    }
});

const transport = new StdioServerTransport();
await server.connect(transport);
