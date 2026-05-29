-- Estructura del jugador y sus estados
local jugador = {
    x = 400,
    y = 300,
    velocidad = 150,
    direccion = "down", -- "up", "down", "left", "right"
    estado = "idle"     -- "idle", "run"
}

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
end

function love.update(dt)
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
        -- Mover al jugador usando delta time
        jugador.x = jugador.x + dx * jugador.velocidad * dt
        jugador.y = jugador.y + dy * jugador.velocidad * dt
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
    
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.print("Controles: WASD o Flechas. Estado actual: " .. jugador.estado .. " | " .. jugador.direccion, 20, 20)
    
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
            4, -- Escala X (Agrandado x4)
            4, -- Escala Y
            animacionActual.w / 2, -- Centrar el pivote en X
            animacionActual.h / 2  -- Centrar el pivote en Y
        )
    end
end