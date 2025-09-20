local battleRoyale = {}
local debugConsole = require "debugconsole"
local musicHandler = require "musichandler"

-- Game state
battleRoyale.game_over = false
battleRoyale.current_round_score = 0
battleRoyale.playerColor = {1, 1, 1}
battleRoyale.screen_width = 800
battleRoyale.screen_height = 600
battleRoyale.camera_x = 0
battleRoyale.camera_y = 0

-- Seed-based synchronization (like laser game)
battleRoyale.seed = 0
battleRoyale.random = love.math.newRandomGenerator()
battleRoyale.gameTime = 0
battleRoyale.nextMeteoroidTime = 0
battleRoyale.nextPowerUpTime = 0
battleRoyale.meteoroidSpawnPoints = {}
battleRoyale.powerUpSpawnPoints = {}
battleRoyale.safeZoneTargets = {}

-- Game settings 
battleRoyale.gravity = 1000
battleRoyale.game_started = false
battleRoyale.start_timer = 3
battleRoyale.shrink_timer = 15
battleRoyale.shrink_interval = 2
battleRoyale.shrink_padding_x = 0
battleRoyale.shrink_padding_y = 0
battleRoyale.max_shrink_padding_x = 300
battleRoyale.max_shrink_padding_y = 200
-- Use safe timer calculation with fallback for party mode
local beatInterval = musicHandler.beatInterval or 2.0 -- Fallback to 2 seconds if not set
battleRoyale.timer = beatInterval * 20 -- 40 seconds
battleRoyale.safe_zone_radius = 450
battleRoyale.center_x = 400
battleRoyale.center_y = 300
battleRoyale.death_timer = 0
battleRoyale.death_shake = 0
battleRoyale.player_dropped = false
battleRoyale.death_animation_done = false
battleRoyale.shrink_duration = 30 -- 30 seconds of shrinking (more aggressive)
battleRoyale.shrink_start_time = 0 -- When shrinking actually starts
battleRoyale.safe_zone_move_speed = 60 -- pixels per second (faster movement)
battleRoyale.safe_zone_move_timer = 0
battleRoyale.safe_zone_target_x = 400
battleRoyale.safe_zone_target_y = 300
battleRoyale.sync_timer = 0
battleRoyale.sync_interval = 1.0 -- Send sync every 1 second

-- Player settings
battleRoyale.player = {
    x = 400,
    y = 300,
    width = 40,
    height = 40,
    speed = 250,
    normal_speed = 250,
    points = 0,
    powerUpsCollected = {},
    max_powerUps = 2,
    active_effects = {},
    is_invincible = false,
    invincibility_timer = 0,
    speed_up_active = false,
    speed_up_timer = 0,
    shield_active = false,
    shield_timer = 0,
    laser_active = false,
    laser_timer = 0,
    laser_charges = 0,
    laser_angle = 0,
    last_movement_angle = 0,
    teleport_charges = 0
}

local sounds = {
    powerup = love.audio.newSource("sounds/laser.mp3", "static"),
    laser = love.audio.newSource("sounds/laser.mp3", "static")
}

-- Game objects
battleRoyale.powerUps = {}
battleRoyale.keysPressed = {}
battleRoyale.safe_zone_alpha = 0.3
battleRoyale.lasers = {}
battleRoyale.asteroids = {}
battleRoyale.asteroid_spawn_timer = 0
battleRoyale.asteroid_spawn_interval = 2.0 -- More reasonable spawning
battleRoyale.asteroid_speed = 600 -- Pixels per second (much faster)
battleRoyale.powerup_spawn_timer = 0
battleRoyale.powerup_spawn_interval = 2.0 -- Spawn power-ups every 2 seconds (but multiple at once)
battleRoyale.stars = {} -- Moving starfield background
battleRoyale.star_direction = 0 -- Global direction for all stars

function battleRoyale.load()
    debugConsole.addMessage("[BattleRoyale] Loading battle royale game")
    debugConsole.addMessage("[BattleRoyale] Party mode status: " .. tostring(_G and _G.partyMode or "nil"))
    -- Reset game state
    battleRoyale.game_over = false
    battleRoyale.current_round_score = 0
    battleRoyale.death_timer = 0
    battleRoyale.death_shake = 0
    battleRoyale.player_dropped = false
    battleRoyale.death_animation_done = false
    battleRoyale.game_started = false
    battleRoyale.start_timer = 3
    battleRoyale.shrink_start_time = 0
    battleRoyale.shrink_padding_x = 0
    battleRoyale.shrink_padding_y = 0
    battleRoyale.safe_zone_radius = 450
    battleRoyale.player.drop_cooldown = 0
    battleRoyale.player.dropping = false
    battleRoyale.player.jump_count = 0
    battleRoyale.player.has_double_jumped = false
    battleRoyale.player.on_ground = false
    -- Use safe timer calculation with fallback for party mode
    local beatInterval = musicHandler.beatInterval or 2.0 -- Fallback to 2 seconds if not set
    battleRoyale.timer = beatInterval * 20 -- 40 seconds
    battleRoyale.gameTime = 0
    debugConsole.addMessage("[BattleRoyale] Battle royale loaded successfully")

    battleRoyale.keysPressed = {}
    
    -- Add rhythmic effects for meteoroids and safety circle
    musicHandler.addEffect("meteoroid_spawn", "beatPulse", {
        baseColor = {1, 1, 1},
        intensity = 0.5,
        duration = 0.1
    })
    
    musicHandler.addEffect("safety_circle_rotate", "combo", {
        scaleAmount = 0,
        rotateAmount = math.pi/4,  -- Rotate 45 degrees per beat (faster)
        frequency = 2,             -- Twice per beat for more speed
        phase = 0,
        snapDuration = 0.1
    })

    -- Reset player
    battleRoyale.player = {
        x = 400,
        y = 300,
        width = 40,
        height = 40,
        speed = 250,
        normal_speed = 250,
        points = 0,
        powerUpsCollected = {},
        max_powerUps = 2,
        is_invincible = false,
        invincibility_timer = 0,
        speed_up_active = false,
        speed_up_timer = 0,
        shield_active = false,
        shield_timer = 0,
        laser_active = false,
        laser_timer = 0,
        laser_charges = 0,
        laser_angle = 0,
        last_movement_angle = 0,
        teleport_charges = 0
    }
    
    -- In party mode, ensure player starts in center of safe zone
    debugConsole.addMessage("[BattleRoyale] Checking party mode: " .. tostring(_G and _G.partyMode or "nil") .. " (type: " .. type(_G and _G.partyMode) .. ")")
    if _G and _G.partyMode == true then
        battleRoyale.player.x = 400
        battleRoyale.player.y = 300
        battleRoyale.center_x = 400
        battleRoyale.center_y = 300
        battleRoyale.safe_zone_radius = 450
        
        -- Debug music handler state
        debugConsole.addMessage("[PartyMode] Player positioned in center of safe zone")
    else
        debugConsole.addMessage("[BattleRoyale] Party mode not detected, using normal initialization")
    end
    
    -- Initialize spacebar flag
    battleRoyale.spacebarPressed = false

    -- Reset safe zone to center
    battleRoyale.center_x = 400
    battleRoyale.center_y = 300
    battleRoyale.safe_zone_radius = 450
    
    -- Set star direction for this round
    battleRoyale.star_direction = math.random(0, 2 * math.pi)
    
    -- Create game elements
    battleRoyale.createStars()
    battleRoyale.createPowerUps()
    battleRoyale.asteroids = {}
    battleRoyale.asteroid_spawn_timer = 0
    battleRoyale.powerup_spawn_timer = 0

    debugConsole.addMessage("[BattleRoyale] Game loaded")
end

function battleRoyale.setSeed(seed)
    battleRoyale.seed = seed
    battleRoyale.random:setSeed(seed)
    battleRoyale.gameTime = 0
    battleRoyale.nextMeteoroidTime = 0
    battleRoyale.nextPowerUpTime = 0
    battleRoyale.meteoroidSpawnPoints = {}
    battleRoyale.powerUpSpawnPoints = {}
    battleRoyale.safeZoneTargets = {}
    
    -- Pre-calculate meteoroid spawn points (like laser game)
    local time = 0
    while time < battleRoyale.timer do
        local spawnInfo = {
            time = time,
            side = battleRoyale.random:random(1, 4), -- 1=top, 2=right, 3=bottom, 4=left
            speed = battleRoyale.random:random(400, 800),
            size = battleRoyale.random:random(25, 45)
        }
        table.insert(battleRoyale.meteoroidSpawnPoints, spawnInfo)
        
        -- Spawn meteoroids every 1-3 seconds
        time = time + battleRoyale.random:random(1.0, 3.0)
    end
    
    -- Pre-calculate power-up spawn points
    time = 0
    while time < battleRoyale.timer do
        local spawnInfo = {
            time = time,
            side = battleRoyale.random:random(1, 4),
            speed = battleRoyale.random:random(150, 250),
            type = battleRoyale.getRandomPowerUpType(time)
        }
        table.insert(battleRoyale.powerUpSpawnPoints, spawnInfo)
        
        -- Spawn power-ups every 2-4 seconds
        time = time + battleRoyale.random:random(2.0, 4.0)
    end
    
    -- Pre-calculate safe zone target positions
    time = 0
    while time < battleRoyale.timer do
        local margin = math.max(50, battleRoyale.safe_zone_radius + 50)
        local targetInfo = {
            time = time,
            x = battleRoyale.random:random(margin, battleRoyale.screen_width - margin),
            y = battleRoyale.random:random(margin, battleRoyale.screen_height - margin)
        }
        table.insert(battleRoyale.safeZoneTargets, targetInfo)
        
        -- Change target every 2 seconds
        time = time + 2.0
    end
    
    debugConsole.addMessage(string.format(
        "[BattleRoyale] Generated %d meteoroid, %d power-up, and %d safe zone targets with seed %d",
        #battleRoyale.meteoroidSpawnPoints,
        #battleRoyale.powerUpSpawnPoints,
        #battleRoyale.safeZoneTargets,
        seed
    ))
end

function battleRoyale.getRandomPowerUpType(timeRemaining)
    local powerUpTypes = {'speed', 'shield', 'laser', 'teleport'}
    
    -- Remove teleport from available types during final 13 seconds
    if timeRemaining <= 13 then
        powerUpTypes = {'speed', 'shield', 'laser'} -- No teleport in final 13 seconds
    end
    
    return powerUpTypes[battleRoyale.random:random(1, #powerUpTypes)]
end

function battleRoyale.update(dt)
    -- Update music effects
    musicHandler.update(dt)
    
    if not battleRoyale.game_started then
        battleRoyale.start_timer = math.max(0, battleRoyale.start_timer - dt)
        battleRoyale.game_started = battleRoyale.start_timer == 0
        
        -- In party mode, give extra time for players to get into safe zone
        if _G and _G.partyMode == true and battleRoyale.game_started then
            -- Reset safe zone to full size when game starts in party mode
            battleRoyale.safe_zone_radius = 450
            battleRoyale.center_x = 400
            battleRoyale.center_y = 300
            debugConsole.addMessage("[PartyMode] Game started - reset safe zone to full size")
            
            -- Reset all player elimination states when game starts
            if _G and _G.players then
                for id, player in pairs(_G.players) do
                    player.battleEliminated = false
                end
            end
            if _G and _G.localPlayer then
                _G.localPlayer.battleEliminated = false
            end
        end
        
        return
    end

    if battleRoyale.game_over then return end

    battleRoyale.timer = battleRoyale.timer - dt
    battleRoyale.gameTime = battleRoyale.gameTime + dt
    
    if battleRoyale.timer <= 0 then
        battleRoyale.timer = 0
        battleRoyale.game_over = true
        
        -- Mark player as eliminated if they're still alive when timer runs out
        if not battleRoyale.player_dropped and _G and _G.localPlayer and _G.localPlayer.id and _G.players and _G.players[_G.localPlayer.id] then
            _G.players[_G.localPlayer.id].battleEliminated = true
        end
        -- Also mark local player as eliminated
        if not battleRoyale.player_dropped and _G and _G.localPlayer then
            _G.localPlayer.battleEliminated = true
        end
        
        -- In party mode, trigger next game transition
        if _G and _G.partyMode == true then
            debugConsole.addMessage("[PartyMode] Timer expired in battle royale, triggering next game")
            _G.partyModeTransition = true
        end
        return
    end
    
    -- Check if all players are eliminated (for multiplayer) or timer runs out (for single player)
    local allEliminated = true
    if _G and _G.players then
        for id, player in pairs(_G.players) do
            if not player.battleEliminated then
                allEliminated = false
                break
            end
        end
    else
        -- Single player mode - only end when timer runs out, not when player dies
        allEliminated = false
    end
    
    if allEliminated then
        battleRoyale.game_over = true
        
        -- In party mode, trigger next game transition
        if _G and _G.partyMode == true then
            debugConsole.addMessage("[PartyMode] All players eliminated in battle royale, triggering next game")
            _G.partyModeTransition = true
        end
        
        return
    end

    -- Update safe zone movement using pre-calculated targets
    if #battleRoyale.safeZoneTargets > 0 and battleRoyale.safeZoneTargets[1].time <= battleRoyale.gameTime then
        local target = table.remove(battleRoyale.safeZoneTargets, 1)
        battleRoyale.safe_zone_target_x = target.x
        battleRoyale.safe_zone_target_y = target.y
        debugConsole.addMessage("[SafeZone] New target: " .. battleRoyale.safe_zone_target_x .. "," .. battleRoyale.safe_zone_target_y)
    end
    
    -- Party mode uses same safe zone logic as standalone (no music handler dependency)
    
    -- Move safe zone towards target
    local dx = battleRoyale.safe_zone_target_x - battleRoyale.center_x
    local dy = battleRoyale.safe_zone_target_y - battleRoyale.center_y
    local distance = math.sqrt(dx*dx + dy*dy)
    if distance > 5 then
        local move_x = (dx / distance) * battleRoyale.safe_zone_move_speed * dt
        local move_y = (dy / distance) * battleRoyale.safe_zone_move_speed * dt
        battleRoyale.center_x = battleRoyale.center_x + move_x
        battleRoyale.center_y = battleRoyale.center_y + move_y
    end

    -- Update shrinking safe zone - continuous shrinking immediately when game starts (deterministic)
    if true then -- Shrinking always happens now
        -- Start shrinking immediately when game starts
        if battleRoyale.shrink_start_time == 0 and battleRoyale.game_started then
            battleRoyale.shrink_start_time = battleRoyale.gameTime
            debugConsole.addMessage("[BattleRoyale] Safe zone shrinking started!")
        end
        
        -- Start shrinking immediately after game starts
        if battleRoyale.shrink_start_time > 0 then
            local elapsed_shrink_time = battleRoyale.gameTime - battleRoyale.shrink_start_time
            
            -- Only shrink if we haven't exceeded the shrink duration
            if elapsed_shrink_time <= battleRoyale.shrink_duration then
                -- Calculate shrink rate: 450 pixels over 30 seconds = 15 pixels per second
                local shrink_rate = 450 / battleRoyale.shrink_duration
                battleRoyale.safe_zone_radius = battleRoyale.safe_zone_radius - (dt * shrink_rate)
            end
        end
    end
    battleRoyale.safe_zone_radius = math.max(0, battleRoyale.safe_zone_radius) -- Minimum radius of 0 (completely closed)

    -- Handle top-down movement (only if not eliminated)
    if not battleRoyale.player_dropped then
        local moveSpeed = battleRoyale.player.speed
        if love.keyboard.isDown('w') or love.keyboard.isDown('up') then
            battleRoyale.player.y = battleRoyale.player.y - moveSpeed * dt
        end
        if love.keyboard.isDown('s') or love.keyboard.isDown('down') then
            battleRoyale.player.y = battleRoyale.player.y + moveSpeed * dt
        end
        if love.keyboard.isDown('a') or love.keyboard.isDown('left') then
            battleRoyale.player.x = battleRoyale.player.x - moveSpeed * dt
        end
        if love.keyboard.isDown('d') or love.keyboard.isDown('right') then
            battleRoyale.player.x = battleRoyale.player.x + moveSpeed * dt
        end
    end

    -- Keep player within screen bounds
    battleRoyale.player.x = math.max(0, math.min(battleRoyale.screen_width - battleRoyale.player.width, battleRoyale.player.x))
    battleRoyale.player.y = math.max(0, math.min(battleRoyale.screen_height - battleRoyale.player.height, battleRoyale.player.y))

    -- Update laser angle based on mouse position
    local mx, my = love.mouse.getPosition()
    battleRoyale.player.laser_angle = math.atan2(my - battleRoyale.player.y - battleRoyale.player.height/2, 
                                                mx - battleRoyale.player.x - battleRoyale.player.width/2)

    -- Check if player is outside safe zone (only after game has started)
    if battleRoyale.game_started then
        -- Use deterministic safe zone data (same on all clients)
        local center_x, center_y, radius = battleRoyale.center_x, battleRoyale.center_y, battleRoyale.safe_zone_radius
        
        local distance_from_center = math.sqrt(
            (battleRoyale.player.x + battleRoyale.player.width/2 - center_x)^2 +
            (battleRoyale.player.y + battleRoyale.player.height/2 - center_y)^2
        )
        
        -- Debug output for party mode
        if _G.partyMode == true then
            debugConsole.addMessage(string.format("[PartyMode] Player at (%.1f,%.1f), center at (%.1f,%.1f), radius=%.1f, distance=%.1f", 
                battleRoyale.player.x, battleRoyale.player.y, center_x, center_y, radius, distance_from_center))
        end
        
        if distance_from_center > radius and not battleRoyale.player.is_invincible and not battleRoyale.player_dropped then
            battleRoyale.player_dropped = true
            battleRoyale.death_timer = 2 -- 2 second death animation
            battleRoyale.death_shake = 15 -- Shake intensity
            debugConsole.addMessage("[BattleRoyale] Player died outside safe zone!")
            
            -- Mark player as eliminated in players table
            if _G.localPlayer and _G.localPlayer.id and _G.players and _G.players[_G.localPlayer.id] then
                _G.players[_G.localPlayer.id].battleEliminated = true
            end
            -- Also mark local player as eliminated
            if _G.localPlayer then
                _G.localPlayer.battleEliminated = true
            end
        end
    end

    -- Handle powerup collisions (circular collision) - only on local player
    for i = #battleRoyale.powerUps, 1, -1 do
        local powerUp = battleRoyale.powerUps[i]
        local powerUp_center_x = powerUp.x + powerUp.width/2
        local powerUp_center_y = powerUp.y + powerUp.height/2
        local powerUp_radius = powerUp.width/2
        
        local player_center_x = battleRoyale.player.x + battleRoyale.player.width/2
        local player_center_y = battleRoyale.player.y + battleRoyale.player.height/2
        local player_radius = math.min(battleRoyale.player.width, battleRoyale.player.height)/2
        
        -- Calculate distance between centers
        local dx = powerUp_center_x - player_center_x
        local dy = powerUp_center_y - player_center_y
        local distance = math.sqrt(dx*dx + dy*dy)
        
        -- Check if circles overlap
        if distance < (powerUp_radius + player_radius) then
            if battleRoyale.collectPowerUp(powerUp) then
                table.remove(battleRoyale.powerUps, i)
                
                -- Send power-up collection to other players
                if _G.localPlayer and _G.localPlayer.id then
                    local message = string.format("battle_powerup_collected,%d,%.2f,%.2f,%s,%.2f,%d", 
                        _G.localPlayer.id, powerUp.x, powerUp.y, powerUp.type, powerUp.spawnTime, powerUp.spawnSide)
                    
                    if _G.returnState == "hosting" and _G.serverClients then
                        for _, client in ipairs(_G.serverClients) do
                            _G.safeSend(client, message)
                        end
                    elseif _G.returnState == "playing" and _G.server then
                        _G.safeSend(_G.server, message)
                    end
                    
                    debugConsole.addMessage("[BattleRoyale] Player collected " .. powerUp.type .. " power-up")
                end
            end
        end
    end

    -- Update power-up timers
    if battleRoyale.player.speed_up_active then
        battleRoyale.player.speed_up_timer = battleRoyale.player.speed_up_timer - dt
        if battleRoyale.player.speed_up_timer <= 0 then
            battleRoyale.player.speed_up_active = false
            battleRoyale.player.speed = battleRoyale.player.normal_speed
        end
    end
    
    if battleRoyale.player.is_invincible then
        battleRoyale.player.invincibility_timer = battleRoyale.player.invincibility_timer - dt
        if battleRoyale.player.invincibility_timer <= 0 then
            battleRoyale.player.is_invincible = false
        end
    end

    if battleRoyale.player.shield_active then
        battleRoyale.player.shield_timer = battleRoyale.player.shield_timer - dt
        if battleRoyale.player.shield_timer <= 0 then
            battleRoyale.player.shield_active = false
        end
    end

    if battleRoyale.player.laser_active and battleRoyale.player.laser_charges <= 0 then
        battleRoyale.player.laser_active = false
    end

    -- Update lasers (bullets)
    for i = #battleRoyale.lasers, 1, -1 do
        local laser = battleRoyale.lasers[i]
        laser.time = laser.time + dt
        
        -- Move the bullet
        laser.x = laser.x + laser.vx * dt
        laser.y = laser.y + laser.vy * dt
        
        -- Remove if expired or off screen
        if laser.time >= laser.duration or 
           laser.x < -50 or laser.x > battleRoyale.screen_width + 50 or
           laser.y < -50 or laser.y > battleRoyale.screen_height + 50 then
            table.remove(battleRoyale.lasers, i)
        end
    end

    -- Update asteroids using deterministic spawning (like laser game)
    battleRoyale.updateAsteroids(dt)
    
    -- Check asteroid collisions with player
    battleRoyale.checkAsteroidCollisions()
    
    -- Check laser collisions with player
    battleRoyale.checkLaserCollisions()
    
    -- Update power-ups using deterministic spawning (like laser game)
    battleRoyale.updatePowerUps(dt)
    
    -- Update starfield
    battleRoyale.updateStars(dt)
    
    -- Send periodic synchronization to keep clients in sync
    battleRoyale.sync_timer = battleRoyale.sync_timer + dt
    if battleRoyale.sync_timer >= battleRoyale.sync_interval then
        battleRoyale.sync_timer = 0
        battleRoyale.sendGameStateSync()
    end

    -- Update death timer and shake
    if battleRoyale.death_timer > 0 then
        battleRoyale.death_timer = battleRoyale.death_timer - dt
        battleRoyale.death_shake = battleRoyale.death_shake * 0.85 -- Decay shake
        if battleRoyale.death_timer <= 0 then
            battleRoyale.death_timer = 0
            battleRoyale.death_shake = 0
            battleRoyale.death_animation_done = true
            -- Don't end game immediately - wait for all players to be eliminated or timer to run out
        end
    end

    -- Update scoring based on survival time
    battleRoyale.current_round_score = battleRoyale.current_round_score + math.floor(dt * 10)
    
    -- Handle spacebar input using isDown (like jump game)
    battleRoyale.handleSpacebar()
end

function battleRoyale.draw(playersTable, localPlayerId)
    -- Apply death shake effect
    if battleRoyale.death_shake > 0 then
        local shake_x = math.random(-battleRoyale.death_shake, battleRoyale.death_shake)
        local shake_y = math.random(-battleRoyale.death_shake, battleRoyale.death_shake)
        love.graphics.translate(shake_x, shake_y)
    end
    
    -- Clear background
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle('fill', 0, 0, battleRoyale.screen_width, battleRoyale.screen_height)
    
    -- Draw starfield background
    battleRoyale.drawStars()
    
    -- Draw safe zone (use synchronized data if available)
    battleRoyale.drawSafeZone(playersTable)
    
    -- Draw game elements
    battleRoyale.drawPowerUps()
    battleRoyale.drawLasers()
    battleRoyale.drawOtherPlayersLasers(playersTable)
    battleRoyale.drawAsteroids()
    
    -- Draw other players (only if not eliminated)
    if playersTable then
        for id, player in pairs(playersTable) do
            -- Debug: Show elimination status
            if player.battleEliminated then
                debugConsole.addMessage("[Draw] Player " .. id .. " is ELIMINATED - not drawing")
            else
                debugConsole.addMessage("[Draw] Player " .. id .. " is ALIVE - drawing")
            end
            if id ~= localPlayerId and player.battleX and player.battleY and not player.battleEliminated then
                -- Draw ghost player body
                love.graphics.setColor(player.color[1], player.color[2], player.color[3], 0.5)
                love.graphics.rectangle('fill',
                    player.battleX,
                    player.battleY,
                    battleRoyale.player.width,
                    battleRoyale.player.height
                )
                
                -- Draw their face if available
                if player.facePoints then
                    love.graphics.setColor(1, 1, 1, 0.5)
                    love.graphics.draw(
                        player.facePoints,
                        player.battleX,
                        player.battleY,
                        0,
                        battleRoyale.player.width/100,
                        battleRoyale.player.height/100
                    )
                end
                
                love.graphics.setColor(1, 1, 0, 0.8)
                love.graphics.printf(
                    "Score: " .. math.floor(player.totalScore or 0),
                    player.battleX - 50,
                    player.battleY - 40,
                    100,
                    "center"
                )
            end
        end
    end
    
    -- Draw spectator mode indicator for eliminated players
    if battleRoyale.player_dropped and battleRoyale.death_animation_done then
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.printf("SPECTATOR MODE", 
            0, 50, battleRoyale.screen_width, "center")
        love.graphics.setColor(0.8, 0.8, 0.8, 0.6)
        love.graphics.printf("You have been eliminated. Watch the remaining players.", 
            0, 80, battleRoyale.screen_width, "center")
    end
    
    -- Draw local player (only if not dropped)
    if not battleRoyale.player_dropped then
        if playersTable and playersTable[localPlayerId] then
            -- Draw shield bubble if active
            if battleRoyale.player.shield_active then
                local shield_radius = 35 -- Larger, more prominent shield
                
                -- Draw outer glow effect
                love.graphics.setColor(0, 0.8, 1, 0.2)
                love.graphics.circle('fill',
                    battleRoyale.player.x + battleRoyale.player.width/2,
                    battleRoyale.player.y + battleRoyale.player.height/2,
                    shield_radius + 10
                )
                
                -- Draw main shield bubble
                love.graphics.setColor(0, 0.8, 1, 0.4) -- More visible blue bubble
                love.graphics.circle('fill',
                    battleRoyale.player.x + battleRoyale.player.width/2,
                    battleRoyale.player.y + battleRoyale.player.height/2,
                    shield_radius
                )
                
                -- Draw shield border with pulsing effect
                local pulse = math.sin(love.timer.getTime() * 8) * 0.2 + 0.8
                love.graphics.setColor(0, 0.8, 1, pulse)
                love.graphics.setLineWidth(3)
                love.graphics.circle('line',
                    battleRoyale.player.x + battleRoyale.player.width/2,
                    battleRoyale.player.y + battleRoyale.player.height/2,
                    shield_radius
                )
                love.graphics.setLineWidth(1)
            end
            
            -- Draw player
            love.graphics.setColor(battleRoyale.playerColor)
            love.graphics.rectangle('fill',
                battleRoyale.player.x,
                battleRoyale.player.y,
                battleRoyale.player.width,
                battleRoyale.player.height
            )
            
            -- Draw face
            if playersTable[localPlayerId].facePoints then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(
                    playersTable[localPlayerId].facePoints,
                    battleRoyale.player.x,
                    battleRoyale.player.y,
                    0,
                    battleRoyale.player.width/100,
                    battleRoyale.player.height/100
                )
            end
        end
    else
        -- Draw death indicator
        love.graphics.setColor(1, 0, 0, 0.7)
        love.graphics.rectangle('fill', battleRoyale.player.x, battleRoyale.player.y, battleRoyale.player.width, battleRoyale.player.height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf('ELIMINATED', battleRoyale.player.x - 20, battleRoyale.player.y - 30, battleRoyale.player.width + 40, 'center')
    end
    
    -- Draw UI elements
    battleRoyale.drawUI(playersTable, localPlayerId)
end



function battleRoyale.drawSafeZone(playersTable)
    -- Use deterministic safe zone data (same on all clients)
    local center_x, center_y, radius = battleRoyale.center_x, battleRoyale.center_y, battleRoyale.safe_zone_radius
    
    -- Only draw if radius is greater than 0
    if radius > 0 then
        -- Get rhythmic rotation for safety circle (only when music is playing)
        local rotation = 0
        if musicHandler.music and musicHandler.isPlaying then
            local _, _, rhythmicRotation = musicHandler.applyToDrawable("safety_circle_rotate", 1, 1)
            rotation = rhythmicRotation or 0
            
            -- Add continuous rotation for more dynamic movement
            local time = love.timer.getTime()
            rotation = rotation + time * 0.5 -- Continuous slow rotation
        end
        
        -- Draw safe zone circle - always blue
        local alpha = 0.2
        local r, g, b = 0.3, 0.6, 1.0 -- Always blue
        
        love.graphics.setColor(r, g, b, alpha)
        love.graphics.circle('fill', center_x, center_y, radius)
        
        -- Draw safe zone border with status-based color and rhythmic rotation
        love.graphics.push()
        love.graphics.translate(center_x, center_y)
        love.graphics.rotate(rotation)
        
        -- Always use blue border
        love.graphics.setColor(0.4, 0.7, 1.0, 0.6) -- Always blue
            love.graphics.circle('line', 0, 0, radius)
        
        love.graphics.pop()
    end
    
    -- If safe zone is completely closed, show a warning
    if battleRoyale.safe_zone_radius <= 0 then
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.printf('SAFE ZONE CLOSED!', 0, battleRoyale.screen_height/2 - 20, battleRoyale.screen_width, 'center')
    end
end

function battleRoyale.drawUI(playersTable, localPlayerId)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('Score: ' .. math.floor(battleRoyale.current_round_score), 10, 10)

    love.graphics.printf(string.format("Time: %.1f", battleRoyale.timer), 
    0, 10, love.graphics.getWidth(), "center")
    
    if playersTable and playersTable[localPlayerId] then
        love.graphics.print('Total Score: ' .. 
            math.floor(playersTable[localPlayerId].totalScore or 0), 10, 30)
    end
    
    -- Display collected powerups
    love.graphics.print('Collected Powerups:', 10, 50)
    for i, powerUp in ipairs(battleRoyale.player.powerUpsCollected) do
        love.graphics.print(i .. ': ' .. powerUp.type, 10, 70 + (i-1) * 20)
    end
    
    -- Display active effects
    local activeY = 130
    if battleRoyale.player.speed_up_active then
        love.graphics.print('Speed Boost: ' .. string.format("%.1f", battleRoyale.player.speed_up_timer), 10, activeY)
        activeY = activeY + 20
    end
    if battleRoyale.player.shield_active then
        love.graphics.print('Shield Bubble: ' .. string.format("%.1f", battleRoyale.player.shield_timer), 10, activeY)
        activeY = activeY + 20
    end
    if battleRoyale.player.laser_active then
        love.graphics.print('Laser Gun: ' .. battleRoyale.player.laser_charges .. ' charges', 10, activeY)
        love.graphics.print('Spacebar to Shoot', 10, activeY + 20)
        activeY = activeY + 40
    end
    if battleRoyale.player.teleport_charges > 0 then
        love.graphics.print('Teleport Charges: ' .. battleRoyale.player.teleport_charges, 10, activeY)
        love.graphics.print('Spacebar to Teleport', 10, activeY + 20)
        activeY = activeY + 40
    end
    
    -- Show safe zone info
    love.graphics.print('Safe Zone Radius: ' .. math.floor(battleRoyale.safe_zone_radius), 10, battleRoyale.screen_height - 80)
    
    -- Show shrink status
    local phase_text = "READY"
    local phase_color = {0.5, 1, 0.5}
    local timer_value = 0
    
    if battleRoyale.shrink_start_time == 0 or not battleRoyale.game_started then
        phase_text = "READY"
        phase_color = {0.5, 1, 0.5}
        timer_value = battleRoyale.shrink_duration
    else
        local elapsed_shrink_time = love.timer.getTime() - battleRoyale.shrink_start_time
        if elapsed_shrink_time <= battleRoyale.shrink_duration then
            phase_text = "SHRINKING"
            phase_color = {1, 0.5, 0.5}
            timer_value = battleRoyale.shrink_duration - elapsed_shrink_time
        else
            phase_text = "CLOSED"
            phase_color = {1, 0, 0}
            timer_value = 0
        end
    end
    
    love.graphics.setColor(phase_color[1], phase_color[2], phase_color[3])
    love.graphics.print('Status: ' .. phase_text, 10, battleRoyale.screen_height - 60)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('Time Left: ' .. string.format("%.1f", math.max(0, timer_value)), 10, battleRoyale.screen_height - 40)
    
    -- Show active power-up status more prominently
    if battleRoyale.player.laser_active then
        love.graphics.setColor(1, 0, 0)
        love.graphics.printf('LASER ACTIVE - PRESS SPACEBAR TO SHOOT', 
            0, battleRoyale.screen_height - 100, battleRoyale.screen_width, 'center')
        love.graphics.setColor(1, 1, 1)
    elseif battleRoyale.player.teleport_charges > 0 then
        love.graphics.setColor(0, 1, 0)
        love.graphics.printf('TELEPORT READY - PRESS SPACEBAR TO TELEPORT', 
            0, battleRoyale.screen_height - 100, battleRoyale.screen_width, 'center')
        love.graphics.setColor(1, 1, 1)
    end
    
    if not battleRoyale.game_started then
        love.graphics.printf('Get Ready: ' .. math.ceil(battleRoyale.start_timer), 
            0, battleRoyale.screen_height / 2 - 50, battleRoyale.screen_width, 'center')
    end
    
    if battleRoyale.game_over then
        love.graphics.printf('Game Over - You were caught outside the safe zone!', 
            0, battleRoyale.screen_height / 2 - 50, battleRoyale.screen_width, 'center')
    end
end


function battleRoyale.checkCollision(obj1, obj2)
    return obj1.x < obj2.x + obj2.width and
            obj1.x + obj1.width > obj2.x and
            obj1.y < obj2.y + obj2.height and
            obj1.y + obj1.height > obj2.y
end


function battleRoyale.createStars()
    battleRoyale.stars = {}
    -- Create a moving starfield with uniform direction and color
    for i = 1, 150 do
        table.insert(battleRoyale.stars, {
            x = math.random(0, battleRoyale.screen_width),
            y = math.random(0, battleRoyale.screen_height),
            size = math.random(1, 3),
            speed = math.random(20, 60) -- Movement speed in pixels per second
            -- All stars use the global star_direction
        })
    end
end

function battleRoyale.updateStars(dt)
    for i = #battleRoyale.stars, 1, -1 do
        local star = battleRoyale.stars[i]
        
        -- Move star in the global direction
        star.x = star.x + math.cos(battleRoyale.star_direction) * star.speed * dt
        star.y = star.y + math.sin(battleRoyale.star_direction) * star.speed * dt
        
        -- Wrap around screen edges
        if star.x < 0 then
            star.x = battleRoyale.screen_width
        elseif star.x > battleRoyale.screen_width then
            star.x = 0
        end
        
        if star.y < 0 then
            star.y = battleRoyale.screen_height
        elseif star.y > battleRoyale.screen_height then
            star.y = 0
        end
    end
end

function battleRoyale.createPowerUps()
    battleRoyale.powerUps = {}
    -- No initial power-ups - they spawn dynamically during gameplay
end

function battleRoyale.collectPowerUp(powerUp)
    if #battleRoyale.player.powerUpsCollected < battleRoyale.player.max_powerUps then
        table.insert(battleRoyale.player.powerUpsCollected, powerUp)
        debugConsole.addMessage("[BattleRoyale] Collected powerup: " .. powerUp.type)
        -- Play collection sound here 
        return true
    end
    return false
end

function battleRoyale.drawStars()
    for _, star in ipairs(battleRoyale.stars) do
        love.graphics.setColor(1, 1, 1, 0.8) -- Uniform white color with slight transparency
        love.graphics.circle('fill', star.x, star.y, star.size)
    end
end

function battleRoyale.drawPowerUps()
    for _, powerUp in ipairs(battleRoyale.powerUps) do
        local center_x = powerUp.x + powerUp.width/2
        local center_y = powerUp.y + powerUp.height/2
        local radius = powerUp.width/2
        
        -- Draw blue circle (all look the same)
        love.graphics.setColor(0.2, 0.6, 1.0)  -- Bright blue
        love.graphics.circle('fill', center_x, center_y, radius)
        
        -- Draw blue circle border
        love.graphics.setColor(0.1, 0.4, 0.8)  -- Darker blue border
        love.graphics.setLineWidth(2)
        love.graphics.circle('line', center_x, center_y, radius)
        love.graphics.setLineWidth(1)
        
        -- Draw question mark
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("?",
            powerUp.x,
            powerUp.y + powerUp.height/4,
            powerUp.width,
            'center')
    end
end

function battleRoyale.drawLasers()
    for i, laser in ipairs(battleRoyale.lasers) do
        -- Draw laser bullet as a small circle
        love.graphics.setColor(1, 1, 1, 1) -- Bright white core
        love.graphics.circle('fill', laser.x, laser.y, laser.size)
        
        -- Draw red glow around it
        love.graphics.setColor(1, 0, 0, 0.6) -- Red glow
        love.graphics.circle('fill', laser.x, laser.y, laser.size + 2)
        
        -- Draw bright center
        love.graphics.setColor(1, 1, 1, 1) -- Bright white center
        love.graphics.circle('fill', laser.x, laser.y, laser.size - 1)
    end
end

function battleRoyale.drawOtherPlayersLasers(playersTable)
    if not playersTable then return end
    
    for id, player in pairs(playersTable) do
        if player.battleLasers and player.battleLasers ~= "" then
            -- Parse laser data: "x,y,vx,vy,time,duration,size|x,y,vx,vy,time,duration,size|..."
            local laserStrings = {}
            for laserStr in player.battleLasers:gmatch("([^|]+)") do
                table.insert(laserStrings, laserStr)
            end
            
            for _, laserStr in ipairs(laserStrings) do
                local x, y, vx, vy, time, duration, size = laserStr:match("([-%d.]+),([-%d.]+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
                if x and y and vx and vy and time and duration and size then
                    x, y, vx, vy, time, duration, size = tonumber(x), tonumber(y), tonumber(vx), tonumber(vy), tonumber(time), tonumber(duration), tonumber(size)
                    
                    -- Check if laser is still valid (not expired)
                    if time < duration then
                        -- Draw laser bullet as a small circle
                        love.graphics.setColor(1, 1, 1, 1) -- Bright white core
                        love.graphics.circle('fill', x, y, size)
                        
                        -- Draw red glow around it
                        love.graphics.setColor(1, 0, 0, 0.6) -- Red glow
                        love.graphics.circle('fill', x, y, size + 2)
                        
                        -- Draw bright center
                        love.graphics.setColor(1, 1, 1, 1) -- Bright white center
                        love.graphics.circle('fill', x, y, size - 1)
                    end
                end
            end
        end
    end
end


function battleRoyale.keypressed(key)
    print("[BattleRoyale] Key pressed: " .. key)
    debugConsole.addMessage("[BattleRoyale] Key pressed: " .. key)
    
    if key == ' ' then -- Spacebar for all power-up actions
        debugConsole.addMessage("[BattleRoyale] Spacebar pressed!")
        debugConsole.addMessage("[BattleRoyale] Power-ups collected: " .. #battleRoyale.player.powerUpsCollected)
        debugConsole.addMessage("[BattleRoyale] Laser active: " .. tostring(battleRoyale.player.laser_active))
        debugConsole.addMessage("[BattleRoyale] Teleport charges: " .. battleRoyale.player.teleport_charges)
        
        -- First check if we have collected power-ups to activate
        if #battleRoyale.player.powerUpsCollected > 0 then
            local powerUp = table.remove(battleRoyale.player.powerUpsCollected, 1)
            if powerUp then
                debugConsole.addMessage("[BattleRoyale] Activating power-up: " .. powerUp.type)
                -- Play sound effect
                sounds.powerup:stop()
                sounds.powerup:play()
                
                battleRoyale.activateSpecificPowerUp(powerUp.type)
            end
        -- If no power-ups to activate, check for active power-up actions
        elseif battleRoyale.player.laser_active then
            debugConsole.addMessage("[BattleRoyale] Shooting laser!")
            battleRoyale.shootLaser()
        elseif battleRoyale.player.teleport_charges > 0 then
            debugConsole.addMessage("[BattleRoyale] Teleporting!")
            battleRoyale.teleportPlayer()
        else
            debugConsole.addMessage("[BattleRoyale] No power-up actions available")
        end
    end
end

-- Add a new function to handle spacebar using isDown like jump game
function battleRoyale.handleSpacebar()
    -- Don't allow power-up usage if eliminated
    if battleRoyale.player_dropped then return end
    
    if love.keyboard.isDown('space') then
        -- Only trigger once per press by using a flag
        if not battleRoyale.spacebarPressed then
            battleRoyale.spacebarPressed = true
            print("[BattleRoyale] Spacebar detected via isDown!")
            debugConsole.addMessage("[BattleRoyale] Spacebar detected via isDown!")
            debugConsole.addMessage("[BattleRoyale] Power-ups collected: " .. #battleRoyale.player.powerUpsCollected)
            debugConsole.addMessage("[BattleRoyale] Laser active: " .. tostring(battleRoyale.player.laser_active))
            debugConsole.addMessage("[BattleRoyale] Teleport charges: " .. battleRoyale.player.teleport_charges)
            
            -- First check if we have collected power-ups to activate
            if #battleRoyale.player.powerUpsCollected > 0 then
                local powerUp = table.remove(battleRoyale.player.powerUpsCollected, 1)
                if powerUp then
                    debugConsole.addMessage("[BattleRoyale] Activating power-up: " .. powerUp.type)
                    -- Play sound effect
                    sounds.powerup:stop()
                    sounds.powerup:play()
                    
                    battleRoyale.activateSpecificPowerUp(powerUp.type)
                end
            -- If no power-ups to activate, check for active power-up actions
            elseif battleRoyale.player.laser_active then
                debugConsole.addMessage("[BattleRoyale] Shooting laser!")
                battleRoyale.shootLaser()
            elseif battleRoyale.player.teleport_charges > 0 then
                debugConsole.addMessage("[BattleRoyale] Teleporting!")
                battleRoyale.teleportPlayer()
            else
                debugConsole.addMessage("[BattleRoyale] No power-up actions available")
            end
        end
    else
        battleRoyale.spacebarPressed = false
    end
end

function battleRoyale.mousepressed(x, y, button)
    -- Mouse input removed - using spacebar for power-ups
end

function battleRoyale.shootLaser()
    if battleRoyale.player.laser_active and battleRoyale.player.laser_charges > 0 then
        local player_center_x = battleRoyale.player.x + battleRoyale.player.width/2
        local player_center_y = battleRoyale.player.y + battleRoyale.player.height/2
        
        -- Calculate angle based on player movement direction (including diagonal)
        local dx, dy = 0, 0
        local moving = false
        
        -- Check horizontal movement
        if love.keyboard.isDown('a') or love.keyboard.isDown('left') then
            dx = dx - 1
            moving = true
        end
        if love.keyboard.isDown('d') or love.keyboard.isDown('right') then
            dx = dx + 1
            moving = true
        end
        
        -- Check vertical movement
        if love.keyboard.isDown('w') or love.keyboard.isDown('up') then
            dy = dy - 1
            moving = true
        end
        if love.keyboard.isDown('s') or love.keyboard.isDown('down') then
            dy = dy + 1
            moving = true
        end
        
        -- Calculate angle from movement vector
        local angle = 0
        if moving and (dx ~= 0 or dy ~= 0) then
            angle = math.atan2(dy, dx)
            battleRoyale.player.last_movement_angle = angle
        else
            -- If not moving, shoot in last movement direction or default right
            angle = battleRoyale.player.last_movement_angle or 0
        end
        
        local laser = {
            x = player_center_x,
            y = player_center_y,
            angle = angle,
            speed = 600, -- Speed in pixels per second
            size = 5,   -- Slightly smaller bullet size
            duration = 2.5, -- How long it exists
            time = 0,
            vx = math.cos(angle) * 600, -- Velocity X
            vy = math.sin(angle) * 600  -- Velocity Y
        }
        table.insert(battleRoyale.lasers, laser)
        
        -- Use one charge
        battleRoyale.player.laser_charges = battleRoyale.player.laser_charges - 1
        
        -- Play laser sound
        sounds.laser:stop()
        sounds.laser:play()
        
        -- Send laser data to other players (like laser game does)
        if _G.localPlayer and _G.localPlayer.id then
            local laserData = string.format("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
                laser.x, laser.y, laser.vx, laser.vy, laser.time, laser.duration, laser.size)
            
            if _G.returnState == "hosting" and _G.serverClients then
                for _, client in ipairs(_G.serverClients) do
                    _G.safeSend(client, string.format("battle_laser_shot,%d,%s", 
                        _G.localPlayer.id, laserData))
                end
            elseif _G.returnState == "playing" and _G.server then
                _G.safeSend(_G.server, string.format("battle_laser_shot,%d,%s", 
                    _G.localPlayer.id, laserData))
            end
        end
    end
end

function battleRoyale.keyreleased(key)
    battleRoyale.keysPressed[key] = false
end

function battleRoyale.teleportPlayer()
    if battleRoyale.player.teleport_charges > 0 then
        -- Teleport to center of safe zone
        battleRoyale.player.x = battleRoyale.center_x - battleRoyale.player.width/2
        battleRoyale.player.y = battleRoyale.center_y - battleRoyale.player.height/2
        
        -- Use one charge
        battleRoyale.player.teleport_charges = battleRoyale.player.teleport_charges - 1
        
        -- Play sound effect
        sounds.powerup:stop()
        sounds.powerup:play()
        
        -- Send teleport notification to other players
        if _G.localPlayer and _G.localPlayer.id then
            if _G.returnState == "hosting" and _G.serverClients then
                for _, client in ipairs(_G.serverClients) do
                    _G.safeSend(client, string.format("battle_teleport,%d,%.2f,%.2f", 
                        _G.localPlayer.id, battleRoyale.player.x, battleRoyale.player.y))
                end
            elseif _G.returnState == "playing" and _G.server then
                _G.safeSend(_G.server, string.format("battle_teleport,%d,%.2f,%.2f", 
                    _G.localPlayer.id, battleRoyale.player.x, battleRoyale.player.y))
            end
        end
    end
end

function battleRoyale.activateSpecificPowerUp(type)
    -- Deactivate all other power-ups first
    battleRoyale.player.speed_up_active = false
    battleRoyale.player.shield_active = false
    battleRoyale.player.laser_active = false
    battleRoyale.player.laser_charges = 0
    battleRoyale.player.teleport_charges = 0
    
    if type == 'speed' then
        battleRoyale.player.speed_up_active = true
        battleRoyale.player.speed_up_timer = 3
        battleRoyale.player.speed = battleRoyale.player.normal_speed * 1.5
        
    elseif type == 'shield' then
        battleRoyale.player.shield_active = true
        battleRoyale.player.shield_timer = 4
        
    elseif type == 'laser' then
        battleRoyale.player.laser_active = true
        battleRoyale.player.laser_charges = 4
        
    elseif type == 'teleport' then
        battleRoyale.player.teleport_charges = 2
    end
end

function battleRoyale.updatePowerUps(dt)
    -- Check if we need to spawn any power-ups based on pre-calculated spawn points
    while #battleRoyale.powerUpSpawnPoints > 0 and battleRoyale.powerUpSpawnPoints[1].time <= battleRoyale.gameTime do
        battleRoyale.spawnPowerUpFromSpawnPoint(table.remove(battleRoyale.powerUpSpawnPoints, 1))
    end
    
    -- Update existing power-ups and remove those outside circle for too long
    for i = #battleRoyale.powerUps, 1, -1 do
        local powerUp = battleRoyale.powerUps[i]
        
        -- Move power-ups like meteoroids
        if powerUp.is_moving then
            powerUp.x = powerUp.x + powerUp.vx * dt
            powerUp.y = powerUp.y + powerUp.vy * dt
            
            -- Remove if off screen
            if powerUp.x < -100 or powerUp.x > battleRoyale.screen_width + 100 or
               powerUp.y < -100 or powerUp.y > battleRoyale.screen_height + 100 then
                table.remove(battleRoyale.powerUps, i)
            end
        end
        
        -- Power-ups no longer have safe zone timer - they persist until off-screen
    end
end

function battleRoyale.spawnPowerUpFromSpawnPoint(spawnInfo)
    local side = spawnInfo.side
    local speed = spawnInfo.speed
    local pType = spawnInfo.type
    
    -- Spawn from screen edges like meteoroids
    local powerUp = {
        width = 35,
        height = 35,
        type = pType,
        outside_circle_time = 0,
        speed = speed,
        is_moving = true,
        spawnTime = spawnInfo.time,
        spawnSide = side
    }
    
    -- Calculate angle towards safe zone center
    local angle_to_center = 0
    local spawn_x, spawn_y = 0, 0
    
    if side == 1 then -- Top
        spawn_x = battleRoyale.random:random(0, battleRoyale.screen_width)
        spawn_y = -50
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    elseif side == 2 then -- Right
        spawn_x = battleRoyale.screen_width + 50
        spawn_y = battleRoyale.random:random(0, battleRoyale.screen_height)
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    elseif side == 3 then -- Bottom
        spawn_x = battleRoyale.random:random(0, battleRoyale.screen_width)
        spawn_y = battleRoyale.screen_height + 50
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    else -- Left
        spawn_x = -50
        spawn_y = battleRoyale.random:random(0, battleRoyale.screen_height)
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    end
    
    -- Add some randomness to the angle (within 45 degrees of center direction)
    local angle_variance = battleRoyale.random:random(-math.pi/4, math.pi/4) -- ±45 degrees
    local final_angle = angle_to_center + angle_variance
    
    -- Set position and velocity
    powerUp.x = spawn_x
    powerUp.y = spawn_y
    powerUp.vx = math.cos(final_angle) * powerUp.speed
    powerUp.vy = math.sin(final_angle) * powerUp.speed
    
    table.insert(battleRoyale.powerUps, powerUp)
end

function battleRoyale.spawnPowerUp()
    local powerUpTypes = {'speed', 'shield', 'laser', 'teleport'}
    
    -- Remove teleport from available types during final 13 seconds
    local time_remaining = battleRoyale.timer
    if time_remaining <= 13 then
        powerUpTypes = {'speed', 'shield', 'laser'} -- No teleport in final 13 seconds
    end
    
    local pType = powerUpTypes[math.random(1, #powerUpTypes)]
    
    -- Spawn from screen edges like meteoroids
    local side = math.random(1, 4) -- 1=top, 2=right, 3=bottom, 4=left
    local base_speed = 150 -- Faster than before
    local speed_variance = math.random(50, 100) -- Add 50-100 pixels/second variance
    local powerUp = {
        width = 35,
        height = 35,
        type = pType,
        outside_circle_time = 0,
        speed = base_speed + speed_variance, -- 200-250 pixels/second with variance
        is_moving = true
    }
    
    -- Calculate angle towards safe zone center
    local angle_to_center = 0
    local spawn_x, spawn_y = 0, 0
    
    if side == 1 then -- Top
        spawn_x = math.random(0, battleRoyale.screen_width)
        spawn_y = -50
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    elseif side == 2 then -- Right
        spawn_x = battleRoyale.screen_width + 50
        spawn_y = math.random(0, battleRoyale.screen_height)
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    elseif side == 3 then -- Bottom
        spawn_x = math.random(0, battleRoyale.screen_width)
        spawn_y = battleRoyale.screen_height + 50
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    else -- Left
        spawn_x = -50
        spawn_y = math.random(0, battleRoyale.screen_height)
        angle_to_center = math.atan2(battleRoyale.center_y - spawn_y, battleRoyale.center_x - spawn_x)
    end
    
    -- Add some randomness to the angle (within 45 degrees of center direction)
    local angle_variance = math.random(-math.pi/4, math.pi/4) -- ±45 degrees
    local final_angle = angle_to_center + angle_variance
    
    -- Set position and velocity
    powerUp.x = spawn_x
    powerUp.y = spawn_y
    powerUp.vx = math.cos(final_angle) * powerUp.speed
    powerUp.vy = math.sin(final_angle) * powerUp.speed
    
    table.insert(battleRoyale.powerUps, powerUp)
end

function battleRoyale.updateAsteroids(dt)
    -- Check if we need to spawn any asteroids based on pre-calculated spawn points
    while #battleRoyale.meteoroidSpawnPoints > 0 and battleRoyale.meteoroidSpawnPoints[1].time <= battleRoyale.gameTime do
        battleRoyale.spawnAsteroidFromSpawnPoint(table.remove(battleRoyale.meteoroidSpawnPoints, 1))
    end
    
    -- Update existing asteroids
    for i = #battleRoyale.asteroids, 1, -1 do
        local asteroid = battleRoyale.asteroids[i]
        
        -- Apply deterministic speed multiplier based on game time
        local speedMultiplier = 1
        -- Speed up after 10 seconds of gameplay
        if battleRoyale.gameTime > 10 then
            speedMultiplier = 1.5 -- 50% faster after 10 seconds
        end
        
        asteroid.x = asteroid.x + asteroid.vx * dt * speedMultiplier
        asteroid.y = asteroid.y + asteroid.vy * dt * speedMultiplier
        
        -- Remove asteroids that are off screen
        if asteroid.x < -50 or asteroid.x > battleRoyale.screen_width + 50 or
           asteroid.y < -50 or asteroid.y > battleRoyale.screen_height + 50 then
            table.remove(battleRoyale.asteroids, i)
        end
    end
end

function battleRoyale.spawnAsteroidFromSpawnPoint(spawnInfo)
    local asteroid = {}
    local side = spawnInfo.side
    local speed = spawnInfo.speed
    local size = spawnInfo.size
    
    if side == 1 then -- Top
        asteroid.x = battleRoyale.random:random(0, battleRoyale.screen_width)
        asteroid.y = -50
        asteroid.vx = battleRoyale.random:random(-speed/4, speed/4)
        asteroid.vy = battleRoyale.random:random(speed/4, speed)
    elseif side == 2 then -- Right
        asteroid.x = battleRoyale.screen_width + 50
        asteroid.y = battleRoyale.random:random(0, battleRoyale.screen_height)
        asteroid.vx = battleRoyale.random:random(-speed, -speed/4)
        asteroid.vy = battleRoyale.random:random(-speed/4, speed/4)
    elseif side == 3 then -- Bottom
        asteroid.x = battleRoyale.random:random(0, battleRoyale.screen_width)
        asteroid.y = battleRoyale.screen_height + 50
        asteroid.vx = battleRoyale.random:random(-speed/4, speed/4)
        asteroid.vy = battleRoyale.random:random(-speed, -speed/4)
    else -- Left
        asteroid.x = -50
        asteroid.y = battleRoyale.random:random(0, battleRoyale.screen_height)
        asteroid.vx = battleRoyale.random:random(speed/4, speed)
        asteroid.vy = battleRoyale.random:random(-speed/4, speed/4)
    end
    
    asteroid.size = size
    asteroid.color = {0.5, 0.5, 0.5} -- Consistent gray color
    asteroid.points = {} -- Store irregular shape points
    battleRoyale.generateAsteroidShape(asteroid) -- Generate the irregular shape
    
    table.insert(battleRoyale.asteroids, asteroid)
end

function battleRoyale.spawnAsteroid()
    local asteroid = {}
    local side = math.random(1, 4) -- 1=top, 2=right, 3=bottom, 4=left
    
    if side == 1 then -- Top
        asteroid.x = math.random(0, battleRoyale.screen_width)
        asteroid.y = -50
        asteroid.vx = math.random(-battleRoyale.asteroid_speed/4, battleRoyale.asteroid_speed/4)
        asteroid.vy = math.random(battleRoyale.asteroid_speed/4, battleRoyale.asteroid_speed)
    elseif side == 2 then -- Right
        asteroid.x = battleRoyale.screen_width + 50
        asteroid.y = math.random(0, battleRoyale.screen_height)
        asteroid.vx = math.random(-battleRoyale.asteroid_speed, -battleRoyale.asteroid_speed/4)
        asteroid.vy = math.random(-battleRoyale.asteroid_speed/4, battleRoyale.asteroid_speed/4)
    elseif side == 3 then -- Bottom
        asteroid.x = math.random(0, battleRoyale.screen_width)
        asteroid.y = battleRoyale.screen_height + 50
        asteroid.vx = math.random(-battleRoyale.asteroid_speed/4, battleRoyale.asteroid_speed/4)
        asteroid.vy = math.random(-battleRoyale.asteroid_speed, -battleRoyale.asteroid_speed/4)
    else -- Left
        asteroid.x = -50
        asteroid.y = math.random(0, battleRoyale.screen_height)
        asteroid.vx = math.random(battleRoyale.asteroid_speed/4, battleRoyale.asteroid_speed)
        asteroid.vy = math.random(-battleRoyale.asteroid_speed/4, battleRoyale.asteroid_speed/4)
    end
    
    asteroid.size = math.random(25, 45)
    asteroid.color = {0.5, 0.5, 0.5} -- Consistent gray color
    asteroid.points = {} -- Store irregular shape points
    battleRoyale.generateAsteroidShape(asteroid) -- Generate the irregular shape
    
    table.insert(battleRoyale.asteroids, asteroid)
end

function battleRoyale.generateAsteroidShape(asteroid)
    -- Generate irregular asteroid shape with 6-8 points using deterministic random
    local num_points = battleRoyale.random:random(6, 8)
    asteroid.points = {}
    
    for i = 1, num_points do
        local angle = (i - 1) * (2 * math.pi / num_points)
        local radius_variation = battleRoyale.random:random(0.7, 1.1) -- Make it irregular but not too extreme
        local base_radius = asteroid.size / 2
        local x = math.cos(angle) * base_radius * radius_variation
        local y = math.sin(angle) * base_radius * radius_variation
        
        -- Add some deterministic jitter to make it more chaotic
        local jitter = asteroid.size / 10
        x = x + battleRoyale.random:random(-jitter, jitter)
        y = y + battleRoyale.random:random(-jitter, jitter)
        
        table.insert(asteroid.points, x)
        table.insert(asteroid.points, y)
    end
end

function battleRoyale.drawAsteroids()
    for _, asteroid in ipairs(battleRoyale.asteroids) do
        love.graphics.push()
        love.graphics.translate(asteroid.x, asteroid.y)
        
        -- Draw asteroid with irregular shape - no animations
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.polygon('fill', asteroid.points)
        
        -- Draw outline
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.polygon('line', asteroid.points)
        
        love.graphics.pop()
    end
end

function battleRoyale.checkAsteroidCollisions()
    for _, asteroid in ipairs(battleRoyale.asteroids) do
        -- Check collision with player
        if battleRoyale.checkCollision(battleRoyale.player, {
            x = asteroid.x - asteroid.size/2,
            y = asteroid.y - asteroid.size/2,
            width = asteroid.size,
            height = asteroid.size
        }) then
            if not battleRoyale.player.shield_active and not battleRoyale.player_dropped then
                battleRoyale.player_dropped = true
                battleRoyale.death_timer = 2 -- 2 second death animation
                battleRoyale.death_shake = 15 -- Shake intensity
                debugConsole.addMessage("[BattleRoyale] Player hit by asteroid!")
                
                -- Mark player as eliminated in players table
                if _G and _G.localPlayer and _G.localPlayer.id and _G.players and _G.players[_G.localPlayer.id] then
                    _G.players[_G.localPlayer.id].battleEliminated = true
                end
                -- Also mark local player as eliminated
                if _G and _G.localPlayer then
                    _G.localPlayer.battleEliminated = true
                    debugConsole.addMessage("[BattleRoyale] Local player ELIMINATED by asteroid!")
                end
            else
                debugConsole.addMessage("[BattleRoyale] Asteroid blocked by shield!")
            end
        end
    end
end

function battleRoyale.checkLaserCollisions()
    if not _G or not _G.players then return end
    
    for id, player in pairs(_G.players) do
        if player.battleLasers and player.battleLasers ~= "" and _G.localPlayer and id ~= _G.localPlayer.id then
            -- Parse laser data
            local laserStrings = {}
            for laserStr in player.battleLasers:gmatch("([^|]+)") do
                table.insert(laserStrings, laserStr)
            end
            
            for _, laserStr in ipairs(laserStrings) do
                local x, y, vx, vy, time, duration, size = laserStr:match("([-%d.]+),([-%d.]+),([-%d.]+),([-%d.]+),([%d.]+),([%d.]+),([%d.]+)")
                if x and y and vx and vy and time and duration and size then
                    x, y, vx, vy, time, duration, size = tonumber(x), tonumber(y), tonumber(vx), tonumber(vy), tonumber(time), tonumber(duration), tonumber(size)
                    
                    -- Check if laser is still valid (not expired)
                    if time < duration then
                        -- Check collision with local player
                        if battleRoyale.checkCollision(battleRoyale.player, {
                            x = x - size/2,
                            y = y - size/2,
                            width = size,
                            height = size
                        }) then
                            if not battleRoyale.player.shield_active and not battleRoyale.player_dropped then
                                battleRoyale.player_dropped = true
                                battleRoyale.death_timer = 2 -- 2 second death animation
                                battleRoyale.death_shake = 15 -- Shake intensity
                                debugConsole.addMessage("[BattleRoyale] Player hit by laser from player " .. id .. "!")
                                
                                -- Mark player as eliminated in players table
                                if _G and _G.localPlayer and _G.localPlayer.id and _G.players and _G.players[_G.localPlayer.id] then
                                    _G.players[_G.localPlayer.id].battleEliminated = true
                                end
                                -- Also mark local player as eliminated
                                if _G and _G.localPlayer then
                                    _G.localPlayer.battleEliminated = true
                                end
                            else
                                debugConsole.addMessage("[BattleRoyale] Laser blocked by shield!")
                            end
                        end
                    end
                end
            end
        end
    end
end

function battleRoyale.reset()
    battleRoyale.load()
end

function battleRoyale.setPlayerColor(color)
    battleRoyale.playerColor = color
end

function battleRoyale.sendGameStateSync()
    -- Only send sync from host
    if _G and _G.returnState == "hosting" and _G.serverClients then
        local message = string.format("battle_sync,%.2f,%.2f,%.2f,%.2f", 
            battleRoyale.gameTime, 
            battleRoyale.center_x, 
            battleRoyale.center_y, 
            battleRoyale.safe_zone_radius)
        
        for _, client in ipairs(_G.serverClients) do
            if _G.safeSend then
                _G.safeSend(client, message)
            end
        end
    end
end

return battleRoyale
