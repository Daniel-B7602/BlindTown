-- Esto es una prueba, nada más.

-- Variables globales para una prueba rápida
local jugador = { x = 400, y = 300, velocity = 200 }

function love.load()
    -- Aquí se cargarían los assets en el futuro
    print("¡BlindTown iniciado correctamente!")
end

function love.update(dt)
    -- Movimiento básico con flechas del teclado o WASD
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
        jugador.x = jugador.x + jugador.velocity * dt
    end
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
        jugador.x = jugador.x - jugador.velocity * dt
    end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then
        jugador.y = jugador.y + jugador.velocity * dt
    end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then
        jugador.y = jugador.y - jugador.velocity * dt
    end
end

function love.draw()
    -- Fondo negro (limpia la pantalla en cada frame)
    love.graphics.clear(0, 0, 0)
    
    -- Texto de guía
    love.graphics.setColor(1, 1, 1, 0.5) -- Color blanco con 50% de transparencia
    love.graphics.print("BlindTown - Entorno de Pruebas", 20, 20)
    love.graphics.print("Usa las flechas o WASD para mover el punto", 20, 40)
    
    -- El "Jugador" (un círculo blanco para el modo debug)
    love.graphics.setColor(1, 1, 1, 1) -- Blanco sólido
    love.graphics.circle("fill", jugador.x, jugador.y, 15)
end