-- Hammerspoon config

claudepet = require("claudepet")

-- OPTIONAL — off by default, on purpose.
--
-- Uncommenting this lets *any* process on your Mac run arbitrary Lua inside
-- Hammerspoon via `osascript`, which means running code as you. It is handy for
-- debugging (some commands in the project's Troubleshooting section use it), but
-- it is a real privilege-escalation surface, so it should be a decision you make
-- rather than a default you inherited.
--
-- The pet does not need it. Everything is reachable from its menu, and
-- Hammerspoon's own Console (menu bar hammer icon -> Console) runs the same
-- commands without opening the door to other processes.
--
-- hs.allowAppleScript(true)
