from __future__ import annotations

from clientdeck.ps1 import (
    ANSI_16,
    DEFAULT_PS1,
    HINTS,
    NEON_PS1,
    PRESETS,
    PromptContext,
    expand_prompt,
    render_ps1_html,
    render_session_html,
    render_title,
    terminal_runs,
)

CTX = PromptContext(username="acme", hostname="box", full_hostname="box.lan", cwd="~/work")


def visible(ps1: str, ctx: PromptContext = CTX) -> str:
    return "".join(text for text, _ in terminal_runs(expand_prompt(ps1, ctx)))


def test_default_prompt_visible_text():
    assert visible(DEFAULT_PS1) == "acme@box:~/work$"


def test_neon_prompt_visible_text():
    assert visible(NEON_PS1) == "acme@box:~/work$"


def test_presets_are_named_and_ordered():
    assert [name for name, _ in PRESETS] == ["Default", "Neon"]


def test_root_gets_hash():
    assert visible(r"\u\$", PromptContext(username="root")) == "root#"


def test_basic_escapes():
    assert visible(r"\H \W \s \n\\") == "box.lan work bash \n\\"


def test_octal_and_e_are_escape_char():
    assert expand_prompt(r"\033[0m\e", CTX) == "\x1b[0m\x1b"


def test_brackets_are_dropped():
    assert expand_prompt(r"\[x\]", CTX) == "x"


def test_unset_parameter_alternate_value_is_empty():
    assert visible(r"${debian_chroot:+($debian_chroot)}x") == "x"


def test_set_parameter_alternate_value_expands():
    ctx = PromptContext(variables={"debian_chroot": "jail"})
    assert visible(r"${debian_chroot:+($debian_chroot)}x", ctx) == "(jail)x"


def test_escaped_dollar_is_not_parameter_expansion():
    assert visible(r"\$HOME") == "$HOME"


def test_window_title_osc_is_invisible():
    assert visible(r"\[\e]0;\u@\h: \w\a\]X") == "X"


def test_sgr_bold_green_then_reset():
    runs = terminal_runs(expand_prompt(r"\[\033[01;32m\]a\[\033[00m\]b", CTX))
    (a_text, a_style), (b_text, b_style) = runs
    assert (a_text, a_style.fg, a_style.bold) == ("a", ANSI_16[2], True)
    assert (b_text, b_style.fg, b_style.bold) == ("b", None, False)


def test_256_color_cube_and_grayscale():
    (_, cyan), = terminal_runs("\x1b[38;5;051mx")
    (_, gray), = terminal_runs("\x1b[38;5;232mx")
    assert cyan.fg == "#00ffff"
    assert gray.fg == "#080808"


def test_truecolor_and_background():
    (_, st), = terminal_runs("\x1b[38;2;1;2;3;48;5;1mx")
    assert (st.fg, st.bg) == ("#010203", ANSI_16[1])


def test_html_uses_theme_independent_terminal_colors():
    dark = render_ps1_html("x", CTX, dark=True)
    light = render_ps1_html("x", CTX, dark=False)
    assert "color:#d0cfcc" in dark
    assert "color:#171421" in light


def test_html_escapes_and_preserves_spaces():
    out = render_ps1_html("<a> b", CTX, dark=True)
    assert "&lt;a&gt;&nbsp;b" in out


def test_reverse_video_swaps_colors():
    out = render_ps1_html(r"\[\033[7m\]x", CTX, dark=True)
    assert "color:#1e1e1e" in out and "background-color:#d0cfcc" in out


def test_every_hint_renders_without_error():
    for _, code, _ in HINTS:
        render_ps1_html(code, CTX, dark=True)


def test_hint_keywords_are_unique_lowercase_words():
    keywords = [k for k, _, _ in HINTS]
    assert len(keywords) == len(set(keywords))
    assert all(k.isalnum() and k == k.lower() for k in keywords)


def test_title_comes_from_the_prompts_osc():
    assert render_title(DEFAULT_PS1, CTX) == "acme@box: ~/work"


def test_title_falls_back_when_prompt_sets_none():
    assert render_title(r"\u\$", CTX) == "Terminal"


def test_session_has_command_output_and_cursor_line():
    out = render_session_html(DEFAULT_PS1, CTX, dark=True)
    assert out.count("acme@box") == 2
    assert out.count("<br>") == 2
    assert "projects" in out and "background-color:#d0cfcc" in out
