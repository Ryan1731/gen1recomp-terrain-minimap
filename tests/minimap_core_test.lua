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

local blocks = {}
for i = 1, 12 * 6 do blocks[i] = 1 end
local facilities = fakeMap(24, 12, {})
facilities.def = {
  width = 12, height = 6, blocks = blocks,
  warps = {
    { destMap = "TEST_POKECENTER", x = 2, y = 7 },
    { destMap = "TEST_GYM", x = 16, y = 7 },
  },
}
function facilities:blockAt(x, y)
  return self.def.blocks[y * self.def.width + x + 1]
end
local function setBlock(x, y, value)
  facilities.def.blocks[y * facilities.def.width + x + 1] = value
end
-- The Centre's normal 2x2-block storefront begins at its door block.
setBlock(1, 2, 32); setBlock(2, 2, 33)
setBlock(1, 3, 124); setBlock(2, 3, 114)
-- A four-block-wide Gym must not be clipped to the smaller three-block shape.
setBlock(5, 2, 12); setBlock(6, 2, 13); setBlock(7, 2, 13); setBlock(8, 2, 14)
setBlock(5, 3, 16); setBlock(6, 3, 17); setBlock(7, 3, 17); setBlock(8, 3, 18)
eq(Core.facilityKind("VIRIDIAN_MART"), "mart", "mart destination")
eq(Core.facilityKind("VIRIDIAN_POKECENTER"), "center", "center destination")
eq(Core.facilityKind("VIRIDIAN_GYM"), "gym", "gym destination")
eq(Core.facilityAt(facilities, 2, 4), "center", "center fills full facade")
eq(Core.facilityAt(facilities, 5, 7), "center", "center far corner")
eq(Core.facilityAt(facilities, 10, 4), "gym", "gym starts at detected left edge")
eq(Core.facilityAt(facilities, 17, 7), "gym", "gym fills entire variable width")
eq(Core.facilityAt(facilities, 6, 4), nil, "outside facility remains terrain")
eq(Core.itemMarkerKind({ machine = { kind = "TM" } }), "machine", "TM marker")
eq(Core.itemMarkerKind({ machine = { kind = "HM" } }), "machine", "HM marker")
eq(Core.itemMarkerKind({}), "item", "ordinary item marker")
eq(Core.areaLabel("CERULEAN_CITY"), "CERULEAN CITY", "city area label")
eq(Core.areaLabel("MT_MOON_1F"), "MT. MOON 1F", "cavern area label")
eq(Core.areaLabel("SS_ANNE_1F"), "S.S. ANNE 1F", "ship area label")

local x1, y1 = Core.rect("bottom_left", 30, 20, 320, 240, 2, 2)
eq(x1, 0, "left window edge x")
eq(y1, 192, "bottom window edge y")
local x2, y2 = Core.rect("top_right", 30, 20, 320, 240, 2, 2)
eq(x2, 252, "right window edge x")
eq(y2, 0, "top window edge y")
local mx, my, cx, cy = Core.stackRect("bottom_left", 30, 20, 10, 2, 320, 240, 2, 2)
eq(mx, 0, "bottom stack stays left aligned")
eq(my, 168, "bottom map lifts for caption")
eq(cx, 0, "caption stays aligned with map")
eq(cy, 220, "caption reaches bottom edge")
print("minimap_core_test: OK")
