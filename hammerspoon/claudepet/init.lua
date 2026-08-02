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
local Voices   = require("claudepet.voices")
local Sounds   = require("claudepet.sounds")
local theme    = require("claudepet.theme")

local M = {}

local HOME = os.getenv("HOME")
local INBOX_DIR = HOME .. "/.claude/pet"
local INBOX = INBOX_DIR .. "/inbox.jsonl"

local DEDUPE_WINDOW = 5   -- seconds; ignore a repeat alert for the same session
local RECENT_MAX = 8
local HOTKEY = { { "ctrl", "alt", "cmd" }, "p" }

-- Wording comes from the chosen personality, the sound from your picks below.
local DEFAULT_SOUNDS = { done = "Hero", idle = "Submarine", ["end"] = "Bottle", ask = "Ping" }
local SOUND_EVENTS = {
  { kind = "done",  label = "Session done" },
  { kind = "ask",   label = "Asking you a question" },
  { kind = "idle",  label = "Waiting on you" },
  { kind = "end",   label = "Session closed" },
}

-- How many summary bullets each detail level shows. nil = announcement only.
local DETAIL_POINTS = { name = nil, summary = 3, full = 6 }
local DETAIL_ORDER = { "name", "summary", "full" }
local DETAIL_LABEL = {
  name    = { label = "Just the name",  blurb = "one line",   example = "session name · session is done" },
  summary = { label = "Summary",        blurb = "3 points",   example = "+ three bullets on what it did" },
  full    = { label = "Full recap",     blurb = "everything", example = "+ up to six bullets, what's left to do" },
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

local function soundFor(kind)
  return (state.sounds and state.sounds[kind]) or DEFAULT_SOUNDS[kind] or DEFAULT_SOUNDS.done
end

local function play(kind)
  if state.muted then return end
  Sounds.play(soundFor(kind))
end

local function focusEvent(event)
  Terminal.focus(event.tty)
end

local function eventKey(event)
  return (event.session_id ~= "" and event.session_id) or event.session
end

--- History holds one row per session: a repeat moves it back to the top with a
--- fresh timestamp rather than adding a second entry for the same session.
local function remember(event)
  local key = eventKey(event)
  for index, existing in ipairs(recent) do
    if eventKey(existing) == key then
      table.remove(recent, index)
      break
    end
  end

  table.insert(recent, 1, event)
  while #recent > RECENT_MAX do table.remove(recent) end
end

--- One card per event — they stack, they never merge, text is never clipped.
local function alert(event)
  play(event.kind)
  remember(event)

  if pet:isHidden() then return end   -- hidden means hidden: sound only

  pet:nudge()
  stack:setAnchor(pet:frame())

  local body = Voices.line(state.voice, event.kind)
  if event.hint and event.hint ~= "" then
    body = body .. "\n“" .. event.hint .. "”"
  end

  -- How much of what the session did to show alongside the announcement.
  local points = nil
  -- A question's options aren't a recap, they're the question — always shown,
  -- whatever detail level the recap bubbles are set to.
  local wanted = (event.kind == "ask") and 6 or DETAIL_POINTS[state.detail]
  if wanted and event.points and #event.points > 0 then
    points = {}
    for index, point in ipairs(event.points) do
      if index > wanted then break end
      points[#points + 1] = point
    end
  end

  stack:push(event.session, body, points, function() focusEvent(event) end)
end

local function handle(event)
  -- Dedupe per kind: a question landing seconds after a recap is a real second
  -- alert, not a repeat of the first.
  local key = eventKey(event) .. "|" .. (event.kind or "done")
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

--- The "Personality" page: every voice, each showing what it actually says.
local function personalityPage()
  local rows = { { kind = "header", title = "PERSONALITY" } }

  for _, key in ipairs(Voices.order) do
    local voice = Voices.get(key)
    local active = (state.voice == key)

    rows[#rows + 1] = {
      title = (active and "● " or "   ") .. voice.label,
      hint = active and "on" or voice.blurb,
      preview = "“" .. Voices.example(key, "done") .. "”",
      fn = function()
        state.voice = key
        State.save(state)
        M.test("preview")          -- show the new voice immediately
      end,
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { title = "← Back", submenu = function() return actions() end }
  return rows
end

--- The "Bubble detail" page: how much of the session's work to show.
local function detailPage()
  local rows = { { kind = "header", title = "BUBBLE DETAIL" } }

  for _, key in ipairs(DETAIL_ORDER) do
    local option = DETAIL_LABEL[key]
    local active = (state.detail == key)

    rows[#rows + 1] = {
      title = (active and "● " or "   ") .. option.label,
      hint = active and "on" or option.blurb,
      preview = option.example,
      fn = function()
        state.detail = key
        State.save(state)
        M.testSummary()        -- show what that level looks like right away
      end,
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { title = "← Back", submenu = function() return actions() end }
  return rows
end

local soundsPage   -- forward declaration; the pickers link back to it

--- Picker for one event's sound. Choosing plays it straight away.
local function soundPickerPage(event)
  local rows = { { kind = "header", title = event.label:upper() } }
  local current = soundFor(event.kind)

  for _, option in ipairs(Sounds.all()) do
    local active = (option.id == current)
    rows[#rows + 1] = {
      title = (active and "● " or "   ") .. option.label,
      hint = active and "on" or (option.builtin and "built-in" or (option.silent and "" or "yours")),
      fn = function()
        state.sounds = state.sounds or {}
        state.sounds[event.kind] = option.id
        State.save(state)
        Sounds.play(option.id)     -- hear it immediately
      end,
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { title = "← Back", submenu = function() return soundsPage() end }
  return rows
end

--- The "Sound effects" page: one row per event, plus the drop folder.
function soundsPage()
  local rows = { { kind = "header", title = "SOUND EFFECTS" } }

  for _, event in ipairs(SOUND_EVENTS) do
    rows[#rows + 1] = {
      title = event.label,
      hint = "▸ " .. Sounds.label(soundFor(event.kind)),
      submenu = function() return soundPickerPage(event) end,
    }
  end

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = {
    title = "Add your own…",
    preview = "drop .mp3 / .m4a / .wav / .mp4 in the folder, then Reload pet",
    fn = function() Sounds.openFolder() end,
  }
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
    title = "Personality",
    hint = "▸ " .. Voices.get(state.voice).label,
    submenu = personalityPage,
  }
  rows[#rows + 1] = {
    title = "Bubble detail",
    hint = "▸ " .. DETAIL_LABEL[state.detail].label,
    submenu = detailPage,
  }
  rows[#rows + 1] = {
    title = "Sound effects",
    hint = "▸ " .. Sounds.label(soundFor("done")),
    submenu = soundsPage,
  }
  rows[#rows + 1] = {
    title = theme.mode == "night" and "Day mode" or "Night mode",
    fn = function() M.toggleTheme() end,
  }

  rows[#rows + 1] = { kind = "sep" }
  rows[#rows + 1] = { title = "Test bubble", fn = function() M.test() end }
  rows[#rows + 1] = { title = "Test question", fn = function() M.testAsk() end }
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
    voice = state.voice,
    detail = state.detail,
    sounds = {
      done = Sounds.label(soundFor("done")),
      ask = Sounds.label(soundFor("ask")),
      idle = Sounds.label(soundFor("idle")),
      ["end"] = Sounds.label(soundFor("end")),
    },
    offset = offset,
    position = { x = pet.baseX, y = pet.baseY },
    cards = #stack.cards,
    recent = names,
  }
end

--- Fire a fake alert carrying summary points, to preview the detail levels.
function M.testSummary()
  handle({
    ts = os.time(),
    kind = "done",
    session = "payments-api-refactor",
    session_id = "test-summary-" .. tostring(os.time()),
    cwd = HOME,
    tty = "",
    points = {
      "Split the payment handler into charge, refund and webhook modules",
      "Added retry with backoff around the provider call",
      "17 tests passing, 2 skipped pending sandbox credentials",
      "Left to do: decide whether refunds should be idempotent by request id",
      "Dev server still running on localhost:3000",
      "Nothing committed yet — say the word and I'll push",
    },
  })
end

--- Fire a fake question alert, to preview what an option picker looks like.
function M.testAsk()
  handle({
    ts = os.time(),
    kind = "ask",
    session = "landing-page-rebuild",
    session_id = "test-ask-" .. tostring(os.time()),
    cwd = HOME,
    tty = "",
    hint = "Which stack should I build it in?  (1 of 4)",
    points = {
      "Next.js 16 + Tailwind (Recommended)",
      "Vite + React + Tailwind",
      "Plain HTML/CSS/JS, single file",
      "then: Brand",
      "then: Deploy target",
    },
  })
end

--- Fire a fake alert — useful for checking placement after moving the pet.
function M.test(name)
  name = name or "test-session"
  handle({
    ts = os.time(),
    kind = "done",
    session = name,
    session_id = "test-" .. name,   -- stable, so repeats collapse like real ones
    cwd = HOME,
    tty = "",
  })
end

-- -------------------------------------------------------------------- start

--- Configure Hammerspoon itself, once, so setup needs no manual clicking and no
--- scripting bridge left switched on.
local function applyPreferences()
  if state.configured then return end

  hs.autoLaunch(true)      -- survive reboots
  hs.dockIcon(false)       -- he lives in the menu bar
  hs.menuIcon(true)        -- keep Preferences and the Console reachable

  state.configured = true
  State.save(state)
end

local function start()
  state = State.load()
  theme.set(state.theme or "night")
  applyPreferences()

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
