local zombieModule = {}

zombieModule.zombies = {}

local function crearZombi(startX, startY, colisiona)
    local z = {
        x = startX,
        y = startY,
        vida = 3,
        velocidad = 50,
        direccion = "left",
        estado = "idle",
        escala = 1.5,
        col_w = 12,
        col_h = 8,
        rangoDeteccion = 180,
        cooldownAtaque = 1.5,
        tiempoUltimoAtaque = 0,
        tiempoFlashRed = 0,
        tiempoMuerte = 0,
        activo = true
    }
    
    -- Escaneo inteligente de colisiones para spawn seguro del zombi (evitar paredes)
    local step = 8
    local found = false
    for r = 0, 15 do
        for x_offset = -r, r do
            for y_offset = -r, r do
                local testX = startX + x_offset * step
                local testY = startY + y_offset * step
                local z_col_x = testX - z.col_w / 2
                local z_col_y = testY + (8 * z.escala) - z.col_h
                if not colisiona(z_col_x, z_col_y, z.col_w, z.col_h) then
                    z.x = testX
                    z.y = testY
                    found = true
                    break
                end
            end
            if found then break end
        end
        if found then break end
    end
    
    return z
end

function zombieModule.iniciar(rutaMapa, colisiona)
    zombieModule.zombies = {}
    
    if rutaMapa == "levels/tutorial.lua" then
        -- Un único zombi a la derecha
        table.insert(zombieModule.zombies, crearZombi(580, 300, colisiona))
    elseif rutaMapa == "levels/mission01.lua" then
        -- Un zombi a la izquierda del mapa (x = 120, y = 300)
        table.insert(zombieModule.zombies, crearZombi(120, 300, colisiona))
        -- Un zombi en la parte superior del mapa (x = 424, y = 120)
        table.insert(zombieModule.zombies, crearZombi(424, 120, colisiona))
    end
end

function zombieModule.update(dt, colisiona, jugador, cambiarGameState)
    for _, z in ipairs(zombieModule.zombies) do
        if z.activo then
            if z.vida > 0 then
                if z.tiempoFlashRed > 0 then
                    z.tiempoFlashRed = z.tiempoFlashRed - dt
                end
                if z.tiempoUltimoAtaque > 0 then
                    z.tiempoUltimoAtaque = z.tiempoUltimoAtaque - dt
                end
                
                local distX = jugador.x - z.x
                local distY = jugador.y - z.y
                local dist = math.sqrt(distX * distX + distY * distY)
                
                if dist < z.rangoDeteccion and jugador.vida > 0 then
                    z.estado = "walk"
                    
                    if math.abs(distX) > math.abs(distY) then
                        z.direccion = distX > 0 and "right" or "left"
                    else
                        z.direccion = distY > 0 and "down" or "up"
                    end
                    
                    if dist > 20 then
                        local dx = distX / dist
                        local dy = distY / dist
                        
                        local nuevoX = z.x + dx * z.velocidad * dt
                        local nuevoY = z.y + dy * z.velocidad * dt
                        
                        local z_col_x = nuevoX - z.col_w / 2
                        local z_col_y = z.y + (8 * z.escala) - z.col_h
                        if not colisiona(z_col_x, z_col_y, z.col_w, z.col_h) then
                            z.x = nuevoX
                        end
                        
                        z_col_x = z.x - z.col_w / 2
                        z_col_y = nuevoY + (8 * z.escala) - z.col_h
                        if not colisiona(z_col_x, z_col_y, z.col_w, z.col_h) then
                            z.y = nuevoY
                        end
                    else
                        z.estado = "attack"
                        if z.tiempoUltimoAtaque <= 0 then
                            z.tiempoUltimoAtaque = z.cooldownAtaque
                            
                            if jugador.tiempoInmune <= 0 then
                                if _G.reproducirSonido then _G.reproducirSonido("zombie_attack") end
                                jugador.vida = jugador.vida - 1
                                jugador.tiempoInmune = 1.5
                                
                                -- Retroceso de Alex
                                local kx = distX > 0 and -1 or 1
                                local ky = distY > 0 and -1 or 1
                                local p_retroceso = 20
                                local targetPlayerX = jugador.x + kx * p_retroceso
                                local targetPlayerY = jugador.y + ky * p_retroceso
                                
                                local p_col_x = targetPlayerX - jugador.col_w / 2
                                local p_col_y = targetPlayerY + (8 * jugador.escala) - jugador.col_h
                                if not colisiona(p_col_x, p_col_y, jugador.col_w, jugador.col_h) then
                                    jugador.x = targetPlayerX
                                    jugador.y = targetPlayerY
                                end
                                
                                if jugador.vida <= 0 then
                                    if _G.reproducirSonido then _G.reproducirSonido("death_alex") end
                                    cambiarGameState("gameover")
                                end
                            end
                        end
                    end
                else
                    z.estado = "idle"
                end
            elseif z.estado == "death" then
                z.tiempoMuerte = z.tiempoMuerte + dt
                local deathDuration = 0.72
                if z.tiempoMuerte >= deathDuration then
                    z.activo = false
                end
            end
        end
    end
end

function zombieModule.draw(animaciones, debug_colisiones)
    for _, z in ipairs(zombieModule.zombies) do
        if z.activo then
            local zAnimKey = "zombie_" .. z.estado
            if z.estado == "death" then
                zAnimKey = "zombie_death"
            end
            
            local zAnim = animaciones.banco[zAnimKey] and animaciones.banco[zAnimKey][z.direccion]
            if zAnim then
                local zFrame = animaciones.cuadroActual
                if z.estado == "death" then
                    local frameDuration = 0.12
                    zFrame = math.min(zAnim.total, math.floor(z.tiempoMuerte / frameDuration) + 1)
                elseif z.estado == "attack" then
                    local frameDuration = 0.15
                    zFrame = math.min(zAnim.total, (math.floor(love.timer.getTime() / frameDuration) % zAnim.total) + 1)
                end
                
                local quadIdx = math.max(1, math.min(zFrame, zAnim.total))
                
                if z.tiempoFlashRed > 0 then
                    love.graphics.setColor(1, 0.2, 0.2, 1)
                else
                    love.graphics.setColor(1, 1, 1, 1)
                end
                
                love.graphics.draw(
                    zAnim.sheet,
                    zAnim.quads[quadIdx],
                    z.x,
                    z.y,
                    0,
                    z.escala,
                    z.escala,
                    zAnim.w / 2,
                    zAnim.h / 2
                )
            end

            love.graphics.setColor(1, 1, 1, 1)

            -- Caja de colisión en modo debug
            if debug_colisiones then
                love.graphics.setColor(0, 0, 1, 0.6)
                local z_col_x = z.x - z.col_w / 2
                local z_col_y = z.y + (8 * z.escala) - z.col_h
                love.graphics.rectangle("fill", z_col_x, z_col_y, z.col_w, z.col_h)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end
end

return zombieModule
