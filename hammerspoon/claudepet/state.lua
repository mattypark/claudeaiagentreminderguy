--- Persistent pet state (position, visibility, mute) backed by hs.settings.

local KEY = "claudepet.state"

local defaults = {
  x = nil,      -- nil => park on the right edge on first launch
  y = nil,
  hidden = false,
  muted = false,
  theme = "night",
  voice = "direct",
  detail = "name",
}

local State = {}

function State.load()
  local stored = hs.settings.get(KEY) or {}
  local out = {}
  for k, v in pairs(defaults) do
    local s = stored[k]
    if s == nil then out[k] = v else out[k] = s end
  end
  return out
end

function State.save(state)
  hs.settings.set(KEY, {
    x = state.x,
    y = state.y,
    hidden = state.hidden,
    muted = state.muted,
    theme = state.theme,
    voice = state.voice,
    detail = state.detail,
  })
end

return State
