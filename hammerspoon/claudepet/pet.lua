--- The floating sprite: draws it, bobs it, drags it, remembers where it sat.

local theme = require("claudepet.theme")

local Pet = {}
Pet.__index = Pet

local ASSET = hs.configdir .. "/claudepet/assets/pet.png"
local BOB_PERIOD = 2.6     -- seconds per full bob cycle
local BOB_AMPLITUDE = 3    -- pixels
local BOB_FPS = 20
local DRAG_SLOP = 4        -- movement under this counts as a click, not a drag

--- @param opts table {state=..., onClick=fn, onDragEnd=fn(x,y)}
function Pet.new(opts)
  local self = setmetatable({}, Pet)

  self.state = opts.state
  self.onClick = opts.onClick
  self.onDragEnd = opts.onDragEnd

  local image = hs.image.imageFromPath(ASSET)
  if not image then
    hs.alert.show("claudepet: missing sprite at " .. ASSET)
    return nil
  end

  local size = image:size()
  self.w = theme.petWidth
  self.h = math.floor(theme.petWidth * (size.h / size.w) + 0.5)

  local x, y = self:defaultPosition()
  self.baseX = self.state.x or x
  self.baseY = self.state.y or y

  self.canvas = hs.canvas.new({ x = self.baseX, y = self.baseY, w = self.w, h = self.h })
  self.canvas:level(hs.canvas.windowLevels.floating)
  self.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                     | hs.canvas.windowBehaviors.stationary)
  self.canvas:clickActivating(false)
  self.canvas[1] = {
    type = "image",
    image = image,
    imageScaling = "scaleProportionally",
    imageAlignment = "center",
    frame = { x = 0, y = 0, w = self.w, h = self.h },
  }

  self:wireMouse()
  self:startBob()

  if not self.state.hidden then self.canvas:show() end
  return self
end

--- Park on the right edge, vertically centred, on a fresh install.
function Pet:defaultPosition()
  local frame = hs.screen.mainScreen():frame()
  return frame.x + frame.w - theme.petWidth - 28,
         frame.y + math.floor(frame.h / 2)
end

--- Where the sprite actually sits right now, bob excluded.
function Pet:frame()
  return { x = self.baseX, y = self.baseY, w = self.w, h = self.h }
end

function Pet:startBob()
  local t = 0
  self.bobTimer = hs.timer.doEvery(1 / BOB_FPS, function()
    if self.dragging or self.state.hidden then return end
    t = t + (1 / BOB_FPS)
    local offset = math.sin((t / BOB_PERIOD) * 2 * math.pi) * BOB_AMPLITUDE
    self.canvas:topLeft({ x = self.baseX, y = self.baseY + offset })
  end)
end

function Pet:wireMouse()
  self.canvas:canvasMouseEvents(true, true, false, false)
  self.canvas:mouseCallback(function(_, event)
    if event == "mouseDown" then
      self:beginDrag()
    end
  end)
end

--- Click-and-hold drag.
-- Polls the mouse rather than using hs.eventtap, so this works with no
-- Accessibility permission granted — eventtap:start() fails outright without it.
function Pet:beginDrag()
  local origin = hs.mouse.absolutePosition()
  local startX, startY = self.baseX, self.baseY
  local moved = 0
  self.dragging = true

  if self.dragTimer then self.dragTimer:stop() end

  self.dragTimer = hs.timer.doEvery(1 / 60, function()
    local buttons = hs.eventtap.checkMouseButtons()
    local held = buttons.left or buttons[1]

    if held then
      local now = hs.mouse.absolutePosition()
      local dx, dy = now.x - origin.x, now.y - origin.y
      moved = math.max(moved, math.abs(dx) + math.abs(dy))
      self.baseX, self.baseY = self:clamp(startX + dx, startY + dy)
      self.canvas:topLeft({ x = self.baseX, y = self.baseY })
      return
    end

    -- Button released: settle.
    self:endDrag(moved)
  end)
end

function Pet:endDrag(moved)
  self.dragging = false
  if self.dragTimer then self.dragTimer:stop(); self.dragTimer = nil end

  if moved < DRAG_SLOP then
    if self.onClick then self.onClick() end
  else
    self.state.x, self.state.y = self.baseX, self.baseY
    if self.onDragEnd then self.onDragEnd(self.baseX, self.baseY) end
  end
end

--- Keep the sprite fully on whichever screen it was dropped nearest.
function Pet:clamp(x, y)
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = screen:frame()
  x = math.max(f.x, math.min(x, f.x + f.w - self.w))
  y = math.max(f.y, math.min(y, f.y + f.h - self.h))
  return x, y
end

function Pet:show()
  self.state.hidden = false
  self.canvas:show()
end

function Pet:hide()
  self.state.hidden = true
  self.canvas:hide()
end

function Pet:isHidden()
  return self.state.hidden
end

--- Quick hop so an alert is visible even out of the corner of your eye.
function Pet:nudge()
  if self.state.hidden then return end

  local hops, i = { -10, 0, -6, 0, -2, 0 }, 0
  local timer
  timer = hs.timer.doEvery(0.07, function()
    i = i + 1
    if i > #hops then
      timer:stop()
      return
    end
    self.canvas:topLeft({ x = self.baseX, y = self.baseY + hops[i] })
  end)
end

function Pet:delete()
  if self.bobTimer then self.bobTimer:stop() end
  if self.dragTimer then self.dragTimer:stop() end
  if self.canvas then self.canvas:delete() end
end

return Pet
