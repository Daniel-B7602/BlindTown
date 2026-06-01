-- Script to re-export mission01.lua with embedded tilesets
-- Run: lua tools/embed_tilesets.lua
-- This reads the TSX files referenced in mission01.lua and produces
-- a corrected version with embedded tileset data.

local lfs_ok = true

-- Helper: read entire file
local function readFile(path)
    local f = io.open(path, "r")
    if not f then error("Cannot open: " .. path) end
    local content = f:read("*a")
    f:close()
    return content
end

-- Parse XML attribute value
local function attr(xml, name)
    return xml:match(name .. '="([^"]*)"')
end

-- Parse a single tileset TSX and return a Lua table string
local function parseTSX(tsxPath, firstgid, basePath)
    local xml = readFile(tsxPath)
    
    local name = attr(xml, "name")
    local tilewidth = attr(xml, "tilewidth")
    local tileheight = attr(xml, "tileheight")
    local tilecount = attr(xml, "tilecount")
    local columns = attr(xml, "columns")
    
    -- Check if it's a sheet-based or image-collection tileset
    local imgSource = xml:match('<image source="([^"]*)" width="(%d+)" height="(%d+)"/>')
    
    local lines = {}
    table.insert(lines, "    {")
    table.insert(lines, '      name = "' .. name .. '",')
    table.insert(lines, "      firstgid = " .. firstgid .. ",")
    table.insert(lines, "      tilewidth = " .. tilewidth .. ",")
    table.insert(lines, "      tileheight = " .. tileheight .. ",")
    table.insert(lines, "      spacing = 0,")
    table.insert(lines, "      margin = 0,")
    table.insert(lines, "      tilecount = " .. tilecount .. ",")
    table.insert(lines, "      columns = " .. columns .. ",")
    
    if imgSource then
        -- Sheet-based tileset (like Background or Buildings)
        -- Get image info from the <image> tag that's a direct child of <tileset>
        local imgSrc, imgW, imgH = xml:match('<image source="([^"]*)" width="(%d+)" height="(%d+)"/>')
        -- Convert relative path from TSX location to relative from levels/
        local imgRelPath = basePath .. "/" .. imgSrc
        table.insert(lines, '      image = "' .. imgRelPath .. '",')
        table.insert(lines, "      imagewidth = " .. imgW .. ",")
        table.insert(lines, "      imageheight = " .. imgH .. ",")
    end
    
    table.insert(lines, "      tileoffset = { x = 0, y = 0 },")
    
    -- Parse tiles with properties or individual images
    local tiles = {}
    -- Match each <tile> block
    for tileBlock in xml:gmatch("<tile (.-)</tile>") do
        local tileId = tileBlock:match('id="(%d+)"')
        if tileId then
            local tile = { id = tonumber(tileId) }
            
            -- Check for collidable property
            if tileBlock:match('name="collidable"') then
                tile.collidable = true
            end
            
            -- Check for individual tile image (image collections)
            local tileSrc, tileW, tileH = tileBlock:match('<image source="([^"]*)" width="(%d+)" height="(%d+)"/>')
            if tileSrc then
                tile.image = basePath .. "/" .. tileSrc
                tile.width = tonumber(tileW)
                tile.height = tonumber(tileH)
            end
            
            table.insert(tiles, tile)
        end
    end
    
    -- Sort tiles by id
    table.sort(tiles, function(a, b) return a.id < b.id end)
    
    if #tiles > 0 then
        table.insert(lines, "      tiles = {")
        for _, tile in ipairs(tiles) do
            local parts = {}
            table.insert(parts, "id = " .. tile.id)
            if tile.image then
                table.insert(parts, 'image = "' .. tile.image .. '"')
                table.insert(parts, "width = " .. tile.width)
                table.insert(parts, "height = " .. tile.height)
            end
            if tile.collidable then
                table.insert(parts, 'properties = { ["collidable"] = true }')
            end
            table.insert(lines, "        { " .. table.concat(parts, ", ") .. " },")
        end
        table.insert(lines, "      }")
    else
        table.insert(lines, "      tiles = {}")
    end
    
    table.insert(lines, "    }")
    
    return table.concat(lines, "\n")
end

-- Main
local tilesets = {
    { firstgid = 1,   tsx = "assets/images/tiles/Background_Bleak-Yellow_TileSet.tsx", base = "../assets/images/tiles" },
    { firstgid = 409, tsx = "assets/images/tiles/buildings/Buildings_beige_TileSet.tsx", base = "../assets/images/tiles/buildings" },
    { firstgid = 578, tsx = "assets/images/objects/vehicles/normal/Vehiculos.tsx", base = "../assets/images/objects/vehicles/normal" },
    { firstgid = 622, tsx = "assets/images/objects/other/Decoracion.tsx", base = "../assets/images/objects/other" },
    { firstgid = 707, tsx = "assets/images/objects/nature/darkgreen_nature/Arboles.tsx", base = "../assets/images/objects/nature/darkgreen_nature" },
    { firstgid = 751, tsx = "assets/images/objects/pickable/Pickable.tsx", base = "../assets/images/objects/pickable" },
}

local tilesetStrings = {}
for _, ts in ipairs(tilesets) do
    print("Processing: " .. ts.tsx)
    local result = parseTSX(ts.tsx, ts.firstgid, ts.base)
    table.insert(tilesetStrings, result)
end

-- Now read mission01.lua and replace the tilesets section
local mission = readFile("levels/mission01.lua")

-- Find and replace the tilesets block
local before = mission:match("(.-tilesets = {)\n")
local after = mission:match("\n  },\n(  layers = .*)")

if not before or not after then
    error("Could not find tilesets block in mission01.lua")
end

local newContent = before .. "\n" .. table.concat(tilesetStrings, ",\n") .. "\n  },\n" .. after

local f = io.open("levels/mission01.lua", "w")
f:write(newContent)
f:close()

print("Done! mission01.lua has been updated with embedded tilesets.")
