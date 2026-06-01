// Script to re-export mission01.lua with embedded tilesets
// Run: node tools/embed_tilesets.js

const fs = require('fs');
const path = require('path');

function getAttribute(str, attrName) {
  const regex = new RegExp(`${attrName}\\s*=\\s*"([^"]*)"`);
  const match = str.match(regex);
  return match ? match[1] : null;
}

function parseTSX(tsxPath, firstgid, basePath) {
  console.log(`Parsing TSX: ${tsxPath}`);
  const xml = fs.readFileSync(tsxPath, 'utf8');
  
  const name = getAttribute(xml, 'name');
  const tilewidth = getAttribute(xml, 'tilewidth');
  const tileheight = getAttribute(xml, 'tileheight');
  const tilecount = getAttribute(xml, 'tilecount');
  const columns = getAttribute(xml, 'columns');
  
  // Check for image source ONLY in the header (before the first <tile> tag)
  const header = xml.split(/<tile\b/)[0];
  const imgMatch = header.match(/<image\s+source="([^"]*)"\s+width="(\d+)"\s+height="(\d+)"\s*\/>/);
  
  let lines = [];
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
  
  // Parse individual tiles
  // Let's match all `<tile ... </tile>` blocks, or self-closing `<tile ... />` blocks
  const tileRegex = /<tile\s+([^>]*?)>([\s\S]*?)<\/tile>/g;
  let tiles = [];
  let match;
  while ((match = tileRegex.exec(xml)) !== null) {
    const tileAttr = match[1];
    const tileContent = match[2];
    const id = getAttribute(' ' + tileAttr, 'id');
    
    if (id) {
      const tile = { id: parseInt(id) };
      if (tileContent.includes('name="collidable"')) {
        tile.collidable = true;
      }
      
      const tileImgMatch = tileContent.match(/<image\s+source="([^"]*)"\s+width="(\d+)"\s+height="(\d+)"\s*\/>/);
      if (tileImgMatch) {
        tile.image = basePath + "/" + tileImgMatch[1];
        tile.width = parseInt(tileImgMatch[2]);
        tile.height = parseInt(tileImgMatch[3]);
      }
      tiles.push(tile);
    }
  }
  
  // Sort tiles by id
  tiles.sort((a, b) => a.id - b.id);
  
  if (tiles.length > 0) {
    lines.push("      tiles = {");
    for (const t of tiles) {
      let parts = [];
      parts.push(`id = ${t.id}`);
      if (t.image) {
        parts.push(`image = "${t.image}"`);
        parts.push(`width = ${t.width}`);
        parts.push(`height = ${t.height}`);
      }
      if (t.collidable) {
        parts.push('properties = { ["collidable"] = true }');
      }
      lines.push(`        { ${parts.join(', ')} },`);
    }
    lines.push("      }");
  } else {
    lines.push("      tiles = {}");
  }
  
  lines.push("    }");
  return lines.join('\n');
}

const tilesets = [
    { firstgid: 1,   tsx: "assets/images/tiles/Background_Bleak-Yellow_TileSet.tsx", base: "../assets/images/tiles" },
    { firstgid: 409, tsx: "assets/images/tiles/buildings/Buildings_beige_TileSet.tsx", base: "../assets/images/tiles/buildings" },
    { firstgid: 578, tsx: "assets/images/objects/vehicles/normal/Vehiculos.tsx", base: "../assets/images/objects/vehicles/normal" },
    { firstgid: 622, tsx: "assets/images/objects/other/Decoracion.tsx", base: "../assets/images/objects/other" },
    { firstgid: 707, tsx: "assets/images/objects/nature/darkgreen_nature/Arboles.tsx", base: "../assets/images/objects/nature/darkgreen_nature" },
];

const tilesetStrings = tilesets.map(ts => {
  return parseTSX(ts.tsx, ts.firstgid, ts.base);
});

// Now read mission01.lua and replace the tilesets section
const missionPath = "levels/mission01.lua";
const missionContent = fs.readFileSync(missionPath, 'utf8');

// Find tilesets table start and end
const tilesetsRegex = /(\s+tilesets\s*=\s*\{)([\s\S]*?)(\n\s+\},\s*\n\s+layers)/;
if (!tilesetsRegex.test(missionContent)) {
  console.error("Could not find tilesets block in mission01.lua!");
  process.exit(1);
}

const newTilesetsContent = `  tilesets = {\n${tilesetStrings.join(',\n')}\n  },`;

const updatedMissionContent = missionContent.replace(tilesetsRegex, (match, p1, p2, p3) => {
  return "  tilesets = {\n" + tilesetStrings.join(',\n') + "\n  },\n  layers";
});

fs.writeFileSync(missionPath, updatedMissionContent, 'utf8');
console.log("Done! mission01.lua has been updated with embedded tilesets successfully!");
