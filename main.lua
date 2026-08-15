-- Terrain Minimap: a live, player-centred terrain overlay for Gen 1.
--
-- The ROM is never read here.  Gen1Recomp has already decoded the player's
-- private import into live Map objects; this mod samples those objects so it
-- also follows map edits made by compatible mods.
return function(mod)
  local function loadModule(path)
    local source, readErr = mod:read(path)
    if not source then
      mod.log:error("cannot read %s: %s; reinstall the mod", path,
        tostring(readErr))
      error("terrain_minimap missing " .. path, 0)
    end
    local compile = loadstring or load
    local chunk, compileErr = compile(source, "@" .. mod.path .. "/" .. path)
    if not chunk then
      mod.log:error("cannot compile %s: %s; reinstall the mod", path,
        tostring(compileErr))
      error("terrain_minimap cannot compile " .. path, 0)
    end
    return chunk()
  end

  local Core = loadModule("minimap_core.lua")
  local SCREEN_ID = "TerrainMinimapOptions"
  local DRAW_KEY = "__terrainMinimapOverlay"

  local SCHEMA = {
    { key = "enabled", label = "SHOW MINIMAP", type = "toggle", default = true },
    { key = "size", label = "MINIMAP SIZE", type = "choice", default = "medium",
      choices = { { "SMALL", "small" }, { "MEDIUM", "medium" },
                  { "LARGE", "large" } } },
    { key = "position", label = "MINIMAP CORNER", type = "choice",
      default = "top_right",
      choices = { { "TOP LEFT", "top_left" }, { "TOP RIGHT", "top_right" },
                  { "BOTTOM LEFT", "bottom_left" },
                  { "BOTTOM RIGHT", "bottom_right" } } },
    { key = "opacity", label = "MINIMAP OPACITY", type = "choice",
      default = 0.75,
      choices = { { "25%", 0.25 }, { "50%", 0.50 },
                  { "75%", 0.75 }, { "100%", 1.00 } } },
  }
  mod.options:define(SCHEMA)

  local CHOICES = {}
  for _, row in ipairs(SCHEMA) do
    if row.type == "choice" then CHOICES[row.key] = row.choices end
  end

  local function optionBucket(game, create)
    local options = game and game.save and game.save.options
    if not options then return nil end
    if create then options.modOptions = options.modOptions or {} end
    local buckets = options.modOptions
    if not buckets then return nil end
    if create then buckets[mod.id] = buckets[mod.id] or {} end
    return buckets[mod.id]
  end

  local function optionValue(game, key)
    local bucket = optionBucket(game, false)
    local value = bucket and bucket[key]
    if value ~= nil then return value end
    return mod.options:get(key)
  end

  local function setOption(game, key, value)
    local bucket = optionBucket(game, true)
    if not bucket then return end
    bucket[key] = value
    -- The loader keeps a live mirror so the mod-manager pane agrees with this
    -- OPTIONS submenu before the next restart.
    if game.mods then
      game.mods.modOptions = game.mods.modOptions or {}
      game.mods.modOptions[mod.id] = game.mods.modOptions[mod.id] or {}
      game.mods.modOptions[mod.id][key] = value
    end
    if game.writeOptions then game:writeOptions()
    elseif game.persistOptions then game:persistOptions() end
  end

  local function choiceLabel(game, key)
    local value = optionValue(game, key)
    for _, choice in ipairs(CHOICES[key] or {}) do
      if choice[2] == value then return choice[1] end
    end
    return "----"
  end

  local function cycleChoice(game, key, direction)
    local choices = CHOICES[key] or {}
    if #choices == 0 then return false end
    local value = optionValue(game, key)
    local index = 1
    for i, choice in ipairs(choices) do
      if choice[2] == value then index = i break end
    end
    index = (index - 1 + direction) % #choices + 1
    setOption(game, key, choices[index][2])
    return true
  end

  local COLORS = {
    void   = { 0.05, 0.07, 0.10, 1 },
    water  = { 0.18, 0.46, 0.76, 1 },
    grass  = { 0.25, 0.62, 0.32, 1 },
    ground = { 0.78, 0.70, 0.49, 1 },
    door   = { 0.82, 0.47, 0.20, 1 },
    wall   = { 0.27, 0.31, 0.36, 1 },
    mart   = { 0.22, 0.48, 0.88, 1 },
    center = { 0.86, 0.25, 0.26, 1 },
    gym    = { 0.91, 0.73, 0.16, 1 },
  }

  local ITEM_ICON_PATHS = {
    item = "assets/item-ball.png",
    machine = "assets/tm-hm-ball.png",
  }
  local itemIcons, itemIconErrors = {}, {}

  local function itemIcon(kind)
    if itemIcons[kind] ~= nil then return itemIcons[kind] or nil end
    if not (mod.assets and mod.assets.image) then return nil end
    local ok, imageOrError = pcall(function()
      return mod.assets:image(ITEM_ICON_PATHS[kind])
    end)
    if not ok then
      itemIcons[kind] = false
      if not itemIconErrors[kind] then
        itemIconErrors[kind] = true
        mod.log:error("cannot load %s: %s", ITEM_ICON_PATHS[kind],
                      tostring(imageOrError))
      end
      return nil
    end
    imageOrError:setFilter("nearest", "nearest")
    itemIcons[kind] = imageOrError
    return imageOrError
  end

  local function itemVisible(ow, save, map, obj)
    if type(ow.objectVisible) == "function" then
      return ow.objectVisible(save, map.id, obj)
    end
    -- Compatibility fallback for engine builds before objectVisible was
    -- exposed to mods.  It observes the same persisted item-taken key.
    if obj.hidden then return false end
    return not (save.itemsTaken and save.itemsTaken[map.id .. "_obj_" .. obj.index])
  end

  -- Build this fresh per frame so a ball disappears immediately after pickup.
  -- The map list is deliberately the current outdoor map plus its already
  -- loaded connected neighbours: no ROM reads or off-screen map loading.
  local function itemMarkers(ow, game)
    local markers, seenMaps = {}, {}
    local save, data = game.save or {}, game.data or {}
    local function addMap(map)
      if not map or seenMaps[map] then return end
      seenMaps[map] = true
      local byCell = {}
      for _, obj in ipairs((map.def and map.def.objects) or {}) do
        if obj.item and obj.item ~= "0" and obj.item ~= 0
            and itemVisible(ow, save, map, obj) then
          local itemDef = data.items and data.items[obj.item]
          local kind = Core.itemMarkerKind(itemDef)
          local key = obj.x .. ":" .. obj.y
          -- A malformed/custom map may stack markers; a machine takes visual
          -- precedence so it cannot be mistaken for an ordinary item.
          if byCell[key] ~= "machine" or kind == "machine" then byCell[key] = kind end
        end
      end
      markers[map] = byCell
    end
    addMap(ow.map)
    for _, neighbor in ipairs(ow.neighbors or {}) do addMap(neighbor.map) end
    return markers
  end

  -- render.hud runs after Gen1Recomp has composited the game into the real
  -- window.  Drawing there anchors to the actual display corners on wide
  -- windows instead of the old 160x144 UI canvas' centred letterbox.
  local function drawMinimap(ow, viewport)
    local game = mod.world and mod.world.game
    if not game or not optionValue(game, "enabled") then return end
    local player = ow and ow.player
    if not viewport or not player or player.cellX == nil or player.cellY == nil then return end

    local preset = Core.preset(optionValue(game, "size"))
    local opacity = Core.opacity(optionValue(game, "opacity"))
    local cellsWide = preset.radiusX * 2 + 1
    local cellsHigh = preset.radiusY * 2 + 1
    local innerW, innerH = cellsWide * preset.scale, cellsHigh * preset.scale
    -- `viewport.scale` is in framebuffer pixels; draw calls use LÖVE's
    -- window units, hence the independent DPI conversion on each axis.
    local scaleX = (viewport.scale or 1) / (viewport.dpiX or 1)
    local scaleY = (viewport.scale or 1) / (viewport.dpiY or 1)
    local x, y = Core.rect(optionValue(game, "position"), innerW, innerH,
                           viewport.width, viewport.height, scaleX, scaleY)
    local G = love.graphics
    local markers = itemMarkers(ow, game)

    G.push("all")
    G.setColor(0, 0, 0, 0.82 * opacity)
    G.rectangle("fill", x, y, (innerW + 4) * scaleX, (innerH + 4) * scaleY)
    G.setColor(0.92, 0.92, 0.86, 0.95 * opacity)
    G.setLineWidth(math.max(scaleX, scaleY))
    G.rectangle("line", x + 0.5 * scaleX, y + 0.5 * scaleY,
                (innerW + 3) * scaleX, (innerH + 3) * scaleY)

    for dy = -preset.radiusY, preset.radiusY do
      for dx = -preset.radiusX, preset.radiusX do
        local map, cx, cy = Core.mapAt(ow, player.cellX + dx, player.cellY + dy)
        -- Facility colour fills every cell of the exterior building's actual
        -- metatile footprint, not merely the door tile.
        local facility = Core.facilityAt(map, cx, cy)
        local terrain = facility or Core.terrain(map, cx, cy)
        local color = COLORS[terrain]
        G.setColor(color[1], color[2], color[3], color[4] * opacity)
        G.rectangle("fill", x + (2 + (dx + preset.radiusX) * preset.scale) * scaleX,
                    y + (2 + (dy + preset.radiusY) * preset.scale) * scaleY,
                    preset.scale * scaleX, preset.scale * scaleY)
      end
    end

    -- Field items are overlaid after terrain/facilities, so their tiny ball
    -- sprites stay visible without hiding the full footprint beneath them.
    local iconNative = 4 -- 8x8 source sprites drawn at half-size, like player marker
    for dy = -preset.radiusY, preset.radiusY do
      for dx = -preset.radiusX, preset.radiusX do
        local map, cx, cy = Core.mapAt(ow, player.cellX + dx, player.cellY + dy)
        local kind = map and markers[map] and markers[map][cx .. ":" .. cy]
        if kind then
          local px = x + (2 + (dx + preset.radiusX) * preset.scale) * scaleX
          local py = y + (2 + (dy + preset.radiusY) * preset.scale) * scaleY
          local image = itemIcon(kind)
          if image then
            G.setColor(1, 1, 1, opacity)
            G.draw(image, px + (preset.scale - iconNative) * 0.5 * scaleX,
                   py + (preset.scale - iconNative) * 0.5 * scaleY, 0,
                   iconNative / 8 * scaleX, iconNative / 8 * scaleY)
          else
            -- A visible fallback makes an incomplete installation obvious
            -- without suppressing useful item information.
            local fallback = kind == "machine" and { 0.96, 0.80, 0.12 }
              or { 0.92, 0.18, 0.20 }
            G.setColor(fallback[1], fallback[2], fallback[3], opacity)
            G.rectangle("fill", px, py, preset.scale * scaleX, preset.scale * scaleY)
          end
        end
      end
    end

    -- The player marker intentionally remains opaque and readable even when
    -- the terrain layer is set to 25% opacity.
    local markerX = x + (2 + preset.radiusX * preset.scale) * scaleX
    local markerY = y + (2 + preset.radiusY * preset.scale) * scaleY
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", markerX - scaleX, markerY - scaleY,
                (preset.scale + 2) * scaleX, (preset.scale + 2) * scaleY)
    G.setColor(1, 1, 1, 1)
    G.rectangle("fill", markerX, markerY,
                preset.scale * scaleX, preset.scale * scaleY)
    G.setColor(1, 1, 1, 1)
    G.pop()
  end

  local visibleOverworld

  local function attach(ow)
    if not ow then return end
    local overlay = rawget(ow, DRAW_KEY)
    if not overlay and type(ow.drawUI) == "function" then
      overlay = {}
      ow[DRAW_KEY] = overlay
      local drawUI = ow.drawUI
      ow.drawUI = function(self, ...)
        drawUI(self, ...)
        local current = rawget(self, DRAW_KEY)
        -- This only runs when the overworld itself rendered this frame.  The
        -- later HUD hook uses the marker to stay out of menus and battles.
        if current and current.draw then visibleOverworld = self end
      end
    end
    if overlay then overlay.draw = true end
  end

  -- map.entered is after the live Map and Player have been created.  The
  -- wrapper composes with other UI mods: it calls the prior drawUI first.
  mod.events:on("map.entered", function()
    attach(mod.world and mod.world:overworld())
  end)

  -- Clear the per-frame marker before states update and draw.  `drawUI` above
  -- re-arms it only when the overworld is visibly composing this frame.
  mod.hooks:wrap("core.update", function(next, game, dt)
    visibleOverworld = nil
    return next(game, dt)
  end)

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local result = next(game, viewport)
    if visibleOverworld then drawMinimap(visibleOverworld, viewport) end
    return result
  end)

  mod.content.screens:register(SCREEN_ID, {
    new = function(game)
      local rows = {
        { id = "enabled", label = "SHOW MINIMAP",
          value = function(g) return optionValue(g, "enabled") and "ON" or "OFF" end,
          step = function(g) setOption(g, "enabled", not optionValue(g, "enabled")); return true end },
        { id = "size", label = "MINIMAP SIZE",
          value = function(g) return choiceLabel(g, "size") end,
          step = function(g, dir) return cycleChoice(g, "size", dir) end },
        { id = "position", label = "MINIMAP CORNER",
          value = function(g) return choiceLabel(g, "position") end,
          step = function(g, dir) return cycleChoice(g, "position", dir) end },
        { id = "opacity", label = "MINIMAP OPACITY",
          value = function(g) return choiceLabel(g, "opacity") end,
          step = function(g, dir) return cycleChoice(g, "opacity", dir) end },
      }
      local screen = { screenId = SCREEN_ID, game = game, rows = rows,
                       index = 1, scroll = 0, isOpaque = true }

      function screen:sgbPalettes(g)
        return require("src.render.PaletteFX").wholeNamed(g.data, "MEWMON")
      end

      function screen:update()
        local input = self.game.input
        if input:wasPressed("up") then
          self.index = (self.index - 2) % #self.rows + 1
        elseif input:wasPressed("down") then
          self.index = self.index % #self.rows + 1
        elseif input:wasPressed("left") or input:wasPressed("right") then
          local dir = input:wasPressed("left") and -1 or 1
          self.rows[self.index].step(self.game, dir)
        elseif input:wasPressed("b") then
          self.game.stack:pop()
        end
        local OptionRows = require("src.ui.OptionRows")
        self.scroll = OptionRows.clampScroll(self.index, self.scroll, #self.rows, nil)
      end

      function screen:draw()
        local OptionRows = require("src.ui.OptionRows")
        local Font = require("src.render.Font")
        OptionRows.draw(self.game, self.rows, self.index, self.scroll)
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw("LEFT/RIGHT:CHANGE B:BACK", 8, 136)
        love.graphics.setColor(1, 1, 1, 1)
      end
      return screen
    end,
  })

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "MODS", {
      id = "terrain_minimap",
      label = "MINIMAP",
      value = function() return "CONFIGURE" end,
      activate = function(g) mod.ui.push(g, SCREEN_ID) end,
    })
  end)
end
