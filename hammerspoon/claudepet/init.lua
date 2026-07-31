--- Claude Desktop Pet
--- A floating pixel Claude that tells you when a Claude Code session finishes.
---
--- Claude Code hooks append events to ~/.claude/pet/inbox.jsonl; this module
--- tails that file and stacks a speech bubble beside the sprite for each one.

local State    = require("claudepet.state")
local Pet      = require("claudepet.pet")
local Stack    = require("claudepet.stack")
local Menu     = require("claudepet.menu")
local Terminal = require("claudepet.terminal")
local theme    = require("claudepet.theme")

local M = {}

local HOME = os.getenv("HOME")
local INBOX_DIR = HOME .. "/.claude/pet"
local INBOX = INBOX_DIR .. "/inbox.jsonl"

local DEDUPE_WINDOW = 5   -- seconds; ignore a repeat alert for the same session
local RECENT_MAX = 8
local HOTKEY = { { "ctrl", "alt", "cmd" }, "p" }

local COPY = {
  done    = { sound = "Hero",      body = "session is done — go look at it." },
  idle    = { sound = "Submarine", body = "is waiting on you." },
  ["end"] = { sound = "Bottle",    body = "session closed." },
}

local state, pet, stack, menu, menubar, watcher, hotkey
local offset = 0
local lastAlert = {}   -- session key -> timestamp
local recent = {}      -- newest-first history, for the menu

-- ---------------------------------------------------------------- inbox tail

local function fileSize(path)
  local attrs = hs.fs.attributes(path)
  return attrs and attrs.size or 0
end

--- Read whatever was appended since the last read.
local function readNewLines()
  local size = fileSize(INBOX)
  if size < offset then
    -- Truncated or rotated. Resume at the new end rather than replaying the
    -- whole file, which would fire a burst of alerts for stale sessions.
    offset = size
    return {}
  end
  if size == offset then return {} end

  local f = io.open(INBOX, "r")
  if not f then return {} end
  f:seek("set", offset)
  local chunk = f:read("*a") or ""
  offset = f:seek()
  f:close()

  local events = {}
  for line in chunk:gmatch("[^\n]+") do
    local ok, event = pcall(hs.json.decode, line)
    if ok and type(event) == "table" and event.session then
      table.insert(events, event)
    end
  end
  return events
end

-- ------------------------------------------------------------------- alerts

local function play(kind)
  if state.muted then return end
  local sound = hs.sound.getByName((COPY[kind] or COPY.done).sound)
  if sound then sound:play() end
end

local function focusEvent(event)
  Terminal.focus(event.tty)
end

--- One card per event — they stack, they never merge, text is never clipped.
local function alert(event)
  play(event.kind)

  table.insert(recent, 1, event)
  while #recent > RECENT_MAX do table.remove(recent) end

  if pet:isHidden() then return end   -- hidden means hidden: sound only

  pet:nudge()
  stack:setAnchor(pet:frame())

  local copy = COPY[event.kind] or COPY.done
  local body = copy.body
  if event.hint and event.hint ~= "" then
    body = body .. "\n“" .. event.hint .. "”"
  end

  stack:push(event.session, body, function() focusEvent(event) end)
end

local function handle(event)
  local key = (event.session_id ~= "" and event.session_id) or event.session
  local now = os.time()
  if lastAlert[key] and (now - lastAlert[key]) < DEDUPE_WINDOW then return end
  lastAlert[key] = now
  alert(event)
end

local function drain()
  for _, event in ipairs(readNewLines()) do handle(event) end
end

-- --------------------------------------------------------------------- menu

local actions   -- forward declaration; the submenu pages reference each other

--- The "Recent sessions" page: every remembered session, plus a way back.
local function recentPage()
  local rows = { { kind = "header", title = "RECENT SESSIONS" } }

  for _, event in ipairs(recent) do
    rows[#rows + 1] = {
      title = event.session,
      hint = os.date("%H:%M", event.ts),
      fn = function() focusEvent(event) end,
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { title = "← Back", submenu = function() return actions() end }
  return rows
end

--- The rows shared by the sprite menu and the menu bar item.
function actions()
  local rows = {}

  if #recent > 0 then
    rows[#rows + 1] = {
      title = "Recent sessions",
      hint = "▸ " .. #recent,
      submenu = recentPage,
    }
    rows[#rows + 1] = { kind = "sep" }
  end

  rows[#rows + 1] = {
    title = pet:isHidden() and "Show pet" or "Hide pet",
    hint = "⌃⌥⌘P",
    fn = function() M.toggle() end,
  }
  rows[#rows + 1] = {
    title = state.muted and "Unmute alerts" or "Mute alerts",
    fn = function()
      state.muted = not state.muted
      State.save(state)
    end,
  }
  rows[#rows + 1] = {
    title = theme.mode == "night" and "Day mode" or "Night mode",
    fn = function() M.toggleTheme() end,
  }

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { title = "Test bubble", fn = function() M.test() end }
  rows[#rows + 1] = { title = "Reload pet", fn = function() hs.reload() end }
  rows[#rows + 1] = {
    title = "Quit pet",
    fn = function() hs.application.get("Hammerspoon"):kill() end,
  }

  return rows
end

--- Drawn menu at the cursor — used when the sprite is clicked.
function M.showMenu()
  if menu:isOpen() then
    menu:hide()
    return
  end
  menu:show(actions(), hs.mouse.absolutePosition())
end

--- The menu bar item has to use AppKit's menu, so map the same rows onto it.
local function nativeMenu()
  local items = {}
  for _, row in ipairs(actions()) do
    if row.kind == "sep" then
      items[#items + 1] = { title = "-" }

    elseif row.kind == "header" then
      items[#items + 1] = { title = row.title, disabled = true }

    elseif row.submenu then
      local nested = {}
      for _, child in ipairs(row.submenu()) do
        if child.kind == "sep" or child.kind == "header" or child.submenu then
          -- skip the drawn menu's chrome; AppKit nests natively
        else
          nested[#nested + 1] = {
            title = child.hint and (child.title .. "   " .. child.hint) or child.title,
            fn = child.fn,
          }
        end
      end
      items[#items + 1] = { title = row.title, menu = nested }

    else
      local title = row.hint and (row.title .. "   " .. row.hint) or row.title
      items[#items + 1] = { title = title, fn = row.fn }
    end
  end
  return items
end

-- ------------------------------------------------------------------ control

function M.show()
  pet:show()
  State.save(state)
end

function M.hide()
  stack:clear()
  pet:hide()
  State.save(state)
end

function M.toggle()
  if pet:isHidden() then M.show() else M.hide() end
end

function M.toggleTheme()
  state.theme = theme.toggle()
  State.save(state)
  stack:clear()          -- redraw cards in the new palette from here on
  return state.theme
end

--- Current internals, for troubleshooting from the console or AppleScript.
function M.debug()
  local names = {}
  for _, event in ipairs(recent) do table.insert(names, event.session) end
  return {
    hidden = pet:isHidden(),
    muted = state.muted,
    theme = theme.mode,
    offset = offset,
    position = { x = pet.baseX, y = pet.baseY },
    cards = #stack.cards,
    recent = names,
  }
end

--- Fire a fake alert — useful for checking placement after moving the pet.
function M.test(name)
  handle({
    ts = os.time(),
    kind = "done",
    session = name or "test-session",
    session_id = "test-" .. tostring(math.floor(hs.timer.absoluteTime() / 1e6)),
    cwd = HOME,
    tty = "",
  })
end

-- -------------------------------------------------------------------- start

local function start()
  state = State.load()
  theme.set(state.theme or "night")

  hs.fs.mkdir(INBOX_DIR)
  -- Skip whatever accumulated while Hammerspoon was closed: only alert live.
  offset = fileSize(INBOX)

  pet = Pet.new({
    state = state,
    onClick = function() M.showMenu() end,
    onDragEnd = function()
      State.save(state)
      stack:setAnchor(pet:frame())
    end,
  })
  if not pet then return end

  stack = Stack.new()
  stack:setAnchor(pet:frame())
  menu = Menu.new()

  -- Always-present control in the top-right menu bar.
  menubar = hs.menubar.new()
  local icon = hs.image.imageFromPath(hs.configdir .. "/claudepet/assets/pet.png")
  if icon then menubar:setIcon(icon:setSize({ w = 20, h = 16 }), false) end
  menubar:setMenu(nativeMenu)

  watcher = hs.pathwatcher.new(INBOX_DIR, function() drain() end):start()
  hotkey = hs.hotkey.bind(HOTKEY[1], HOTKEY[2], function() M.toggle() end)

  -- Safety net in case a filesystem event is coalesced away.
  M.poll = hs.timer.doEvery(3, drain)
end

start()

return M
