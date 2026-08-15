-- Exercise the render.hud path without a LÖVE window.  The important
-- regression is that a top-right minimap uses the real window width (1024),
-- not a 160px UI canvas centred inside it.
local function read(path)
  local file = assert(io.open(path, "r"))
  local source = file:read("*a")
  file:close()
  return source
end

local function eq(actual, expected, label)
  if actual ~= expected then
    error((label or "value") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local rectangles = {}
local draws = {}
love = { graphics = {
  push = function() end,
  pop = function() end,
  setColor = function() end,
  setLineWidth = function() end,
  rectangle = function(kind, x, y, w, h)
    rectangles[#rectangles + 1] = { kind = kind, x = x, y = y, w = w, h = h }
  end,
  draw = function(image, x, y, rotation, sx, sy)
    draws[#draws + 1] = { image = image, x = x, y = y, sx = sx, sy = sy }
  end,
} }

local hooks, events = {}, {}
local options = { schema = nil }
function options:define(schema) self.schema = schema end
function options:get(key)
  for _, row in ipairs(self.schema or {}) do
    if row.key == key then return row.default end
  end
end

local map = {
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 2 and y < 2 end,
  isWaterCell = function() return false end,
  isGrassCell = function() return false end,
  isDoorTileCell = function() return false end,
  isWarpTileCell = function() return false end,
  isWalkableCell = function() return true end,
  id = "TEST_MAP",
  def = { width = 1, height = 1, blocks = { 1 }, objects = {
    { index = 1, x = 1, y = 0, item = "POTION" },
    { index = 2, x = 0, y = 1, item = "TM_TEST" },
    { index = 3, x = 1, y = 1, item = "HM_TEST" },
    { index = 4, x = 0, y = 0, item = "TAKEN_ITEM" },
  } },
}
local overworld = {
  map = map,
  neighbors = {},
  player = { cellX = 0, cellY = 0 },
  drawUI = function() end,
  objectVisible = function(save, mapId, obj)
    return not (save.itemsTaken and save.itemsTaken[mapId .. "_obj_" .. obj.index])
  end,
}
local game = { save = { options = {}, itemsTaken = { TEST_MAP_obj_4 = true } },
  data = { items = {
    POTION = {}, TM_TEST = { machine = { kind = "TM" } },
    HM_TEST = { machine = { kind = "HM" } }, TAKEN_ITEM = {},
  } } }
local mod = {
  id = "terrain_minimap",
  path = ".",
  options = options,
  world = { game = game, overworld = function() return overworld end },
  content = { screens = { register = function() end } },
  ui = { insertBefore = function(rows) return rows end,
         push = function() end },
  log = { error = function() end },
  assets = { image = function(_, path)
    return { path = path, setFilter = function() end }
  end },
}
function mod:read(path) return read(path) end
mod.events = { on = function(_, name, callback) events[name] = callback end }
mod.hooks = { wrap = function(_, name, callback) hooks[name] = callback end }

local entry = assert(loadstring(read("main.lua"), "@main.lua"))()
entry(mod)

events["map.entered"]()
hooks["core.update"](function() end, game, 1 / 60)
overworld:drawUI()
hooks["render.hud"](function() end, game, {
  width = 1024, height = 768, scale = 5, dpiX = 1, dpiY = 1,
})

local frame = rectangles[1]
eq(frame.kind, "fill", "minimap frame draw")
eq(frame.x, 774, "top-right frame reaches true window edge")
eq(frame.y, 0, "top-right frame reaches top window edge")
eq(frame.w, 250, "medium minimap width scales with the game")
eq(frame.h, 190, "medium minimap height scales with the game")
eq(#draws, 3, "only visible field items draw icons")
local iconPaths = {}
for _, draw in ipairs(draws) do iconPaths[draw.image.path] = (iconPaths[draw.image.path] or 0) + 1 end
eq(iconPaths["assets/item-ball.png"], 1, "ordinary item uses red ball")
eq(iconPaths["assets/tm-hm-ball.png"], 2, "TM and HM use yellow ball")

local drawn = #rectangles
hooks["core.update"](function() end, game, 1 / 60)
hooks["render.hud"](function() end, game, {
  width = 1024, height = 768, scale = 5, dpiX = 1, dpiY = 1,
})
eq(#rectangles, drawn, "minimap stays hidden when overworld did not render")

print("hud_anchor_test: OK")
