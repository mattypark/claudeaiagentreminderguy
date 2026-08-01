--- Sound effects: macOS system sounds as templates, plus any audio file you
--- drop into ~/.hammerspoon/claudepet/sounds/.

local Sounds = {}

Sounds.dir = hs.configdir .. "/claudepet/sounds"

-- Curated from hs.sound.systemSounds() — the ones that read as notifications.
Sounds.builtin = {
  "Hero", "Submarine", "Bottle", "Glass", "Ping", "Pop",
  "Purr", "Tink", "Blow", "Frog", "Funk", "Morse", "Sosumi", "Basso",
}

local EXTENSIONS = { mp3 = true, m4a = true, wav = true, aiff = true, aif = true,
                     mp4 = true, caf = true, aac = true }

--- Audio files you've added yourself, as { label = ..., id = "file:<path>" }.
function Sounds.custom()
  local found = {}
  hs.fs.mkdir(Sounds.dir)

  -- hs.fs.dir returns an iterator plus its state, so it has to be driven
  -- directly by the for loop, not stashed in a single local first.
  local ok = pcall(function()
    for name in hs.fs.dir(Sounds.dir) do
      local ext = name:match("%.([^.]+)$")
      if ext and EXTENSIONS[ext:lower()] and name:sub(1, 1) ~= "." then
        found[#found + 1] = {
          label = name:gsub("%.[^.]+$", ""),
          id = "file:" .. Sounds.dir .. "/" .. name,
        }
      end
    end
  end)
  if not ok then return {} end

  table.sort(found, function(a, b) return a.label < b.label end)
  return found
end

--- Every choosable sound, templates first.
function Sounds.all()
  local list = {}
  for _, name in ipairs(Sounds.builtin) do
    list[#list + 1] = { label = name, id = name, builtin = true }
  end
  for _, entry in ipairs(Sounds.custom()) do
    list[#list + 1] = entry
  end
  list[#list + 1] = { label = "Silent", id = "none", silent = true }
  return list
end

function Sounds.label(id)
  if not id or id == "none" then return "Silent" end
  if id:sub(1, 5) == "file:" then
    return (id:match("([^/]+)$") or id):gsub("%.[^.]+$", "")
  end
  return id
end

--- Resolve an id to a playable sound, or nil.
local cache = {}

function Sounds.resolve(id)
  if not id or id == "none" then return nil end

  if cache[id] then return cache[id] end

  local sound
  if id:sub(1, 5) == "file:" then
    local path = id:sub(6)
    if hs.fs.attributes(path) then
      sound = hs.sound.getByFile(path)
    end
  else
    sound = hs.sound.getByName(id)
  end

  cache[id] = sound
  return sound
end

function Sounds.play(id)
  local sound = Sounds.resolve(id)
  if not sound then return false end
  sound:stop()          -- restart rather than overlap when alerts land together
  sound:play()
  return true
end

--- Reveal the folder so you can drop files in.
function Sounds.openFolder()
  hs.fs.mkdir(Sounds.dir)
  hs.execute("open " .. ("%q"):format(Sounds.dir))
end

return Sounds
