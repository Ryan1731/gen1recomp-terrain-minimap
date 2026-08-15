local source = assert(io.open("minimap_core.lua", "r")):read("*a")
local Core = assert(loadstring(source, "@minimap_core.lua"))()

local function eq(actual, expected, label)
  if actual ~= expected then
    error((label or "value") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function fakeMap(width, height, terrain)
  return {
    inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < width and y < height end,
    isWaterCell = function(_, x, y) return terrain[x .. ":" .. y] == "water" end,
    isGrassCell = function(_, x, y) return terrain[x .. ":" .. y] == "grass" end,
    isDoorTileCell = function(_, x, y) return terrain[x .. ":" .. y] == "door" end,
    isWarpTileCell = function() return false end,
    isWalkableCell = function(_, x, y)
      local t = terrain[x .. ":" .. y]
      return t ~= "wall" and t ~= nil
    end,
  }
end

local root = fakeMap(4, 4, { ["1:1"] = "grass", ["2:1"] = "water", ["3:1"] = "wall" })
local east = fakeMap(3, 4, { ["0:1"] = "door" })
local overworld = { map = root, neighbors = { { map = east, ox = 64, oy = 0 } } }

local map, x, y = Core.mapAt(overworld, 1, 1)
eq(map, root, "current map")
eq(Core.terrain(map, x, y), "grass", "grass terrain")

map, x, y = Core.mapAt(overworld, 4, 1)
eq(map, east, "east neighbor")
eq(x, 0, "neighbor x conversion")
eq(Core.terrain(map, x, y), "door", "door terrain")

eq(Core.terrain(nil), "void", "empty space")
eq(Core.preset("large").radiusX, 15, "large preset")
eq(Core.preset("unknown").radiusY, 8, "fallback preset")
eq(Core.opacity(0.25), 0.25, "minimum opacity")
eq(Core.opacity(2), 1, "maximum opacity")
eq(Core.opacity("missing"), 0.75, "default opacity")
local x1, y1 = Core.rect("bottom_left", 30, 20)
eq(x1, 4, "left corner x")
eq(y1, 116, "bottom corner y")
print("minimap_core_test: OK")
