--- Personalities. Each voice phrases the same three events differently, with a
--- few variants so the pet doesn't say the identical line every single time.

local Voices = {}

Voices.order = { "direct", "kind", "hype", "chill", "butler", "gremlin" }

Voices.all = {
  direct = {
    label = "Direct",
    blurb = "no fluff",
    done = {
      "session is done — go look at it.",
      "session finished. go look at it.",
    },
    idle = {
      "is waiting on you.",
      "needs an answer.",
    },
    ["end"] = {
      "session closed.",
    },
  },

  kind = {
    label = "Kind",
    blurb = "warm and gentle",
    done = {
      "your session is done — would love for you to take a look :)",
      "all finished! come see what it did whenever you can :)",
    },
    idle = {
      "is waiting on you — no rush, just whenever you're free :)",
      "has a question for you when you have a moment :)",
    },
    ["end"] = {
      "session closed — hope it went well :)",
    },
  },

  hype = {
    label = "Hype",
    blurb = "loud and caffeinated",
    done = {
      "IS DONE. GO LOOK :D",
      "just wrapped — go see it, it cooked :D",
    },
    idle = {
      "NEEDS YOU. RIGHT NOW >:O",
      "is stuck waiting on you — unblock it! :O",
    },
    ["end"] = {
      "session closed. good run \\o/",
    },
  },

  chill = {
    label = "Chill",
    blurb = "unbothered",
    done = {
      "all wrapped up whenever you're ready :]",
      "finished. it'll be here when you get back :]",
    },
    idle = {
      "is waiting on you, no pressure :]",
      "paused for you whenever you wander back :]",
    },
    ["end"] = {
      "session closed. later :]",
    },
  },

  butler = {
    label = "Butler",
    blurb = "very formal",
    done = {
      "has concluded its work. At your convenience.",
      "is complete. I have taken the liberty of finishing up.",
    },
    idle = {
      "awaits your instruction.",
      "requires a word with you when convenient.",
    },
    ["end"] = {
      "session has been closed. Good day.",
    },
  },

  gremlin = {
    label = "Gremlin",
    blurb = "smug little creature",
    done = {
      "done. i did the thing o7",
      "finished. you're welcome >:3",
    },
    idle = {
      "is bored. it wants you 0_0",
      "is just sitting there. waiting. staring -_-",
    },
    ["end"] = {
      "session closed. bye o7",
    },
  },
}

Voices.default = "direct"

function Voices.get(key)
  return Voices.all[key] or Voices.all[Voices.default]
end

--- A line for this event, picked at random from the voice's variants.
function Voices.line(key, kind)
  local voice = Voices.get(key)
  local lines = voice[kind] or voice.done
  return lines[math.random(#lines)]
end

--- The first variant, used for the preview in the personality picker.
function Voices.example(key, kind)
  local voice = Voices.get(key)
  local lines = voice[kind or "done"] or voice.done
  return lines[1]
end

return Voices
