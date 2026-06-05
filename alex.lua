local alexModule = {}

alexModule.jugador = {
    x = 400,
    y = 300,
    velocidad = 150,
    direccion = "down",
    estado = "idle",
    escala = 1.5,
    col_w = 12,
    col_h = 8,
    inventory = {},
    vida = 3,
    selectedSlot = nil,
    equipo = nil,
    tiempoInmune = 0,
    tiempoAtaque = 0,
    cuadroAtaque = 1,
    golpeDetectado = false,
    tiempoColisionSound = 0
}

function alexModule.iniciar(rutaMapa)
    local j = alexModule.jugador
    if rutaMapa == "levels/mission01.lua" then
        j.x = 424
        j.y = 312
    else
        j.x = 400
        j.y = 300
    end
    j.estado = "idle"
    j.direccion = "down"
    j.inventory = {}
    j.vida = 3
    j.selectedSlot = nil
    j.equipo = nil
    j.tiempoInmune = 0
    j.tiempoAtaque = 0
    j.cuadroAtaque = 1
    j.golpeDetectado = false
    j.tiempoColisionSound = 0
end

function alexModule.update(dt, colisiona, zombies, pickups, mostrarMensaje, cambiarGameState)
    local j = alexModule.jugador

    -- Control de inmunidad
    if j.tiempoInmune > 0 then
        j.tiempoInmune = j.tiempoInmune - dt
    end

    -- Cooldown del sonido de colisión
    if j.tiempoColisionSound > 0 then
        j.tiempoColisionSound = j.tiempoColisionSound - dt
    end

    -- Ataque con bate
    if j.estado == "attack" then
        j.tiempoAtaque = j.tiempoAtaque + dt
        local animKey = "attack_bat"
        local anim = animaciones.banco[animKey] and animaciones.banco[animKey][j.direccion]
        if anim then
            local frameDuration = 0.08
            j.cuadroAtaque = math.floor(j.tiempoAtaque / frameDuration) + 1
            
            -- Verificar impacto a mitad de la animación
            local midFrame = math.floor(anim.total / 2) + 1
            if j.cuadroAtaque == midFrame and not j.golpeDetectado then
                j.golpeDetectado = true
                
                for _, z in ipairs(zombies) do
                    if z.activo and z.vida > 0 then
                        local dist = math.sqrt((j.x - z.x)^2 + (j.y - z.y)^2)
                        if dist < 45 then
                            local deCara = false
                            if j.direccion == "right" and z.x > j.x - 10 then deCara = true
                            elseif j.direccion == "left" and z.x < j.x + 10 then deCara = true
                            elseif j.direccion == "up" and z.y < j.y + 10 then deCara = true
                            elseif j.direccion == "down" and z.y > j.y - 10 then deCara = true
                            end
                            
                            if deCara then
                                if _G.reproducirSonido then _G.reproducirSonido("hit_bat") end
                                z.vida = z.vida - 1
                                z.tiempoFlashRed = 0.2
                                z.alertado = true
                                
                                -- Retroceso físico
                                local kx, ky = 0, 0
                                if j.direccion == "right" then kx = 1
                                elseif j.direccion == "left" then kx = -1
                                elseif j.direccion == "up" then ky = -1
                                elseif j.direccion == "down" then ky = 1
                                end
                                
                                local retroceso = 30
                                local targetZombieX = z.x + kx * retroceso
                                local targetZombieY = z.y + ky * retroceso
                                
                                local z_col_x = targetZombieX - z.col_w / 2
                                local z_col_y = targetZombieY + (8 * z.escala) - z.col_h
                                if not colisiona(z_col_x, z_col_y, z.col_w, z.col_h) then
                                    z.x = targetZombieX
                                    z.y = targetZombieY
                                end
                                
                                if z.vida <= 0 then
                                    if _G.reproducirSonido then _G.reproducirSonido("death_zombie") end
                                    z.estado = "death"
                                    z.tiempoMuerte = 0
                                end
                            end
                        end
                    end
                end
            end
            
            if j.cuadroAtaque > anim.total then
                j.estado = "idle"
                j.tiempoAtaque = 0
                j.cuadroAtaque = 1
                j.golpeDetectado = false
            end
        else
            j.estado = "idle"
        end
    end

    -- Movimiento del jugador (bloqueado si está atacando)
    local moviendose = false
    local dx, dy = 0, 0
    
    if j.estado ~= "attack" then
        if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
            dy = -1
            j.direccion = "up"
            moviendose = true
        elseif love.keyboard.isDown("s") or love.keyboard.isDown("down") then
            dy = 1
            j.direccion = "down"
            moviendose = true
        end
        
        if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
            dx = -1
            j.direccion = "left"
            moviendose = true
        elseif love.keyboard.isDown("d") or love.keyboard.isDown("right") then
            dx = 1
            j.direccion = "right"
            moviendose = true
        end
        
        if moviendose then
            j.estado = "run"
            
            -- Activar la voz del tutorial al moverse por primera vez
            if _G.tutorialActive and not _G.tutorialFlags.moved then
                _G.tutorialFlags.moved = true
                if _G.reproducirVoz then
                    _G.reproducirVoz("voz_tutorial_info_pickables", true)
                end
            end
            
            if dx ~= 0 and dy ~= 0 then
                local len = math.sqrt(dx*dx + dy*dy)
                dx = dx / len
                dy = dy / len
            end
            
            local nuevo_x = j.x + dx * j.velocidad * dt
            local nuevo_y = j.y + dy * j.velocidad * dt
            local colisionado = false
            
            local col_x = nuevo_x - j.col_w / 2
            local col_y = j.y + (8 * j.escala) - j.col_h
            if not colisiona(col_x, col_y, j.col_w, j.col_h) then
                j.x = nuevo_x
            else
                if dx ~= 0 then colisionado = true end
            end
            
            col_x = j.x - j.col_w / 2
            col_y = nuevo_y + (8 * j.escala) - j.col_h
            if not colisiona(col_x, col_y, j.col_w, j.col_h) then
                j.y = nuevo_y
            else
                if dy ~= 0 then colisionado = true end
            end

            -- Sonido de colisión con cooldown para evitar saturación
            if colisionado and j.tiempoColisionSound <= 0 then
                if _G.reproducirSonido then _G.reproducirSonido("collision") end
                j.tiempoColisionSound = 0.35
                
                -- Si el tutorial o la misión 01 está activa, también reproducir la voz de evasión de obstáculo
                if _G.tutorialActive or _G.mission01Active then
                    local rightFree = not colisiona(j.x + 24 - j.col_w/2, j.y + (8 * j.escala) - j.col_h, j.col_w, j.col_h)
                    local leftFree = not colisiona(j.x - 24 - j.col_w/2, j.y + (8 * j.escala) - j.col_h, j.col_w, j.col_h)
                    local upFree = not colisiona(j.x - j.col_w/2, j.y + (8 * j.escala) - 24 - j.col_h, j.col_w, j.col_h)
                    local downFree = not colisiona(j.x - j.col_w/2, j.y + (8 * j.escala) + 24 - j.col_h, j.col_w, j.col_h)
                    
                    local blockedDir = nil
                    if dx > 0 then blockedDir = "derecha"
                    elseif dx < 0 then blockedDir = "izquierda"
                    elseif dy > 0 then blockedDir = "abajo"
                    elseif dy < 0 then blockedDir = "arriba"
                    end
                    
                    local dir = nil
                    if blockedDir == "derecha" or blockedDir == "izquierda" then
                        if upFree and downFree then
                            if _G.objetivoActual then
                                local distUp = math.abs((j.y - 24) - _G.objetivoActual.y)
                                local distDown = math.abs((j.y + 24) - _G.objetivoActual.y)
                                dir = (distUp < distDown) and "arriba" or "abajo"
                            else
                                dir = "arriba"
                            end
                        elseif upFree then dir = "arriba"
                        elseif downFree then dir = "abajo"
                        elseif blockedDir == "derecha" and leftFree then dir = "izquierda"
                        elseif blockedDir == "izquierda" and rightFree then dir = "derecha"
                        end
                    elseif blockedDir == "arriba" or blockedDir == "abajo" then
                        if rightFree and leftFree then
                            if _G.objetivoActual then
                                local distRight = math.abs((j.x + 24) - _G.objetivoActual.x)
                                local distLeft = math.abs((j.x - 24) - _G.objetivoActual.x)
                                dir = (distRight < distLeft) and "derecha" or "izquierda"
                            else
                                dir = "derecha"
                            end
                        elseif rightFree then dir = "derecha"
                        elseif leftFree then dir = "izquierda"
                        elseif blockedDir == "arriba" and downFree then dir = "abajo"
                        elseif blockedDir == "abajo" and upFree then dir = "arriba"
                        end
                    end
                    
                    if not dir then
                        if rightFree then dir = "derecha"
                        elseif leftFree then dir = "izquierda"
                        elseif upFree then dir = "arriba"
                        elseif downFree then dir = "abajo"
                        else dir = "derecha"
                        end
                    end
                    
                    if _G.activarAlertaObstaculo and blockedDir then
                        _G.activarAlertaObstaculo(blockedDir, dir)
                    end
                end
            end
        else
            j.estado = "idle"
        end
    end
    
    -- Lógica de recolección de pickups
    local i = 1
    while i <= #pickups do
        local p = pickups[i]
        local distX = j.x - p.cx
        local distY = j.y - p.cy
        local dist = math.sqrt(distX * distX + distY * distY)
        
        if dist < 20 then
            if _G.reproducirSonido then _G.reproducirSonido("pickup") end
            table.insert(j.inventory, {
                tipo = p.tipo,
                gid = p.gid,
                image = p.image,
                iconImage = p.iconImage,
                imgW = p.imgW,
                imgH = p.imgH
            })

            -- Voces del tutorial para recolección de objetos
            if _G.tutorialActive then
                -- Primer objeto recogido
                if not _G.tutorialFlags.pickedAny then
                    _G.tutorialFlags.pickedAny = true
                    if _G.reproducirVoz then
                        _G.reproducirVoz("voz_tutorial_info_inventario", true)
                    end
                end
                
                -- Si recoge el bate
                if p.tipo == "bat" and not _G.tutorialFlags.pickedBat then
                    _G.tutorialFlags.pickedBat = true
                    if _G.reproducirVoz then
                        _G.reproducirVoz("voz_tutorial_info_bate", true)
                    end
                end
                
                -- Si recoge una venda
                if p.tipo == "bandage" and not _G.tutorialFlags.pickedBandage then
                    _G.tutorialFlags.pickedBandage = true
                    if _G.reproducirVoz then
                        _G.reproducirVoz("voz_tutorial_info_benda", true)
                    end
                end
            end

            table.remove(pickups, i)
        else
            i = i + 1
        end
    end
end

function alexModule.draw(animaciones, debug_colisiones)
    local j = alexModule.jugador

    -- Configurar color y parpadeo si es inmune
    love.graphics.setColor(1, 1, 1, 1)
    if j.tiempoInmune > 0 then
        if math.floor(love.timer.getTime() * 15) % 2 == 0 then
            love.graphics.setColor(1, 1, 1, 0.3)
        end
    end

    if j.equipo == "bat" then
        -- 1. Dibujar el cuerpo (nohands)
        local cuerpoKey = j.estado .. "_nohands"
        if j.estado == "attack" then
            cuerpoKey = "punch_nohands"
        end
        local cuerpoAnim = animaciones.banco[cuerpoKey] and animaciones.banco[cuerpoKey][j.direccion]
        
        local armaKey = "idle_bat"
        if j.estado == "run" then
            armaKey = "run_bat"
        elseif j.estado == "attack" then
            armaKey = "attack_bat"
        end
        local armaAnim = animaciones.banco[armaKey] and animaciones.banco[armaKey][j.direccion]
        
        if cuerpoAnim then
            local frameIdx = animaciones.cuadroActual
            if j.estado == "attack" and armaAnim then
                local progress = (j.cuadroAtaque - 1) / (armaAnim.total - 1)
                frameIdx = math.floor(progress * (cuerpoAnim.total - 1)) + 1
            end
            local quadIdx = math.max(1, math.min(frameIdx, cuerpoAnim.total))
            
            love.graphics.draw(
                cuerpoAnim.sheet, 
                cuerpoAnim.quads[quadIdx], 
                j.x, 
                j.y, 
                0,    
                j.escala,
                j.escala,
                cuerpoAnim.w / 2,
                cuerpoAnim.h / 2
            )
        end
        
        -- Resetear el color para el arma en caso de parpadeo
        love.graphics.setColor(1, 1, 1, 1)
        if j.tiempoInmune > 0 then
            if math.floor(love.timer.getTime() * 15) % 2 == 0 then
                love.graphics.setColor(1, 1, 1, 0.3)
            end
        end

        -- 2. Dibujar el bate (overlay)
        if armaAnim then
            local frameIdx = animaciones.cuadroActual
            if j.estado == "attack" then
                frameIdx = j.cuadroAtaque
            end
            local quadIdx = math.max(1, math.min(frameIdx, armaAnim.total))
            
            love.graphics.draw(
                armaAnim.sheet, 
                armaAnim.quads[quadIdx], 
                j.x, 
                j.y, 
                0,    
                j.escala,
                j.escala,
                armaAnim.w / 2,
                armaAnim.h / 2
            )
        end
    else
        -- Dibujado normal sin arma
        local animacionActual = animaciones.banco[j.estado] and animaciones.banco[j.estado][j.direccion]
        if animacionActual then
            love.graphics.draw(
                animacionActual.sheet, 
                animacionActual.quads[animaciones.cuadroActual], 
                j.x, 
                j.y, 
                0,    
                j.escala,
                j.escala,
                animacionActual.w / 2,
                animacionActual.h / 2
            )
        end
    end

    love.graphics.setColor(1, 1, 1, 1)

    -- Caja de colisión en modo debug
    if debug_colisiones then
        love.graphics.setColor(0, 1, 0, 0.6)
        local col_x = j.x - j.col_w / 2
        local col_y = j.y + (8 * j.escala) - j.col_h
        love.graphics.rectangle("fill", col_x, col_y, j.col_w, j.col_h)
    end
end

function alexModule.keypressed(key, mostrarMensaje)
    local j = alexModule.jugador

    if key == "space" and j.estado ~= "attack" and j.equipo == "bat" then
        j.estado = "attack"
        j.tiempoAtaque = 0
        j.cuadroAtaque = 1
        j.golpeDetectado = false
    elseif key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "6" then
        local idx = tonumber(key)
        if j.inventory[idx] then
            local item = j.inventory[idx]
            if item.tipo == "bandage" then
                if _G.reproducirVoz then _G.reproducirVoz("voz_benda") end
                if j.vida < 3 then
                    j.vida = math.min(3, j.vida + 1)
                    table.remove(j.inventory, idx)
                    mostrarMensaje("¡Te has curado! Vida: " .. j.vida .. "/3")
                    if j.selectedSlot == idx then
                        j.selectedSlot = nil
                    end
                else
                    mostrarMensaje("¡Vida al máximo!")
                end
            elseif item.tipo == "bat" then
                if _G.reproducirVoz then _G.reproducirVoz("voz_bate") end
                if j.selectedSlot == idx then
                    j.selectedSlot = nil
                    j.equipo = nil
                    mostrarMensaje("Bate desequipado")
                else
                    j.selectedSlot = idx
                    j.equipo = "bat"
                    mostrarMensaje("Bate equipado")
                end
            else
                if item.tipo == "canned-soup" or item.tipo == "canned-food" then
                    if _G.reproducirVoz then _G.reproducirVoz("voz_latasopa") end
                end
                if j.selectedSlot == idx then
                    j.selectedSlot = nil
                    mostrarMensaje("Ranura deseleccionada")
                else
                    j.selectedSlot = idx
                    mostrarMensaje("Seleccionado: " .. item.tipo:upper())
                end
            end
        else
            if _G.reproducirVoz then _G.reproducirVoz("voz_vacio") end
            j.selectedSlot = nil
            j.equipo = nil
        end
    end
end

function alexModule.mousepressed(button)
    local j = alexModule.jugador
    if j.estado ~= "attack" and j.equipo == "bat" and button == 1 then
        j.estado = "attack"
        j.tiempoAtaque = 0
        j.cuadroAtaque = 1
        j.golpeDetectado = false
    end
end

return alexModule
