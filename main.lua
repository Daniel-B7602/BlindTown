-- Librería STI para cargar mapas de Tiled
local sti = require("libs.sti")

-- Variable global del mapa y estado del juego
local mapa
local debug_colisiones = false
local gameState = "menu" -- "menu" o "play"

-- Estructura del jugador y sus estados
-- Estructura del jugador y sus estados
local jugador = {
    x = 400,
    y = 300,
    velocidad = 150,
    direccion = "down", -- "up", "down", "left", "right"
    estado = "idle",    -- "idle", "run", "attack"
    escala = 1.5,
    col_w = 12,         -- Ancho de la caja de colisión (pies)
    col_h = 8,          -- Alto de la caja de colisión (pies)
    inventory = {},     -- Inventario del jugador
    vida = 3,           -- Salud actual del jugador (3 corazones)
    selectedSlot = nil, -- Ranura de inventario seleccionada
    equipo = nil,       -- Ítem equipado (ej. "bat")
    tiempoInmune = 0,   -- Periodo de inmunidad tras recibir daño
    tiempoAtaque = 0,   -- Tiempo transcurrido en animación de ataque
    cuadroAtaque = 1,   -- Fotograma actual del ataque
    golpeDetectado = false -- Bandera para procesar daño una única vez por swing
}

-- Alias global para acceder como alex.inventory
local alex = jugador

-- Lista global de rectángulos colisionables
local colisionables = {}

-- Lista de pickups activos en el suelo
local pickups = {}

-- Imágenes individuales de los pickups (cargadas desde los tilesets del mapa)
local pickupImages = {}

-- Íconos de inventario (desde assets/images/ui/inventory/objects/)
local inventoryIcons = {}

-- Mapeo de tipo de pickup -> nombre del ícono de inventario
local tipoToIcon = {
    ["bandage"]       = "Icon_Bandage.png",
    ["bat"]           = "Icon_Bat.png",
    ["canned-soup"]   = "Icon_Canned-soup.png",
    ["canned-food"]   = "Icon_Canned-food.png",
    ["pistol"]        = "Icon_Pistol.png",
    ["ammo-blue"]     = "Icon_Bullet-crate_Blue.png",
    ["ammo-green"]    = "Icon_Bullet-crate_Green.png",
    ["ammo-red"]      = "Icon_Bullet-crate_Red.png",
    ["bullet-blue"]   = "Icon_Bullet-box_Blue.png",
    ["bullet-green"]  = "Icon_Bullet-box_Green.png",
    ["bullet-red"]    = "Icon_Bullet-box_Red.png",
}

-- UI del inventario y salud
local inventoryBarImage
local inventoryBarW, inventoryBarH
local INVENTORY_SCALE = 3
local INVENTORY_SLOTS = 6
local SLOT_SIZE = 20  -- Tamaño de cada celda en píxeles originales del sprite
local heartFullImage
local heartEmptyImage

-- Estructura del Zombi enemigo
local zombi = {
    x = 580,
    y = 300,
    vida = 3,
    velocidad = 50,
    direccion = "left",
    estado = "idle", -- "idle", "walk", "attack", "death"
    escala = 1.5,
    col_w = 12,
    col_h = 8,
    rangoDeteccion = 180,
    cooldownAtaque = 1.5,
    tiempoUltimoAtaque = 0,
    tiempoFlashRed = 0,
    tiempoMuerte = 0,
    activo = false
}

-- Sistema de avisos/mensajes temporales en UI
local messageTimer = 0
local messageText = ""

local function mostrarMensaje(texto)
    messageText = texto
    messageTimer = 2.0
end

-- Contenedor de las animaciones del juego
local animaciones = {
    tiempoAcumulado = 0,
    velocidadEnmarcado = 0.12, -- Tiempo entre cuadros (un poco más rápido para correr)
    cuadroActual = 1,
    totalCuadros = 6,          -- Por defecto
    banco = {}                 -- Aquí guardaremos los spritesheets y sus quads
}

-- Función auxiliar para cargar de manera estructurada cada tira de animación
local function cargarAnimacion(estado, direccion, ruta, totalCuadros)
    local success, sprite = pcall(love.graphics.newImage, ruta)
    if not success then
        print("[Animacion] Error cargando ruta: " .. tostring(ruta) .. " -> " .. tostring(sprite))
        return
    end
    sprite:setFilter("nearest", "nearest") -- Pixel art nítido
    
    totalCuadros = totalCuadros or animaciones.totalCuadros
    local anchoTotal = sprite:getWidth()
    local altoTotal = sprite:getHeight()
    local anchoCuadro = anchoTotal / totalCuadros
    local altoCuadro = altoTotal
    
    local quads = {}
    for i = 0, totalCuadros - 1 do
        table.insert(quads, love.graphics.newQuad(
            i * anchoCuadro, 0, 
            anchoCuadro, altoCuadro, 
            anchoTotal, altoTotal
        ))
    end
    
    -- Guardamos en el banco indexando por [estado][direccion]
    if not animaciones.banco[estado] then animaciones.banco[estado] = {} end
    animaciones.banco[estado][direccion] = {
        sheet = sprite,
        quads = quads,
        w = anchoCuadro,
        h = altoCuadro,
        total = totalCuadros
    }
end

-- Función auxiliar para comprobar si un GID es colisionable
local function esGidColisionable(map, gid)
    if not gid or gid == 0 then return false end
    for _, tileset in ipairs(map.tilesets) do
        if gid >= tileset.firstgid and gid < tileset.firstgid + tileset.tilecount then
            local tile_id = gid - tileset.firstgid
            if tileset.tiles then
                for _, tile in ipairs(tileset.tiles) do
                    if tile.id == tile_id then
                        return tile.properties and tile.properties.collidable == true
                    end
                end
            end
            break
        end
    end
    return false
end

-- Cargar colisiones desde el mapa de STI
local function cargarColisiones(map)
    colisionables = {}
    
    -- 1. Analizar tileInstances para baldosas individuales
    for gid, instances in pairs(map.tileInstances) do
        if esGidColisionable(map, gid) then
            for _, instance in ipairs(instances) do
                table.insert(colisionables, {
                    x = instance.x + map.offsetx,
                    y = instance.y + map.offsety,
                    w = map.tilewidth,
                    h = map.tileheight
                })
            end
        end
    end

    -- 2. Analizar capas de objetos (edificios en objectgroup, vehículos, árboles, etc.)
    for _, layer in ipairs(map.layers) do
        if layer.type == "objectgroup" then
            -- Excluir la capa de pickups del sistema de colisiones
            if layer.name ~= "Pickable" and layer.name ~= "Pickups" then
                for _, obj in ipairs(layer.objects) do
                    local es_colisionable = (layer.properties and layer.properties.collidable == true) or
                                           (obj.properties and obj.properties.collidable == true) or
                                           (obj.gid and esGidColisionable(map, obj.gid))
                                           
                    if es_colisionable and obj.shape == "rectangle" then
                        local ox = obj.x + map.offsetx
                        local oy = obj.y + map.offsety
                        local ow = obj.width
                        local oh = obj.height
                        
                        if obj.gid then
                            -- Los objetos de tile (gid) tienen su origen abajo-izquierda en Tiled
                            oy = oy - oh
                        end
                        
                        table.insert(colisionables, {
                            x = ox,
                            y = oy,
                            w = ow,
                            h = oh
                        })
                    end
                end
            end
        end
    end

    -- 3. Si una capa entera de tiles tiene collidable = true
    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" and layer.properties and layer.properties.collidable == true then
            for y, row in pairs(layer.data) do
                for x, tile in pairs(row) do
                    table.insert(colisionables, {
                        x = (x - 1) * map.tilewidth + map.offsetx,
                        y = (y - 1) * map.tileheight + map.offsety,
                        w = map.tilewidth,
                        h = map.tileheight
                    })
                end
            end
        end
    end
end

-- Comprobar si una caja de colisión AABB intersecta con algún colisionable
local function colisiona(x, y, w, h)
    for _, rect in ipairs(colisionables) do
        if x < rect.x + rect.w and
           x + w > rect.x and
           y < rect.y + rect.h and
           y + h > rect.y then
            return true
        end
    end
    return false
end

-- Corregir ruta de imagen del mapa (las rutas del tileset usan '../' relativo a levels/)
local function corregirRuta(imgPath)
    if imgPath and imgPath:sub(1, 3) == "../" then
        return imgPath:sub(4)  -- Quitar '../' para que sea relativo al root del juego
    end
    return imgPath
end

-- Buscar la imagen de un tile por su GID en los tilesets del mapa
local function buscarImagenPorGid(map, gid)
    for _, tileset in ipairs(map.tilesets) do
        if gid >= tileset.firstgid and gid < tileset.firstgid + tileset.tilecount then
            local tile_id = gid - tileset.firstgid
            if tileset.tiles then
                for _, tile in ipairs(tileset.tiles) do
                    if tile.id == tile_id and tile.image then
                        return corregirRuta(tile.image), tile.width, tile.height
                    end
                end
            end
            break
        end
    end
    return nil
end

-- Cargar pickups del mapa (busca capas "Pickable" o "Pickups")
local function cargarPickups(map)
    pickups = {}
    pickupImages = {}
    
    for _, layer in ipairs(map.layers) do
        if layer.type == "objectgroup" and (layer.name == "Pickable" or layer.name == "Pickups") then
            -- Ocultar la capa de STI para evitar renderizado duplicado
            layer.visible = false
            
            for _, obj in ipairs(layer.objects) do
                local tipo = (obj.properties and obj.properties["tipo"]) or "unknown"
                
                -- El centro del objeto para calcular distancia
                local cx = obj.x + obj.width / 2
                -- En Tiled los objetos con gid tienen origen abajo-izquierda
                local cy
                if obj.gid then
                    cy = obj.y - obj.height / 2
                else
                    cy = obj.y + obj.height / 2
                end
                
                -- Buscar la imagen del tile para renderizar
                local imgPath, imgW, imgH
                if obj.gid then
                    imgPath, imgW, imgH = buscarImagenPorGid(map, obj.gid)
                end
                
                -- Cargar la imagen si existe y no la tenemos cacheada
                local image = nil
                if imgPath then
                    if not pickupImages[imgPath] then
                        local success, img = pcall(love.graphics.newImage, imgPath)
                        if success then
                            img:setFilter("nearest", "nearest")
                            pickupImages[imgPath] = img
                        else
                            print("[Pickup] Error cargando imagen: " .. imgPath .. " -> " .. tostring(img))
                        end
                    end
                    image = pickupImages[imgPath]
                end
                
                -- Cargar el ícono de inventario para este tipo
                local iconImg = nil
                local iconFile = tipoToIcon[tipo]
                if iconFile then
                    local iconPath = "assets/images/ui/inventory/objects/" .. iconFile
                    if not inventoryIcons[iconPath] then
                        local suc, ic = pcall(love.graphics.newImage, iconPath)
                        if suc then
                            ic:setFilter("nearest", "nearest")
                            inventoryIcons[iconPath] = ic
                        end
                    end
                    iconImg = inventoryIcons[iconPath]
                end
                
                table.insert(pickups, {
                    x = obj.x,
                    y = obj.gid and (obj.y - obj.height) or obj.y,
                    cx = cx,
                    cy = cy,
                    w = obj.width,
                    h = obj.height,
                    tipo = tipo,
                    gid = obj.gid,
                    image = image,
                    iconImage = iconImg,
                    imgW = imgW,
                    imgH = imgH
                })
            end
        end
    end
end

-- Cargar un nivel dinámicamente
local function iniciarNivel(rutaMapa)
    mapa = sti(rutaMapa)
    mapa.ruta = rutaMapa -- Guardar para reintentos
    cargarColisiones(mapa)
    cargarPickups(mapa)
    
    if rutaMapa == "levels/mission01.lua" then
        jugador.x = 424
        jugador.y = 312
    else
        jugador.x = 400
        jugador.y = 300
    end
    
    jugador.estado = "idle"
    jugador.direccion = "down"
    jugador.inventory = {}
    jugador.vida = 3
    jugador.selectedSlot = nil
    jugador.equipo = nil
    jugador.tiempoInmune = 0
    jugador.tiempoAtaque = 0
    jugador.cuadroAtaque = 1
    jugador.golpeDetectado = false
    messageTimer = 0
    
    if rutaMapa == "levels/tutorial.lua" then
        zombi.activo = true
        zombi.vida = 3
        zombi.estado = "idle"
        zombi.direccion = "left"
        zombi.tiempoFlashRed = 0
        zombi.tiempoMuerte = 0
        zombi.tiempoUltimoAtaque = 0
        
        -- Escaneo inteligente de colisiones para spawn seguro del zombi (evitar paredes)
        local spawnX, spawnY = 580, 300
        local dx, dy = 0, 0
        local step = 8
        local found = false
        for r = 0, 10 do
            for x_offset = -r, r do
                for y_offset = -r, r do
                    local testX = spawnX + x_offset * step
                    local testY = spawnY + y_offset * step
                    local z_col_x = testX - zombi.col_w / 2
                    local z_col_y = testY + (8 * zombi.escala) - zombi.col_h
                    if not colisiona(z_col_x, z_col_y, zombi.col_w, zombi.col_h) then
                        zombi.x = testX
                        zombi.y = testY
                        found = true
                        break
                    end
                end
                if found then break end
            end
            if found then break end
        end
        if not found then
            zombi.x = 580
            zombi.y = 300
        end
    else
        zombi.activo = false
    end
    
    gameState = "play"
end

function love.load()
    -- Cargar todas las combinaciones de IDLE (según image_0d0c40.png)
    cargarAnimacion("idle", "down",  "assets/images/alex/idle/alex_idle_down.png")
    cargarAnimacion("idle", "up",    "assets/images/alex/idle/alex_idle_up.png")
    cargarAnimacion("idle", "left",  "assets/images/alex/idle/alex_idle_left.png")
    cargarAnimacion("idle", "right", "assets/images/alex/idle/alex_idle_right.png")
    
    -- Cargar todas las combinaciones de RUN (según image_0d0c65.png)
    cargarAnimacion("run", "down",  "assets/images/alex/run/alex_run_down.png")
    cargarAnimacion("run", "up",    "assets/images/alex/run/alex_run_up.png")
    cargarAnimacion("run", "left",  "assets/images/alex/run/alex_run_left.png")
    cargarAnimacion("run", "right", "assets/images/alex/run/alex_run_right.png")
    
    -- Animaciones de Alex con el BATE (Idle & Run) - 6 cuadros cada una
    cargarAnimacion("idle_bat", "down",  "assets/images/alex/weapons/bat/bat_down_idle_run.png")
    cargarAnimacion("idle_bat", "up",    "assets/images/alex/weapons/bat/bat_up_idle_run.png")
    cargarAnimacion("idle_bat", "left",  "assets/images/alex/weapons/bat/bat_left_idle_run.png")
    cargarAnimacion("idle_bat", "right", "assets/images/alex/weapons/bat/bat_right_idle_run.png")
    
    cargarAnimacion("run_bat", "down",  "assets/images/alex/weapons/bat/bat_down_idle_run.png")
    cargarAnimacion("run_bat", "up",    "assets/images/alex/weapons/bat/bat_up_idle_run.png")
    cargarAnimacion("run_bat", "left",  "assets/images/alex/weapons/bat/bat_left_idle_run.png")
    cargarAnimacion("run_bat", "right", "assets/images/alex/weapons/bat/bat_right_idle_run.png")
    
    -- Animaciones de ataque de Alex con BATE (5 cuadros para down/up, 7 cuadros para left/right)
    cargarAnimacion("attack_bat", "down",  "assets/images/alex/weapons/bat/bat_down_attack.png", 5)
    cargarAnimacion("attack_bat", "up",    "assets/images/alex/weapons/bat/bat_up_attack.png", 5)
    cargarAnimacion("attack_bat", "left",  "assets/images/alex/weapons/bat/bat_left_attack.png", 7)
    cargarAnimacion("attack_bat", "right", "assets/images/alex/weapons/bat/bat_right_attack.png", 7)
    
    -- Animaciones del ZOMBI
    cargarAnimacion("zombie_idle", "down",  "assets/images/enemies/zombie/zombie_idle/zombie_idle_down.png")
    cargarAnimacion("zombie_idle", "up",    "assets/images/enemies/zombie/zombie_idle/zombie_idle_up.png")
    cargarAnimacion("zombie_idle", "left",  "assets/images/enemies/zombie/zombie_idle/zombie_idle_left.png")
    cargarAnimacion("zombie_idle", "right", "assets/images/enemies/zombie/zombie_idle/zombie_idle_right.png")
    
    cargarAnimacion("zombie_walk", "down",  "assets/images/enemies/zombie/zombie_walk/zombie_walk_down.png")
    cargarAnimacion("zombie_walk", "up",    "assets/images/enemies/zombie/zombie_walk/zombie_walk_up.png")
    cargarAnimacion("zombie_walk", "left",  "assets/images/enemies/zombie/zombie_walk/zombie_walk_left.png")
    cargarAnimacion("zombie_walk", "right", "assets/images/enemies/zombie/zombie_walk/zombie_walk_right.png")
    
    cargarAnimacion("zombie_attack", "down",  "assets/images/enemies/zombie/zombie_attack/zombie_attack_down1.png", 4)
    cargarAnimacion("zombie_attack", "up",    "assets/images/enemies/zombie/zombie_attack/zombie_attack_up1.png", 4)
    cargarAnimacion("zombie_attack", "left",  "assets/images/enemies/zombie/zombie_attack/zombie_attack_left1.png", 4)
    cargarAnimacion("zombie_attack", "right", "assets/images/enemies/zombie/zombie_attack/zombie_attack_right1.png", 4)
    
    cargarAnimacion("zombie_death", "left",  "assets/images/enemies/zombie/zombie_death/zombie_death_left1.png")
    cargarAnimacion("zombie_death", "up",    "assets/images/enemies/zombie/zombie_death/zombie_death_left1.png")
    cargarAnimacion("zombie_death", "right", "assets/images/enemies/zombie/zombie_death/zombie_death_right1.png")
    cargarAnimacion("zombie_death", "down",  "assets/images/enemies/zombie/zombie_death/zombie_death_right1.png")
    
    -- Cargar texturas de salud (UI corazones)
    heartFullImage = love.graphics.newImage("assets/images/ui/hp/Heart_Full.png")
    heartEmptyImage = love.graphics.newImage("assets/images/ui/hp/Heart_Empty.png")
    heartFullImage:setFilter("nearest", "nearest")
    heartEmptyImage:setFilter("nearest", "nearest")
    
    -- Cargar la barra de inventario
    inventoryBarImage = love.graphics.newImage("assets/images/ui/inventory/Quick-Access-Inventory.png")
    inventoryBarImage:setFilter("nearest", "nearest")
    inventoryBarW = inventoryBarImage:getWidth()
    inventoryBarH = inventoryBarImage:getHeight()
end

function love.update(dt)
    if gameState ~= "play" then
        return
    end

    -- Actualizar el mapa (animaciones de tiles, etc.)
    mapa:update(dt)

    -- Control de Avisos UI
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
    end

    -- Control de inmunidad del jugador
    if jugador.tiempoInmune > 0 then
        jugador.tiempoInmune = jugador.tiempoInmune - dt
    end

    -- === Procesamiento de Ataque de Alex ===
    if jugador.estado == "attack" then
        jugador.tiempoAtaque = jugador.tiempoAtaque + dt
        local animKey = "attack_bat"
        local anim = animaciones.banco[animKey] and animaciones.banco[animKey][jugador.direccion]
        if anim then
            local frameDuration = 0.08
            jugador.cuadroAtaque = math.floor(jugador.tiempoAtaque / frameDuration) + 1
            
            -- Verificar impacto a mitad de la animación
            local midFrame = math.floor(anim.total / 2) + 1
            if jugador.cuadroAtaque == midFrame and not jugador.golpeDetectado then
                jugador.golpeDetectado = true
                
                -- Detectar si golpeamos al zombi
                if zombi.activo and zombi.vida > 0 then
                    local dist = math.sqrt((jugador.x - zombi.x)^2 + (jugador.y - zombi.y)^2)
                    if dist < 45 then
                        local deCara = false
                        if jugador.direccion == "right" and zombi.x > jugador.x - 10 then
                            deCara = true
                        elseif jugador.direccion == "left" and zombi.x < jugador.x + 10 then
                            deCara = true
                        elseif jugador.direccion == "up" and zombi.y < jugador.y + 10 then
                            deCara = true
                        elseif jugador.direccion == "down" and zombi.y > jugador.y - 10 then
                            deCara = true
                        end
                        
                        if deCara then
                            zombi.vida = zombi.vida - 1
                            zombi.tiempoFlashRed = 0.2
                            
                            -- Retroceso físico
                            local kx, ky = 0, 0
                            if jugador.direccion == "right" then kx = 1
                            elseif jugador.direccion == "left" then kx = -1
                            elseif jugador.direccion == "up" then ky = -1
                            elseif jugador.direccion == "down" then ky = 1
                            end
                            
                            local retroceso = 30
                            local targetZombieX = zombi.x + kx * retroceso
                            local targetZombieY = zombi.y + ky * retroceso
                            
                            local z_col_x = targetZombieX - zombi.col_w / 2
                            local z_col_y = targetZombieY + (8 * zombi.escala) - zombi.col_h
                            if not colisiona(z_col_x, z_col_y, zombi.col_w, zombi.col_h) then
                                zombi.x = targetZombieX
                                zombi.y = targetZombieY
                            end
                            
                            if zombi.vida <= 0 then
                                zombi.estado = "death"
                                zombi.tiempoMuerte = 0
                            end
                        end
                    end
                end
            end
            
            if jugador.cuadroAtaque > anim.total then
                jugador.estado = "idle"
                jugador.tiempoAtaque = 0
                jugador.cuadroAtaque = 1
                jugador.golpeDetectado = false
            end
        else
            jugador.estado = "idle"
        end
    end

    -- === Lógica del Zombi ===
    if zombi.activo then
        if zombi.vida > 0 then
            if zombi.tiempoFlashRed > 0 then
                zombi.tiempoFlashRed = zombi.tiempoFlashRed - dt
            end
            if zombi.tiempoUltimoAtaque > 0 then
                zombi.tiempoUltimoAtaque = zombi.tiempoUltimoAtaque - dt
            end
            
            local distX = jugador.x - zombi.x
            local distY = jugador.y - zombi.y
            local dist = math.sqrt(distX * distX + distY * distY)
            
            if dist < zombi.rangoDeteccion and jugador.vida > 0 then
                zombi.estado = "walk"
                
                if math.abs(distX) > math.abs(distY) then
                    zombi.direccion = distX > 0 and "right" or "left"
                else
                    zombi.direccion = distY > 0 and "down" or "up"
                end
                
                if dist > 20 then
                    local dx = distX / dist
                    local dy = distY / dist
                    
                    local nuevoX = zombi.x + dx * zombi.velocidad * dt
                    local nuevoY = zombi.y + dy * zombi.velocidad * dt
                    
                    local z_col_x = nuevoX - zombi.col_w / 2
                    local z_col_y = zombi.y + (8 * zombi.escala) - zombi.col_h
                    if not colisiona(z_col_x, z_col_y, zombi.col_w, zombi.col_h) then
                        zombi.x = nuevoX
                    end
                    
                    z_col_x = zombi.x - zombi.col_w / 2
                    z_col_y = nuevoY + (8 * zombi.escala) - zombi.col_h
                    if not colisiona(z_col_x, z_col_y, zombi.col_w, zombi.col_h) then
                        zombi.y = nuevoY
                    end
                else
                    zombi.estado = "attack"
                    if zombi.tiempoUltimoAtaque <= 0 then
                        zombi.tiempoUltimoAtaque = zombi.cooldownAtaque
                        
                        if jugador.tiempoInmune <= 0 then
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
                                gameState = "gameover"
                            end
                        end
                    end
                end
            else
                zombi.estado = "idle"
            end
        elseif zombi.estado == "death" then
            zombi.tiempoMuerte = zombi.tiempoMuerte + dt
            local deathDuration = 0.72
            if zombi.tiempoMuerte >= deathDuration then
                zombi.activo = false
            end
        end
    end

    -- Movimiento del jugador (bloqueado si está atacando)
    local moviendose = false
    local dx, dy = 0, 0
    
    if jugador.estado ~= "attack" then
        if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
            dy = -1
            jugador.direccion = "up"
            moviendose = true
        elseif love.keyboard.isDown("s") or love.keyboard.isDown("down") then
            dy = 1
            jugador.direccion = "down"
            moviendose = true
        end
        
        if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
            dx = -1
            jugador.direccion = "left"
            moviendose = true
        elseif love.keyboard.isDown("d") or love.keyboard.isDown("right") then
            dx = 1
            jugador.direccion = "right"
            moviendose = true
        end
        
        if moviendose then
            jugador.estado = "run"
            
            if dx ~= 0 and dy ~= 0 then
                local len = math.sqrt(dx*dx + dy*dy)
                dx = dx / len
                dy = dy / len
            end
            
            local nuevo_x = jugador.x + dx * jugador.velocidad * dt
            local nuevo_y = jugador.y + dy * jugador.velocidad * dt
            
            local col_x = nuevo_x - jugador.col_w / 2
            local col_y = jugador.y + (8 * jugador.escala) - jugador.col_h
            if not colisiona(col_x, col_y, jugador.col_w, jugador.col_h) then
                jugador.x = nuevo_x
            end
            
            col_x = jugador.x - jugador.col_w / 2
            col_y = nuevo_y + (8 * jugador.escala) - jugador.col_h
            if not colisiona(col_x, col_y, jugador.col_w, jugador.col_h) then
                jugador.y = nuevo_y
            end
        else
            jugador.estado = "idle"
        end
    end
    
    -- === Lógica de recolección de pickups ===
    local i = 1
    while i <= #pickups do
        local p = pickups[i]
        local distX = jugador.x - p.cx
        local distY = jugador.y - p.cy
        local dist = math.sqrt(distX * distX + distY * distY)
        
        if dist < 15 then
            table.insert(jugador.inventory, {
                tipo = p.tipo,
                gid = p.gid,
                image = p.image,
                iconImage = p.iconImage,
                imgW = p.imgW,
                imgH = p.imgH
            })
            table.remove(pickups, i)
        else
            i = i + 1
        end
    end
    
    -- Manejo del temporizador global para la animación activa
    animaciones.tiempoAcumulado = animaciones.tiempoAcumulado + dt
    if animaciones.tiempoAcumulado >= animaciones.velocidadEnmarcado then
        animaciones.tiempoAcumulado = 0
        animaciones.cuadroActual = animaciones.cuadroActual + 1
        
        if animaciones.cuadroActual > animaciones.totalCuadros then
            animaciones.cuadroActual = 1
        end
    end
end

function love.draw()
    if gameState == "menu" then
        love.graphics.clear(0, 0, 0)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("BlindTown", 200, 150, 0, 4, 4)
        
        love.graphics.print("1. Iniciar Tutorial", 200, 260, 0, 1.8, 1.8)
        love.graphics.print("2. Iniciar Misión 1", 200, 310, 0, 1.8, 1.8)
        love.graphics.print("3. Salir", 200, 360, 0, 1.8, 1.8)
        return
    elseif gameState == "gameover" then
        love.graphics.clear(0, 0, 0)
        
        love.graphics.setColor(1, 0.2, 0.2, 1)
        love.graphics.print("¡HAS MUERTO!", love.graphics.getWidth() / 2 - 160, 180, 0, 4, 4)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("1. Reintentar", love.graphics.getWidth() / 2 - 80, 290, 0, 1.8, 1.8)
        love.graphics.print("2. Volver al Menu Principal", love.graphics.getWidth() / 2 - 170, 340, 0, 1.8, 1.8)
        return
    end

    love.graphics.clear(0.1, 0.1, 0.1) -- Fondo gris oscuro de pruebas
    
    -- Dibujar todas las capas del mapa DETRÁS de Alex
    mapa:draw()
    
    -- === Dibujar pickups en el suelo ===
    for _, p in ipairs(pickups) do
        if p.image then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(p.image, p.x, p.y)
        end
    end
    
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.print("Controles: WASD o Flechas. Estado actual: " .. jugador.estado .. " | " .. jugador.direccion, 20, 20)
    love.graphics.print("Presiona 'c' para mostrar/ocultar cajas de colision", 20, 40)
    love.graphics.print("Presiona 'Escape' para volver al Menu Principal", 20, 60)
    
    -- === Dibujar Zombi ===
    if zombi.activo then
        local zAnimKey = "zombie_" .. zombi.estado
        if zombi.estado == "death" then
            zAnimKey = "zombie_death"
        end
        
        local zAnim = animaciones.banco[zAnimKey] and animaciones.banco[zAnimKey][zombi.direccion]
        if zAnim then
            local zFrame = animaciones.cuadroActual
            if zombi.estado == "death" then
                local frameDuration = 0.12
                zFrame = math.min(zAnim.total, math.floor(zombi.tiempoMuerte / frameDuration) + 1)
            elseif zombi.estado == "attack" then
                local frameDuration = 0.15
                zFrame = math.min(zAnim.total, (math.floor(love.timer.getTime() / frameDuration) % zAnim.total) + 1)
            end
            
            local quadIdx = math.max(1, math.min(zFrame, zAnim.total))
            
            if zombi.tiempoFlashRed > 0 then
                love.graphics.setColor(1, 0.2, 0.2, 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            
            love.graphics.draw(
                zAnim.sheet,
                zAnim.quads[quadIdx],
                zombi.x,
                zombi.y,
                0,
                zombi.escala,
                zombi.escala,
                zAnim.w / 2,
                zAnim.h / 2
            )
        end
    end
    
    -- Buscar de forma dinámica la animación de Alex
    local animKey = jugador.estado
    if jugador.equipo == "bat" then
        if jugador.estado == "idle" or jugador.estado == "run" then
            animKey = jugador.estado .. "_bat"
        elseif jugador.estado == "attack" then
            animKey = "attack_bat"
        end
    end
    
    local animacionActual = animaciones.banco[animKey] and animaciones.banco[animKey][jugador.direccion]
    
    if animacionActual then
        love.graphics.setColor(1, 1, 1, 1)
        if jugador.tiempoInmune > 0 then
            -- Parpadeo de visibilidad (alternar cada 0.1s)
            if math.floor(love.timer.getTime() * 15) % 2 == 0 then
                love.graphics.setColor(1, 1, 1, 0.3)
            end
        end
        
        local frameIdx = animaciones.cuadroActual
        if jugador.estado == "attack" then
            frameIdx = jugador.cuadroAtaque
        end
        local quadIdx = math.max(1, math.min(frameIdx, animacionActual.total or animaciones.totalCuadros))
        
        love.graphics.draw(
            animacionActual.sheet, 
            animacionActual.quads[quadIdx], 
            jugador.x, 
            jugador.y, 
            0,    
            jugador.escala, -- Escala X
            jugador.escala, -- Escala Y
            animacionActual.w / 2, -- Centrar el pivote en X
            animacionActual.h / 2  -- Centrar el pivote en Y
        )
    end

    if debug_colisiones then
        -- Dibujar rectángulos de colisión en rojo
        love.graphics.setColor(1, 0, 0, 0.4)
        for _, rect in ipairs(colisionables) do
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        end
        
        -- Dibujar caja de colisión del jugador en verde
        love.graphics.setColor(0, 1, 0, 0.6)
        local col_x = jugador.x - jugador.col_w / 2
        local col_y = jugador.y + (8 * jugador.escala) - jugador.col_h
        love.graphics.rectangle("fill", col_x, col_y, jugador.col_w, jugador.col_h)
        
        -- Dibujar caja de colisión del zombi en azul
        if zombi.activo and zombi.vida > 0 then
            love.graphics.setColor(0, 0, 1, 0.6)
            local z_col_x = zombi.x - zombi.col_w / 2
            local z_col_y = zombi.y + (8 * zombi.escala) - zombi.col_h
            love.graphics.rectangle("fill", z_col_x, z_col_y, zombi.col_w, zombi.col_h)
        end
        
        -- Dibujar indicadores de pickups para depuración
        love.graphics.setColor(1, 1, 0, 0.6)
        for _, p in ipairs(pickups) do
            love.graphics.circle("line", p.cx, p.cy, 15)
            love.graphics.print(p.tipo, p.cx - 10, p.cy - 20)
        end
    end
    
    -- === Dibujar la barra de inventario centrada en la parte inferior ===
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    local barScaledW = inventoryBarW * INVENTORY_SCALE
    local barScaledH = inventoryBarH * INVENTORY_SCALE
    local barX = (screenW - barScaledW) / 2
    local barY = screenH - barScaledH - 10  -- 10px de margen inferior
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(inventoryBarImage, barX, barY, 0, INVENTORY_SCALE, INVENTORY_SCALE)
    
    -- Dibujar los íconos de inventario en cada ranura
    for i, item in ipairs(jugador.inventory) do
        if i > INVENTORY_SLOTS then break end
        local icon = item.iconImage or item.image
        if icon then
            love.graphics.setColor(1, 1, 1, 1)
            local slotOrigX = 2 + (i - 1) * SLOT_SIZE
            local slotOrigY = 1
            
            local slotScreenX = barX + slotOrigX * INVENTORY_SCALE
            local slotScreenY = barY + slotOrigY * INVENTORY_SCALE
            
            local iconW = icon:getWidth()
            local iconH = icon:getHeight()
            
            local itemScale = INVENTORY_SCALE
            local offsetX = (SLOT_SIZE * INVENTORY_SCALE - iconW * itemScale) / 2
            local offsetY = (inventoryBarH * INVENTORY_SCALE - 2 * INVENTORY_SCALE - iconH * itemScale) / 2
            
            love.graphics.draw(icon, slotScreenX + offsetX, slotScreenY + offsetY, 0, itemScale, itemScale)
        end
    end
    
    -- Dibujar borde de selección dorado
    if jugador.selectedSlot and jugador.selectedSlot <= INVENTORY_SLOTS then
        local i = jugador.selectedSlot
        local slotOrigX = 2 + (i - 1) * SLOT_SIZE
        local slotOrigY = 1
        local slotScreenX = barX + slotOrigX * INVENTORY_SCALE
        local slotScreenY = barY + slotOrigY * INVENTORY_SCALE
        
        love.graphics.setColor(1, 0.8, 0, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", slotScreenX, slotScreenY, SLOT_SIZE * INVENTORY_SCALE, inventoryBarH * INVENTORY_SCALE - 2 * INVENTORY_SCALE)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
    
    -- Indicador de ítems en inventario
    if #jugador.inventory > 0 then
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.print("Inventario: " .. #jugador.inventory .. "/" .. INVENTORY_SLOTS, barX, barY - 18)
    end
    
    -- === Dibujar UI de Vida (Corazones) ===
    local hpBarX = screenW - 140
    local hpBarY = 20
    local scaleHp = 2.5
    local heartSpacing = 38
    
    for i = 1, 3 do
        local heartImg = (i <= jugador.vida) and heartFullImage or heartEmptyImage
        if heartImg then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(heartImg, hpBarX + (i - 1) * heartSpacing, hpBarY, 0, scaleHp, scaleHp)
        end
    end
    
    -- === Dibujar avisos UI de mensajes ===
    if messageTimer > 0 then
        love.graphics.setColor(1, 0.3, 0.3, 1)
        local font = love.graphics.getFont()
        local textW = font:getWidth(messageText)
        love.graphics.print(messageText, (screenW - textW) / 2, 80, 0, 1.5, 1.5)
    end
    
    -- Siempre resetear el color al final
    love.graphics.setColor(1, 1, 1, 1)
end

function love.keypressed(key)
    if gameState == "menu" then
        if key == "1" then
            iniciarNivel("levels/tutorial.lua")
        elseif key == "2" then
            iniciarNivel("levels/mission01.lua")
        elseif key == "3" then
            love.event.quit()
        end
    elseif gameState == "gameover" then
        if key == "1" then
            iniciarNivel(mapa.ruta or "levels/tutorial.lua")
        elseif key == "2" then
            gameState = "menu"
        end
    elseif gameState == "play" then
        if key == "c" then
            debug_colisiones = not debug_colisiones
        elseif key == "escape" then
            gameState = "menu"
        elseif key == "space" and jugador.estado ~= "attack" and jugador.equipo == "bat" then
            jugador.estado = "attack"
            jugador.tiempoAtaque = 0
            jugador.cuadroAtaque = 1
            jugador.golpeDetectado = false
        -- Selección rápida de ranuras de inventario
        elseif key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "6" then
            local idx = tonumber(key)
            if jugador.inventory[idx] then
                local item = jugador.inventory[idx]
                if item.tipo == "bandage" then
                    if jugador.vida < 3 then
                        jugador.vida = math.min(3, jugador.vida + 1)
                        table.remove(jugador.inventory, idx)
                        mostrarMensaje("¡Te has curado! Vida: " .. jugador.vida .. "/3")
                        if jugador.selectedSlot == idx then
                            jugador.selectedSlot = nil
                        end
                    else
                        mostrarMensaje("¡Vida al máximo!")
                    end
                elseif item.tipo == "bat" then
                    if jugador.selectedSlot == idx then
                        jugador.selectedSlot = nil
                        jugador.equipo = nil
                        mostrarMensaje("Bate desequipado")
                    else
                        jugador.selectedSlot = idx
                        jugador.equipo = "bat"
                        mostrarMensaje("Bate equipado")
                    end
                else
                    if jugador.selectedSlot == idx then
                        jugador.selectedSlot = nil
                        mostrarMensaje("Ranura deseleccionada")
                    else
                        jugador.selectedSlot = idx
                        mostrarMensaje("Seleccionado: " .. item.tipo:upper())
                    end
                end
            else
                jugador.selectedSlot = nil
                jugador.equipo = nil
            end
        end
    end
end

function love.mousepressed(x, y, button)
    if gameState == "play" and jugador.estado ~= "attack" and jugador.equipo == "bat" then
        if button == 1 then
            jugador.estado = "attack"
            jugador.tiempoAtaque = 0
            jugador.cuadroAtaque = 1
            jugador.golpeDetectado = false
        end
    end
end