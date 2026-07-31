--- Look-and-feel tokens. Two palettes, terminal-flavoured: black/orange at
--- night, white/orange by day. Everything the pet draws reads from here.

local Theme = {}

local palettes = {
  night = {
    card       = { red = 0.055, green = 0.055, blue = 0.063, alpha = 0.98 },
    stroke     = { red = 0.91,  green = 0.38,  blue = 0.25,  alpha = 0.28 },
    text       = { red = 0.96,  green = 0.96,  blue = 0.97,  alpha = 1 },
    dim        = { red = 0.62,  green = 0.62,  blue = 0.65,  alpha = 1 },
    accent     = { red = 0.91,  green = 0.38,  blue = 0.25,  alpha = 1 },
    hover      = { red = 0.91,  green = 0.38,  blue = 0.25,  alpha = 0.16 },
    rule       = { red = 1,     green = 1,     blue = 1,     alpha = 0.09 },
  },
  day = {
    card       = { red = 0.99,  green = 0.98,  blue = 0.97,  alpha = 0.99 },
    stroke     = { red = 0.85,  green = 0.34,  blue = 0.19,  alpha = 0.35 },
    text       = { red = 0.10,  green = 0.10,  blue = 0.11,  alpha = 1 },
    dim        = { red = 0.38,  green = 0.37,  blue = 0.36,  alpha = 1 },
    accent     = { red = 0.82,  green = 0.31,  blue = 0.16,  alpha = 1 },
    hover      = { red = 0.85,  green = 0.34,  blue = 0.19,  alpha = 0.13 },
    rule       = { red = 0,     green = 0,     blue = 0,     alpha = 0.10 },
  },
}

Theme.mode = "night"

function Theme.palette()
  return palettes[Theme.mode] or palettes.night
end

function Theme.set(mode)
  if palettes[mode] then Theme.mode = mode end
end

function Theme.toggle()
  Theme.set(Theme.mode == "night" and "day" or "night")
  return Theme.mode
end

-- Sprite
Theme.petWidth   = 96

-- Bubbles
Theme.bubbleMaxW = 320
Theme.bubbleWideW = 430   -- summary cards need more room
Theme.bubblePad  = 14
Theme.bubbleGap  = 12    -- pet ↔ bubble
Theme.stackGap   = 8     -- bubble ↔ bubble
Theme.bubbleHold = 12    -- seconds before a card fades itself out

-- Menu
Theme.menuWidth  = 272
Theme.menuRow    = 30
Theme.menuPad    = 8

-- Type: monospace, to match the terminal the sessions live in.
Theme.fontName   = "Menlo"
Theme.titleSize  = 13
Theme.bodySize   = 12
Theme.menuSize   = 12.5
Theme.smallSize  = 10.5
Theme.closeSize  = 12    -- the small dismiss X on each card

return Theme
