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
    return redact(" ".join(text.split()))


# Anything matching these never reaches the inbox file or the screen. Session
# text can quote whatever you pasted into Claude, including credentials.
SECRET_PATTERNS = [
    r"sk-[A-Za-z0-9_\-]{16,}",                  # OpenAI / Anthropic style
    r"gh[pousr]_[A-Za-z0-9]{16,}",              # GitHub tokens
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"xox[abprs]-[A-Za-z0-9\-]{10,}",           # Slack
    r"AKIA[0-9A-Z]{16}",                        # AWS access key id
    r"AIza[0-9A-Za-z_\-]{30,}",                 # Google
    r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}",  # JWT
    r"-----BEGIN[^-]{0,40}PRIVATE KEY-----",
    r"(?i)\b(api[_-]?key|secret|password|passwd|token|bearer)\b\s*[:=]\s*\S+",
    r"[A-Za-z0-9+/]{40,}={0,2}",                # long opaque blobs
]


def redact(text):
    """Strip anything that looks like a credential."""
    for pattern in SECRET_PATTERNS:
        text = re.sub(pattern, "[redacted]", text)
    return text


def clean_markdown(text):
    """Flatten markdown to plain text a speech bubble can render."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # code fences
    text = re.sub(r"`([^`]*)`", r"\1", text)                # inline code
    text = re.sub(r"\*\*([^*]*)\*\*", r"\1", text)          # bold
    text = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)    # links
    text = re.sub(r"^#{1,6}\s*", "", text, flags=re.M)      # headings
    text = re.sub(r"<[^>]*>", " ", text)

    # Tables and rules don't survive as prose — drop them entirely.
    kept = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.count("|") >= 2:
            continue
        if re.fullmatch(r"[-=_*\s]{3,}", stripped):
            continue
        kept.append(line)
    return "\n".join(kept)


def summary_points(transcript_path, max_points=6, width=96):
    """Bullet points describing what the session just did.

    Derived from the last substantive assistant message: its own bullets if it
    wrote any, otherwise its opening sentences.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return []

    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as f:
            f.seek(max(0, size - 400_000))
            tail = f.read().decode("utf-8", "ignore")
    except Exception:
        return []

    def bullets_in(text):
        found = []
        for line in text.splitlines():
            stripped = line.strip()
            if re.match(r"^([-*•]|\d+[.)])\s+", stripped):
                point = re.sub(r"^([-*•]|\d+[.)])\s+", "", stripped).strip(" :—-")
                if len(point) > 6:
                    found.append(point)
        return found

    # Walk backwards over recent assistant turns and take the last one that
    # actually reports work — a short "on it" reply is not a summary.
    fallback = ""
    body, points = "", []
    checked = 0

    for line in reversed(tail.splitlines()):
        if checked >= 12:
            break
        try:
            entry = json.loads(line)
        except Exception:
            continue
        if entry.get("type") != "assistant":
            continue

        content = (entry.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue

        text = ""
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text += block.get("text", "") + "\n"

        text = re.split(r"(?im)^\s*\**ECC tips?\b", text.strip())[0]
        if len(text) < 60:
            continue
        checked += 1

        cleaned = clean_markdown(text)
        found = bullets_in(cleaned)
        if len(found) >= 2:
            body, points = cleaned, found
            break
        if not fallback and len(cleaned) >= 200:
            fallback = cleaned

    if not points:
        body = body or fallback
        if not body:
            return []
        # No bullets written — fall back to the opening sentences.
        flat = " ".join(body.split())
        points = [s.strip() for s in re.split(r"(?<=[.!?])\s+", flat) if len(s.strip()) > 12]

    trimmed = []
    for point in points[:max_points]:
        point = " ".join(point.split())
        if len(point) > width:
            point = point[: width - 1].rstrip() + "…"
        trimmed.append(redact(point))
    return trimmed


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
            title = redact((entry.get("aiTitle") or "").strip())
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
# "derived" is the placeholder state (e.g. "yourname-59") before any naming.
name = meta.get("name") or ""
named = bool(name) and meta.get("nameSource") != "derived"

title, prompt = ("", "") if named else transcript_signals(payload.get("transcript_path", ""))

session = redact(name if named else (title or folder))
# Un-named session: say what it was actually working on.
hint = "" if named else prompt

# What the session actually did — the pet shows as much of this as you ask for.
points = summary_points(payload.get("transcript_path", "")) if KIND == "done" else []

event = {
    "ts": int(time.time()),
    "kind": KIND,
    "session": session,
    "session_id": session_id,
    "named": named,
    "hint": hint,
    "points": points,
    "cwd": cwd,
    "tty": tty_for_pid(meta.get("pid")),
}

try:
    os.makedirs(INBOX_DIR, mode=0o700, exist_ok=True)
    with open(INBOX, "a") as f:
        f.write(json.dumps(event) + "\n")
    os.chmod(INBOX, 0o600)
except Exception:
    pass
PY

exit 0
