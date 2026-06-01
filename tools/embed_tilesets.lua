-- embed_tilesets.lua
-- Run with: lua tools/embed_tilesets.lua
-- Converts external TSX tileset references in levels/tutorial.lua to embedded tilesets

-- Simple XML attribute parser
local function parse_attrs(tag)
    local attrs = {}
    for k, v in tag:gmatch('(%w+)%s*=%s*"([^"]*)"') do
        -- Try to convert numbers
        local num = tonumber(v)
        if num then
            attrs[k] = num
        elseif v == "true" then
            attrs[k] = true
        elseif v == "false" then
            attrs[k] = false
        else
            attrs[k] = v
        end
    end
    return attrs
end

-- Parse a TSX file and return a Lua tileset table (without firstgid/name, those come from the map)
local function parse_tsx(tsx_path, tileset_dir)
    local f = io.open(tsx_path, "r")
    if not f then
        error("Cannot open TSX: " .. tsx_path)
    end
    local content = f:read("*a")
    f:close()

    -- Parse <tileset> attributes
    local ts_tag = content:match("<tileset[^>]+>")
    local ts = parse_attrs(ts_tag)

    local result = {}
    result.tilewidth = ts.tilewidth
    result.tileheight = ts.tileheight
    result.tilecount = ts.tilecount
    result.columns = ts.columns or 0
    result.spacing = ts.spacing or 0
    result.margin = ts.margin or 0

    -- Check for grid element
    local grid_tag = content:match("<grid[^/]*/?>")
    if grid_tag then
        local grid = parse_attrs(grid_tag)
        -- grid is present for image collections
    end

    -- Check for single <image> at tileset level (spritesheet tileset)
    local tileset_image = content:match("<tileset[^>]*>%s*\n?%s*<image([^/]*/?)>?")
    -- More robust: find <image> that is a direct child of <tileset> (not inside <tile>)
    local main_image_tag = nil
    -- Find <image> tags that are NOT inside <tile>...</tile>
    local before_tiles = content:match("^(.-)<tile[ >]") or content
    main_image_tag = before_tiles:match("<image([^>]+)/>")

    if main_image_tag and result.columns > 0 then
        -- Spritesheet tileset
        local img = parse_attrs(main_image_tag)
        result.image = img.source
        result.imagewidth = img.width
        result.imageheight = img.height
    end

    -- Parse tiles with properties or per-tile images
    result.tiles = {}
    -- Match each <tile>...</tile> block or self-closing <tile .../>
    for tile_block in content:gmatch("<tile ([^>]-)>(.-)<%/tile>") do
        -- This doesn't work well, let's use a different approach
    end

    -- Better approach: iterate over all <tile> elements
    result.tiles = {}
    local pos = 1
    while true do
        -- Find next <tile
        local tile_start = content:find("<tile ", pos)
        if not tile_start then break end

        -- Check if self-closing
        local tag_end = content:find(">", tile_start)
        local is_self_closing = content:sub(tag_end - 1, tag_end) == "/>"

        local tile_tag = content:sub(tile_start, tag_end)
        local tile_attrs = parse_attrs(tile_tag)

        local tile = { id = tile_attrs.id }

        if is_self_closing then
            pos = tag_end + 1
        else
            -- Find </tile>
            local close_tile = content:find("</tile>", tag_end)

            local tile_content = content:sub(tag_end + 1, close_tile - 1)

            -- Parse <image> inside tile (for image collections)
            local img_tag = tile_content:match("<image([^/]+)/>")
            if img_tag then
                local img = parse_attrs(img_tag)
                tile.image = img.source
                tile.width = img.width
                tile.height = img.height
            end

            -- Parse <properties>
            local props_block = tile_content:match("<properties>(.-)</properties>")
            if props_block then
                tile.properties = {}
                for prop_tag in props_block:gmatch("<property([^/]+)/>") do
                    local p = parse_attrs(prop_tag)
                    if p.type == "bool" then
                        tile.properties[p.name] = p.value
                    else
                        tile.properties[p.name] = p.value
                    end
                end
            end

            pos = close_tile + 7 -- length of "</tile>"
        end

        table.insert(result.tiles, tile)
    end

    return result
end

-- Generate Lua code for a property value
local function lua_val(v)
    if type(v) == "boolean" then
        return tostring(v)
    elseif type(v) == "number" then
        return tostring(v)
    else
        return string.format("%q", v)
    end
end

-- Generate the embedded tileset Lua string
local function generate_tileset_lua(name, firstgid, tsx_path, tileset_dir, indent)
    local ts = parse_tsx(tsx_path, tileset_dir)
    indent = indent or "    "
    local i2 = indent .. "  "
    local i3 = i2 .. "  "
    local i4 = i3 .. "  "
    local i5 = i4 .. "  "

    local lines = {}
    table.insert(lines, indent .. "{")
    table.insert(lines, i2 .. string.format('name = %q,', name))
    table.insert(lines, i2 .. string.format('firstgid = %d,', firstgid))
    table.insert(lines, i2 .. string.format('tilewidth = %d,', ts.tilewidth))
    table.insert(lines, i2 .. string.format('tileheight = %d,', ts.tileheight))
    table.insert(lines, i2 .. string.format('spacing = %d,', ts.spacing))
    table.insert(lines, i2 .. string.format('margin = %d,', ts.margin))
    table.insert(lines, i2 .. string.format('tilecount = %d,', ts.tilecount))
    table.insert(lines, i2 .. string.format('columns = %d,', ts.columns))

    if ts.image then
        -- Spritesheet: image path relative to the map file's directory
        local rel_image = tileset_dir .. ts.image
        table.insert(lines, i2 .. string.format('image = %q,', rel_image))
        table.insert(lines, i2 .. string.format('imagewidth = %d,', ts.imagewidth))
        table.insert(lines, i2 .. string.format('imageheight = %d,', ts.imageheight))
    end

    -- tileoffset
    table.insert(lines, i2 .. 'tileoffset = {')
    table.insert(lines, i3 .. 'x = 0,')
    table.insert(lines, i3 .. 'y = 0')
    table.insert(lines, i2 .. '},')

    -- tiles array
    if #ts.tiles > 0 then
        table.insert(lines, i2 .. 'tiles = {')
        for _, tile in ipairs(ts.tiles) do
            table.insert(lines, i3 .. '{')
            table.insert(lines, i4 .. string.format('id = %d,', tile.id))

            if tile.image then
                local rel_tile_image = tileset_dir .. tile.image
                table.insert(lines, i4 .. string.format('image = %q,', rel_tile_image))
                table.insert(lines, i4 .. string.format('width = %d,', tile.width))
                table.insert(lines, i4 .. string.format('height = %d,', tile.height))
            end

            if tile.properties and next(tile.properties) then
                table.insert(lines, i4 .. 'properties = {')
                for pk, pv in pairs(tile.properties) do
                    table.insert(lines, i5 .. string.format('[%q] = %s,', pk, lua_val(pv)))
                end
                table.insert(lines, i4 .. '},')
            end

            table.insert(lines, i3 .. '},')
        end
        table.insert(lines, i2 .. '}')
    else
        table.insert(lines, i2 .. 'tiles = {}')
    end

    table.insert(lines, indent .. "}")

    return table.concat(lines, "\n")
end

-- Main: Define the tilesets to embed
local tilesets = {
    {
        name = "Background_Dark-Green_TileSet",
        firstgid = 1,
        tsx = "assets/images/tiles/Background_Dark-Green_TileSet.tsx",
        dir = "../assets/images/tiles/"
    },
    {
        name = "Buildings_white_TileSet",
        firstgid = 409,
        tsx = "assets/images/tiles/buildings/Buildings_white_TileSet.tsx",
        dir = "../assets/images/tiles/buildings/"
    },
    {
        name = "Buildings_beige_TileSet",
        firstgid = 578,
        tsx = "assets/images/tiles/buildings/Buildings_beige_TileSet.tsx",
        dir = "../assets/images/tiles/buildings/"
    },
    {
        name = "Vehiculos",
        firstgid = 747,
        tsx = "assets/images/objects/vehicles/normal/Vehiculos.tsx",
        dir = "../assets/images/objects/vehicles/normal/"
    },
    {
        name = "Decoracion",
        firstgid = 791,
        tsx = "assets/images/objects/other/Decoracion.tsx",
        dir = "../assets/images/objects/other/"
    },
    {
        name = "Arboles",
        firstgid = 876,
        tsx = "assets/images/objects/nature/darkgreen_nature/Arboles.tsx",
        dir = "../assets/images/objects/nature/darkgreen_nature/"
    },
}

-- Read existing tutorial.lua
local f = io.open("levels/tutorial.lua", "r")
local content = f:read("*a")
f:close()

-- Generate the new tilesets block
local tileset_parts = {}
for _, ts in ipairs(tilesets) do
    table.insert(tileset_parts, generate_tileset_lua(ts.name, ts.firstgid, ts.tsx, ts.dir, "    "))
end

local new_tilesets = "  tilesets = {\n" .. table.concat(tileset_parts, ",\n") .. "\n  },"

-- Replace the old tilesets block
-- Find "  tilesets = {" and the matching closing "},"
local ts_start = content:find("  tilesets = {")
if not ts_start then
    error("Could not find tilesets block in tutorial.lua")
end

-- Count braces to find the end
local depth = 0
local ts_end = nil
for i = ts_start + #"  tilesets = " , #content do
    local c = content:sub(i, i)
    if c == "{" then
        depth = depth + 1
    elseif c == "}" then
        depth = depth - 1
        if depth == 0 then
            -- Find the comma after
            local after = content:sub(i + 1, i + 1)
            if after == "," then
                ts_end = i + 1
            else
                ts_end = i
            end
            break
        end
    end
end

if not ts_end then
    error("Could not find end of tilesets block")
end

local new_content = content:sub(1, ts_start - 1) .. new_tilesets .. content:sub(ts_end + 1)

-- Write the new file
local out = io.open("levels/tutorial.lua", "w")
out:write(new_content)
out:close()

print("Successfully embedded all tilesets into levels/tutorial.lua!")
