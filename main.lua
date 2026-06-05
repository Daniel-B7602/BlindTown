-- Librería STI para cargar mapas de Tiled
local sti = require("libs.sti")

-- Variable global del mapa y estado del juego
local mapa
local debug_colisiones = false
local gameState = "menu" -- "menu" o "play"

-- Configuración de resolución virtual (Letterboxing)
local virtualW = 800
local virtualH = 600
local canvas

-- Módulos de juego (Alex y Zombie) refactorizados
local alexModule = require("alex")
local zombieModule = require("zombie")

local jugador = alexModule.jugador
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

-- Banco de efectos de sonido y voz guía
local sonidos = {}
local currentVoiceSource = nil
local currentVoiceName = nil
local voiceQueue = {}

-- Flags y estado del tutorial
_G.tutorialActive = false
_G.mission01Active = false
_G.tutorialFlags = {
    moved = false,
    pickedAny = false,
    pickedBat = false,
    pickedBandage = false
}

_G.resetTutorialFlags = function()
    _G.tutorialFlags.moved = false
    _G.tutorialFlags.pickedAny = false
    _G.tutorialFlags.pickedBat = false
    _G.tutorialFlags.pickedBandage = false
end

-- Sistema de avisos/mensajes temporales en UI
local messageTimer = 0
local messageText = ""
local tutorialVoiceTimer = 4.0

-- Sistema de evasión de obstáculos (nuevo algoritmo basado en eje bloqueado)
local bloqueado_eje = nil          -- "X" o "Y": eje donde el jugador está atascado
local direccion_bloqueada = nil    -- "derecha"/"izquierda"/"arriba"/"abajo": la dirección original bloqueada
local direccion_escape = nil       -- "derecha"/"izquierda"/"arriba"/"abajo": la salida lateral calculada
local posicion_escape_inicio = nil -- {x, y}: posición donde se activó el escape (para medir avance lateral)
local lastIndicatedDirection = nil -- Última dirección indicada por la voz (para el timer de voz)

_G.escapeLockTimer = 0
_G.lockedEscapeDir = nil
_G.lockedEscapeAxis = nil

-- Función global para activar la alerta de obstáculo (invocada desde alex.lua al colisionar)
_G.activarAlertaObstaculo = function(dir_bloqueada, dir_evasion)
    -- Si ya estamos en un bloqueo activo de escape, no reiniciar el temporizador ni cambiar de dirección
    if _G.escapeLockTimer and _G.escapeLockTimer > 0 then
        return
    end

    -- dir_bloqueada: dirección en la que el jugador chocó ("derecha", "izquierda", "arriba", "abajo")
    -- dir_evasion: la salida óptima calculada por alex.lua
    if dir_bloqueada == "derecha" or dir_bloqueada == "izquierda" then
        bloqueado_eje = "X"
    else
        bloqueado_eje = "Y"
    end
    direccion_bloqueada = dir_bloqueada
    direccion_escape = dir_evasion
    posicion_escape_inicio = { x = jugador.x, y = jugador.y }
    lastIndicatedDirection = dir_evasion
    tutorialVoiceTimer = 0.1  -- Disparar la voz casi inmediatamente

    -- Iniciar el temporizador de bloqueo de 1.5 segundos
    _G.escapeLockTimer = 1.5
    _G.lockedEscapeDir = dir_evasion
    _G.lockedEscapeAxis = bloqueado_eje
end

local function mostrarMensaje(texto)
    messageText = texto
    messageTimer = 2.0
end

-- Hacer global las animaciones para que los módulos tengan acceso directo
_G.animaciones = {
    tiempoAcumulado = 0,
    velocidadEnmarcado = 0.12, -- Tiempo entre cuadros
    cuadroActual = 1,
    totalCuadros = 6,          -- Por defecto
    banco = {}                 -- Aquí guardaremos los spritesheets y sus quads
}
local animaciones = _G.animaciones

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
            if layer.name ~= "Pickable" and layer.name ~= "Pickups" and layer.name ~= "Pickables" then
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

-- Determinar si una línea recta entre dos puntos está libre de colisiones (muestreando cada 12 píxeles)
local function lineaLibre(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 16 then return true end
    
    local stepSize = 12
    local steps = math.floor(dist / stepSize)
    for i = 1, steps - 1 do
        local t = i * stepSize / dist
        local px = x1 + dx * t
        local py = y1 + dy * t
        
        local col_x = px - jugador.col_w / 2
        local col_y = py + (8 * jugador.escala) - jugador.col_h
        if colisiona(col_x, col_y, jugador.col_w, jugador.col_h) then
            return false
        end
    end
    return true
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
        if layer.type == "objectgroup" and (layer.name == "Pickable" or layer.name == "Pickups" or layer.name == "Pickables") then
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
    
    alexModule.iniciar(rutaMapa)
    zombieModule.iniciar(rutaMapa, colisiona)
    
    messageTimer = 0
    gameState = "play"

    bloqueado_eje = nil
    direccion_bloqueada = nil
    direccion_escape = nil
    posicion_escape_inicio = nil
    lastIndicatedDirection = nil
    _G.escapeLockTimer = 0
    _G.lockedEscapeDir = nil
    _G.lockedEscapeAxis = nil

    if rutaMapa == "levels/tutorial.lua" then
        _G.tutorialActive = true
        _G.mission01Active = false
        _G.resetTutorialFlags()
        tutorialVoiceTimer = 10.0 -- Dar tiempo para que suene la voz de bienvenida/inicial
        if _G.reproducirVoz then
            _G.reproducirVoz("voz_tutorial_movimiento_alex")
        end
    elseif rutaMapa == "levels/mission01.lua" then
        _G.tutorialActive = false
        _G.mission01Active = true
        tutorialVoiceTimer = 6.0 -- Dar tiempo para que suene la bienvenida
        if _G.reproducirVoz then
            _G.reproducirVoz("voz_bienvenida_mision01")
        end
    else
        _G.tutorialActive = false
        _G.mission01Active = false
        if _G.detenerVoz then
            _G.detenerVoz()
        end
    end
end

function love.load()
    -- Cargar todas las combinaciones de IDLE
    cargarAnimacion("idle", "down",  "assets/images/alex/idle/alex_idle_down.png")
    cargarAnimacion("idle", "up",    "assets/images/alex/idle/alex_idle_up.png")
    cargarAnimacion("idle", "left",  "assets/images/alex/idle/alex_idle_left.png")
    cargarAnimacion("idle", "right", "assets/images/alex/idle/alex_idle_right.png")
    
    -- Cargar todas las combinaciones de RUN
    cargarAnimacion("run", "down",  "assets/images/alex/run/alex_run_down.png")
    cargarAnimacion("run", "up",    "assets/images/alex/run/alex_run_up.png")
    cargarAnimacion("run", "left",  "assets/images/alex/run/alex_run_left.png")
    cargarAnimacion("run", "right", "assets/images/alex/run/alex_run_right.png")
    
    -- Animaciones base de Alex SIN manos (Nohands) para combinar con armas
    cargarAnimacion("idle_nohands", "down",  "assets/images/alex/idle/alex_idle_down_nohands.png")
    cargarAnimacion("idle_nohands", "up",    "assets/images/alex/idle/alex_idle_up_nohands.png")
    cargarAnimacion("idle_nohands", "left",  "assets/images/alex/idle/alex_idle_left_nohands.png")
    cargarAnimacion("idle_nohands", "right", "assets/images/alex/idle/alex_idle_right_nohands.png")
    
    cargarAnimacion("run_nohands", "down",  "assets/images/alex/run/alex_run_down_nohands.png")
    cargarAnimacion("run_nohands", "up",    "assets/images/alex/run/alex_run_up_nohands.png")
    cargarAnimacion("run_nohands", "left",  "assets/images/alex/run/alex_run_left_nohands.png")
    cargarAnimacion("run_nohands", "right", "assets/images/alex/run/alex_run_right_nohands.png")
    
    cargarAnimacion("punch_nohands", "down",  "assets/images/alex/punch/alex_punch_down_nohands.png", 4)
    cargarAnimacion("punch_nohands", "up",    "assets/images/alex/punch/alex_punch_up_nohands.png", 4)
    cargarAnimacion("punch_nohands", "left",  "assets/images/alex/punch/alex_punch_left_nohands.png", 4)
    cargarAnimacion("punch_nohands", "right", "assets/images/alex/punch/alex_punch_right_nohands.png", 4)
    
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

    -- Cargar efectos de sonido (SFX)
    local function cargarSonido(nombre, ruta)
        local success, src = pcall(love.audio.newSource, ruta, "static")
        if success then
            sonidos[nombre] = src
        else
            print("[Audio] Error al cargar sonido: " .. ruta .. " -> " .. tostring(src))
        end
    end

    cargarSonido("death_alex", "assets/audio/sfx/alex_sfx/death_alex.wav")
    cargarSonido("hit_bat", "assets/audio/sfx/alex_sfx/hit_bat.wav")
    cargarSonido("death_zombie", "assets/audio/sfx/zombie_sfx/death_zombie.wav")
    cargarSonido("zombie_attack", "assets/audio/sfx/zombie_sfx/attack.wav")
    cargarSonido("pickup", "assets/audio/sfx/alex_sfx/pickup_objects.wav")
    cargarSonido("collision", "assets/audio/sfx/environment_sfx/collision.wav")

    -- Cargar voces guía
    cargarSonido("bienvenido_a_blindtown", "assets/audio/guide_voice/bienvenido_a_blindtown.wav")
    cargarSonido("voz_bate", "assets/audio/guide_voice/voz_bate.wav")
    cargarSonido("voz_benda", "assets/audio/guide_voice/voz_benda.wav")
    cargarSonido("voz_estas_muerto", "assets/audio/guide_voice/voz_estas_muerto.wav")
    cargarSonido("voz_latasopa", "assets/audio/guide_voice/voz_latasopa.wav")
    cargarSonido("voz_vacio", "assets/audio/guide_voice/voz_vacio.wav")
    
    cargarSonido("voz_tutorial_final", "assets/audio/guide_voice/tutorial_voice/voz_tutorial_final.wav")
    cargarSonido("voz_tutorial_info_bate", "assets/audio/guide_voice/tutorial_voice/voz_tutorial_info_bate.wav")
    cargarSonido("voz_tutorial_info_benda", "assets/audio/guide_voice/tutorial_voice/voz_tutorial_info_benda.wav")
    cargarSonido("voz_tutorial_info_inventario", "assets/audio/guide_voice/tutorial_voice/voz_tutorial_info_inventario.wav")
    cargarSonido("voz_tutorial_info_pickables", "assets/audio/guide_voice/tutorial_voice/voz_tutorial_info_pickables.wav")
    cargarSonido("voz_tutorial_movimiento_alex", "assets/audio/guide_voice/tutorial_voice/voz_tutorial_movimiento_alex.wav")

    -- Voces de Misión 1
    cargarSonido("voz_bienvenida_mision01", "assets/audio/guide_voice/mission01_voice/voz_bienvenida_mision01.wav")
    cargarSonido("voz_fin_partida_mision01", "assets/audio/guide_voice/mission01_voice/voz_fin_partida_mision01.wav")
    cargarSonido("voz_fin_juego_opciones", "assets/audio/guide_voice/mission01_voice/voz_fin_juego_opciones.wav")

    -- Cargar audios de indicación de dirección para el tutorial
    cargarSonido("abajo", "assets/audio/guide_voice/indication_voice/abajo.wav")
    cargarSonido("arriba", "assets/audio/guide_voice/indication_voice/arriba.wav")
    cargarSonido("derecha", "assets/audio/guide_voice/indication_voice/derecha.wav")
    cargarSonido("izquierda", "assets/audio/guide_voice/indication_voice/izquierda.wav")
    cargarSonido("obstaculo_derecha", "assets/audio/guide_voice/indication_voice/obstaculo_derecha.wav")
    cargarSonido("obstaculo_izquierda", "assets/audio/guide_voice/indication_voice/obstaculo_izquierda.wav")
    cargarSonido("obstaculo_arriba", "assets/audio/guide_voice/indication_voice/obstaculo_arriba.wav")
    cargarSonido("obstaculo_abajo", "assets/audio/guide_voice/indication_voice/obstaculo_abajo.wav")
    cargarSonido("enemigo_abajo", "assets/audio/guide_voice/indication_voice/enemigo_abajo.wav")
    cargarSonido("enemigo_arriba", "assets/audio/guide_voice/indication_voice/enemigo_arriba.wav")
    cargarSonido("enemigo_derecha", "assets/audio/guide_voice/indication_voice/enemigo_derecha.wav")
    cargarSonido("enemigo_izquierda", "assets/audio/guide_voice/indication_voice/enemigo_izquierda.wav")

    -- Función global para reproducir sonido de forma polifónica
    _G.reproducirSonido = function(nombre)
        local src = sonidos[nombre]
        if src then
            local clon = src:clone()
            clon:play()
        end
    end

    -- Sistema de Voz Guía y Cola de Narración
    _G.reproducirVoz = function(nombre, queueUp)
        local src = sonidos[nombre]
        if not src then return end

        if not queueUp then
            -- Interrumpir todo lo que está sonando y limpiar cola
            if currentVoiceSource then
                currentVoiceSource:stop()
            end
            voiceQueue = {}
            src:play()
            currentVoiceSource = src
            currentVoiceName = nombre
        else
            -- Encolar si ya se está reproduciendo algo activo
            if currentVoiceSource and currentVoiceSource:isPlaying() then
                -- Comprobar si ya está en la cola para no duplicar de forma consecutiva
                if voiceQueue[#voiceQueue] ~= nombre then
                    table.insert(voiceQueue, nombre)
                end
            else
                -- Si no hay nada reproduciéndose, reproducir de inmediato
                src:play()
                currentVoiceSource = src
                currentVoiceName = nombre
            end
        end
    end

    _G.detenerVoz = function()
        if currentVoiceSource then
            currentVoiceSource:stop()
        end
        currentVoiceSource = nil
        currentVoiceName = nil
        voiceQueue = {}
    end

    -- Inicializar el lienzo virtual para el escalado (Letterboxing)
    canvas = love.graphics.newCanvas(virtualW, virtualH)
    canvas:setFilter("nearest", "nearest")

    -- Reproducir audio de bienvenida al abrir el juego
    if _G.reproducirVoz then
        _G.reproducirVoz("bienvenido_a_blindtown")
    end
end

function love.update(dt)
    -- Procesar la cola de la voz guía en cualquier estado de juego
    if (not currentVoiceSource or not currentVoiceSource:isPlaying()) and #voiceQueue > 0 then
        local nextVoice = table.remove(voiceQueue, 1)
        local src = sonidos[nextVoice]
        if src then
            src:play()
            currentVoiceSource = src
            currentVoiceName = nextVoice
        end
    end

    if gameState ~= "play" then
        return
    end

    -- Decrementar el temporizador de bloqueo de escape si está activo
    if _G.escapeLockTimer and _G.escapeLockTimer > 0 then
        _G.escapeLockTimer = _G.escapeLockTimer - dt
        if _G.escapeLockTimer <= 0 then
            _G.escapeLockTimer = 0
            _G.lockedEscapeDir = nil
            _G.lockedEscapeAxis = nil
            bloqueado_eje = nil
            direccion_bloqueada = nil
            direccion_escape = nil
            posicion_escape_inicio = nil
        else
            -- Forzar que la dirección de escape siga fija durante el bloqueo
            bloqueado_eje = _G.lockedEscapeAxis
            direccion_escape = _G.lockedEscapeDir
        end
    end

    -- Actualizar el mapa (animaciones de tiles, etc.)
    mapa:update(dt)

    -- Control de Avisos UI
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
    end

    -- Callback para cambiar gameState desde modulos
    local function cambiarGameState(state)
        gameState = state
        if state == "gameover" then
            _G.tutorialActive = false
            _G.mission01Active = false
            if _G.reproducirVoz then
                _G.reproducirVoz("voz_estas_muerto")
            end
        end
    end

    local prevPlayerX = jugador.x
    local prevPlayerY = jugador.y

    -- Actualizar módulos delegados
    alexModule.update(dt, colisiona, zombieModule.zombies, pickups, mostrarMensaje, cambiarGameState)

    -- Restricción de coordenadas (clamping) para que Alex no pueda salir de los límites de la pantalla virtual (800x600)
    local spriteW = 32 * jugador.escala
    local spriteH = 32 * jugador.escala
    local estado = jugador.estado
    local direccion = jugador.direccion
    local animKey = estado
    if jugador.equipo == "bat" then
        if estado == "idle" or estado == "run" then
            animKey = estado .. "_nohands"
        elseif estado == "attack" then
            animKey = "punch_nohands"
        end
    end
    if _G.animaciones and _G.animaciones.banco[animKey] and _G.animaciones.banco[animKey][direccion] then
        local anim = _G.animaciones.banco[animKey][direccion]
        spriteW = anim.w * jugador.escala
        spriteH = anim.h * jugador.escala
    end

    local minX = spriteW / 2
    local maxX = virtualW - spriteW / 2
    local minY = spriteH / 2
    local maxY = virtualH - spriteH / 2

    if jugador.x < minX then jugador.x = minX end
    if jugador.x > maxX then jugador.x = maxX end
    if jugador.y < minY then jugador.y = minY end
    if jugador.y > maxY then jugador.y = maxY end

    zombieModule.update(dt, colisiona, jugador, cambiarGameState)

    -- Calcular movimiento real de Alex en este frame
    local movedX = math.abs(jugador.x - prevPlayerX)
    local movedY = math.abs(jugador.y - prevPlayerY)
    local actualMovement = math.sqrt(movedX * movedX + movedY * movedY)

    -- Verificar si el tutorial ha finalizado
    if _G.tutorialActive and mapa and mapa.ruta == "levels/tutorial.lua" then
        local allPickupsGrabbed = (#pickups == 0)
        local zombieKilled = true
        for _, z in ipairs(zombieModule.zombies) do
            if z.activo or z.vida > 0 then
                zombieKilled = false
                break
            end
        end
        
        if allPickupsGrabbed and zombieKilled then
            gameState = "tutorial_complete"
            _G.tutorialActive = false
            if _G.reproducirVoz then
                _G.reproducirVoz("voz_tutorial_final")
            end
        end
    end

    -- Verificar si la misión 1 ha finalizado
    if _G.mission01Active and mapa and mapa.ruta == "levels/mission01.lua" then
        local allPickupsGrabbed = (#pickups == 0)
        local zombieKilled = true
        for _, z in ipairs(zombieModule.zombies) do
            if z.activo or z.vida > 0 then
                zombieKilled = false
                break
            end
        end
        
        if allPickupsGrabbed and zombieKilled then
            gameState = "mission01_complete"
            _G.mission01Active = false
            if _G.reproducirVoz then
                _G.reproducirVoz("voz_fin_partida_mision01")
                _G.reproducirVoz("voz_fin_juego_opciones", true)
            end
        end
    end

    -- Guía por voz del tutorial/misión 1 hacia los pickables y enemigos (con evasión de obstáculos)
    if (_G.tutorialActive or _G.mission01Active) and gameState == "play" then
        -- 1. Calcular el objetivo actual dinámicamente
        local objetivoActual = nil
        
        -- Verificar si el jugador tiene el bate en el inventario
        local tieneBate = false
        for _, item in ipairs(jugador.inventory) do
            if item.tipo == "bat" then
                tieneBate = true
                break
            end
        end
        
        -- Verificar si el zombie está vivo y calcular la distancia hacia el más cercano
        local zombieVivo = false
        local zombiePos = nil
        local distZombie = math.huge
        for _, z in ipairs(zombieModule.zombies) do
            if z.activo and z.vida > 0 then
                local dx = jugador.x - z.x
                local dy = jugador.y - z.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < distZombie then
                    distZombie = dist
                    zombiePos = { x = z.x, y = z.y }
                    zombieVivo = true
                end
            end
        end
        
        if not tieneBate then
            -- Si el jugador NO tiene el bate en el inventario, objetivoActual será la posición del bate
            for _, p in ipairs(pickups) do
                if p.tipo == "bat" then
                    objetivoActual = { x = p.cx, y = p.cy }
                    break
                end
            end
        elseif zombieVivo then
            -- Si ya tiene el bate pero el zombie está vivo, objetivoActual será la posición del zombie
            objetivoActual = zombiePos
        else
            -- Si el zombie murió, objetivoActual será el pickup más cercano que quede en el mapa (vendas o comida)
            local minDist = math.huge
            local nearestPickup = nil
            for _, p in ipairs(pickups) do
                if p.tipo == "bandage" or p.tipo == "canned-soup" or p.tipo == "canned-food" then
                    local dx = jugador.x - p.cx
                    local dy = jugador.y - p.cy
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < minDist then
                        minDist = dist
                        nearestPickup = { x = p.cx, y = p.cy }
                    end
                end
            end
            objetivoActual = nearestPickup
        end

        -- Exponer objetivoActual como global para que alex.lua lo use al calcular evasión
        _G.objetivoActual = objetivoActual

        -- 2. Verificar si el estado de escape debe desactivarse
        if bloqueado_eje and objetivoActual and posicion_escape_inicio and (_G.escapeLockTimer or 0) <= 0 then
            -- Medir cuánto ha avanzado lateralmente el jugador desde que se activó el escape
            local avanceLateral = 0
            if bloqueado_eje == "Y" then
                avanceLateral = math.abs(jugador.x - posicion_escape_inicio.x)
            elseif bloqueado_eje == "X" then
                avanceLateral = math.abs(jugador.y - posicion_escape_inicio.y)
            end
            
            -- Desactivar escape SÓLO si se avanzó suficiente lateralmente Y la línea al objetivo está libre
            if avanceLateral >= 20 and lineaLibre(jugador.x, jugador.y, objetivoActual.x, objetivoActual.y) then
                bloqueado_eje = nil
                direccion_bloqueada = nil
                direccion_escape = nil
                posicion_escape_inicio = nil
            end
        end
        
        -- Si no hay objetivo, limpiar estado de escape
        if not objetivoActual then
            bloqueado_eje = nil
            direccion_bloqueada = nil
            direccion_escape = nil
            posicion_escape_inicio = nil
        end

        -- 3. Temporizador de voz guía
        tutorialVoiceTimer = tutorialVoiceTimer - dt
        if tutorialVoiceTimer <= 0 then
            local isDirectionVoice = (currentVoiceName == "abajo" or currentVoiceName == "arriba" or currentVoiceName == "derecha" or currentVoiceName == "izquierda" or currentVoiceName == "obstaculo_derecha" or currentVoiceName == "obstaculo_izquierda" or currentVoiceName == "obstaculo_arriba" or currentVoiceName == "obstaculo_abajo" or currentVoiceName == "enemigo_abajo" or currentVoiceName == "enemigo_arriba" or currentVoiceName == "enemigo_derecha" or currentVoiceName == "enemigo_izquierda")
            local voiceIsPlaying = currentVoiceSource and currentVoiceSource:isPlaying()
            
            if not voiceIsPlaying or isDirectionVoice then
                if bloqueado_eje and direccion_escape then
                    -- MODO ESCAPE: indicar estrictamente la dirección de escape del obstáculo
                    if (_G.escapeLockTimer or 0) <= 0 then
                        -- Recalcular por si las condiciones del mapa cambiaron (solo si no está congelado)
                        local rightFree = not colisiona(jugador.x + 24 - jugador.col_w/2, jugador.y + (8 * jugador.escala) - jugador.col_h, jugador.col_w, jugador.col_h)
                        local leftFree = not colisiona(jugador.x - 24 - jugador.col_w/2, jugador.y + (8 * jugador.escala) - jugador.col_h, jugador.col_w, jugador.col_h)
                        local upFree = not colisiona(jugador.x - jugador.col_w/2, jugador.y + (8 * jugador.escala) - 24 - jugador.col_h, jugador.col_w, jugador.col_h)
                        local downFree = not colisiona(jugador.x - jugador.col_w/2, jugador.y + (8 * jugador.escala) + 24 - jugador.col_h, jugador.col_w, jugador.col_h)
                        
                        -- Verificar que la dirección de escape sigue siendo válida
                        local escapeValida = false
                        if direccion_escape == "derecha" and rightFree then escapeValida = true
                        elseif direccion_escape == "izquierda" and leftFree then escapeValida = true
                        elseif direccion_escape == "arriba" and upFree then escapeValida = true
                        elseif direccion_escape == "abajo" and downFree then escapeValida = true
                        end
                        
                        if not escapeValida then
                            -- Recalcular dirección de escape excluyendo la dirección bloqueada
                            local nuevaEscape = nil
                            if bloqueado_eje == "Y" then
                                -- Bloqueado en Y: probar laterales (derecha/izquierda)
                                if rightFree and leftFree and objetivoActual then
                                    local dR = math.abs((jugador.x + 24) - objetivoActual.x)
                                    local dL = math.abs((jugador.x - 24) - objetivoActual.x)
                                    nuevaEscape = (dR < dL) and "derecha" or "izquierda"
                                elseif rightFree then nuevaEscape = "derecha"
                                elseif leftFree then nuevaEscape = "izquierda"
                                end
                            elseif bloqueado_eje == "X" then
                                -- Bloqueado en X: probar laterales (arriba/abajo)
                                if upFree and downFree and objetivoActual then
                                    local dU = math.abs((jugador.y - 24) - objetivoActual.y)
                                    local dD = math.abs((jugador.y + 24) - objetivoActual.y)
                                    nuevaEscape = (dU < dD) and "arriba" or "abajo"
                                elseif upFree then nuevaEscape = "arriba"
                                elseif downFree then nuevaEscape = "abajo"
                                end
                            end
                            
                            if nuevaEscape then
                                direccion_escape = nuevaEscape
                            end
                        end
                    end
                    
                    local audioAPlayar = "obstaculo_" .. direccion_escape
                    if _G.reproducirVoz then
                        _G.reproducirVoz(audioAPlayar)
                        lastIndicatedDirection = direccion_escape
                    end
                else
                    -- MODO NORMAL: indicar dirección hacia el objetivo
                    if objetivoActual then
                        local dx = math.abs(objetivoActual.x - jugador.x)
                        local dy = math.abs(objetivoActual.y - jugador.y)
                        local direccion = nil
                        
                        if dx > dy then
                            if objetivoActual.x > jugador.x then
                                direccion = "derecha"
                            else
                                direccion = "izquierda"
                            end
                        else
                            if objetivoActual.y > jugador.y then
                                direccion = "abajo"
                            else
                                direccion = "arriba"
                            end
                        end
                        
                        local audioAPlayar = direccion
                        if objetivoActual == zombiePos and distZombie < 120 then
                            local diffX = math.abs(zombiePos.x - jugador.x)
                            local diffY = math.abs(zombiePos.y - jugador.y)
                            
                            if diffY < 40 then
                                -- Priorizar el eje X cuando la distancia vertical es menor a 40 píxeles
                                if zombiePos.x > jugador.x then
                                    direccion = "derecha"
                                else
                                    direccion = "izquierda"
                                end
                            else
                                -- Priorizar el eje Y
                                if zombiePos.y < jugador.y then
                                    direccion = "arriba"
                                else
                                    direccion = "abajo"
                                end
                            end
                            audioAPlayar = "enemigo_" .. direccion
                        end
                        
                        if audioAPlayar and _G.reproducirVoz then
                            _G.reproducirVoz(audioAPlayar)
                            lastIndicatedDirection = direccion
                        end
                    end
                end
                tutorialVoiceTimer = 4.0
            else
                -- Si está hablando otra cosa, reintentar pronto
                tutorialVoiceTimer = 1.5
            end
        end
    else
        tutorialVoiceTimer = 4.0
        bloqueado_eje = nil
        direccion_bloqueada = nil
        direccion_escape = nil
        posicion_escape_inicio = nil
        lastIndicatedDirection = nil
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

local function dibujarContenido()
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
        love.graphics.print("¡HAS MUERTO!", virtualW / 2 - 160, 180, 0, 4, 4)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("1. Reintentar", virtualW / 2 - 80, 290, 0, 1.8, 1.8)
        love.graphics.print("2. Volver al Menu Principal", virtualW / 2 - 170, 340, 0, 1.8, 1.8)
        return
    elseif gameState == "tutorial_complete" then
        love.graphics.clear(0, 0, 0)
        
        love.graphics.setColor(0.2, 1, 0.2, 1)
        love.graphics.print("Tutorial Finalizado", virtualW / 2 - 190, 180, 0, 4, 4)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("1. Ir a la misión", virtualW / 2 - 110, 290, 0, 1.8, 1.8)
        love.graphics.print("2. Ir al menú principal", virtualW / 2 - 140, 340, 0, 1.8, 1.8)
        return
    elseif gameState == "mission01_complete" then
        love.graphics.clear(0, 0, 0)
        
        love.graphics.setColor(1, 1, 1, 1)
        local screenW = virtualW
        local font = love.graphics.getFont()
        
        local scaleTitle = 4
        local titleText = "Fin del Juego"
        local titleW = font:getWidth(titleText) * scaleTitle
        love.graphics.print(titleText, (screenW - titleW) / 2, 180, 0, scaleTitle, scaleTitle)
        
        local scaleOpt = 1.8
        local opt1Text = "1. Volver al menu"
        local opt1W = font:getWidth(opt1Text) * scaleOpt
        love.graphics.print(opt1Text, (screenW - opt1W) / 2, 290, 0, scaleOpt, scaleOpt)
        
        local opt2Text = "2. Salir del juego"
        local opt2W = font:getWidth(opt2Text) * scaleOpt
        love.graphics.print(opt2Text, (screenW - opt2W) / 2, 340, 0, scaleOpt, scaleOpt)
        return
    end

    love.graphics.clear(0.1, 0.1, 0.1) -- Fondo gris oscuro de pruebas
    
    -- Dibujar todas las capas del mapa DETRÁS de los personajes
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
    zombieModule.draw(animaciones, debug_colisiones)
    
    -- === Dibujar Alex ===
    alexModule.draw(animaciones, debug_colisiones)

    if debug_colisiones then
        -- Dibujar rectángulos de colisión del mapa en rojo
        love.graphics.setColor(1, 0, 0, 0.4)
        for _, rect in ipairs(colisionables) do
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        end
        
        -- Indicadores de pickups para depuración
        love.graphics.setColor(1, 1, 0, 0.6)
        for _, p in ipairs(pickups) do
            love.graphics.circle("line", p.cx, p.cy, 15)
            love.graphics.print(p.tipo, p.cx - 10, p.cy - 20)
        end
    end
    
    -- === Dibujar la barra de inventario centrada en la parte inferior ===
    local screenW = virtualW
    local screenH = virtualH
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

function love.draw()
    -- Redirigir todo el dibujado al lienzo virtual
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0)
    
    dibujarContenido()
    
    -- Volver al destino de pantalla física
    love.graphics.setCanvas()
    
    -- Calcular el escalado uniforme (Letterboxing) manteniendo la relación de aspecto original
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    local scale = math.min(screenW / virtualW, screenH / virtualH)
    
    local ox = (screenW - virtualW * scale) / 2
    local oy = (screenH - virtualH * scale) / 2
    
    love.graphics.clear(0, 0, 0) -- Pintar barras negras de fondo
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, ox, oy, 0, scale, scale)
end

function love.keypressed(key)
    if gameState == "menu" then
        if key == "1" then
            iniciarNivel("levels/tutorial.lua")
        elseif key == "2" then
            iniciarNivel("levels/mission01.lua")
        elseif key == "3" then
            love.event.quit()
        elseif key == "4" then
            if _G.reproducirVoz then
                _G.reproducirVoz("bienvenido_a_blindtown")
            end
        end
    elseif gameState == "gameover" then
        if key == "1" then
            iniciarNivel(mapa.ruta or "levels/tutorial.lua")
        elseif key == "2" then
            gameState = "menu"
            _G.tutorialActive = false
            _G.mission01Active = false
            if _G.reproducirVoz then
                _G.reproducirVoz("bienvenido_a_blindtown")
            end
        end
    elseif gameState == "tutorial_complete" then
        if key == "1" then
            iniciarNivel("levels/mission01.lua")
        elseif key == "2" then
            gameState = "menu"
            _G.tutorialActive = false
            _G.mission01Active = false
            if _G.reproducirVoz then
                _G.reproducirVoz("bienvenido_a_blindtown")
            end
        end
    elseif gameState == "mission01_complete" then
        if key == "1" then
            gameState = "menu"
            _G.tutorialActive = false
            _G.mission01Active = false
            if _G.reproducirVoz then
                _G.reproducirVoz("bienvenido_a_blindtown")
            end
        elseif key == "2" then
            love.event.quit()
        end
    elseif gameState == "play" then
        if key == "c" then
            debug_colisiones = not debug_colisiones
        elseif key == "escape" then
            gameState = "menu"
            _G.tutorialActive = false
            _G.mission01Active = false
            if _G.reproducirVoz then
                _G.reproducirVoz("bienvenido_a_blindtown")
            end
        elseif key == "space" then
            tutorialVoiceTimer = 0
            alexModule.keypressed(key, mostrarMensaje)
        else
            alexModule.keypressed(key, mostrarMensaje)
        end
    end
end

function love.mousepressed(x, y, button)
    if gameState == "play" then
        alexModule.mousepressed(button)
    end
end