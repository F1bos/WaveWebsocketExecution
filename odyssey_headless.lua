local brainrot_game_id = 7709344486

if game.GameId ~= brainrot_game_id then
    return
end

local BYPASS_ALLOWED_USERNAMES = false

-- Список скриптов для загрузки (через запятую)
local scriptsToLoad = {
    "Odyssey SAB",
    -- 'Brainrot Finder Panel'
}

-- getgenv().incognito = true
-- getgenv().use_public_gateway = true
-- odyssey_key = '9ef57dc7-f019-45c4-9ce4-011ca32c6626'
-- getgenv().DISABLE_ADVANCED_MODE = true
-- getgenv().FORCE_OPEN_BUTTON = true
-- getgenv().WINDUI_SEARCH_DEBUG = true

-- getgenv().raknet.add_send_hook = nil
-- getgenv().raknet.desync = function ()
    
-- end

if not BYPASS_ALLOWED_USERNAMES then
    -- -- Игнорируемые пользователи
    local ignored_usernames = {
        'mega_abobasc2',
        -- 'mega_abobasc',
        -- 'abobiumnumber1',
        -- 'OldZave_47',
        -- 'robafellohoha359',
        -- 'Blast_Power90',
        -- 'Ven0mMystic2018'
        -- 'abobiumonly',
        -- 'MisterJoshua04'
    }

    local Players = game:GetService("Players")

    -- === ФИКС: Ожидание инициализации LocalPlayer ===
    -- В режиме Pre-ReplicatedFirst LocalPlayer может быть nil при старте.
    -- Ждем, пока свойство LocalPlayer не будет установлено.
    if not Players.LocalPlayer then
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    end
    local LocalPlayer = Players.LocalPlayer
    -- ================================================

    if table.find(ignored_usernames, LocalPlayer.Name) then
        warn("Ignoring user:", LocalPlayer.Name)
        return
    end
end

-- Адрес вашего сервера
-- local WEBSOCKET_URL = "ws://abobahost:8765"
local WEBSOCKET_URL = "ws://192.168.137.1:8765"

if not WebSocket then
    warn("WebSocket library not found!")
    return
end

-- Основные сервисы Roblox
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- Таблицы и переменные состояния
local loadedScripts = {}
local Socket
local isConnected = false

-- Подключение к WebSocket
Socket = WebSocket.connect(WEBSOCKET_URL)

if not Socket then
    warn("Failed to connect to the WebSocket server.")
    return
end

isConnected = true
print("Connected to server. Requesting script list...")

local function safeLoadstring(code)
    local func, compileErr = loadstring(code)
    if not func then
        return nil, "Compile error: " .. tostring(compileErr)
    end
    local success, result = pcall(func)
    if not success then
        return nil, "Runtime error: " .. tostring(result)
    end
    return result
end

-- Обработчик входящих сообщений от сервера
Socket.OnMessage:Connect(function(message)
    local success, data = pcall(function() return HttpService:JSONDecode(message) end)
    if not success then return end

    if data.action == "script_list" then
        local serverScripts = data.scripts
        
        for _, scriptName in ipairs(scriptsToLoad) do
            if table.find(serverScripts, scriptName) and not table.find(loadedScripts, scriptName) then
                -- Запрашиваем загрузку скрипта
                local requestPayload = HttpService:JSONEncode({
                    action = "load_scripts",
                    scripts = {scriptName}
                })
                Socket:Send(requestPayload)
            end
        end

    elseif data.action == "load_script" then
        local scriptName = data.name
        local scriptCode = data.code
        
        if table.find(scriptsToLoad, scriptName) and not table.find(loadedScripts, scriptName) then
            -- task.spawn(function ()
            --     local loadSuccess, err = pcall(function() loadstring(scriptCode)() end)

            --     if loadSuccess then
            --         table.insert(loadedScripts, scriptName)
            --         print("Script '"..scriptName.."' loaded successfully!")
            --     else
            --         warn("Failed to load script '"..scriptName.."':", err)
            --     end
            -- end)

            local loadSuccess, err = safeLoadstring(scriptCode)

            if loadSuccess then
                table.insert(loadedScripts, scriptName)
                print("Script '"..scriptName.."' loaded successfully!")
            else
                print("Failed to load script '"..scriptName.."':", err)
            end
        end
    
    elseif data.action == "script_updated" then
        local updatedScriptName = data.name
        
        print("Received update notification for script:", updatedScriptName)
        if table.find(scriptsToLoad, updatedScriptName) then
            print("Script '" .. updatedScriptName .. "' was updated. Reloading game...")
            task.spawn(function()
                TeleportService:TeleportReconnect()
            end)
        end
    end
end)

Socket.OnClose:Connect(function()
    isConnected = false
    warn("Lost connection to the server.")
end)

-- Запрос начального списка скриптов
local initialRequest = HttpService:JSONEncode({action = "get_list"})
Socket:Send(initialRequest)
