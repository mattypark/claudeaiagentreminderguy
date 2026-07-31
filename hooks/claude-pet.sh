#!/bin/bash
# Claude Desktop Pet — hook bridge.
#
# Reads a Claude Code hook payload on stdin, resolves the session's display name
# (the one set with /rename), and appends a single event line to the pet inbox
# that the Hammerspoon pet tails.
#
# Never blocks or fails a turn: all errors are swallowed, exit is always 0.

KIND="${1:-done}"

# Buffer stdin first — the python heredoc below takes over fd 0.
PAYLOAD="$(cat)"

CLAUDE_PET_KIND="$KIND" CLAUDE_PET_PAYLOAD="$PAYLOAD" python3 - <<'PY' 2>/dev/null
import json, os, re, sys, time, glob, subprocess

KIND = os.environ.get("CLAUDE_PET_KIND", "done")
PAYLOAD = os.environ.get("CLAUDE_PET_PAYLOAD", "")

HOME = os.path.expanduser("~")
SESSIONS_DIR = os.path.join(HOME, ".claude", "sessions")
# Own directory so the pet's file watcher isn't woken by every other
# write under ~/.claude (history.jsonl, transcripts, caches...).
INBOX_DIR = os.path.join(HOME, ".claude", "pet")
INBOX = os.path.join(INBOX_DIR, "inbox.jsonl")


def load(raw):
    try:
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def session_meta(session_id):
    """Find the ~/.claude/sessions/<pid>.json record for this session."""
    if not session_id:
        return {}
    for path in glob.glob(os.path.join(SESSIONS_DIR, "*.json")):
        try:
            with open(path) as f:
                meta = json.load(f)
        except Exception:
            continue
        if meta.get("sessionId") == session_id:
            return meta
    return {}


def tty_for_pid(pid):
    """The Claude process owns the Terminal tab — ask ps for its tty."""
    if not pid:
        return ""
    try:
        out = subprocess.run(
            ["ps", "-p", str(pid), "-o", "tty="],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
    except Exception:
        return ""
    if not out or "?" in out:
        return ""
    return out if out.startswith("/dev/") else "/dev/" + out


def clean_prompt(text):
    """Strip the machinery out of a raw prompt so it reads like a sentence."""
    # Attachment markers, system reminders, hook-injected context.
    text = re.sub(r"\[Image[^\]]*\]", " ", text)
    text = re.sub(r"<[^>]+>.*?</[^>]+>", " ", text, flags=re.S)
    text = re.sub(r"<[^>]*>", " ", text)
    text = re.sub(r"(?im)^\s*(caveman mode|command-name|local-command).*$", " ", text)
    text = re.sub(r"/private/\S+|/var/folders/\S+", " ", text)
    return " ".join(text.split())


def transcript_signals(transcript_path, limit=180):
    """(title, prompt) for a session that has no usable name yet.

    Claude Code writes its own `ai-title` and `last-prompt` records into the
    transcript, so read those instead of trawling user messages (most of which
    are tool results). Only the tail is read, to stay fast on long sessions.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return "", ""

    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as f:
            f.seek(max(0, size - 200_000))
            tail = f.read().decode("utf-8", "ignore")
    except Exception:
        return "", ""

    title, prompt = "", ""
    for line in reversed(tail.splitlines()):
        try:
            entry = json.loads(line)
        except Exception:
            continue

        kind = entry.get("type")
        if kind == "ai-title" and not title:
            title = (entry.get("aiTitle") or "").strip()
        elif kind == "last-prompt" and not prompt:
            prompt = clean_prompt(entry.get("lastPrompt") or "")[:limit]

        if title and prompt:
            break

    return title, prompt


payload = load(PAYLOAD)
session_id = payload.get("session_id") or ""
meta = session_meta(session_id)

cwd = payload.get("cwd") or meta.get("cwd") or ""
folder = os.path.basename(cwd.rstrip("/")) if cwd else "claude"

# Name priority:
#   1. the session's name (your /rename, or the title Claude auto-generated)
#   2. the transcript's ai-title, if the session record hasn't caught up yet
#   3. the project folder
# "derived" is the placeholder state (e.g. "matthewpark-59") before any naming.
name = meta.get("name") or ""
named = bool(name) and meta.get("nameSource") != "derived"

title, prompt = ("", "") if named else transcript_signals(payload.get("transcript_path", ""))

session = name if named else (title or folder)
# Un-named session: say what it was actually working on.
hint = "" if named else prompt

event = {
    "ts": int(time.time()),
    "kind": KIND,
    "session": session,
    "session_id": session_id,
    "named": named,
    "hint": hint,
    "cwd": cwd,
    "tty": tty_for_pid(meta.get("pid")),
}

try:
    os.makedirs(INBOX_DIR, exist_ok=True)
    with open(INBOX, "a") as f:
        f.write(json.dumps(event) + "\n")
except Exception:
    pass
PY

exit 0
