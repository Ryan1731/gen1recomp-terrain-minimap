-- Pure terrain and layout helpers.  Kept separate so it can be tested without
-- a LÖVE window or an imported ROM.
local M = {}

local PRESETS = {
  small  = { radiusX = 7,  radiusY = 5,  scale = 2 },
  medium = { radiusX = 11, radiusY = 8,  scale = 2 },
  large  = { radiusX = 15, radiusY = 11, scale = 2 },
}

function M.preset(size)
  return PRESETS[size] or PRESETS.medium
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

function M.rect(position, innerW, innerH)
  local margin, border = 4, 4
  local fullW, fullH = innerW + border, innerH + border
  local x = (position == "top_left" or position == "bottom_left")
    and margin or 160 - fullW - margin
  local y = (position == "top_left" or position == "top_right")
    and margin or 144 - fullH - margin
  return x, y
end

return M
