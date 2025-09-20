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
battleRoyale.timer = (musicHandler.beatInterval * 13) -- 25 seconds
battleRoyale.safe_zone_radius = 450
battleRoyale.center_x = 400
battleRoyale.center_y = 300
battleRoyale.death_timer = 0
battleRoyale.death_shake = 0
battleRoyale.player_dropped = false
battleRoyale.death_animation_done = false
battleRoyale.shrink_phase = "initial_pause" -- "initial_pause", "shrinking", or "paused"
battleRoyale.initial_pause_timer = 3 -- 3 seconds initial pause
battleRoyale.shrink_timer = 3 -- 3 seconds of shrinking
battleRoyale.pause_timer = 2 -- 2 seconds of pause
battleRoyale.safe_zone_move_speed = 30 -- pixels per second
battleRoyale.safe_zone_move_timer = 0
battleRoyale.safe_zone_target_x = 400
battleRoyale.safe_zone_target_y = 300

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
    teleport_active = false,
    teleport_timer = 0,
    shield_active = false,
    shield_timer = 0,
    freeze_active = false,
    freeze_timer = 0,
    laser_active = false,
    laser_timer = 0,
    laser_angle = 0
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
battleRoyale.asteroid_spawn_interval = 1.5 -- Spawn every 1.5 seconds for more chaos
battleRoyale.asteroid_speed = 200 -- Pixels per second (faster to match music)

function battleRoyale.load()
    -- Reset game state
    battleRoyale.game_over = false
    battleRoyale.current_round_score = 0
    battleRoyale.death_timer = 0
    battleRoyale.death_shake = 0
    battleRoyale.player_dropped = false
    battleRoyale.death_animation_done = false
    battleRoyale.game_started = false
    battleRoyale.start_timer = 3
    battleRoyale.shrink_timer = 0
    battleRoyale.shrink_padding_x = 0
    battleRoyale.shrink_padding_y = 0
    battleRoyale.safe_zone_radius = 400
    battleRoyale.player.drop_cooldown = 0
    battleRoyale.player.dropping = false
    battleRoyale.player.jump_count = 0
    battleRoyale.player.has_double_jumped = false
    battleRoyale.player.on_ground = false
    battleRoyale.timer = (musicHandler.beatInterval * 13) -- 25 seconds

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
        teleport_active = false,
        teleport_timer = 0,
        shield_active = false,
        shield_timer = 0,
        freeze_active = false,
        freeze_timer = 0,
        laser_active = false,
        laser_timer = 0,
        laser_angle = 0
    }

    -- Reset safe zone to center
    battleRoyale.center_x = 400
    battleRoyale.center_y = 300
    battleRoyale.safe_zone_radius = 450
    
    -- Create game elements
    battleRoyale.createPowerUps()
    battleRoyale.asteroids = {}
    battleRoyale.asteroid_spawn_timer = 0

    debugConsole.addMessage("[BattleRoyale] Game loaded")
end

function battleRoyale.update(dt)
    -- Update music effects
    musicHandler.update(dt)
    
    if not battleRoyale.game_started then
        battleRoyale.start_timer = math.max(0, battleRoyale.start_timer - dt)
        battleRoyale.game_started = battleRoyale.start_timer == 0
        return
    end

    if battleRoyale.game_over then return end

    battleRoyale.timer = battleRoyale.timer - dt
    if battleRoyale.timer <= 0 then
        battleRoyale.timer = 0
        battleRoyale.game_over = true
        
        -- Send final score
        if _G.gameState == "hosting" then
            if _G.players[_G.localPlayer.id] then
                _G.players[_G.localPlayer.id].totalScore = 
                    (_G.players[_G.localPlayer.id].totalScore or 0) + battleRoyale.current_round_score
                _G.localPlayer.totalScore = _G.players[_G.localPlayer.id].totalScore
            end
            
            -- Broadcast to clients
            for _, client in ipairs(_G.serverClients or {}) do
                safeSend(client, string.format("total_score,%d,%d", 
                    _G.localPlayer.id, 
                    _G.players[_G.localPlayer.id].totalScore))
            end
        else
            if _G.server then
                safeSend(_G.server, "battleroyale_score," .. math.floor(battleRoyale.current_round_score))
            end
        end
        
        if _G.returnState then
            _G.gameState = _G.returnState
        end
        return
    end

    -- Update safe zone movement
    battleRoyale.safe_zone_move_timer = battleRoyale.safe_zone_move_timer + dt
    if battleRoyale.safe_zone_move_timer >= 2 then -- Change target every 2 seconds
        battleRoyale.safe_zone_move_timer = 0
        -- Generate new target position within screen bounds
        local margin = math.max(50, battleRoyale.safe_zone_radius + 50)
        battleRoyale.safe_zone_target_x = math.random(margin, battleRoyale.screen_width - margin)
        battleRoyale.safe_zone_target_y = math.random(margin, battleRoyale.screen_height - margin)
    end
    
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

    -- Update shrinking safe zone with intervals
    if not battleRoyale.player.freeze_active then
        if battleRoyale.shrink_phase == "initial_pause" then
            battleRoyale.initial_pause_timer = battleRoyale.initial_pause_timer - dt
            if battleRoyale.initial_pause_timer <= 0 then
                battleRoyale.shrink_phase = "shrinking"
                battleRoyale.shrink_timer = 3
            end
        elseif battleRoyale.shrink_phase == "shrinking" then
            battleRoyale.shrink_timer = battleRoyale.shrink_timer - dt
            battleRoyale.safe_zone_radius = battleRoyale.safe_zone_radius - (dt * 20) -- Shrink 20 pixels per second during shrink phase
            if battleRoyale.shrink_timer <= 0 then
                battleRoyale.shrink_phase = "paused"
                battleRoyale.pause_timer = 2
            end
        elseif battleRoyale.shrink_phase == "paused" then
            battleRoyale.pause_timer = battleRoyale.pause_timer - dt
            if battleRoyale.pause_timer <= 0 then
                battleRoyale.shrink_phase = "shrinking"
                battleRoyale.shrink_timer = 3
            end
        end
    end
    battleRoyale.safe_zone_radius = math.max(0, battleRoyale.safe_zone_radius) -- Minimum radius of 0 (completely closed)

    -- Handle top-down movement
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

    -- Keep player within screen bounds
    battleRoyale.player.x = math.max(0, math.min(battleRoyale.screen_width - battleRoyale.player.width, battleRoyale.player.x))
    battleRoyale.player.y = math.max(0, math.min(battleRoyale.screen_height - battleRoyale.player.height, battleRoyale.player.y))

    -- Update laser angle based on mouse position
    local mx, my = love.mouse.getPosition()
    battleRoyale.player.laser_angle = math.atan2(my - battleRoyale.player.y - battleRoyale.player.height/2, 
                                                mx - battleRoyale.player.x - battleRoyale.player.width/2)

    -- Check if player is outside safe zone
    local distance_from_center = math.sqrt(
        (battleRoyale.player.x + battleRoyale.player.width/2 - battleRoyale.center_x)^2 + 
        (battleRoyale.player.y + battleRoyale.player.height/2 - battleRoyale.center_y)^2
    )
    
    if distance_from_center > battleRoyale.safe_zone_radius and not battleRoyale.player.is_invincible and not battleRoyale.player_dropped then
        battleRoyale.player_dropped = true
        battleRoyale.death_timer = 2 -- 2 second death animation
        battleRoyale.death_shake = 15 -- Shake intensity
        debugConsole.addMessage("[BattleRoyale] Player died outside safe zone!")
    end

    -- Handle powerup collisions
    for i = #battleRoyale.powerUps, 1, -1 do
        local powerUp = battleRoyale.powerUps[i]
        if battleRoyale.checkCollision(battleRoyale.player, powerUp) then
            if battleRoyale.collectPowerUp(powerUp) then
                table.remove(battleRoyale.powerUps, i)
            end
        end
    end

    -- Update power-up timers
    if battleRoyale.player.speed_up_active then
        battleRoyale.player.speed_up_timer = battleRoyale.player.speed_up_timer - dt
        if battleRoyale.player.speed_up_timer <= 0 then
            battleRoyale.player.speed_up_active = false
            battleRoyale.player.speed = battleRoyale.player.normal_speed
            debugConsole.addMessage("[BattleRoyale] Speed boost expired")
        end
    end
    
    if battleRoyale.player.is_invincible then
        battleRoyale.player.invincibility_timer = battleRoyale.player.invincibility_timer - dt
        if battleRoyale.player.invincibility_timer <= 0 then
            battleRoyale.player.is_invincible = false
            debugConsole.addMessage("[BattleRoyale] Invincibility expired")
        end
    end

    if battleRoyale.player.teleport_active then
        battleRoyale.player.teleport_timer = battleRoyale.player.teleport_timer - dt
        if battleRoyale.player.teleport_timer <= 0 then
            battleRoyale.player.teleport_active = false
            debugConsole.addMessage("[BattleRoyale] Teleport expired")
        end
    end

    if battleRoyale.player.shield_active then
        battleRoyale.player.shield_timer = battleRoyale.player.shield_timer - dt
        if battleRoyale.player.shield_timer <= 0 then
            battleRoyale.player.shield_active = false
            debugConsole.addMessage("[BattleRoyale] Shield expired")
        end
    end

    if battleRoyale.player.freeze_active then
        battleRoyale.player.freeze_timer = battleRoyale.player.freeze_timer - dt
        if battleRoyale.player.freeze_timer <= 0 then
            battleRoyale.player.freeze_active = false
            debugConsole.addMessage("[BattleRoyale] Freeze expired")
        end
    end

    if battleRoyale.player.laser_active then
        battleRoyale.player.laser_timer = battleRoyale.player.laser_timer - dt
        if battleRoyale.player.laser_timer <= 0 then
            battleRoyale.player.laser_active = false
            debugConsole.addMessage("[BattleRoyale] Laser expired")
        end
    end

    -- Update lasers
    for i = #battleRoyale.lasers, 1, -1 do
        local laser = battleRoyale.lasers[i]
        laser.time = laser.time + dt
        if laser.time >= laser.duration then
            table.remove(battleRoyale.lasers, i)
        end
    end

    -- Update asteroids
    battleRoyale.updateAsteroids(dt)
    
    -- Check asteroid collisions with player
    battleRoyale.checkAsteroidCollisions()

    -- Update death timer and shake
    if battleRoyale.death_timer > 0 then
        battleRoyale.death_timer = battleRoyale.death_timer - dt
        battleRoyale.death_shake = battleRoyale.death_shake * 0.85 -- Decay shake
        if battleRoyale.death_timer <= 0 then
            battleRoyale.death_timer = 0
            battleRoyale.death_shake = 0
            battleRoyale.death_animation_done = true
            battleRoyale.game_over = true
        end
    end

    -- Update scoring based on survival time
    battleRoyale.current_round_score = battleRoyale.current_round_score + math.floor(dt * 10)
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
    
    -- Draw safe zone
    battleRoyale.drawSafeZone()
    
    -- Draw game elements
    battleRoyale.drawPowerUps()
    battleRoyale.drawLasers()
    battleRoyale.drawAsteroids()
    
    -- Draw other players
    if playersTable then
        for id, player in pairs(playersTable) do
            if id ~= localPlayerId and player.battleX and player.battleY then
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
    
    -- Draw local player (only if not dropped)
    if not battleRoyale.player_dropped then
        if playersTable and playersTable[localPlayerId] then
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



function battleRoyale.drawSafeZone()
    -- Only draw if radius is greater than 0
    if battleRoyale.safe_zone_radius > 0 then
        -- Get rhythmic rotation for safety circle (only when music is playing)
        local rotation = 0
        if musicHandler.music and musicHandler.isPlaying then
            local _, _, rhythmicRotation = musicHandler.applyToDrawable("safety_circle_rotate", 1, 1)
            rotation = rhythmicRotation or 0
            
            -- Add continuous rotation for more dynamic movement
            local time = love.timer.getTime()
            rotation = rotation + time * 0.5 -- Continuous slow rotation
        end
        
        -- Draw safe zone circle with consistent color
        love.graphics.setColor(0, 1, 0, 0.3) -- Fixed alpha, no color changes
        love.graphics.circle('fill', battleRoyale.center_x, battleRoyale.center_y, battleRoyale.safe_zone_radius)
        
        -- Draw safe zone border with phase-based color and rhythmic rotation
        love.graphics.push()
        love.graphics.translate(battleRoyale.center_x, battleRoyale.center_y)
        love.graphics.rotate(rotation)
        
        if battleRoyale.shrink_phase == "initial_pause" then
            love.graphics.setColor(1, 1, 0.5, 1) -- Yellowish when getting ready
        elseif battleRoyale.shrink_phase == "shrinking" then
            love.graphics.setColor(1, 0.5, 0.5, 1) -- Reddish when shrinking
        else
            love.graphics.setColor(0.5, 1, 0.5, 1) -- Greenish when paused
        end
        love.graphics.circle('line', 0, 0, battleRoyale.safe_zone_radius)
        
        love.graphics.pop()
    end
    
    -- Draw center dot (always visible)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle('fill', battleRoyale.center_x, battleRoyale.center_y, 3)
    
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
    if battleRoyale.player.teleport_active then
        love.graphics.print('Teleport: ' .. string.format("%.1f", battleRoyale.player.teleport_timer), 10, activeY)
        activeY = activeY + 20
    end
    if battleRoyale.player.shield_active then
        love.graphics.print('Shield: ' .. string.format("%.1f", battleRoyale.player.shield_timer), 10, activeY)
        activeY = activeY + 20
    end
    if battleRoyale.player.freeze_active then
        love.graphics.print('Freeze: ' .. string.format("%.1f", battleRoyale.player.freeze_timer), 10, activeY)
        activeY = activeY + 20
    end
    if battleRoyale.player.laser_active then
        love.graphics.print('Laser: ' .. string.format("%.1f", battleRoyale.player.laser_timer), 10, activeY)
        activeY = activeY + 20
    end
    
    -- Show safe zone info
    love.graphics.print('Safe Zone Radius: ' .. math.floor(battleRoyale.safe_zone_radius), 10, battleRoyale.screen_height - 80)
    
    -- Show shrink phase
    local phase_text = "PAUSED"
    local phase_color = {0.5, 1, 0.5}
    if battleRoyale.shrink_phase == "initial_pause" then
        phase_text = "GET READY"
        phase_color = {1, 1, 0.5}
    elseif battleRoyale.shrink_phase == "shrinking" then
        phase_text = "SHRINKING"
        phase_color = {1, 0.5, 0.5}
    end
    love.graphics.setColor(phase_color[1], phase_color[2], phase_color[3])
    love.graphics.print('Phase: ' .. phase_text, 10, battleRoyale.screen_height - 60)
    
    -- Show timer
    local timer_value = 0
    if battleRoyale.shrink_phase == "initial_pause" then
        timer_value = battleRoyale.initial_pause_timer
    elseif battleRoyale.shrink_phase == "shrinking" then
        timer_value = battleRoyale.shrink_timer
    else
        timer_value = battleRoyale.pause_timer
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('Timer: ' .. string.format("%.1f", timer_value), 10, battleRoyale.screen_height - 40)
    
    love.graphics.print('Press E to use power-ups', 10, battleRoyale.screen_height - 20)
    
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


function battleRoyale.createPowerUps()
    battleRoyale.powerUps = {}
    local powerUpTypes = {'speed', 'teleport', 'shield', 'freeze', 'laser'}
    for i = 1, 15 do
        local x = math.random(50, battleRoyale.screen_width - 50)
        local y = math.random(50, battleRoyale.screen_height - 50)
        local pType = powerUpTypes[math.random(1, #powerUpTypes)]
        table.insert(battleRoyale.powerUps, {
            x = x,
            y = y,
            width = 35,
            height = 35,
            type = pType
        })
    end
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

function battleRoyale.drawPowerUps()
    for _, powerUp in ipairs(battleRoyale.powerUps) do
        -- Draw power up circle
        if powerUp.type == 'speed' then
            love.graphics.setColor(1, 1, 0)  -- Yellow for speed
        elseif powerUp.type == 'teleport' then
            love.graphics.setColor(0, 1, 0)  -- Green for teleport
        elseif powerUp.type == 'shield' then
            love.graphics.setColor(0, 0, 1)  -- Blue for shield
        elseif powerUp.type == 'freeze' then
            love.graphics.setColor(0, 1, 1)  -- Cyan for freeze
        elseif powerUp.type == 'laser' then
            love.graphics.setColor(1, 0, 0)  -- Red for laser
        end
        love.graphics.circle('fill',
            powerUp.x + powerUp.width/2,
            powerUp.y + powerUp.height/2,
            powerUp.width/2)
            
        -- Draw power up type indicator
        love.graphics.setColor(0, 0, 0)
        local letter = powerUp.type:sub(1, 1):upper()
        love.graphics.printf(letter,
            powerUp.x,
            powerUp.y + powerUp.height/4,
            powerUp.width,
            'center')
    end
end

function battleRoyale.drawLasers()
    love.graphics.setColor(1, 0, 0, 0.8)
    for _, laser in ipairs(battleRoyale.lasers) do
        love.graphics.push()
        love.graphics.translate(laser.x, laser.y)
        love.graphics.rotate(laser.angle)
        love.graphics.rectangle('fill', 0, -laser.width/2, laser.length, laser.width)
        love.graphics.pop()
    end
end

function battleRoyale.keypressed(key)
    debugConsole.addMessage("[BattleRoyale] Key pressed: " .. key)
    
    if key == 'e' then
        debugConsole.addMessage("[BattleRoyale] E key pressed, powerups collected: " .. 
            #battleRoyale.player.powerUpsCollected)
        
        if #battleRoyale.player.powerUpsCollected > 0 then
            local powerUp = table.remove(battleRoyale.player.powerUpsCollected, 1)
            if powerUp then
                -- Play sound effect
                sounds.powerup:stop()
                sounds.powerup:play()
                
                debugConsole.addMessage("[BattleRoyale] Activating powerup: " .. powerUp.type)
                battleRoyale.activateSpecificPowerUp(powerUp.type)
            end
        end
    end
end

function battleRoyale.keyreleased(key)
    battleRoyale.keysPressed[key] = false
end

function battleRoyale.activateSpecificPowerUp(type)
    if type == 'speed' then
        battleRoyale.player.speed_up_active = true
        battleRoyale.player.speed_up_timer = 4
        battleRoyale.player.speed = battleRoyale.player.normal_speed * 1.8
        debugConsole.addMessage("[BattleRoyale] Speed boost activated! New speed: " .. battleRoyale.player.speed)
        
    elseif type == 'teleport' then
        battleRoyale.player.teleport_active = true
        battleRoyale.player.teleport_timer = 3
        -- Teleport to center of safe zone
        battleRoyale.player.x = battleRoyale.center_x - battleRoyale.player.width/2
        battleRoyale.player.y = battleRoyale.center_y - battleRoyale.player.height/2
        debugConsole.addMessage("[BattleRoyale] Teleported to center!")
        
    elseif type == 'shield' then
        battleRoyale.player.shield_active = true
        battleRoyale.player.shield_timer = 6
        debugConsole.addMessage("[BattleRoyale] Shield activated for " .. 
            battleRoyale.player.shield_timer .. " seconds")
        
    elseif type == 'freeze' then
        battleRoyale.player.freeze_active = true
        battleRoyale.player.freeze_timer = 5
        debugConsole.addMessage("[BattleRoyale] Safe zone freeze activated!")
        
    elseif type == 'laser' then
        battleRoyale.player.laser_active = true
        battleRoyale.player.laser_timer = 3
        -- Create laser beam
        local laser = {
            x = battleRoyale.player.x + battleRoyale.player.width/2,
            y = battleRoyale.player.y + battleRoyale.player.height/2,
            angle = battleRoyale.player.laser_angle,
            length = 250,
            width = 12,
            duration = 3,
            time = 0
        }
        table.insert(battleRoyale.lasers, laser)
        debugConsole.addMessage("[BattleRoyale] Laser fired!")
    end
end

function battleRoyale.updateAsteroids(dt)
    -- Spawn new asteroids on rhythm (every beat) or use timer if no music
    battleRoyale.asteroid_spawn_timer = battleRoyale.asteroid_spawn_timer + dt
    
    -- Check if we're on a beat (when music is playing) or use timer fallback
    local currentBeat = math.floor(musicHandler.effectBeat)
    local previousBeat = math.floor((musicHandler.effectTimer - dt) / musicHandler.beatInterval)
    
    if (musicHandler.music and musicHandler.isPlaying and currentBeat > previousBeat) or 
       battleRoyale.asteroid_spawn_timer >= battleRoyale.asteroid_spawn_interval then
        battleRoyale.spawnAsteroid()
        battleRoyale.asteroid_spawn_timer = 0
    end
    
    -- Update existing asteroids
    for i = #battleRoyale.asteroids, 1, -1 do
        local asteroid = battleRoyale.asteroids[i]
        
        -- Apply music-based speed multiplier when music is playing
        local speedMultiplier = 1
        if musicHandler.music and musicHandler.isPlaying then
            speedMultiplier = 1.5 -- 50% faster when music is playing
        end
        
        asteroid.x = asteroid.x + asteroid.vx * dt * speedMultiplier
        asteroid.y = asteroid.y + asteroid.vy * dt * speedMultiplier
        -- Removed rotation animation for stability
        
        -- Remove asteroids that are off screen
        if asteroid.x < -50 or asteroid.x > battleRoyale.screen_width + 50 or
           asteroid.y < -50 or asteroid.y > battleRoyale.screen_height + 50 then
            table.remove(battleRoyale.asteroids, i)
        end
    end
end

function battleRoyale.spawnAsteroid()
    local asteroid = {}
    local side = math.random(1, 4) -- 1=top, 2=right, 3=bottom, 4=left
    
    if side == 1 then -- Top
        asteroid.x = math.random(0, battleRoyale.screen_width)
        asteroid.y = -50
        asteroid.vx = math.random(-50, 50)
        asteroid.vy = math.random(50, 150)
    elseif side == 2 then -- Right
        asteroid.x = battleRoyale.screen_width + 50
        asteroid.y = math.random(0, battleRoyale.screen_height)
        asteroid.vx = math.random(-150, -50)
        asteroid.vy = math.random(-50, 50)
    elseif side == 3 then -- Bottom
        asteroid.x = math.random(0, battleRoyale.screen_width)
        asteroid.y = battleRoyale.screen_height + 50
        asteroid.vx = math.random(-50, 50)
        asteroid.vy = math.random(-150, -50)
    else -- Left
        asteroid.x = -50
        asteroid.y = math.random(0, battleRoyale.screen_height)
        asteroid.vx = math.random(50, 150)
        asteroid.vy = math.random(-50, 50)
    end
    
    asteroid.size = math.random(25, 45)
    asteroid.color = {0.5, 0.5, 0.5} -- Consistent gray color
    asteroid.points = {} -- Store irregular shape points
    battleRoyale.generateAsteroidShape(asteroid) -- Generate the irregular shape
    
    table.insert(battleRoyale.asteroids, asteroid)
end

function battleRoyale.generateAsteroidShape(asteroid)
    -- Generate irregular asteroid shape with 6-8 points
    local num_points = math.random(6, 8)
    asteroid.points = {}
    
    for i = 1, num_points do
        local angle = (i - 1) * (2 * math.pi / num_points)
        local radius_variation = math.random(0.7, 1.1) -- Make it irregular but not too extreme
        local base_radius = asteroid.size / 2
        local x = math.cos(angle) * base_radius * radius_variation
        local y = math.sin(angle) * base_radius * radius_variation
        
        -- Add some random jitter to make it more chaotic
        local jitter = asteroid.size / 10
        x = x + math.random(-jitter, jitter)
        y = y + math.random(-jitter, jitter)
        
        table.insert(asteroid.points, x)
        table.insert(asteroid.points, y)
    end
end

function battleRoyale.drawAsteroids()
    for _, asteroid in ipairs(battleRoyale.asteroids) do
        love.graphics.push()
        love.graphics.translate(asteroid.x, asteroid.y)
        -- Removed rotation for stability
        
        -- Draw asteroid with irregular shape
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.polygon('fill', asteroid.points)
        
        -- Draw outline
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.polygon('line', asteroid.points)
        
        -- Add some surface details for more chaos
        love.graphics.setColor(0.2, 0.2, 0.2)
        for i = 1, 2 do
            local detail_x = math.random(-asteroid.size/4, asteroid.size/4)
            local detail_y = math.random(-asteroid.size/4, asteroid.size/4)
            love.graphics.circle('fill', detail_x, detail_y, 3)
        end
        
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
            else
                debugConsole.addMessage("[BattleRoyale] Asteroid blocked by shield!")
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

return battleRoyale
