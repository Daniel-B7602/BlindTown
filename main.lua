local animacion = {
    spritesheet = nil,
    quads = {},
    cuadroActual = 1,
    tiempoAcumulado = 0,
    velocidadEnmarcado = 0.15, -- Cambia de cuadro cada 0.15 segundos
    totalCuadros = 6          -- Tu archivo dice "Sheet6", así que trae 6 cuadros
}

local jugador = { x = 400, y = 300 }

function love.load()
    -- 1. Cargar la imagen completa
    animacion.spritesheet = love.graphics.newImage("assets/images/alex/idle/Character_down_idle-Sheet6.png")
    
    -- Desactivar el filtro borroso para que el pixel art se vea nítido
    animacion.spritesheet:setFilter("nearest", "nearest")
    
    -- 2. CALCULO AUTOMÁTICO: Dividimos el ancho total de la imagen entre los 6 cuadros
    local anchoTotal = animacion.spritesheet:getWidth()
    local altoTotal = animacion.spritesheet:getHeight()
    
    local anchoCuadro = anchoTotal / animacion.totalCuadros  -- Esto da el tamaño exacto por cuadro
    local altoCuadro = altoTotal                             -- Alto completo de la tira
    
    -- Creamos los recortes basados en la división exacta
    for i = 0, animacion.totalCuadros - 1 do
        table.insert(animacion.quads, love.graphics.newQuad(
            i * anchoCuadro, 0, 
            anchoCuadro, altoCuadro, 
            anchoTotal, altoTotal
        ))
    end
end

function love.update(dt)
    -- 3. El temporizador de la animación
    animacion.tiempoAcumulado = animacion.tiempoAcumulado + dt
    
    if animacion.tiempoAcumulado >= animacion.velocidadEnmarcado then
        animacion.tiempoAcumulado = 0
        animacion.cuadroActual = animacion.cuadroActual + 1
        
        -- Si llega al final de la tira, vuelve a empezar (bucle)
        if animacion.cuadroActual > animacion.totalCuadros then
            animacion.cuadroActual = 1
        end
    end
end

function love.draw()
    love.graphics.clear(0, 0, 0) -- Fondo oscuro
    
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.print("Test de Animación - Estado Idle", 20, 20)
    
    -- 4. Dibujar el cuadro actual escalado (x4) para que no se vea minúsculo
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        animacion.spritesheet, 
        animacion.quads[animacion.cuadroActual], 
        jugador.x, 
        jugador.y, 
        0,    
        4,    -- Escala X (Mantenemos el tamaño x4)
        4,    -- Escala Y
        8,    -- Origen X (Mitad de 16)
        8     -- Origen Y (Mitad de 16)
    )
end