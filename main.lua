-- Librería STI para cargar mapas de Tiled
local sti = require("libs.sti")

-- Variable global del mapa
local mapa
local debug_colisiones = false

-- Estructura del jugador y sus estados
local jugador = {
    x = 400,
    y = 300,
    velocidad = 150,
    direccion = "down", -- "up", "down", "left", "right"
    estado = "idle",    -- "idle", "run"
    escala = 1.5,
    col_w = 12,         -- Ancho de la caja de colisión (pies)
    col_h = 8           -- Alto de la caja de colisión (pies)
}

-- Lista global de rectángulos colisionables
local colisionables = {}

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

function love.load()
    -- Cargar el mapa del tutorial usando STI
    mapa = sti("levels/tutorial.lua")
    
    -- Inicializar las colisiones del mapa
    cargarColisiones(mapa)

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
end

function love.update(dt)
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
    love.graphics.clear(0.1, 0.1, 0.1) -- Fondo gris oscuro de pruebas
    
    -- Dibujar todas las capas del mapa DETRÁS de Alex
    mapa:draw()
    
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.print("Controles: WASD o Flechas. Estado actual: " .. jugador.estado .. " | " .. jugador.direccion, 20, 20)
    love.graphics.print("Presiona 'c' para mostrar/ocultar cajas de colision", 20, 40)
    
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
    end
end

function love.keypressed(key)
    if key == "c" then
        debug_colisiones = not debug_colisiones
    end
end