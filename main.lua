-- Librería STI para cargar mapas de Tiled
local sti = require("libs.sti")

-- Variable global del mapa y estado del juego
local mapa
local debug_colisiones = false
local gameState = "menu" -- "menu" o "play"

-- Estructura del jugador y sus estados
local jugador = {
    x = 400,
    y = 300,
    velocidad = 150,
    direccion = "down", -- "up", "down", "left", "right"
    estado = "idle",    -- "idle", "run"
    escala = 1.5,
    col_w = 12,         -- Ancho de la caja de colisión (pies)
    col_h = 8,          -- Alto de la caja de colisión (pies)
    inventory = {}      -- Inventario del jugador
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

-- UI del inventario
local inventoryBarImage
local inventoryBarW, inventoryBarH
local INVENTORY_SCALE = 3
local INVENTORY_SLOTS = 6
local SLOT_SIZE = 20  -- Tamaño de cada celda en píxeles originales del sprite

-- Contenedor de las animaciones del juego
local animaciones = {
    tiempoAcumulado = 0,
    velocidadEnmarcado = 0.12, -- Tiempo entre cuadros (un poco más rápido para correr)
    cuadroActual = 1,
    totalCuadros = 6,          -- Todos tus sheets tienen 6 cuadros
    banco = {}                 -- Aquí guardaremos los spritesheets y sus quads
}

-- Función auxiliar para cargar de manera estructurada cada tira de animación
local function cargarAnimacion(estado, direccion, ruta)
    local sprite = love.graphics.newImage(ruta)
    sprite:setFilter("nearest", "nearest") -- Pixel art nítido
    
    local anchoTotal = sprite:getWidth()
    local altoTotal = sprite:getHeight()
    local anchoCuadro = anchoTotal / animaciones.totalCuadros
    local altoCuadro = altoTotal
    
    local quads = {}
    for i = 0, animaciones.totalCuadros - 1 do
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
        h = altoCuadro
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

    local moviendose = false
    local dx, dy = 0, 0
    
    -- Detectar movimiento y dirección actual
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
    
    -- Cambiar de estado dinámicamente
    if moviendose then
        jugador.estado = "run"
        
        -- Normalizar dx y dy para velocidad diagonal uniforme
        if dx ~= 0 and dy ~= 0 then
            local len = math.sqrt(dx*dx + dy*dy)
            dx = dx / len
            dy = dy / len
        end
        
        local nuevo_x = jugador.x + dx * jugador.velocidad * dt
        local nuevo_y = jugador.y + dy * jugador.velocidad * dt
        
        -- Verificar colisión independiente en X (permite deslizamiento)
        local col_x = nuevo_x - jugador.col_w / 2
        local col_y = jugador.y + (8 * jugador.escala) - jugador.col_h
        if not colisiona(col_x, col_y, jugador.col_w, jugador.col_h) then
            jugador.x = nuevo_x
        end
        
        -- Verificar colisión independiente en Y (permite deslizamiento)
        col_x = jugador.x - jugador.col_w / 2
        col_y = nuevo_y + (8 * jugador.escala) - jugador.col_h
        if not colisiona(col_x, col_y, jugador.col_w, jugador.col_h) then
            jugador.y = nuevo_y
        end
    else
        jugador.estado = "idle"
    end
    
    -- === Lógica de recolección de pickups ===
    local i = 1
    while i <= #pickups do
        local p = pickups[i]
        local distX = jugador.x - p.cx
        local distY = jugador.y - p.cy
        local dist = math.sqrt(distX * distX + distY * distY)
        
        if dist < 15 then
            -- Agregar al inventario
            table.insert(jugador.inventory, {
                tipo = p.tipo,
                gid = p.gid,
                image = p.image,
                iconImage = p.iconImage,
                imgW = p.imgW,
                imgH = p.imgH
            })
            -- Eliminar el pickup del suelo
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
        -- Título grande
        love.graphics.print("BlindTown", 200, 150, 0, 4, 4)
        
        -- Opciones
        love.graphics.print("1. Iniciar Tutorial", 200, 260, 0, 1.8, 1.8)
        love.graphics.print("2. Iniciar Misión 1", 200, 310, 0, 1.8, 1.8)
        love.graphics.print("3. Salir", 200, 360, 0, 1.8, 1.8)
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
    
    -- Buscar de forma dinámica la animación que corresponde al estado y dirección actual
    local animacionActual = animaciones.banco[jugador.estado][jugador.direccion]
    
    if animacionActual then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            animacionActual.sheet, 
            animacionActual.quads[animaciones.cuadroActual], 
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
        -- Dibujar rectángulos de colisión del mapa en rojo translúcido
        love.graphics.setColor(1, 0, 0, 0.4)
        for _, rect in ipairs(colisionables) do
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        end
        
        -- Dibujar caja de colisión del jugador en verde translúcido
        love.graphics.setColor(0, 1, 0, 0.6)
        local col_x = jugador.x - jugador.col_w / 2
        local col_y = jugador.y + (8 * jugador.escala) - jugador.col_h
        love.graphics.rectangle("fill", col_x, col_y, jugador.col_w, jugador.col_h)
        
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
            -- Calcular la posición centrada dentro de la ranura
            -- La barra tiene 6 celdas de ~20px cada una en el sprite original
            -- Primer slot empieza aprox. en x=2 del sprite original
            local slotOrigX = 2 + (i - 1) * SLOT_SIZE
            local slotOrigY = 1
            
            local slotScreenX = barX + slotOrigX * INVENTORY_SCALE
            local slotScreenY = barY + slotOrigY * INVENTORY_SCALE
            
            local iconW = icon:getWidth()
            local iconH = icon:getHeight()
            
            -- Escalar el ícono para que quepa bien en la ranura
            local itemScale = INVENTORY_SCALE
            -- Centrar el ícono dentro de la ranura
            local offsetX = (SLOT_SIZE * INVENTORY_SCALE - iconW * itemScale) / 2
            local offsetY = (inventoryBarH * INVENTORY_SCALE - 2 * INVENTORY_SCALE - iconH * itemScale) / 2
            
            love.graphics.draw(icon, slotScreenX + offsetX, slotScreenY + offsetY, 0, itemScale, itemScale)
        end
    end
    
    -- Indicador de ítems en inventario
    if #jugador.inventory > 0 then
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.print("Inventario: " .. #jugador.inventory .. "/" .. INVENTORY_SLOTS, barX, barY - 18)
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
    elseif gameState == "play" then
        if key == "c" then
            debug_colisiones = not debug_colisiones
        elseif key == "escape" then
            gameState = "menu"
        end
    end
end