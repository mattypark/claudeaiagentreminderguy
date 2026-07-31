--- A drawn menu, styled like the terminal the sessions live in — not an
--- AppKit context menu.
---
--- Rows come in as { title = ..., hint = ..., fn = ..., kind = "item"|"sep"|"header" }.
--- A full-screen transparent shield behind it catches clicks that land outside,
--- which avoids needing an event tap (and therefore any permissions).

local theme = require("claudepet.theme")

local Menu = {}
Menu.__index = Menu

local FADE = 0.10

function Menu.new()
  return setmetatable({ rows = {}, hovered = nil }, Menu)
end

local HINT_W = 62      -- fixed right column, so titles can never collide with it
local TITLE_X = theme.menuPad + 8

--- Menu text is always one line: long session names get an ellipsis rather
--- than wrapping out of their row.
local function styled(text, size, color, align)
  return hs.styledtext.new(text, {
    font = { name = theme.fontName, size = size },
    color = color,
    paragraphStyle = {
      lineBreak = "truncateTail",
      alignment = align or "left",
    },
  })
end

local function rowHeight(row)
  if row.kind == "sep" then return 9 end
  if row.kind == "header" then return 22 end
  return theme.menuRow
end

--- Draw (or redraw) every row; `hovered` gets a highlight behind it.
function Menu:render()
  local palette = theme.palette()
  local w = theme.menuWidth
  local canvas = self.canvas

  canvas:replaceElements({
    type = "rectangle",
    action = "strokeAndFill",
    roundedRectRadii = { xRadius = 12, yRadius = 12 },
    fillColor = palette.card,
    strokeColor = palette.stroke,
    strokeWidth = 1,
    frame = { x = 0, y = 0, w = w, h = self.height },
  })

  local y = theme.menuPad
  for index, row in ipairs(self.rows) do
    local h = rowHeight(row)

    if row.kind == "sep" then
      canvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = palette.rule,
        frame = { x = theme.menuPad + 2, y = y + 4, w = w - (theme.menuPad + 2) * 2, h = 1 },
      })

    elseif row.kind == "header" then
      canvas:appendElements({
        type = "text",
        text = styled(row.title, theme.smallSize, palette.dim),
        frame = { x = theme.menuPad + 8, y = y + 4, w = w - theme.menuPad * 2, h = h },
      })

    else
      if index == self.hovered then
        canvas:appendElements({
          type = "rectangle",
          action = "fill",
          roundedRectRadii = { xRadius = 7, yRadius = 7 },
          fillColor = palette.hover,
          frame = { x = 5, y = y, w = w - 10, h = h },
        })
      end

      local color = (index == self.hovered) and palette.accent or palette.text
      local titleW = w - TITLE_X - theme.menuPad
      if row.hint then titleW = titleW - HINT_W - 10 end

      canvas:appendElements({
        type = "text",
        text = styled(row.title, theme.menuSize, color),
        frame = { x = TITLE_X, y = y + 7, w = titleW, h = h - 8 },
      })

      if row.hint then
        canvas:appendElements({
          type = "text",
          text = styled(row.hint, theme.smallSize, palette.dim, "right"),
          frame = { x = w - theme.menuPad - HINT_W, y = y + 9, w = HINT_W, h = h - 10 },
        })
      end
    end

    row._y, row._h = y, h
    y = y + h
  end
end

function Menu:rowAt(y)
  for index, row in ipairs(self.rows) do
    if row.kind ~= "sep" and row.kind ~= "header"
       and y >= row._y and y < (row._y + row._h) then
      return index
    end
  end
  return nil
end

--- Swap the contents in place — used to drill into a submenu and back out.
function Menu:replace(rows)
  if not self.canvas then return end
  self.rows = rows
  self.hovered = nil

  local height = theme.menuPad * 2
  for _, row in ipairs(rows) do height = height + rowHeight(row) end
  self.height = height

  local screen = hs.screen.mainScreen():frame()
  local top = self.canvas:topLeft()
  local y = math.max(screen.y + 6, math.min(top.y, screen.y + screen.h - height - 6))

  self.canvas:frame({ x = top.x, y = y, w = theme.menuWidth, h = height })
  self:render()
end

--- Open at `point` (a screen coordinate).
function Menu:show(rows, point)
  self:hide()
  self.rows = rows
  self.hovered = nil

  local height = theme.menuPad * 2
  for _, row in ipairs(rows) do height = height + rowHeight(row) end
  self.height = height

  local screen = hs.screen.mainScreen():frame()
  local x = math.max(screen.x + 6, math.min(point.x - 12, screen.x + screen.w - theme.menuWidth - 6))
  local y = math.max(screen.y + 6, math.min(point.y - 10, screen.y + screen.h - height - 6))

  -- Click-outside shield.
  self.shield = hs.canvas.new(screen)
  self.shield:level(hs.canvas.windowLevels.floating - 1)
  self.shield:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                     | hs.canvas.windowBehaviors.stationary)
  self.shield:clickActivating(false)
  self.shield[1] = {
    type = "rectangle",
    action = "fill",
    fillColor = { white = 0, alpha = 0.001 },
    frame = { x = 0, y = 0, w = screen.w, h = screen.h },
  }
  self.shield:canvasMouseEvents(true, false, false, false)
  self.shield:mouseCallback(function() self:hide() end)
  self.shield:show()

  self.canvas = hs.canvas.new({ x = x, y = y, w = theme.menuWidth, h = height })
  self.canvas:level(hs.canvas.windowLevels.floating + 1)
  self.canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces
                     | hs.canvas.windowBehaviors.stationary)
  self.canvas:clickActivating(false)
  self:render()

  self.canvas:canvasMouseEvents(true, true, true, true)
  self.canvas:mouseCallback(function(_, event, _, _, cy)
    if event == "mouseMove" or event == "mouseEnter" then
      local index = self:rowAt(cy)
      if index ~= self.hovered then
        self.hovered = index
        self:render()
      end

    elseif event == "mouseExit" then
      if self.hovered then
        self.hovered = nil
        self:render()
      end

    elseif event == "mouseUp" then
      local index = self:rowAt(cy)
      local row = index and self.rows[index]
      if not row then return end

      -- `submenu` rows swap the panel's contents instead of closing it.
      if row.submenu then
        self:replace(row.submenu())
        return
      end

      self:hide()
      if row.fn then row.fn() end
    end
  end)

  self.canvas:show(FADE)
end

function Menu:hide()
  if self.canvas then
    local canvas = self.canvas
    self.canvas = nil
    canvas:hide(FADE)
    hs.timer.doAfter(FADE + 0.05, function() canvas:delete() end)
  end
  if self.shield then
    self.shield:delete()
    self.shield = nil
  end
end

function Menu:isOpen()
  return self.canvas ~= nil
end

return Menu
