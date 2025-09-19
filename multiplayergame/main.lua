-- CHANGE LOG:
-- problem with host playing game causing guest disconnect. 
-- problem with only host being able to change colors.


local enet = require "enet"
local anim8 = require "anim8"
local jumpGame = require "jumpgame"
local laserGame = require "lasergame"
local duelGame = require "duelgame"
local raceGame = require "racegame"
local characterCustomization = require "charactercustom"
local debugConsole = require "debugconsole"
local musicHandler = require "musichandler"
local instructions = require "instructions"
local returnState = "playing"
local afterCustomization = nil
local connectionAttempted = false
local statusMessages = {}
local host
local server
local peerToId = {}
local connected = false
local players = {}
local localPlayer = {x = 100, y = 100, color = {1, 0, 0}, id = 0, totalScore = 0}
local serverStatus = "Unknown"
local nextClientId = 1
local menuBackground = nil
local lobbyBackground = nil
local partyMode = false
local currentPartyGame = nil
local partyMode = false
local currentPartyGame = nil
local isFirstPartyInstruction = true

local gameState = "menu"  -- Can be "menu", "connecting", "customization", "playing", or "hosting"
local highScore = 0 -- this is high score for jumpgame
local inputIP = "localhost"
local inputPort = "12345"


-- How to add effects to objects:
-- musicHandler.addEffect("player", "bounce") -- Makes player bounce up and down
-- musicHandler.addEffect("enemy", "pulse") -- Makes enemy pulse in size
-- musicHandler.addEffect("background", "colorPulse", {
--     baseColor = {0.5, 0, 1}, -- Purple
--     frequency = 2 -- Twice per beat
-- })


-- UI elements
local buttons = {}
local inputField = {x = 300, y = 250, width = 200, height = 30, text = "localhost", active = false}

-- Server variables
local serverHost
local serverClients = {}

-- Networking variables
local updateRate = 1/20  -- 20 updates per second
local updateTimer = 0

-- Physics variables
local fixedTimestep = 1/60  -- 60 physics updates per second
local accumulatedTime = 0

-- Debug log system
local debugLog = {}
local MAX_DEBUG_MESSAGES = 10

function addDebugMessage(msg)
    table.insert(debugLog, 1, os.date("%H:%M:%S") .. ": " .. msg)
    if #debugLog > MAX_DEBUG_MESSAGES then
        table.remove(debugLog)
    end
end

function safeSend(peer, message)
    if peer and peer.send then
        local success, err = pcall(function()
            peer:send(message)
        end)
        if not success then
            debugConsole.addMessage("Failed to send message: " .. tostring(err))
        end
    else
        debugConsole.addMessage("Warning: Attempted to send to invalid peer")
    end
end

function love.load() -- music effect
    players = {}
    debugConsole.init()
    characterCustomization.init()
    love.keyboard.setKeyRepeat(true)
    musicHandler.loadMenuMusic()
    instructions.load()
    duelGame.load()


    -- load background
    menuBackground = love.graphics.newImage("menu-background.jpg")
    lobbyBackground = love.graphics.newImage("menu-background.jpg")

    -- gif frames synced with BPM
    titleGifSprite = love.graphics.newImage("title.png") 
    titleGifSprite:setFilter("nearest", "nearest") -- keeps image sharp no matter the scale
    local g = anim8.newGrid(71, 32, titleGifSprite:getWidth(), titleGifSprite:getHeight()) 
    titleGifAnim = anim8.newAnimation(g('1-5','1-4'), (60/musicHandler.bpm) / 8) 

    -- Create buttons
    buttons.host = {x = 300, y = 150, width = 200, height = 50, text = "Host Game"}
    buttons.join = {x = 300, y = 220, width = 200, height = 50, text = "Join Game"}
    buttons.start = {x = 300, y = 300, width = 200, height = 50, text = "Start", visible = false}

    -- Clear any existing effects first
    musicHandler.removeEffect("host_button")
    musicHandler.removeEffect("join_button")
    musicHandler.removeEffect("menu_bg")
    musicHandler.removeEffect("title")

    musicHandler.addEffect("host_button", "combo", {
        scaleAmount = 0.1,      -- Pulse up to 20% bigger
        rotateAmount = math.pi/64,  -- Small rotation
        frequency = 1,          -- Once per beat
        phase = 0,              -- Start of beat
        snapDuration = 1.0    -- Quick snap
    })

    musicHandler.addEffect("join_button", "combo", {
        scaleAmount = 0.1,
        rotateAmount = math.pi/64,
        frequency = 1,
        phase = 0.5,   -- Opposite timing
        snapDuration = 1.0
    })

    musicHandler.addEffect("menu_bg", "bounce", {
        amplitude = 5,
        frequency = 0.5,
        phase = 0
    })

    musicHandler.addEffect("title", "combo", {
        scaleAmount = 0.1,      
        rotateAmount = 0,  
        frequency = 1.5,          
        phase = 1,             
        snapDuration = 0.1    
    })

    checkServerStatus()
    jumpGame.load()
end

function love.update(dt)
    musicHandler.update(dt)
    instructions.update(dt)

    -- Track actual game transitions
    if gameState == "jumpgame" then
        currentPartyGame = "jumpgame"
    elseif gameState == "lasergame" then
        currentPartyGame = "lasergame"
    elseif gameState == "duelgame" then
        currentPartyGame = "duelgame"
    elseif gameState == "racegame" then
        currentPartyGame = "racegame"
    end

    -- Only check party mode transitions when we're actually in the lobby
    if partyMode and gameState == "hosting" and not instructions.isTransitioning then
        if currentPartyGame == "jumpgame" then
            instructions.clear()    
            love.keypressed("2")
            currentPartyGame = "lasergame"
        elseif currentPartyGame == "lasergame" then
            instructions.clear()    
            love.keypressed("3")
            currentPartyGame = "duelgame"
        elseif currentPartyGame == "duelgame" then
            instructions.clear()    
            love.keypressed("4")  
            currentPartyGame = "racegame"
        elseif currentPartyGame == "racegame" then 
            instructions.clear()    
            love.keypressed("1")
            currentPartyGame = "jumpgame"
        end
    end

    if partyMode then
        if gameState == "jumpgame" then
            currentPartyGame = "jumpgame"
        elseif gameState == "lasergame" then
            currentPartyGame = "lasergame"
        elseif gameState == "duelgame" then
            currentPartyGame = "duelgame"
        elseif gameState == "racegame" then
            currentPartyGame = "racegame"
        end
    end

    if gameState == "menu" then
        titleGifAnim:update(dt)
    end

    if gameState == "menu" then
        if not musicHandler.isPlaying then
            musicHandler.loadMenuMusic()
        end
        musicHandler.clearEffects()
    elseif gameState == "customization" then
        if not musicHandler.isPlaying then
            musicHandler.loadMenuMusic()
        end
        musicHandler.applyCustomizationEffect()
    else
        -- Only stop music if we're not in party mode
        if not partyMode then
            musicHandler.stopMusic()
        end
        musicHandler.clearEffects()
    end

    if gameState == "jumpgame" then
        if returnState == "hosting" then
            updateServer()
        else
            updateClient()
        end

        jumpGame.update(dt)

        if jumpGame.game_over then
            debugConsole.addMessage("Jump game over, returning to state: " .. returnState)
            if returnState == "hosting" then
                if players[localPlayer.id] then
                    players[localPlayer.id].totalScore = (players[localPlayer.id].totalScore or 0) + jumpGame.current_round_score
                    localPlayer.totalScore = players[localPlayer.id].totalScore
                end
                for _, client in ipairs(serverClients) do
                    safeSend(client, string.format("total_score,%d,%d", localPlayer.id, localPlayer.totalScore))
                end
            else
                if server and connected then
                    safeSend(server, "jump_score," .. jumpGame.current_round_score)
                end
            end
            gameState = returnState
            debugConsole.addMessage("Returned to state: " .. gameState)
            jumpGame.reset()
        end
    elseif gameState == "lasergame" then
        if returnState == "hosting" then
            updateServer()
        else
            updateClient()
        end

        laserGame.update(dt)

        if connected then
            local message = string.format("laser_position,%d,%.2f,%.2f,%.2f,%.2f,%.2f",
                localPlayer.id or 0,
                laserGame.player.x,
                laserGame.player.y,
                localPlayer.color[1],
                localPlayer.color[2],
                localPlayer.color[3]
            )
            if returnState == "hosting" then
                for _, client in ipairs(serverClients) do
                    safeSend(client, message)
                end
            else
                safeSend(server, message)
            end
        end

        if laserGame.game_over then
            debugConsole.addMessage("Laser game transitioning to: " .. returnState)
            
            if not laserGame.is_dead then
                local finalScore = math.floor(laserGame.current_round_score)
                
                if returnState == "hosting" then
                    if players[localPlayer.id] then
                        local previousTotal = players[localPlayer.id].totalScore or 0
                        players[localPlayer.id].totalScore = previousTotal + finalScore
                        localPlayer.totalScore = players[localPlayer.id].totalScore
                        
                        debugConsole.addMessage(string.format("[Score] Host: Added %d to total, now: %d", 
                            finalScore, localPlayer.totalScore))
                        
                        for _, client in ipairs(serverClients) do
                            safeSend(client, string.format("total_score,%d,%d", 
                                localPlayer.id, localPlayer.totalScore))
                        end
                    end
                else
                    if server and connected then
                        safeSend(server, "laser_score," .. finalScore)
                        debugConsole.addMessage(string.format("[Score] Client: Sending final score: %d", finalScore))
                    end
                end
            end
            
            gameState = returnState
        end
    elseif gameState == "duelgame" then
        if returnState == "hosting" then
            updateServer()
        else
            updateClient()
        end

        duelGame.update(dt)

        if duelGame.game_over then
            debugConsole.addMessage("Duel game over, returning to state: " .. returnState)
            if returnState == "hosting" then
                if players[localPlayer.id] then
                    players[localPlayer.id].totalScore = 
                        (players[localPlayer.id].totalScore or 0) + duelGame.current_round_score
                    localPlayer.totalScore = players[localPlayer.id].totalScore
                end
                for _, client in ipairs(serverClients) do
                    safeSend(client, string.format("total_score,%d,%d", 
                        localPlayer.id, localPlayer.totalScore))
                end
            else
                if server and connected then
                    safeSend(server, "duel_score," .. duelGame.current_round_score)
                end
            end
            gameState = returnState
            debugConsole.addMessage("Returned to state: " .. gameState)
        end
    elseif gameState == "hosting" then
        updateServer()
    elseif gameState == "playing" or gameState == "connecting" then
        updateClient()
    elseif gameState == "racegame" then
        if returnState == "hosting" then
            updateServer()
        else
            updateClient()
        end

        raceGame.update(dt)  -- This was likely missing

        if raceGame.game_over then
            debugConsole.addMessage("Race game over, returning to state: " .. returnState)
            if returnState == "hosting" then
                if players[localPlayer.id] then
                    players[localPlayer.id].totalScore = 
                        (players[localPlayer.id].totalScore or 0) + raceGame.current_round_score
                    localPlayer.totalScore = players[localPlayer.id].totalScore
                end
                for _, client in ipairs(serverClients) do
                    safeSend(client, string.format("total_score,%d,%d", 
                        localPlayer.id, localPlayer.totalScore))
                end
            else
                if server and connected then
                    safeSend(server, "race_score," .. raceGame.current_round_score)
                end
            end
            gameState = returnState
            debugConsole.addMessage("Returned to state: " .. gameState)
        end
    end
    accumulatedTime = accumulatedTime + dt
    while accumulatedTime >= fixedTimestep do
        updatePhysics(fixedTimestep)
        accumulatedTime = accumulatedTime - fixedTimestep
    end
end

function updatePhysics(dt)
    if gameState == "hosting" or gameState == "playing" then
        local moved = false
        if love.keyboard.isDown('w') then
            localPlayer.y = localPlayer.y - 200 * dt
            moved = true
        elseif love.keyboard.isDown('s') then
            localPlayer.y = localPlayer.y + 200 * dt
            moved = true
        end
        if love.keyboard.isDown('a') then
            localPlayer.x = localPlayer.x - 200 * dt
            moved = true
        elseif love.keyboard.isDown('d') then
            localPlayer.x = localPlayer.x + 200 * dt
            moved = true
        end
        
        if moved and localPlayer.id ~= nil then
            -- Update local player's position in the players table while preserving all data
            local existingFacePoints = players[localPlayer.id] and players[localPlayer.id].facePoints
            local existingScore = players[localPlayer.id] and players[localPlayer.id].totalScore or 0
            players[localPlayer.id] = {
                x = localPlayer.x,
                y = localPlayer.y,
                color = localPlayer.color,
                id = localPlayer.id,
                totalScore = existingScore,
                facePoints = existingFacePoints or localPlayer.facePoints
            }
        end
    end
end

function updateServer()
    if not serverHost then return end

    -- sends positions and colors in lobby
    for _, client in ipairs(serverClients) do
        safeSend(client, string.format("0,%d,%d,%.2f,%.2f,%.2f", 
            math.floor(localPlayer.x), 
            math.floor(localPlayer.y),
            localPlayer.color[1],
            localPlayer.color[2],
            localPlayer.color[3]
        ))
    end

    -- send jump game positions
    if gameState == "jumpgame" then
        local jumpX = jumpGame.player.rect.x
        local jumpY = jumpGame.player.rect.y 
        
        for _, client in ipairs(serverClients) do
            safeSend(client, string.format("jump_position,0,%.2f,%.2f,%.2f,%.2f,%.2f",
                jumpX, jumpY,
                localPlayer.color[1], localPlayer.color[2], localPlayer.color[3]))
        end
    end

    -- Handle network events
    local event = serverHost:service(0)
    while event do
        if event.type == "connect" then
            if event.peer then
                local clientId = nextClientId
                nextClientId = nextClientId + 1
                peerToId[event.peer] = clientId
                
                table.insert(serverClients, event.peer)
                players[clientId] = {
                    x = 100, 
                    y = 100, 
                    id = clientId,
                    color = {0, 0, 1}  -- Default blue color until client sends their color
                }
                
                safeSend(event.peer, "your_id," .. clientId)
                
                -- Send existing players to new client
                for id, player in pairs(players) do
                    -- Send position and color
                    safeSend(event.peer, string.format("new_player,%d,%d,%d,%.2f,%.2f,%.2f",
                        id, math.floor(player.x), math.floor(player.y),
                        player.color[1], player.color[2], player.color[3]))
                    
                    -- Send face data if it exists
                    if player.facePoints then
                        local faceData = serializeFacePoints(player.facePoints)
                        if faceData then
                            safeSend(event.peer, "face_data," .. id .. "," .. faceData)
                            debugConsole.addMessage("[Server] Sent player " .. id .. "'s face to new client")
                        end
                    end
                end
            end
        elseif event.type == "receive" then
            if event.peer then
                local clientId = peerToId[event.peer]
                if clientId then
                    handleServerMessage(clientId, event.data)
                end
            end
        elseif event.type == "disconnect" then
            if event.peer then
                local clientId = peerToId[event.peer]
                if clientId and players[clientId] then
                    players[clientId] = nil
                    -- Notify other clients
                    for _, client in ipairs(serverClients) do
                        if client ~= event.peer then
                            safeSend(client, "player_disconnect," .. clientId)
                        end
                    end
                    -- Remove from clients list
                    for i, client in ipairs(serverClients) do
                        if client == event.peer then
                            table.remove(serverClients, i)
                            break
                        end
                    end
                    peerToId[event.peer] = nil
                end
            end
        end
        
        event = serverHost:service(0)
    end
end

function updateClient()
    if not host then return end

    -- Handle network events
    local success, err = pcall(function()
        local event = host:service(0)
        while event do
            if event.type == "connect" then
                connected = true
                gameState = "playing"
            elseif event.type == "receive" then
                handleClientMessage(event.data)
            elseif event.type == "disconnect" then
                handleDisconnection()
            end
            event = host:service(0)
        end
    end)

    if not success then
        handleDisconnection()
        return
    end

    -- sends regular position updates
    if connected and localPlayer.id then
        if gameState == "playing" then
            local message = string.format("%d,%d,%d,%.2f,%.2f,%.2f",
                localPlayer.id,
                math.floor(localPlayer.x),
                math.floor(localPlayer.y),
                localPlayer.color[1],
                localPlayer.color[2],
                localPlayer.color[3]
            )
            safeSend(server, message)
        end

        -- jump game positions
        if gameState == "jumpgame" then
            local jumpX = jumpGame.player.rect.x
            local jumpY = jumpGame.player.rect.y
            safeSend(server, string.format("jump_position,%d,%.2f,%.2f,%.2f,%.2f,%.2f",
                localPlayer.id, jumpX, jumpY,
                localPlayer.color[1], localPlayer.color[2], localPlayer.color[3]))
        end
    end
end

function love.draw()
    if gameState == "jumpgame" then
        jumpGame.draw(players, localPlayer.id)
    elseif gameState == "lasergame" then
        love.graphics.setColor(1, 1, 1, 1)
        laserGame.draw(players, localPlayer.id)
    elseif gameState == "duelgame" then
        duelGame.draw()
    elseif gameState == "racegame" then
        raceGame.draw(players, localPlayer.id)
    elseif gameState == "menu" then
        local bgx, bgy = musicHandler.applyToDrawable("menu_bg", 0, 0) --changes for music effect
        local scale = 3
        local frameWidth = 71 * scale
        local ex, ey, er, esx, esy = musicHandler.applyToDrawable("title", love.graphics.getWidth()/2, 100) -- for music effect
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(menuBackground, bgx, bgy) --changes for music effect
        titleGifAnim:draw(titleGifSprite, ex, ey, er or 0, scale * (esx or 1), scale * (esx or 1), 71/2, 32/2)

        drawButton(buttons.host, "host_button")
        drawButton(buttons.join, "join_button")

        love.graphics.setColor(1, 1, 1)  
        love.graphics.printf("Server Status: " .. serverStatus, 0, 400, love.graphics.getWidth(), "center")
    elseif gameState == "customization" then
        characterCustomization.draw()
    elseif gameState == "connecting" then
        love.graphics.printf("Connecting to " .. inputField.text .. ":" .. inputPort, 
            0, 100, love.graphics.getWidth(), "center")
        drawInputField()
        drawButton(buttons.start)
    elseif gameState == "playing" or gameState == "hosting" then
        -- Draw background
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(lobbyBackground, 0, 0)

        
        
        -- Draw all players
        for id, player in pairs(players) do
            if player and player.color then
                -- Draw player square
                love.graphics.setColor(player.color[1], player.color[2], player.color[3])
                love.graphics.rectangle("fill", player.x, player.y, 50, 50)
                
                -- Draw face image if it exists
                if player.facePoints and type(player.facePoints) == "userdata" then
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(
                        player.facePoints,
                        player.x,
                        player.y,
                        0,
                        50/100,
                        50/100
                    )
                end
                
                -- Draw player score instead of ID
                love.graphics.setColor(1, 1, 0)  -- Yellow color for score
                love.graphics.printf(
                    "Score: " .. math.floor(player.totalScore or 0),
                    player.x - 30,
                    player.y - 25,
                    120,
                    "center"
                )
                
                -- Draw position info for debugging
                love.graphics.setColor(1, 1, 1)
                love.graphics.print(string.format(
                    "x: %.0f\ny: %.0f", 
                    player.x,
                    player.y
                ), player.x + 55, player.y)
            end
        end
        
        if gameState ~= "instructions" then
            love.graphics.setColor(1, 1, 0)
            love.graphics.printf("(1) Jump Game, (2) Laser Game, (3) Duel Game, (4) Race Game, (P) Party Mode", 
                0, love.graphics.getHeight() - 30, love.graphics.getWidth(), "center")
        end
    end

    -- Draw instructions overlay last (if showing)
    if instructions.showing then
        instructions.draw()
    end

    -- Draw FPS counter (always visible)
    love.graphics.setColor(1, 1, 1)
    local fps = love.timer.getFPS()
    love.graphics.print(string.format("FPS: %d", fps), 
        love.graphics.getWidth() - 80, 30)

    -- Draw connection info (always visible)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Game State: " .. gameState, 10, 30)
    love.graphics.print("Players: " .. #table_keys(players), 10, 50)

    -- Draw debug console last so it's always on top
    debugConsole.draw()
end

function drawButton(button, effectId)
    if button.visible == false then return end
    
    local x, y, r = button.x, button.y, 0
    local sx, sy = 1, 1  -- Default scale values
    
    if effectId then
        -- Get ALL transform values including scale
        x, y, r, sx, sy = musicHandler.applyToDrawable(effectId, x, y)
        -- Debug print
        print(effectId, "scale:", sx, sy)
    end
    
    love.graphics.push()
    
    -- Move to button center for rotation AND scaling
    love.graphics.translate(x + button.width/2, y + button.height/2)
    if r then 
        love.graphics.rotate(r)
    end
    -- Apply scale BEFORE moving back
    love.graphics.scale(sx, sy)
    love.graphics.translate(-button.width/2, -button.height/2)
    
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.rectangle("fill", 0, 0, button.width, button.height)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(button.text, 0, 15, button.width, "center")
    
    love.graphics.pop()
end

function drawInputField()
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 
        inputField.x, inputField.y, inputField.width, inputField.height)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(inputField.text, 
        inputField.x + 5, inputField.y + 5, inputField.width - 10, "left")
    if inputField.active then
        love.graphics.rectangle("line", 
            inputField.x, inputField.y, inputField.width, inputField.height)
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then  -- Left mouse button
        if gameState == "menu" then
            if isMouseOver(buttons.host) then
                gameState = "customization"
                afterCustomization = "host"
            elseif isMouseOver(buttons.join) then
                gameState = "customization"
                afterCustomization = "join"
            end
        elseif gameState == "customization" then
            local result = characterCustomization.mousepressed(x, y, button)
            if result == "confirm" then
                -- Apply the selected color and face to localPlayer
                localPlayer.color = characterCustomization.getCurrentColor()
                localPlayer.facePoints = characterCustomization.faceCanvas
                debugConsole.addMessage("[Customization] Face saved successfully")
                
                -- Proceed with the stored action
                if afterCustomization == "host" then
                    startServer()
                elseif afterCustomization == "join" then
                    gameState = "connecting"
                    buttons.start.visible = true
                end
            end
        elseif gameState == "connecting" and isMouseOver(buttons.start) then
            startNetworking()
        elseif isMouseOver(inputField) then
            inputField.active = true
        else
            inputField.active = false
        end
    end
end

function love.keypressed(key)
    if key == "f3" then  
        debugConsole.toggle()
    end

    if gameState == "connecting" and inputField.active then
        if key == "backspace" then
            inputField.text = inputField.text:sub(1, -2)
        end
    end

    if gameState == "racegame" then
        raceGame.keypressed(key)
        return
    end

    -- Only allow host to start games
    if key == "1" or key == "2" or key == "3" or key == "4" then
        if gameState ~= "hosting" then
            debugConsole.addMessage("[Game] Only the host can start games")
            return
        end
        
        if key == "1" then
            -- Notify clients BEFORE showing host instructions
            for _, client in ipairs(serverClients) do
                safeSend(client, "show_jump_instructions")
            end
            
            instructions.show("jumpgame", function()
                -- Start party music only after the first instruction if in party mode
                if partyMode and isFirstPartyInstruction then
                    musicHandler.loadPartyMusic()
                    isFirstPartyInstruction = false  -- Clear the flag
                    debugConsole.addMessage("[Party Mode] Starting music after first instruction")
                end
        
                gameState = "jumpgame"
                returnState = "hosting"
                jumpGame.reset(players)
                jumpGame.setPlayerColor(localPlayer.color)
        
                -- Only send game start after instructions
                for _, client in ipairs(serverClients) do
                    safeSend(client, "start_jump_game")
                    if partyMode and isFirstPartyInstruction then
                        safeSend(client, "start_party_music")
                    end
                end
            end)
        elseif key == "2" then
            -- Notify clients BEFORE showing host instructions
            for _, client in ipairs(serverClients) do
                safeSend(client, "show_laser_instructions")
            end
            
            instructions.show("lasergame", function()
                gameState = "lasergame"
                returnState = "hosting"
                local seed = os.time() + love.timer.getTime() * 10000
                laserGame.reset()
                laserGame.setSeed(seed)
                laserGame.setPlayerColor(localPlayer.color)
                
                -- Only send game start after instructions
                for _, client in ipairs(serverClients) do
                    safeSend(client, "start_laser_game," .. seed)
                end
            end)
        elseif key == "3" then
            -- Notify clients BEFORE showing host instructions
            for _, client in ipairs(serverClients) do
                safeSend(client, "show_duel_instructions")
            end
            
            instructions.show("duelgame", function()
                gameState = "duelgame"
                returnState = "hosting"
                duelGame.reset()
                
                -- Only send game start after instructions
                for _, client in ipairs(serverClients) do
                    safeSend(client, "start_duel_game")
                end
            end)
        elseif key == "4" then
            for _, client in ipairs(serverClients) do
                safeSend(client, "show_race_instructions")
            end
            
            instructions.show("racegame", function()
                gameState = "racegame"
                returnState = "hosting"
                local seed = os.time() + love.timer.getTime() * 10000
                raceGame.reset()
                raceGame.setPlayerColor(localPlayer.color)
                
                -- Only send game start after instructions
                for _, client in ipairs(serverClients) do
                    safeSend(client, "start_race_game," .. seed)
                end
            end)
        end
    end
    if key == "p" then
        if gameState == "hosting" then
            partyMode = not partyMode
            debugConsole.addMessage("[Party Mode] " .. (partyMode and "Enabled" or "Disabled"))
            if partyMode then
                isFirstPartyInstruction = true  -- Reset the flag when party mode starts
                -- Start with jump game by simulating '1' key press
                debugConsole.addMessage("[Party Mode] Starting initial Jump game")
                currentPartyGame = nil  -- Reset this so we start fresh
                love.keypressed("1")    -- Start with jump game through instructions
            else
                -- Return to lobby when party mode is turned off
                gameState = "hosting"
                currentPartyGame = nil
                musicHandler.stopMusic()  -- Only stop music when party mode ends
                
                -- Broadcast party mode end to clients
                for _, client in ipairs(serverClients) do
                    safeSend(client, "end_party_mode")
                end
            end
        end
    end

    if gameState == "duelgame" then
        duelGame.keypressed(key)
    end
end

function love.textinput(t)
    if inputField.active then
        inputField.text = inputField.text .. t
    end
end

function drawInputField()
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", inputField.x, inputField.y, inputField.width, inputField.height)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(inputField.text, inputField.x + 5, inputField.y + 5, inputField.width - 10, "left")
    if inputField.active then
        love.graphics.rectangle("line", inputField.x, inputField.y, inputField.width, inputField.height)
    end
end

function isMouseOver(item)
    local mx, my = love.mouse.getPosition()
    return mx > item.x and mx < item.x + item.width and my > item.y and my < item.y + item.height
end

function addStatusMessage(msg)
    debugConsole.addMessage("[Status] " .. msg)
end

function startServer()
    serverHost = enet.host_create("0.0.0.0:12345")
    if not serverHost then
        debugConsole.addMessage("[Server] Failed to create server")
        return
    end
    debugConsole.addMessage("[Server] Started on 0.0.0.0:12345")
    
    players = {}
    peerToId = {}
    localPlayer.id = 0  -- Ensure host ID is set
    
    -- Create initial player entry with correct data
    players[localPlayer.id] = {
        x = localPlayer.x,
        y = localPlayer.y,
        color = localPlayer.color,
        id = localPlayer.id,
        facePoints = characterCustomization.faceCanvas  -- Store the canvas directly for the host
    }
    
    nextClientId = 1
    gameState = "hosting"
    connected = true
    serverStatus = "Running"
    debugConsole.addMessage("[Server] Server started with face data")
end

function startNetworking()
    debugConsole.addMessage("[Client] Creating host...")
    host = enet.host_create()
    if not host then
        debugConsole.addMessage("[Client] Failed to create host")
        return
    end
    
    local address = inputField.text .. ":" .. inputPort
    debugConsole.addMessage("[Client] Connecting to " .. address .. "...")
    server = host:connect(address)
    if not server then
        debugConsole.addMessage("[Client] Failed to connect to server at " .. address)
        return
    end
    
    debugConsole.addMessage("[Client] Connection attempt sent...")
    gameState = "connecting"
    
    -- Initialize local player with correct data
    local savedColor = localPlayer.color
    local savedFace = localPlayer.facePoints
    localPlayer = {
        x = 100,
        y = 100,
        color = savedColor,
        facePoints = savedFace,  -- Preserve face data
        id = nil
    }
    players = {}
end

function handleDisconnection()
    if gameState == "jumpgame" then
        jumpGame.game_over = true
    end
    gameState = "menu"
    connected = false
    players = {}
    debugConsole.addMessage("[Connection] Disconnected from server. Returning to main menu.")
end

function handleServerMessage(id, data)
    -- Handle scores from both games
    if data:match("^jump_score,(%d+)") or data:match("^laser_score,(%d+)") then
        local score = math.floor(tonumber(data:match(",(%d+)")))
        debugConsole.addMessage("[Score] Server received score: " .. score)
        if score then
            if not players[id] then
                players[id] = {totalScore = 0}
            end
            players[id].totalScore = math.floor((players[id].totalScore or 0) + score)
            
            -- Broadcast updated score to all clients
            for _, client in ipairs(serverClients) do
                safeSend(client, string.format("total_score,%d,%d", id, math.floor(players[id].totalScore)))
            end
            debugConsole.addMessage(string.format("[Score] Server: Player %d scored %d points, total now %d", 
                id, score, players[id].totalScore))
        end
        return
    end

    -- Handle face data
    if data:match("^face_data,") then
        local face_id, face_points = data:match("^face_data,(%d+),(.+)")
        face_id = tonumber(face_id)
        if face_id and players[face_id] then
            local faceImage = deserializeFacePoints(face_points)
            if faceImage then
                players[face_id].facePoints = faceImage
                debugConsole.addMessage("[Server] Received face data for player " .. face_id)
                
                -- Forward face data to other clients
                for _, client in ipairs(serverClients) do
                    safeSend(client, data)
                end
            end
        end
        return
    end

    if data:match("^duel_score,(%d+)") then
        local score = tonumber(data:match(",(%d+)"))
        if score then
            if not players[id] then players[id] = {totalScore = 0} end
            players[id].totalScore = (players[id].totalScore or 0) + score
            
            -- Broadcast updated score
            for _, client in ipairs(serverClients) do
                safeSend(client, string.format("total_score,%d,%d", id, players[id].totalScore))
            end
        end
        return
    end

    -- Handle jump game positions
    if data:match("jump_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)") then
        local playerId, x, y, r, g, b = data:match("jump_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
        playerId = tonumber(playerId)
        if not players[playerId] then
            players[playerId] = {}
        end
        players[playerId].jumpX = tonumber(x)
        players[playerId].jumpY = tonumber(y)
        players[playerId].color = {tonumber(r), tonumber(g), tonumber(b)}
        
        for _, client in ipairs(serverClients) do
            safeSend(client, string.format("jump_position,%d,%.2f,%.2f,%.2f,%.2f,%.2f",
                playerId, x, y, r, g, b))
        end
        return
    end

    -- Handle laser game requests
    if data:match("^request_laser_game") then
        local seed = os.time() + love.timer.getTime() * 10000
        instructions.show("lasergame", function()
            for _, client in ipairs(serverClients) do
                safeSend(client, "start_laser_game," .. seed)
            end
            gameState = "lasergame"
            returnState = "hosting"
            laserGame.load()
            laserGame.setSeed(seed)
            laserGame.setPlayerColor(localPlayer.color)
        end)
        return
    end

    -- Handle laser positions
    if data:match("^laser_position,") then
        local id, x, y, r, g, b = data:match("laser_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
        id = tonumber(id)
        if id and id ~= localPlayer.id then
            if not players[id] then
                players[id] = {}
            end
            players[id].laserX = tonumber(x)
            players[id].laserY = tonumber(y)
            players[id].color = {tonumber(r), tonumber(g), tonumber(b)}
            
            for _, client in ipairs(serverClients) do
                safeSend(client, data)
            end
        end
        return
    end

    -- Handle regular position and color updates
    local id_from_msg, x, y, r, g, b = data:match("(%d+),(%d+),(%d+),([%d.]+),([%d.]+),([%d.]+)")
    if id_from_msg and x and y and r and g and b then
        id_from_msg = tonumber(id_from_msg)
        x = tonumber(x)
        y = tonumber(y)
        r, g, b = tonumber(r), tonumber(g), tonumber(b)
        
        local existingFacePoints = players[id_from_msg] and players[id_from_msg].facePoints
        local existingScore = players[id_from_msg] and players[id_from_msg].totalScore or 0
        
        if not players[id_from_msg] then
            players[id_from_msg] = {
                x = x, 
                y = y, 
                color = {r, g, b}, 
                id = id_from_msg,
                totalScore = existingScore,
                facePoints = nil
            }
        else
            players[id_from_msg].x = x
            players[id_from_msg].y = y
            players[id_from_msg].color = {r, g, b}
            players[id_from_msg].facePoints = existingFacePoints
            players[id_from_msg].totalScore = existingScore
        end

        for _, client in ipairs(serverClients) do
            safeSend(client, string.format("%d,%d,%d,%.2f,%.2f,%.2f",
                id_from_msg, x, y, r, g, b))
        end
        return
    end

    if data == "disconnect" then
        if players[id] then
            debugConsole.addMessage("Player " .. id .. " disconnected")
            players[id] = nil
            
            for _, client in ipairs(serverClients) do
                safeSend(client, "player_disconnect," .. id)
            end
        end
        return
    end

    if data == "request_party_mode" then
        partyMode = true
        gameState = "jumpgame"
        currentPartyGame = "jumpgame"
        returnState = "hosting"
        jumpGame.reset(players)
        jumpGame.setPlayerColor(localPlayer.color)
        
        -- Broadcast to all clients
        for _, client in ipairs(serverClients) do
            safeSend(client, "start_party_mode")
        end
        return
    end

    debugConsole.addMessage("[Server] Unhandled message from player " .. id .. ": " .. data)
end

function handleClientMessage(data)
    -- instructions
    if data == "show_jump_instructions" then
        instructions.show("jumpgame", function() end)
        return
    end
    
    if data == "show_laser_instructions" then
        instructions.show("lasergame", function() end)
        return
    end

    if data == "start_party_music" then
        musicHandler.loadPartyMusic()
        return
    end

    if data == "show_race_instructions" then
        instructions.show("racegame", function() end)
        return
    end

    -- Handle total score updates from server
    if data:match("^total_score,(%d+),(%d+)") then
        local id, score = data:match("^total_score,(%d+),(%d+)")
        id = tonumber(id)
        score = math.floor(tonumber(score))
        if id then
            if not players[id] then
                players[id] = {totalScore = score}
            else
                players[id].totalScore = score
            end
            
            if id == localPlayer.id then
                localPlayer.totalScore = score
                debugConsole.addMessage(string.format("[Score] Client: Total score updated to: %d", score))
            end
        end
        return
    end

    if data:match("^duel_score,(%d+)") then
        local score = tonumber(data:match(",(%d+)"))
        if score then
            local previousScore = localPlayer.totalScore or 0
            localPlayer.totalScore = previousScore + score
            if players[localPlayer.id] then
                players[localPlayer.id].totalScore = localPlayer.totalScore
            end
            if server then
                safeSend(server, string.format("total_score,%d,%d", localPlayer.id, localPlayer.totalScore))
            end
        end
        return
    end

    -- Handle direct game score updates
    if data:match("^jump_score,(%d+)") or data:match("^laser_score,(%d+)") then
        local score = math.floor(tonumber(data:match(",(%d+)")))
        debugConsole.addMessage("[Score] Client received game score: " .. score)
        if score then
            -- Preserve existing score
            local previousScore = localPlayer.totalScore or 0
            -- Add new score
            localPlayer.totalScore = previousScore + score
            
            -- Update player table to match
            if players[localPlayer.id] then
                players[localPlayer.id].totalScore = localPlayer.totalScore
            end
            
            -- Confirm back to server
            if server then
                safeSend(server, string.format("total_score,%d,%d", localPlayer.id, localPlayer.totalScore))
            end
            
            debugConsole.addMessage(string.format("[Score] Client: Added %d to previous %d, new total: %d", 
                score, previousScore, localPlayer.totalScore))
        end
        return
    end
    
    if data:match("^face_data,") then
        local face_id, face_points = data:match("^face_data,(%d+),(.+)")
        face_id = tonumber(face_id)
        if face_id then
            local faceImage = deserializeFacePoints(face_points)
            if faceImage then
                if not players[face_id] then
                    players[face_id] = {
                        x = 100,
                        y = 100,
                        color = {1, 1, 1},
                        id = face_id,
                        totalScore = 0
                    }
                end
                players[face_id].facePoints = faceImage
                debugConsole.addMessage("[Client] Updated face for player " .. face_id)
            end
        end
        return
    end

    if data == "start_jump_game" then
        gameState = "jumpgame"
        returnState = "playing"
        jumpGame.reset(players)
        jumpGame.setPlayerColor(localPlayer.color)
        return
    end

    if data == "start_duel_game" then
        gameState = "duelgame"
        returnState = "playing"
        duelGame.reset()
        return
    end

    if data == "start_race_game" then
        gameState = "racegame"
        returnState = "playing"
        raceGame.reset()
        raceGame.setPlayerColor(localPlayer.color)
        return
    end

    if data:match("high_score,(%d+)") then
        highScore = tonumber(data:match("high_score,(%d+)")) -- wtf
        debugConsole.addMessage("New high score: " .. highScore)
        return
    end

    if data:match("jump_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)") then
        local playerId, x, y, r, g, b = data:match("jump_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
        playerId = tonumber(playerId)
        if playerId ~= localPlayer.id then
            if not players[playerId] then
                players[playerId] = {}
            end
            players[playerId].jumpX = tonumber(x)
            players[playerId].jumpY = tonumber(y)
            players[playerId].color = {tonumber(r), tonumber(g), tonumber(b)}
        end
        return
    end

    if data:match("^start_laser_game,(%d+)") then
        local seed = tonumber(data:match("^start_laser_game,(%d+)"))
        gameState = "lasergame"
        returnState = "playing"
        laserGame.load()
        laserGame.setSeed(seed)
        laserGame.setPlayerColor(localPlayer.color)
        return
    end
    
    if data:match("^laser_position,") then
        local id, x, y, r, g, b = data:match("laser_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
        id = tonumber(id)
        if id and id ~= localPlayer.id then
            if not players[id] then
                players[id] = {}
            end
            players[id].laserX = tonumber(x)
            players[id].laserY = tonumber(y)
            players[id].color = {tonumber(r), tonumber(g), tonumber(b)}
        end
        return
    end

    if data:match("^race_position,") then
        local id, x, y, r, g, b = data:match("race_position,(%d+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
        id = tonumber(id)
        if id and id ~= localPlayer.id then
            if not players[id] then
                players[id] = {}
            end
            players[id].raceX = tonumber(x)
            players[id].raceY = tonumber(y)
            players[id].color = {tonumber(r), tonumber(g), tonumber(b)}
        end
        return
    end

    -- Handle your_id assignment
    if data:match("your_id,(%d+)") then
        localPlayer.id = tonumber(data:match("your_id,(%d+)"))
        debugConsole.addMessage("[Client] Assigned player ID: " .. localPlayer.id)
        
        players[localPlayer.id] = {
            x = localPlayer.x,
            y = localPlayer.y,
            color = localPlayer.color,
            id = localPlayer.id,
            totalScore = localPlayer.totalScore,
            facePoints = localPlayer.facePoints
        }
        
        if server then
            safeSend(server, string.format("%d,%d,%d,%.2f,%.2f,%.2f",
                localPlayer.id,
                math.floor(localPlayer.x),
                math.floor(localPlayer.y),
                localPlayer.color[1],
                localPlayer.color[2],
                localPlayer.color[3]))
            
            if localPlayer.facePoints then
                local serializedFace = serializeFacePoints(localPlayer.facePoints)
                if serializedFace then
                    safeSend(server, "face_data," .. localPlayer.id .. "," .. serializedFace)
                    debugConsole.addMessage("[Client] Sent face data")
                end
            end
        end
        return
    end

    -- Handle regular position updates
    local id, x, y, r, g, b = data:match("(%d+),(%d+),(%d+),([%d.]+),([%d.]+),([%d.]+)")
    if id and x and y and r and g and b then
        id = tonumber(id)
        if id ~= localPlayer.id then
            local existingFacePoints = players[id] and players[id].facePoints
            local existingScore = players[id] and players[id].totalScore or 0
            
            if not players[id] then
                players[id] = {
                    x = tonumber(x),
                    y = tonumber(y),
                    color = {tonumber(r), tonumber(g), tonumber(b)},
                    id = id,
                    totalScore = existingScore,
                    facePoints = nil
                }
            else
                players[id].x = tonumber(x)
                players[id].y = tonumber(y)
                players[id].color = {tonumber(r), tonumber(g), tonumber(b)}
                players[id].facePoints = existingFacePoints
                players[id].totalScore = existingScore
            end
        end
        return
    end

    if data:match("player_disconnect,(%d+)") then
        local disconnected_id = tonumber(data:match("player_disconnect,(%d+)"))
        if players[disconnected_id] then
            debugConsole.addMessage("Player " .. disconnected_id .. " disconnected")
            players[disconnected_id] = nil
        end
        return
    end

    if data == "start_party_mode" then
        partyMode = true
        gameState = "jumpgame"
        currentPartyGame = "jumpgame"
        returnState = "playing"
        jumpGame.reset(players)
        jumpGame.setPlayerColor(localPlayer.color)
        return
    end
    
    if data == "end_party_mode" then
        partyMode = false
        currentPartyGame = nil
        gameState = "playing"
        return
    end

    debugConsole.addMessage("Unhandled message format: " .. data)
end

--////////// OLD CHECK SERVER ///////// KEEP THIS AS BACKUP

--[[
function checkServerStatus()
    if gameState == "jumpgame" or gameState == "hosting" then   -- Don't check status during jump game or if we're hosting
        serverStatus = "Running"
        return
    end

    local testHost = enet.host_create()
    if not testHost then return end
    
    local testServer = testHost:connect("localhost:12345")
    if not testServer then 
        testHost:destroy()
        return 
    end
    
    local startTime = love.timer.getTime()
    while love.timer.getTime() - startTime < 0.1 do
        local event = testHost:service(0)
        if event and event.type == "connect" then
            testServer:disconnect()
            testHost:flush()
            serverStatus = "Running"
            return
        end
    end
    
    serverStatus = "Not Running"
    testServer:disconnect()
    testHost:flush()
end
--]]

function checkServerStatus()
    local oldStatus = serverStatus
    -- NEVER check if we're the host
    if gameState == "hosting" then
        serverStatus = "Running"
    -- Don't create test connections if server exists
    elseif serverHost then
        serverStatus = "Running"
    else
        serverStatus = "Not Running"
    end
    
    -- Log status changes to debug console
    if oldStatus ~= serverStatus then
        debugConsole.addMessage("[Server] Status changed to: " .. serverStatus)
    end
end

function table_keys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    return keys
end

function table_dump(o)
    if type(o) == 'table' then
        local s = '{'
        for k,v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            s = s .. '['..k..'] = ' .. table_dump(v) .. ','
        end
        return s .. '}'
    else
        return tostring(o)
    end
end

function love.mousemoved(x, y)
    if gameState == "customization" then
        characterCustomization.mousemoved(x, y)
    end
end

function love.mousereleased(x, y, button)
    if gameState == "customization" then
        characterCustomization.mousereleased(x, y, button)
    end
end

function serializeFacePoints(canvas)
    if not canvas then return nil end
    
    local success, result = pcall(function()
        local imageData = canvas:newImageData()
        return love.data.encode("string", "base64", imageData:encode("png"))
    end)
    
    if success then
        return result
    else
        debugConsole.addMessage("[Error] Failed to serialize face: " .. tostring(result))
        return nil
    end
end

function deserializeFacePoints(str)
    if not str or str == "" then return nil end
    
    local success, result = pcall(function()
        local pngData = love.data.decode("string", "base64", str)
        local fileData = love.filesystem.newFileData(pngData, "face.png")
        local imageData = love.image.newImageData(fileData)
        return love.graphics.newImage(imageData)
    end)
    
    if success then
        return result
    else
        debugConsole.addMessage("[Error] Failed to deserialize face: " .. tostring(result))
        return nil
    end
end

function love.quit()
    if characterCustomization.faceCanvas then
        characterCustomization.faceCanvas:release()
    end
end

function hasFaceData(player)
    return player and player.facePoints and 
            (type(player.facePoints) == "userdata" or type(player.facePoints) == "table")
end