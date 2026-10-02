"""Bash PS1 preview: expands prompt escapes and renders the resulting
terminal output (ANSI colors/attributes) as Qt rich-text HTML.

Pure logic, no Qt — exposed to QML via app.py's `_Ps1Renderer`. See
docs/comments-details.md [130].
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass, field, replace

DEFAULT_PS1 = (
    r"\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}"
    r"\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$"
)
NEON_PS1 = (
    r"\[\e]0;\u@\h: \w\a\]\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}"
    r"\[\033[38;5;051m\]\u@\h\[\033[00m\]:\[\033[38;5;207m\]\w\[\033[00m\]\$"
)

# (name, PS1) — order is the order shown in the preset combo box.
PRESETS: list[tuple[str, str]] = [
    ("Default", DEFAULT_PS1),
    ("Neon", NEON_PS1),
]

# Colon hints for the PS1 field: (keyword typed after ":", PS1 code it
# expands to, description). See docs/comments-details.md [136].
HINTS: list[tuple[str, str, str]] = [
    ("user", r"\u", "Username"),
    ("hostname", r"\h", "Hostname, short"),
    ("fullhostname", r"\H", "Hostname, full"),
    ("cwd", r"\w", "Working directory"),
    ("basename", r"\W", "Working directory, last part"),
    ("prompt", r"\$", "$, or # for root"),
    ("time", r"\t", "Time, 24h HH:MM:SS"),
    ("time12", r"\T", "Time, 12h HH:MM:SS"),
    ("ampm", r"\@", "Time, 12h am/pm"),
    ("hhmm", r"\A", "Time, 24h HH:MM"),
    ("date", r"\d", "Date"),
    ("shell", r"\s", "Shell name"),
    ("version", r"\v", "Bash version"),
    ("jobs", r"\j", "Jobs count"),
    ("history", r"\!", "History number"),
    ("command", r"\#", "Command number"),
    ("newline", r"\n", "Newline"),
    ("title", r"\[\e]0;\u@\h: \w\a\]", "Window title: user@host: dir"),
    ("green", r"\[\033[01;32m\]", "Color: green, bold"),
    ("blue", r"\[\033[01;34m\]", "Color: blue, bold"),
    ("red", r"\[\033[01;31m\]", "Color: red, bold"),
    ("yellow", r"\[\033[01;33m\]", "Color: yellow, bold"),
    ("cyan", r"\[\033[36m\]", "Color: cyan"),
    ("magenta", r"\[\033[35m\]", "Color: magenta"),
    ("color256", r"\[\033[38;5;208m\]", "Color: 256-color (edit number)"),
    ("reset", r"\[\033[00m\]", "Color: reset"),
]

# GNOME Terminal's default 16-color palette.
ANSI_16 = [
    "#171421", "#c01c28", "#26a269", "#a2734c", "#12488b", "#a347ba", "#2aa1b3", "#d0cfcc",
    "#5e5c64", "#f66151", "#33da7a", "#e9ad0c", "#2a7bde", "#c061cb", "#33c7de", "#ffffff",
]

@dataclass(frozen=True)
class TerminalColors:
    """One simulated terminal window's chrome + default text colors."""

    background: str
    foreground: str
    title_bar: str
    title_text: str
    border: str


# Approximates GNOME Terminal's dark/light Adwaita look.
DARK_TERMINAL = TerminalColors("#1e1e1e", "#d0cfcc", "#303030", "#e6e6e6", "#0f0f0f")
LIGHT_TERMINAL = TerminalColors("#ffffff", "#171421", "#ebebeb", "#2e2e2e", "#c8c8c8")

FALLBACK_TITLE = "Terminal"
# Sample earlier command + output shown above the live prompt — see [134].
SAMPLE_COMMAND = "ls"
SAMPLE_OUTPUT = "\x1b[01;34mprojects\x1b[0m  notes.txt  \x1b[01;34mscripts\x1b[0m"


@dataclass(frozen=True)
class PromptContext:
    """Sample values substituted for prompt escapes in the preview."""

    username: str = "user"
    hostname: str = "hostname"
    full_hostname: str = "hostname.local"
    cwd: str = "~/work"
    time_24: str = "14:05:09"
    time_12: str = "02:05:09"
    time_ampm: str = "02:05 PM"
    time_hm: str = "14:05"
    date: str = "Thu Oct 02"
    shell: str = "bash"
    version: str = "5.2"
    version_full: str = "5.2.21"
    tty: str = "pts/0"
    jobs: str = "0"
    history: str = "1"
    command: str = "1"
    variables: dict[str, str] = field(default_factory=dict)

    @property
    def cwd_basename(self) -> str:
        if self.cwd in ("~", "/"):
            return self.cwd
        return self.cwd.rstrip("/").rsplit("/", 1)[-1]


_PARAM_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:?[-+=?])(.*?))?\}|\$([A-Za-z_][A-Za-z0-9_]*)")


def _expand_parameters(text: str, variables: dict[str, str]) -> str:
    """Bash-style `$name`/`${name}`/`${name:+word}`/`${name:-word}` on
    already-escape-expanded text; unset variables expand to "" — see [131]."""

    def sub(m: re.Match) -> str:
        name = m.group(1) or m.group(4)
        value = variables.get(name)
        op, word = m.group(2), m.group(3)
        if op is None:
            return value or ""
        is_set = bool(value) if op.startswith(":") else value is not None
        if op.endswith("+"):
            return _expand_parameters(word, variables) if is_set else ""
        if op.endswith("-") or op.endswith("="):
            return value if is_set else _expand_parameters(word, variables)
        return value or ""

    return _PARAM_RE.sub(sub, text)


def expand_prompt(ps1: str, ctx: PromptContext) -> str:
    """PS1 -> the raw character stream bash would write to the terminal."""
    simple = {
        "u": ctx.username, "h": ctx.hostname, "H": ctx.full_hostname,
        "w": ctx.cwd, "W": ctx.cwd_basename,
        "$": "#" if ctx.username == "root" else "$",
        "t": ctx.time_24, "T": ctx.time_12, "@": ctx.time_ampm, "A": ctx.time_hm,
        "d": ctx.date, "s": ctx.shell, "v": ctx.version, "V": ctx.version_full,
        "l": ctx.tty, "j": ctx.jobs, "!": ctx.history, "#": ctx.command,
        "n": "\n", "r": "\r", "a": "\a", "e": "\x1b", "\\": "\\",
        "[": "", "]": "",
    }
    out: list[str] = []
    i = 0
    while i < len(ps1):
        ch = ps1[i]
        if ch != "\\" or i + 1 >= len(ps1):
            out.append(ch)
            i += 1
            continue
        nxt = ps1[i + 1]
        if nxt in "01234567":
            m = re.match(r"[0-7]{1,3}", ps1[i + 1:])
            out.append(chr(int(m.group(0), 8)))
            i += 1 + len(m.group(0))
        elif nxt == "D" and ps1[i + 2:i + 3] == "{":
            end = ps1.find("}", i + 3)
            end = len(ps1) - 1 if end == -1 else end
            out.append(ctx.date)
            i = end + 1
        elif nxt in simple:
            # Protect a literal "$" from parameter expansion below.
            out.append("\x00" if nxt == "$" and simple[nxt] == "$" else simple[nxt])
            i += 2
        else:
            out.append(ch + nxt)
            i += 2
    return _expand_parameters("".join(out), ctx.variables).replace("\x00", "$")


@dataclass(frozen=True)
class _Style:
    fg: str | None = None
    bg: str | None = None
    bold: bool = False
    italic: bool = False
    underline: bool = False
    reverse: bool = False


def _color_256(n: int) -> str:
    if n < 16:
        return ANSI_16[n]
    if n < 232:
        n -= 16
        levels = (0, 95, 135, 175, 215, 255)
        r, g, b = levels[n // 36], levels[(n // 6) % 6], levels[n % 6]
        return f"#{r:02x}{g:02x}{b:02x}"
    v = 8 + (n - 232) * 10
    return f"#{v:02x}{v:02x}{v:02x}"


def _apply_sgr(style: _Style, params: str) -> _Style:
    codes = [int(p) if p.isdigit() else 0 for p in params.split(";")] if params else [0]
    i = 0
    while i < len(codes):
        c = codes[i]
        if c == 0:
            style = _Style()
        elif c == 1:
            style = replace(style, bold=True)
        elif c == 3:
            style = replace(style, italic=True)
        elif c == 4:
            style = replace(style, underline=True)
        elif c == 7:
            style = replace(style, reverse=True)
        elif c == 22:
            style = replace(style, bold=False)
        elif c == 23:
            style = replace(style, italic=False)
        elif c == 24:
            style = replace(style, underline=False)
        elif c == 27:
            style = replace(style, reverse=False)
        elif 30 <= c <= 37:
            style = replace(style, fg=ANSI_16[c - 30])
        elif 90 <= c <= 97:
            style = replace(style, fg=ANSI_16[c - 90 + 8])
        elif 40 <= c <= 47:
            style = replace(style, bg=ANSI_16[c - 40])
        elif 100 <= c <= 107:
            style = replace(style, bg=ANSI_16[c - 100 + 8])
        elif c == 39:
            style = replace(style, fg=None)
        elif c == 49:
            style = replace(style, bg=None)
        elif c in (38, 48) and i + 1 < len(codes):
            color = None
            if codes[i + 1] == 5 and i + 2 < len(codes):
                color = _color_256(max(0, min(255, codes[i + 2])))
                i += 2
            elif codes[i + 1] == 2 and i + 4 < len(codes):
                r, g, b = (max(0, min(255, v)) for v in codes[i + 2:i + 5])
                color = f"#{r:02x}{g:02x}{b:02x}"
                i += 4
            if color is not None:
                style = replace(style, fg=color) if c == 38 else replace(style, bg=color)
        i += 1
    return style


_CSI_RE = re.compile(r"\x1b\[([0-9;?]*)([@-~])")
_OSC_RE = re.compile(r"\x1b\].*?(?:\x07|\x1b\\|$)", re.DOTALL)


def terminal_runs(stream: str) -> list[tuple[str, _Style]]:
    """Interpret a terminal character stream into (visible text, style)
    runs. OSC sequences (e.g. window title) are invisible — see [132]."""
    runs: list[tuple[str, _Style]] = []
    style = _Style()
    i = 0
    buf: list[str] = []

    def flush() -> None:
        if buf:
            runs.append(("".join(buf), style))
            buf.clear()

    while i < len(stream):
        ch = stream[i]
        if ch == "\x1b":
            m = _OSC_RE.match(stream, i)
            if m:
                i = m.end()
                continue
            m = _CSI_RE.match(stream, i)
            if m:
                if m.group(2) == "m":
                    flush()
                    style = _apply_sgr(style, m.group(1))
                i = m.end()
                continue
            i += 2  # Other two-char escape: ignore.
            continue
        if ch in "\a\r\x00":
            i += 1
            continue
        buf.append(ch)
        i += 1
    flush()
    return runs


_TITLE_RE = re.compile(r"\x1b\][02];(.*?)(?:\x07|\x1b\\)", re.DOTALL)


def window_title(stream: str) -> str | None:
    """Last window title set via OSC 0/2 in a terminal stream, if any."""
    titles = _TITLE_RE.findall(stream)
    return titles[-1] if titles else None


def runs_to_html(runs: list[tuple[str, _Style]], background: str, foreground: str) -> str:
    parts: list[str] = []
    for text, st in runs:
        fg = st.fg or foreground
        bg = st.bg
        if st.reverse:
            fg, bg = (st.bg or background), (st.fg or foreground)
        css = [f"color:{fg}"]
        if bg:
            css.append(f"background-color:{bg}")
        if st.bold:
            css.append("font-weight:bold")
        if st.italic:
            css.append("font-style:italic")
        if st.underline:
            css.append("text-decoration:underline")
        body = html.escape(text).replace(" ", "&nbsp;").replace("\n", "<br>")
        parts.append(f'<span style="{";".join(css)}">{body}</span>')
    return "".join(parts)


def render_ps1_html(ps1: str, ctx: PromptContext, dark: bool) -> str:
    """PS1 -> HTML for the prompt alone, in a dark or light terminal."""
    colors = DARK_TERMINAL if dark else LIGHT_TERMINAL
    return runs_to_html(terminal_runs(expand_prompt(ps1, ctx)), colors.background, colors.foreground)


def render_session_html(ps1: str, ctx: PromptContext, dark: bool) -> str:
    """A short simulated session: prompt + sample command, its output, then
    the prompt again with a block cursor — see [134]."""
    colors = DARK_TERMINAL if dark else LIGHT_TERMINAL
    prompt = render_ps1_html(ps1, ctx, dark)
    plain = lambda text: runs_to_html([(text, _Style())], colors.background, colors.foreground)
    output = runs_to_html(terminal_runs(SAMPLE_OUTPUT), colors.background, colors.foreground)
    cursor = f'<span style="background-color:{colors.foreground}">&nbsp;</span>'
    return f"{prompt}{plain(SAMPLE_COMMAND)}<br>{output}<br>{prompt}{cursor}"


def render_title(ps1: str, ctx: PromptContext) -> str:
    """Window title the prompt sets (e.g. `user@host: ~/work`), or a
    generic fallback when it sets none."""
    return window_title(expand_prompt(ps1, ctx)) or FALLBACK_TITLE
