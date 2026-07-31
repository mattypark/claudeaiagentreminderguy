# Security & privacy

Short version: this runs entirely on your machine, makes no network calls, needs
no macOS permissions, and never sends your session content anywhere.

Longer version, because you should not have to take that on faith.

## What it touches

| Path | Access | Why |
|---|---|---|
| `~/.claude/sessions/*.json` | read | Match a session id to its name and pid |
| Your session transcript | read (tail only) | The session title and, if you enable summaries, what it did |
| `~/.claude/pet/inbox.jsonl` | write | The event queue the pet reads |
| `~/.claude/settings.json` | append on install | Register the hook. Backed up first |
| `~/.hammerspoon/claudepet/` | write on install | The pet itself |
| `hs.settings` | read/write | Pet position, theme, personality, detail level |

That's the whole list. No sockets, no HTTP, no telemetry, no analytics, no
crash reporting of its own.

## Network

None. Grep the source: there is no `hs.http`, no `curl`, no `urllib`, no socket.
The only network activity in this project is `brew install --cask hammerspoon`
during setup, which is Homebrew fetching the official signed Hammerspoon cask.

## macOS permissions

None required. Specifically **not** Accessibility.

Dragging is done by polling `hs.mouse.absolutePosition()` and
`hs.eventtap.checkMouseButtons()`, neither of which needs permission. The global
hotkey uses Carbon hotkey registration, which doesn't either. Hammerspoon will
still show a red "Accessibility is not enabled!" warning — that's Hammerspoon
talking about itself, not this project. Leave it off.

## The AppleScript bridge is off by default

`hs.allowAppleScript(true)` would let **any** process on your Mac execute
arbitrary Lua inside Hammerspoon — which is arbitrary code execution as you.
It's genuinely useful for debugging, so the line ships in `init.lua`
**commented out**, and nothing in the install or in normal use turns it on.

Hammerspoon's own **Console** (menu bar hammer icon → Console) runs the same
commands without exposing that surface. Use it in preference to the bridge.

If you do enable it, understand what you're accepting, and turn it back off when
you're done debugging.

> **Important:** the setting is persisted by Hammerspoon, not by this config.
> Deleting or re-commenting the line does **not** switch it off — the preference
> survives. To actually close it, run this once in Hammerspoon's Console:
>
> ```lua
> hs.allowAppleScript(false)
> ```
>
> To check the current state: `hs.allowAppleScript()` returns true or false.

If you followed an older version of this README that used `osascript` commands,
you enabled it. Run the line above.

## Credential redaction

If you turn on summaries, the pet reads the last assistant message from your
transcript and displays part of it. That text can contain anything you pasted
into Claude — including secrets.

So every string is run through a redactor **before** it is written to the inbox
file or drawn on screen. Covered: OpenAI/Anthropic style `sk-` keys, GitHub
tokens (`ghp_`, `github_pat_`), Slack tokens, AWS access key ids, Google API
keys, JWTs, PEM private key headers, `key=`/`password=`/`token=` assignments,
and long opaque base64-ish blobs. Matches become `[redacted]`.

Treat this as a safety net, not a guarantee — no regex catches every secret
format. Two things follow from that:

- **`~/.claude/pet/inbox.jsonl` is created `0600`** (its directory `0700`), so
  only your user account can read it.
- **Bubbles are visible on your screen.** If you screen-share or record with
  summaries enabled, session text may be captured. Set **Bubble detail → Just
  the name** before demoing, or hide the pet with `⌃⌥⌘P`.

## Command injection

The one place external data reaches an interpreter is the Terminal-focus
AppleScript, which interpolates a tty path. That value is validated against
`^/dev/tty[a-zA-Z0-9]+$` before use; anything else falls back to simply
activating Terminal.

The hook passes its payload to Python through an environment variable rather
than the command line or `eval`, so payload content is never shell-interpreted.

## What the installer changes

- Appends **one** command to each of `Stop`, `SessionEnd` and `Notification` in
  `~/.claude/settings.json`. Existing hooks are preserved, not replaced.
- Copies `~/.claude/settings.json` to a timestamped `.bak` first.
- Appends a `require("claudepet")` line to `~/.hammerspoon/init.lua` if you
  already have one, rather than overwriting your config.
- Turns on Hammerspoon's launch-at-login, hides its dock icon, keeps its menu
  icon. Nothing else about your system is modified.

Removing it is in the README's prompt library, or by hand: delete
`~/.hammerspoon/claudepet/`, `~/.claude/hooks/claude-pet.sh`, `~/.claude/pet/`,
and strip the `claude-pet.sh` lines from `settings.json`.

## The hook runs on every turn

It's a short Python script that fails silently and always exits 0, so a bug in
it can't block or break a Claude Code session. Worst case it stops producing
alerts.

## Reporting something

Open an issue. If it's sensitive, say so in the issue without the details and
we'll find another channel.
