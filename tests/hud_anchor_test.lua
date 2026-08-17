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
local translates = {}
love = { graphics = {
  push = function() end,
  pop = function() end,
  translate = function(x, y) translates[#translates + 1] = { x = x, y = y } end,
  scale = function() end,
  setColor = function() end,
  setShader = function() end,
  setLineWidth = function() end,
  newShader = function() return {} end,
  rectangle = function(kind, x, y, w, h)
    rectangles[#rectangles + 1] = { kind = kind, x = x, y = y, w = w, h = h }
  end,
  draw = function(image, x, y, rotation, sx, sy)
    draws[#draws + 1] = { image = image, x = x, y = y, sx = sx, sy = sy }
  end,
} }

package.preload["src.render.Font"] = function()
  return {
    width = function(text) return #text * 8 end,
    draw = function() end,
  }
end

local hooks, events = {}, {}
local registeredScreen
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
local topState = overworld
game.stack = { top = function() return topState end }
local mod = {
  id = "terrain_minimap",
  path = ".",
  options = options,
  world = { game = game, overworld = function() return overworld end },
  content = { screens = { register = function(_, _, screen) registeredScreen = screen end } },
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

local function findRow(rows, id)
  for _, row in ipairs(rows) do
    if row.id == id or row.key == id then return row end
  end
  error("missing row: " .. id, 2)
end

local hudViewSchema = findRow(options.schema, "hud_view")
eq(hudViewSchema.default, "auto", "HUD View defaults to Auto")
local settings = registeredScreen.new(game)
local hudViewRow = findRow(settings.rows, "hud_view")
eq(hudViewRow.value(game), "AUTO", "HUD View displays Auto by default")
hudViewRow.step(game, 1)
eq(hudViewRow.value(game), "ALWAYS", "HUD View cycles to Always")
hudViewRow.step(game, -1)
eq(hudViewRow.value(game), "AUTO", "HUD View cycles back to Auto")

local viewport = {
  width = 1024, height = 768, scale = 5, dpiX = 1, dpiY = 1,
}
local function render()
  hooks["render.hud"](function() end, game, viewport)
end

render()

local frame = rectangles[1]
eq(frame.kind, "fill", "minimap frame draw")
eq(frame.x, 774, "top-right frame reaches true window edge")
eq(frame.y, 0, "top-right frame reaches top window edge")
eq(frame.w, 250, "medium minimap width scales with the game")
eq(frame.h, 190, "medium minimap height scales with the game")
local caption = rectangles[#rectangles - 1]
eq(caption.kind, "fill", "area caption background draw")
eq(caption.x, 774, "caption keeps minimap right alignment")
eq(caption.y, 200, "caption sits below top minimap")
eq(caption.w, 250, "caption matches minimap width")
eq(caption.h, 50, "caption has native 10px height")
eq(#translates, 1, "area label text receives one centred transform")
eq(#draws, 3, "only visible field items draw icons")
local iconPaths = {}
for _, draw in ipairs(draws) do iconPaths[draw.image.path] = (iconPaths[draw.image.path] or 0) + 1 end
eq(iconPaths["assets/item-ball.png"], 1, "ordinary item uses red ball")
eq(iconPaths["assets/tm-hm-ball.png"], 2, "TM and HM use yellow ball")

local function resetAutoState()
  topState = overworld
  overworld.transitioning = false
  overworld.flyAnim, overworld.flyArrive, overworld.teleportOut = nil, nil, nil
  overworld.engaging, overworld.emote, overworld.pikaHop = false, nil, nil
  overworld.healAnim, overworld.cutAnim, overworld.playerHidden = nil, nil, nil
  overworld.fishing, overworld.fishPose = nil, nil
  overworld.player.inputLocked = false
  overworld.runner = nil
  overworld.scriptMoves = {}
end

local function expectAutoHidden(label)
  local before = #rectangles
  render()
  eq(#rectangles, before, "Auto hides the HUD during " .. label)
  resetAutoState()
end

topState = { isTextBox = true }
expectAutoHidden("dialogue")
topState = { screenId = "Options" }
expectAutoHidden("menus")
topState = { isBattle = true }
expectAutoHidden("battles")
overworld.transitioning = true
expectAutoHidden("transitions")
overworld.engaging = true
expectAutoHidden("engagements")
overworld.player.inputLocked = true
expectAutoHidden("input locks")
overworld.runner = { isRunning = function() return true end }
expectAutoHidden("cutscene scripts")
overworld.scriptMoves = { {} }
expectAutoHidden("scripted movement")
overworld.fishing = {}
expectAutoHidden("field-action animations")

-- Always deliberately ignores all Auto visibility gates, but still needs a
-- live overworld (there is none on title/boot screens).
hudViewRow.step(game, 1)
topState = { isBattle = true }
overworld.transitioning = true
overworld.engaging = true
overworld.player.inputLocked = true
overworld.runner = { isRunning = function() return true end }
overworld.scriptMoves = { {} }
local beforeAlways = #rectangles
render()
if #rectangles <= beforeAlways then error("Always renders over an active battle", 2) end
eq(rectangles[beforeAlways + 1].kind, "fill", "Always starts with minimap frame")

print("hud_anchor_test: OK")
