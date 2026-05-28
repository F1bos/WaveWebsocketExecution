-- SUNC VS Code WebSocket Client Emulator
-- Author: Assistant
-- Description: Connects SUNC executor to VS Code "Lua WebSocket" extension.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")

-- Конфигурация
local PORT = 61417
local HOST = "localhost"
-- local HOST = "192.168.137.1"
local URL = "ws://" .. HOST .. ":" .. PORT

-- Генерация фейковых данных процесса (так как SUNC не дает реальный PID)
local FAKE_PID = '-1'
local PROCESS_NAME = "RobloxPlayerBeta.exe"

-- Глобальные переменные
local socket = nil
local isConnected = false
local LocalPlayer = Players.LocalPlayer

-- Ожидаем загрузки игрока, если скрипт запущен слишком рано
if not LocalPlayer then
    LocalPlayer = Players.PlayerAdded:Wait()
end

--------------------------------------------------------------------------------
-- Вспомогательные функции
--------------------------------------------------------------------------------

local function safeEncode(data)
    local success, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    return success and result or nil
end

local function safeDecode(data)
    local success, result = pcall(function()
        return HttpService:JSONDecode(data)
    end)
    return success and result or nil
end

local function getGameName()
    -- Пытаемся получить имя игры, иначе фоллбэк
    local success, name = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end)
    if success and name then return name end
    return game.Name or "Unknown Place"
end

--------------------------------------------------------------------------------
-- Логика протокола
--------------------------------------------------------------------------------

-- 1. Отправка пакета идентификации (client/identify)
local function sendIdentify()
    if not socket then return end

    local payload = {
        op = "client/identify",
        data = {
            game = {
                name = getGameName()
            },
            player = {
                id = tostring(LocalPlayer.UserId),
                name = LocalPlayer.Name,
                display_name = LocalPlayer.DisplayName
            },
            process = {
                id = FAKE_PID, -- Эмуляция
                name = PROCESS_NAME
            }
        }
    }

    local json = safeEncode(payload)
    if json then
        socket:Send(json)
        print("[VSCode-Link] Identified as " .. LocalPlayer.Name)
    end
end

-- 2. Обработка входящих сообщений от сервера
local function onMessage(message)
    local decoded = safeDecode(message)
    if not decoded or not decoded.op then return end

    -- Выполнение скрипта (client/onDidTextDocumentExecute)
    if decoded.op == "client/onDidTextDocumentExecute" then
        if decoded.data and decoded.data.textDocument and decoded.data.textDocument.text then
            local scriptSource = decoded.data.textDocument.text
            
            -- Используем loadstring из SUNC (или нативный Lua loadstring)
            local chunk, compileErr = loadstring(scriptSource)
            
            if not chunk then
                -- Если ошибка компиляции, отправляем обратно как ошибку
                warn("[VSCode] Compilation Error: " .. tostring(compileErr))
            else
                -- Запускаем в новом потоке
                task.spawn(function()
                    chunk()
                end)
                
                -- Опционально: можно отправить подтверждение, но протокол этого не требует явно
                print("[VSCode] Script executed successfully")
            end
        end
    end
end

-- 3. Отправка логов из Roblox в VS Code (client/console/*)
local function setupLogHook()
    LogService.MessageOut:Connect(function(message, type)
        if not socket or not isConnected then return end

        local opCode = "client/console/print" -- Default

        if type == Enum.MessageType.MessageOutput then
            opCode = "client/console/print"
        elseif type == Enum.MessageType.MessageInfo then
            opCode = "client/console/info"
        elseif type == Enum.MessageType.MessageWarning then
            opCode = "client/console/warning"
        elseif type == Enum.MessageType.MessageError then
            opCode = "client/console/error"
        end

        -- Фильтрация наших собственных служебных сообщений, чтобы избежать спама
        if message:find("%[VSCode%-Link%]") then return end

        local payload = {
            op = opCode,
            data = {
                message = message
            }
        }

        local json = safeEncode(payload)
        if json then
            socket:Send(json)
        end
    end)
end

--------------------------------------------------------------------------------
-- Управление соединением
--------------------------------------------------------------------------------

local function connect()
    if isConnected then return end

    print("[VSCode-Link] Attempting to connect to " .. URL)

    local success, err = pcall(function()
        -- Используем библиотеку WebSocket из SUNC (предполагаем стандартный интерфейс WebSocket.connect)
        if not WebSocket or not WebSocket.connect then
            error("WebSocket library not found in SUNC!")
        end
        
        socket = WebSocket.connect(URL)
    end)

    if success and socket then
        isConnected = true
        print("[VSCode-Link] Connected!")

        -- Настраиваем обработчики событий сокета
        socket.OnMessage:Connect(onMessage)
        
        socket.OnClose:Connect(function()
            isConnected = false
            print("[VSCode-Link] Connection closed. Retrying in 5s...")
            socket = nil
        end)

        -- Сразу отправляем Identification пакет
        sendIdentify()
    else
        warn("[VSCode-Link] Connection failed: " .. tostring(err))
    end
end

-- Инициализация хука логов (делаем один раз)
setupLogHook()

-- Цикл поддержания соединения (Keep-Alive / Reconnect)
task.spawn(function()
    while true do
        if not isConnected or not socket then
            connect()
        end
        task.wait(5) -- Проверка каждые 5 секунд
    end
end)