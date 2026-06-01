const fs = require('fs');
const path = require('path');

function attr(xml, name) {
    const regex = new RegExp(name + '="([^"]*)"');
    const match = xml.match(regex);
    return match ? match[1] : null;
}

function parseTSX(tsxPath, firstgid, basePath) {
    const xml = fs.readFileSync(tsxPath, 'utf8');
    
    const name = attr(xml, "name");
    const tilewidth = attr(xml, "tilewidth");
    const tileheight = attr(xml, "tileheight");
    const tilecount = attr(xml, "tilecount");
    const columns = attr(xml, "columns");
    
    // Check if it's a sheet-based or image-collection tileset
    const isImageCollection = (columns === "0");
    const imgMatch = !isImageCollection ? xml.match(/<image\s+source="([^"]*)"\s+width="(\d+)"\s+height="(\d+)"\/>/) : null;
    
    const lines = [];
    lines.push("    {");
    lines.push(`      name = "${name}",`);
    lines.push(`      firstgid = ${firstgid},`);
    lines.push(`      tilewidth = ${tilewidth},`);
    lines.push(`      tileheight = ${tileheight},`);
    lines.push("      spacing = 0,");
    lines.push("      margin = 0,");
    lines.push(`      tilecount = ${tilecount},`);
    lines.push(`      columns = ${columns},`);
    
    if (imgMatch) {
        const imgSrc = imgMatch[1];
        const imgW = imgMatch[2];
        const imgH = imgMatch[3];
        const imgRelPath = basePath + "/" + imgSrc;
        lines.push(`      image = "${imgRelPath}",`);
        lines.push(`      imagewidth = ${imgW},`);
        lines.push(`      imageheight = ${imgH},`);
    }
    
    lines.push("      tileoffset = { x = 0, y = 0 },");
    
    // Parse tiles
    const tiles = [];
    const tileBlocks = xml.match(/<tile\s+[\s\S]*?<\/tile>/g) || [];
    
    for (const tileBlock of tileBlocks) {
        const tileId = attr(tileBlock, "id");
        if (tileId) {
            const tile = { id: parseInt(tileId) };
            
            // Check for collidable property
            if (tileBlock.includes('name="collidable"')) {
                tile.collidable = true;
            }
            
            // Check for individual tile image
            const tileImgMatch = tileBlock.match(/<image\s+source="([^"]*)"\s+width="(\d+)"\s+height="(\d+)"\/>/);
            if (tileImgMatch) {
                tile.image = basePath + "/" + tileImgMatch[1];
                tile.width = parseInt(tileImgMatch[2]);
                tile.height = parseInt(tileImgMatch[3]);
            }
            
            tiles.push(tile);
        }
    }
    
    tiles.sort((a, b) => a.id - b.id);
    
    if (tiles.length > 0) {
        lines.push("      tiles = {");
        for (const tile of tiles) {
            const parts = [];
            parts.push(`id = ${tile.id}`);
            if (tile.image) {
                parts.push(`image = "${tile.image}"`);
                parts.push(`width = ${tile.width}`);
                parts.push(`height = ${tile.height}`);
            }
            if (tile.collidable) {
                parts.push('properties = { ["collidable"] = true }');
            }
            lines.push(`        { ${parts.join(", ")} },`);
        }
        lines.push("      }");
    } else {
        lines.push("      tiles = {}");
    }
    
    lines.push("    }");
    return lines.join("\n");
}

const tilesets = [
    { firstgid: 1,   tsx: "assets/images/tiles/Background_Bleak-Yellow_TileSet.tsx", base: "../assets/images/tiles" },
    { firstgid: 409, tsx: "assets/images/tiles/buildings/Buildings_beige_TileSet.tsx", base: "../assets/images/tiles/buildings" },
    { firstgid: 578, tsx: "assets/images/objects/vehicles/normal/Vehiculos.tsx", base: "../assets/images/objects/vehicles/normal" },
    { firstgid: 622, tsx: "assets/images/objects/other/Decoracion.tsx", base: "../assets/images/objects/other" },
    { firstgid: 707, tsx: "assets/images/objects/nature/darkgreen_nature/Arboles.tsx", base: "../assets/images/objects/nature/darkgreen_nature" },
    { firstgid: 751, tsx: "assets/images/objects/pickable/Pickable.tsx", base: "../assets/images/objects/pickable" },
];

console.log("Starting JS parser...");
const tilesetStrings = [];
for (const ts of tilesets) {
    console.log(`Processing: ${ts.tsx}`);
    const result = parseTSX(ts.tsx, ts.firstgid, ts.base);
    tilesetStrings.push(result);
}

const missionPath = "levels/mission01.lua";
const mission = fs.readFileSync(missionPath, "utf8");

// Split by tilesets block
const tilesetIndexStart = mission.indexOf("  tilesets = {");
const tilesetIndexEnd = mission.indexOf("  layers = {");

if (tilesetIndexStart === -1 || tilesetIndexEnd === -1) {
    console.error("Could not find tilesets block in mission01.lua");
    process.exit(1);
}

const before = mission.substring(0, tilesetIndexStart);
const after = mission.substring(tilesetIndexEnd);

const newContent = before + "  tilesets = {\n" + tilesetStrings.join(",\n") + "\n  },\n" + after;

fs.writeFileSync(missionPath, newContent, "utf8");
console.log("Done! mission01.lua has been successfully updated with embedded tilesets.");
