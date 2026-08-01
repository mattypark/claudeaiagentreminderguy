--- Persistent pet state — position, visibility, theme, voice, sounds —
--- backed by hs.settings.

local KEY = "claudepet.state"

-- Note the absent x/y: a nil value in a Lua table constructor means the key
-- simply is not in the table, so anything defaulting to nil must not be relied
-- on here. `load` iterates what was stored first for exactly that reason —
-- otherwise a dragged position would never come back after a reload.
local defaults = {
  hidden = false,
  muted = false,
  theme = "night",
  voice = "direct",
  detail = "name",
  sounds = {},     -- { done = ..., idle = ..., ["end"] = ... }
}

local KEYS = { "x", "y", "hidden", "muted", "theme", "voice", "detail", "sounds" }

local State = {}

function State.load()
  local stored = hs.settings.get(KEY) or {}
  local out = {}

  -- Everything that was saved, including keys with no default (x, y).
  for _, key in ipairs(KEYS) do
    out[key] = stored[key]
  end

  -- Then fill in anything missing.
  for key, value in pairs(defaults) do
    if out[key] == nil then out[key] = value end
  end

  return out
end

function State.save(state)
  local out = {}
  for _, key in ipairs(KEYS) do
    out[key] = state[key]
  end
  hs.settings.set(KEY, out)
end

return State
