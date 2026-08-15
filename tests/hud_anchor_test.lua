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
love = { graphics = {
  push = function() end,
  pop = function() end,
  setColor = function() end,
  setLineWidth = function() end,
  rectangle = function(kind, x, y, w, h)
    rectangles[#rectangles + 1] = { kind = kind, x = x, y = y, w = w, h = h }
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
  inBounds = function() return false end,
}
local overworld = {
  map = map,
  neighbors = {},
  player = { cellX = 0, cellY = 0 },
  drawUI = function() end,
}
local game = { save = { options = {} } }
local mod = {
  id = "terrain_minimap",
  path = ".",
  options = options,
  world = { game = game, overworld = function() return overworld end },
  content = { screens = { register = function() end } },
  ui = { insertBefore = function(rows) return rows end,
         push = function() end },
  log = { error = function() end },
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

local drawn = #rectangles
hooks["core.update"](function() end, game, 1 / 60)
hooks["render.hud"](function() end, game, {
  width = 1024, height = 768, scale = 5, dpiX = 1, dpiY = 1,
})
eq(#rectangles, drawn, "minimap stays hidden when overworld did not render")

print("hud_anchor_test: OK")
