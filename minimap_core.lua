-- Pure terrain and layout helpers.  Kept separate so it can be tested without
-- a LÖVE window or an imported ROM.
local M = {}

-- Facility footprints do not change while a map is loaded.  Keep this cache
-- separate from the Map itself so a mod's map objects remain unmodified.
local facilityCache = setmetatable({}, { __mode = "k" })

local PRESETS = {
  small  = { radiusX = 7,  radiusY = 5,  scale = 2 },
  medium = { radiusX = 11, radiusY = 8,  scale = 2 },
  large  = { radiusX = 15, radiusY = 11, scale = 2 },
}

function M.preset(size)
  return PRESETS[size] or PRESETS.medium
end

function M.opacity(value)
  if type(value) ~= "number" then return 0.75 end
  return math.max(0.25, math.min(1, value))
end

-- gx/gy are in the current-map 16px-cell coordinate space.  Connected maps
-- carry their offsets in world pixels, so translate those before testing their
-- own cell bounds.  The current map wins where map rectangles overlap.
function M.mapAt(overworld, gx, gy)
  if not overworld then return nil end
  local current = overworld.map
  if current and current:inBounds(gx, gy) then return current, gx, gy end
  for _, neighbor in ipairs(overworld.neighbors or {}) do
    local map = neighbor.map
    local cx = gx - math.floor((neighbor.ox or 0) / 16)
    local cy = gy - math.floor((neighbor.oy or 0) / 16)
    if map and map:inBounds(cx, cy) then return map, cx, cy end
  end
  return nil
end

function M.terrain(map, cx, cy)
  if not map then return "void" end
  if map:isWaterCell(cx, cy) then return "water" end
  if map:isGrassCell(cx, cy) then return "grass" end
  if map:isDoorTileCell(cx, cy) or map:isWarpTileCell(cx, cy) then return "door" end
  if map:isWalkableCell(cx, cy) then return "ground" end
  return "wall"
end

local function cellKey(x, y)
  return x .. ":" .. y
end

local function blockAt(map, bx, by)
  local def = map and map.def
  if not def or bx < 0 or by < 0 or bx >= (def.width or 0)
     or by >= (def.height or 0) then
    return nil
  end
  if type(map.blockAt) == "function" then return map:blockAt(bx, by) end
  return def.blocks and def.blocks[by * def.width + bx + 1]
end

-- Facility maps are the reliable semantic link between an exterior door and
-- the building drawn around it.  This deliberately avoids brittle tile-color
-- matching and continues to work with palette-changing mods.
function M.facilityKind(destMap)
  if type(destMap) ~= "string" then return nil end
  if destMap:find("_POKECENTER", 1, true) then return "center" end
  if destMap:find("_MART", 1, true) then return "mart" end
  if destMap:match("_GYM$") then return "gym" end
  return nil
end

-- Return a cell -> facility-kind lookup for the full exterior footprint of
-- every Mart, Poké Center and Gym on `map`.  Kanto's small service buildings
-- have a stable 2x2-block facade around their door.  Gyms use the canonical
-- 12/13/14 and 16/17/18 metatile rows, whose width varies by town, so their
-- actual full width is recovered from those rows rather than guessed.
function M.facilityCells(map)
  if not map then return {} end
  local cached = facilityCache[map]
  if cached then return cached end

  local cells, def = {}, map.def or {}
  local function fill(kind, bx, by, width, height)
    for y = by * 2, (by + height) * 2 - 1 do
      for x = bx * 2, (bx + width) * 2 - 1 do
        if not map.inBounds or map:inBounds(x, y) then
          cells[cellKey(x, y)] = kind
        end
      end
    end
  end

  -- Celadon's department store has two exterior doors and a larger facade;
  -- merge both warps into one exact 4x4-block footprint.  This is the one
  -- vanilla Mart whose geometry is not the common two-block-wide storefront.
  local celadonMart
  for _, warp in ipairs(def.warps or {}) do
    if warp.destMap == "CELADON_MART_1F" then
      local bx, by = math.floor(warp.x / 2), math.floor(warp.y / 2)
      if not celadonMart then celadonMart = { bx = bx, by = by }
      else
        celadonMart.bx = math.min(celadonMart.bx, bx)
        celadonMart.by = math.min(celadonMart.by, by)
      end
    end
  end

  for _, warp in ipairs(def.warps or {}) do
    local kind = M.facilityKind(warp.destMap)
    if kind and warp.destMap ~= "CELADON_MART_1F" then
      local bx, by = math.floor(warp.x / 2), math.floor(warp.y / 2)
      if kind == "gym" then
        local left = bx
        -- The entrance is at the right edge: scan across the real facade so
        -- Cerulean/Celadon/Saffron's wider Gyms are preserved intact.
        if blockAt(map, bx, by - 1) == 14 and blockAt(map, bx, by) == 18 then
          left = bx - 1
          while blockAt(map, left, by - 1) == 13 and blockAt(map, left, by) == 17 do
            left = left - 1
          end
          if blockAt(map, left, by - 1) == 12 and blockAt(map, left, by) == 16 then
            fill(kind, left, by - 1, bx - left + 1, 2)
          else
            fill(kind, bx - 2, by - 1, 3, 2)
          end
        else
          fill(kind, bx - 2, by - 1, 3, 2)
        end
      elseif warp.destMap == "CELADON_MART_5F"
          and blockAt(map, bx, by - 1) == 32 then
        -- This exterior doorway routes to Mart 5F and has a four-block-wide
        -- shop front instead of the common two-block storefront.
        fill(kind, bx, by - 1, 4, 2)
      else
        -- Standard Mart / Poké Center facade: top 32/33, lower 124/variant.
        -- The fallback keeps compatible custom maps useful even before their
        -- facade block layout is known.
        fill(kind, bx, by - 1, 2, 2)
      end
    end
  end
  if celadonMart then
    fill("mart", celadonMart.bx - 1, celadonMart.by - 3, 4, 4)
  end

  facilityCache[map] = cells
  return cells
end

function M.facilityAt(map, cx, cy)
  if not map or cx == nil or cy == nil then return nil end
  return M.facilityCells(map)[cellKey(cx, cy)]
end

function M.itemMarkerKind(itemDef)
  local machine = itemDef and itemDef.machine
  if machine and (machine.kind == "TM" or machine.kind == "HM") then
    return "machine"
  end
  return "item"
end

-- Return the overlay's upper-left corner in window coordinates.  The old
-- 160x144 UI canvas is deliberately not involved: an HUD overlay must follow
-- the actual window edge when widescreen exposes more of the overworld.
-- scaleX/scaleY convert the minimap's native pixels into LÖVE window units.
function M.rect(position, innerW, innerH, windowW, windowH, scaleX, scaleY)
  local border = 4
  windowW, windowH = windowW or 160, windowH or 144
  scaleX, scaleY = scaleX or 1, scaleY or scaleX
  local fullW, fullH = (innerW + border) * scaleX, (innerH + border) * scaleY
  local x = (position == "top_left" or position == "bottom_left")
    and 0 or windowW - fullW
  local y = (position == "top_left" or position == "top_right")
    and 0 or windowH - fullH
  return x, y
end

return M
