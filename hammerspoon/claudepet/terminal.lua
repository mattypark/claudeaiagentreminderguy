--- Bring the Terminal.app tab that ran a Claude session back to the front.

local Terminal = {}

local SCRIPT = [[
tell application "Terminal"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      try
        if tty of t is "%s" then
          set selected tab of w to t
          set index of w to 1
          return "ok"
        end if
      end try
    end repeat
  end repeat
  return "notfound"
end tell
]]

--- Focus the tab bound to `tty` (e.g. "/dev/ttys003").
-- Falls back to just activating Terminal when the tab is gone.
function Terminal.focus(tty)
  -- The tty is interpolated into an AppleScript string, so only ever accept the
  -- exact shape ps produces. Anything else could smuggle in script of its own.
  if not tty or not tty:match("^/dev/tty[a-zA-Z0-9]+$") then
    hs.application.launchOrFocus("Terminal")
    return false
  end

  local ok, result = hs.osascript.applescript(string.format(SCRIPT, tty))
  if not ok or result == "notfound" then
    hs.application.launchOrFocus("Terminal")
    return false
  end
  return true
end

return Terminal
