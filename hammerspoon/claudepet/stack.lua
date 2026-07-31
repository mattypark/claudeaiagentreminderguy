--- A vertical stack of speech bubbles.
---
--- One card per finished session — they never merge and text is never clipped.
--- Newest sits closest to the pet; older cards ride upward. Each card fades on
--- its own timer and the rest reflow into the gap.

local theme = require("claudepet.theme")

local Stack = {}
Stack.__index = Stack

local FADE = 0.18

function Stack.new()
  return setmetatable({ cards = {} }, Stack)
end

local function styled(text, size, color)
  return hs.styledtext.new(text, {
    font = { name = theme.fontName, size = size },
    color = color,
    paragraphStyle = { lineBreak = "wordWrap", lineSpacing = 2 },
  })
end

--- Wrapped height for `str` at the card's content width.
local function measure(str, size, width)
  local box = hs.drawing.getTextDrawingSize(styled(str, size, { white = 1 }), { w = width })
  return math.ceil(box.w), math.ceil(box.h)
end

--- Push a new card. `onClick` fires when it is clicked.
function Stack:push(title, body, onClick)
  local palette = theme.palette()
  local contentW = theme.bubbleMaxW - theme.bubblePad * 2

  local titleW, titleH = measure(title, theme.titleSize, contentW)
  local bodyW, bodyH = measure(body, theme.bodySize, contentW)

  -- Shrink to the text when it is short, but never clip: height follows the
  -- wrapped body, however many lines that turns out to be.
  local w = math.min(theme.bubbleMaxW, math.max(titleW, bodyW) + theme.bubblePad * 2)
  local h = titleH + bodyH + theme.bubblePad * 2 + 5

  local canvas = hs.canvas.new({ x = 0, y = 0, w = w, h = h })
  canvas:level(hs.canvas.windowLevels.floating)
  canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                | hs.canvas.windowBehaviors.stationary)
  canvas:clickActivating(false)

  canvas:appendElements({
    type = "rectangle",
    action = "strokeAndFill",
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
    fillColor = palette.card,
    strokeColor = palette.stroke,
    strokeWidth = 1,
    frame = { x = 0, y = 0, w = w, h = h },
  }, {
    type = "text",
    text = styled(title, theme.titleSize, palette.accent),
    frame = { x = theme.bubblePad, y = theme.bubblePad, w = contentW, h = titleH },
  }, {
    type = "text",
    text = styled(body, theme.bodySize, palette.dim),
    frame = {
      x = theme.bubblePad,
      y = theme.bubblePad + titleH + 5,
      w = contentW,
      h = bodyH,
    },
  })

  local card = { canvas = canvas, w = w, h = h }

  canvas:canvasMouseEvents(true, false, false, false)
  canvas:mouseCallback(function()
    self:remove(card)
    if onClick then onClick() end
  end)

  table.insert(self.cards, card)
  card.timer = hs.timer.doAfter(theme.bubbleHold, function() self:remove(card) end)

  self:layout()
  canvas:show(FADE)
  return card
end

--- Reposition every card: newest beside the pet, older ones stacked above.
function Stack:layout()
  if not self.anchor then return end

  local pet = self.anchor
  local screen = hs.screen.mainScreen():frame()

  -- Sit on whichever side of the pet has room.
  local onLeft = (pet.x + pet.w / 2) > (screen.x + screen.w / 2)

  local y = pet.y + pet.h / 2
  for i = #self.cards, 1, -1 do
    local card = self.cards[i]
    local x = onLeft and (pet.x - card.w - theme.bubbleGap)
                     or (pet.x + pet.w + theme.bubbleGap)

    if i == #self.cards then
      y = y - card.h / 2          -- newest centred on the pet
    else
      y = y - card.h - theme.stackGap
    end

    local cx = math.max(screen.x + 8, math.min(x, screen.x + screen.w - card.w - 8))
    local cy = math.max(screen.y + 8, math.min(y, screen.y + screen.h - card.h - 8))
    card.canvas:topLeft({ x = cx, y = cy })
  end

  -- Anything pushed off the top of the screen goes away.
  while #self.cards > 0 do
    local oldest = self.cards[1]
    local top = oldest.canvas:topLeft()
    if top.y > screen.y + 8 then break end
    self:remove(oldest, true)
  end
end

function Stack:remove(card, skipLayout)
  for i, existing in ipairs(self.cards) do
    if existing == card then
      table.remove(self.cards, i)
      break
    end
  end

  if card.timer then card.timer:stop(); card.timer = nil end
  if card.canvas then
    local canvas = card.canvas
    card.canvas = nil
    canvas:hide(FADE)
    hs.timer.doAfter(FADE + 0.05, function() canvas:delete() end)
  end

  if not skipLayout then self:layout() end
end

--- Tell the stack where the pet currently is.
function Stack:setAnchor(frame)
  self.anchor = frame
  self:layout()
end

function Stack:clear()
  for _, card in ipairs({ table.unpack(self.cards) }) do
    self:remove(card, true)
  end
  self.cards = {}
end

return Stack
