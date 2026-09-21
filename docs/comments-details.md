# Comment details

Long, "why"-focused explanations that used to live inline in source comments
now live here instead, so the source only carries brief "what" comments.
Each entry has a reference number; a source comment that needs the backing
rationale points at it with `[N]`, e.g. `// Absolute import — see [N].`

This file must be kept in sync as code changes: when a marked comment's
code changes in a way that invalidates the explanation, update or remove
the matching entry here (and its `[N]` marker in the source). When adding a
new explanatory comment anywhere in the project, don't write it inline —
add an entry here and leave only a brief pointer in the code.

Entries are grouped by source file, in the order the files were processed.

---

## src/clientdeck/__main__.py

### [1] Why an absolute import instead of `from .app import main`

This file is also Nuitka's compiled entry point (see `build.sh`/the
packaging blueprint), and Nuitka compiles it as a bare top-level
`__main__` module with no parent package — a relative import there fails
with "attempted relative import with no known parent package" (confirmed
by actually building and running the packaged binary). An absolute import
resolves the same way in both source and packaged mode, since `clientdeck`
is always pip/uv-installed.

## src/clientdeck/app.py

### [2] Test-coverage caveat for this module

This module isn't covered by the pytest suite — it needs a real Qt GUI
platform, which the agent's sandbox can't provide for an actual window
(see CLAUDE.md's "Environment constraints"). It *has* been smoke-tested
headlessly with `QT_QPA_PLATFORM=offscreen` (Qt's no-display platform
plugin — doesn't pop a window, so it doesn't violate that constraint),
which is how the QML module-import bug and the packaged-build asset-path
bugs documented in build.sh/paths.py were actually caught and fixed, rather
than just written to spec and hoped for. Still needs manual, on-host
verification for anything that plugin can't exercise: real visual
rendering/theme appearance, window-manager interaction (drag, monitor
placement/restore across a real multi-monitor setup), and the
`su`/`xhost`/`pkexec` launch flows.

### [3] `_ClientProvisioner` design notes

Runs synchronously (blocks on the pkexec auth dialog) — acceptable for
an infrequent "add client" action; not attempted asynchronously here to
avoid the added complexity of a QML-visible pending state for something
this rare.

While the app is in UI/UX-prototyping phase, `create_user.py`'s own
MOCK_MODE means this still runs the real pkexec authentication flow but
does not actually create a Linux user — see that script's module
docstring. The same MOCK_MODE caveat applies to `deleteLinuxUser` below.

### [4] Why `pkexec <script>` invokes the script by its own shebang

Not via `sys.executable` — in a packaged build `sys.executable` is the
compiled ClientDeck binary itself, not a Python interpreter. Applies
equally to `_spawn_launch_script`'s invocation of `launch_as_user.py`.

### [5] `_AppLauncher` design notes

Every app a client has is added via the "add app" dialog — there are no
hardcoded/builtin apps (a terminal, an editor, etc. are just apps like any
other, added the same way). While the app is in UI/UX-prototyping phase,
`launch_as_user.py`'s own MOCK_MODE means no `su`/`xhost`/actual app
process happens — see that script's module docstring.

### [6] Why `run()` installs a repeating QTimer alongside the SIGINT handler

Qt's C++ event loop never yields back to the Python interpreter on its
own, so a bare `signal.signal(SIGINT, ...)` handler installed here would
never actually run — Ctrl+C in a terminal would do nothing until/unless
something else caused Python to regain control. A trivial repeating
QTimer forces that handoff regularly, so the handler (which triggers the
normal `app.quit()` shutdown path, saving window state via `aboutToQuit`
like any other quit) actually fires.

Source mode only (`run.sh` / `uv run python -m clientdeck`): confirmed
working there, but the packaged onefile binary is actually two processes
(a bootstrap plus the extracted payload it execs) and SIGINT delivered to
that process group does not reach this handler the same way — see
CHANGELOG.md. Rather than install something known not to behave correctly
there, it's skipped entirely for a packaged build.

### [7] `theme_icon_provider` registration

Makes `image://theme/<name>` resolve via the desktop's actual icon theme
(see icon_provider.py) — AddAppDialog.qml uses this for discovered
`.desktop` apps whose `Icon=` is a theme name rather than an absolute
path, which is the common case. `addImageProvider()` transfers ownership
to the engine (per Qt docs), but it's named here rather than passed as a
bare temporary anyway, matching the context-property object-pinning
practice in [8] below (a different, real gotcha, but the same defensive
habit).

### [8] Why context-property QObjects are pinned on `engine._retained_context_objects`

A QObject handed to `setContextProperty()` is only *referenced* by the
QML side, not Python-refcounted through it, so without an explicit
long-lived Python reference it can be garbage-collected out from under a
live QML binding — intermittently, since it depends on GC timing. This is
a well-known PySide6/PyQt gotcha; observed here as an occasional (roughly
1-in-5 runs) "TypeError: Cannot read property 'count' of null" for
`clientModel` in Main.qml, on an otherwise-unchanged QML file with no
edits between a clean run and a failing one.

### [9] Why no `addImportPath()` call before loading Main.qml

Main.qml and the qmldir declaring the "ClientDeck" module live in the
same directory, so Qt's automatic local-directory import already gives
every file there access to it (confirmed the hard way — an explicit
`import ClientDeck 1.0` in the QML files resolved to "module ClientDeck
is not installed", since that path-based module lookup expects a
directory literally named ClientDeck/, not one that merely declares that
module name).

### [10] Backdrop blur is best-effort and X11-only

Real backdrop blur (vs. the plain alpha-transparency Main.qml/Theme.qml
already do) is compositor-specific and X11-only here — see compositor.py.
Silently a no-op anywhere it doesn't apply (Wayland, GNOME/Mutter, a WM
that isn't KWin, no Xlib, ...).

## src/clientdeck/compositor.py

### [11] Why real backdrop blur is KWin/X11-only, and how detection works

Making the desktop *behind* a translucent window actually blurry (not
just alpha-transparent, which is all plain QML/Qt Quick can do on its
own) is a compositor-specific window-manager hint — there is no
cross-desktop Qt/QML API for it:

- KWin (KDE Plasma, X11) supports it directly via a documented X11
  property, `_KDE_NET_WM_BLUR_BEHIND_REGION`, set on the app's own window.
- Mutter (GNOME) has no equivalent per-app hint at all — real blur there
  would need a GNOME Shell extension (a desktop-level install, not
  something this app can do from inside itself), so the existing
  alpha-transparency-only glass look is the best available fallback.
- Wayland KWin uses a completely different mechanism (the
  `org_kde_kwin_blur` Wayland protocol extension) — not implemented here;
  everything in this module is X11-only (guard with
  `QGuiApplication.platformName() == "xcb"` before calling in).

Detection queries the *actually running* window manager via the
ICCCM/EWMH-standard `_NET_SUPPORTING_WM_CHECK` mechanism (something any
compliant X11 WM must implement to identify itself), rather than trusting
environment variables like `XDG_CURRENT_DESKTOP` — those describe the
logged-in session, which can be stale, absent, or simply wrong about what's
actually compositing right now.

Everything here is best-effort: any failure (no X11, `Xlib` unavailable, a
WM that doesn't implement EWMH, a property-set that fails) just means
detection/blur silently does nothing — never raises, never blocks
startup. See CLAUDE.md's environment constraints: none of this is
verifiable by the agent (no real X server/compositor in the sandbox), so
it's written to be safe to call blind and needs manual, on-host
verification against a real KWin session.

## src/clientdeck/config.py

### [12] Why `update_client` mutates in place rather than remove+re-add

Edits an existing client's fields in place — including, possibly, its
username, which is otherwise this store's lookup key everywhere else.
Mutating the same `ClientEntry` (rather than remove+re-add) keeps its
`apps` list attached across a rename.

### [13] Why `move_app` treats out-of-range indices as a no-op

Reorders one client's apps — used by drag-and-drop reordering in
ClientRow.qml. Both endpoints (including moving to the very first or very
last position) are valid; out-of-range indices are a no-op rather than an
error, since this is driven by live UI state that could in principle race
with a concurrent removal.

## src/clientdeck/desktop_apps.py

### [14] Why a missing `Type=` is rejected rather than defaulted

`Type=` is a required key per the Desktop Entry Specification — no
lenient default for a missing one. A previous version defaulted a missing
`Type` to "Application", which admitted malformed/non-standard entries a
strict reading of the spec would reject.

## src/clientdeck/icon_provider.py

### [15] Why this module exists and how it was debugged into its current shape

Qt does not register a "theme" image provider automatically for a plain
`QGuiApplication` + `QQmlApplicationEngine` app — confirmed missing on a
real host: Qt logged `Invalid image provider: image://theme/<name>` for
every discovered `.desktop` app whose `Icon=` value was a theme name
rather than an absolute path (which is the common case; see
`desktop_apps.py`). `QIcon.fromTheme()` implements the freedesktop icon
theme spec on Linux and works fine under `QGuiApplication` — it needs no
widgets — so a small `QQuickImageProvider` wrapping it is enough to make
`image://theme/<name>` resolve, once the provider itself is registered.

That alone wasn't sufficient, though: `QIcon.themeSearchPaths()` defaults
to just `[":/icons"]` (a Qt *resource* path, always empty for an app that
doesn't bundle icons into a .qrc) — real filesystem directories like
`/usr/share/icons` are only added by Qt's own platform-theme integration,
which isn't guaranteed to run (confirmed empty under the `offscreen` QPA
platform used for this project's own headless testing, and not something
to assume works for every real desktop session either).
`ensure_icon_theme_configured()` adds the standard XDG icon directories
unconditionally, and falls back to the universal "hicolor" theme name
only if nothing was already detected — confirmed this combination
resolves real icon names (including the exact ones reported missing:
"gsmartcontrol", "gwenview", "granatier") that otherwise came back null.

One further gap confirmed by that same testing: some apps (e.g. "gummi")
only ship an icon in `/usr/share/pixmaps/<name>.<ext>` — the legacy
freedesktop fallback location, outside the theme-directory hierarchy
entirely — and `QIcon.fromTheme()` does not check it.
`resolve_theme_pixmap()` falls back to it directly when the theme lookup
comes back empty.

## src/clientdeck/paths.py

### [16] What breaks between source and packaged builds, and how bundling works

See `claude-blocks/python-single-app-instance.claude.md`'s "Gotchas": a
path built relative to `__file__`/the original repo layout is correct
when running from source, but breaks once packaged (Nuitka onefile
self-extracts to a temp directory with a different layout). This module
is the one place that distinction lives, so the rest of the app never has
to think about it.

Actual bundling (see `build.sh` / `pysidedeploy.spec`):
- `qml/` is auto-bundled by `pyside6-deploy` as a data dir sitting right
  next to the compiled binary's extraction root, i.e. `<root>/qml`.
- `src/scripts/` is *not* auto-detected (it's a sibling of the package,
  not a subdirectory of it), so `build.sh` bundles it explicitly via
  Nuitka's `--include-data-dir`, landing at `<root>/scripts`.
- `clientdeck-loader` (the compiled splash binary — see `src/loader/`) is
  a single file, not a directory, so it's bundled via Nuitka's
  `--include-data-files` instead, landing at `<root>/clientdeck-loader`.
  `build.sh` builds it (via `make -C src/loader`) before bundling it.

### [17] Why `is_packaged_build()` matters beyond path resolution

`app.py` only installs its Ctrl+C/SIGINT handler in source mode, since
it's not confirmed to work correctly against the packaged binary's
two-process (bootstrap + extracted payload) structure yet.

### [18] How `get_packaged_root_dir()` finds the onefile extraction directory

Nuitka onefile injects `__nuitka_binary_dir` into `builtins` at runtime
(see the packaging blueprint) pointing at that directory; falls back to
the running executable's own directory if that hint isn't present.

## src/scripts/create_user.py, delete_user.py, launch_as_user.py

### [19] MOCK_MODE

The app is currently in UI/UX-prototyping phase, so these three scripts
don't perform their real privileged action (`useradd`/`userdel`/`su`+
`xhost`) — they still require root, so the real pkexec authentication
dialog can be exercised end-to-end, but the actual mutating command is
replaced with a printed line saying what would have run. Flip `MOCK_MODE`
to `False` in each script once prototyping is done and the real action
should happen.

## tools/check_versions.py

### [20] Purpose and scope of this script

Fails loudly on version drift before a build, per the packaging
blueprint's Step 2 (`claude-blocks/python-single-app-instance.claude.md`):
`pyproject.toml`'s `[project].version` and `clientdeck.__version__` must
always agree — a packaged binary that misreports its own version is a
real, easy-to-miss bug class.

Not part of the `clientdeck` package itself (it's a build-time-only
concern, kept out of what actually gets shipped) — invoked directly by
`build.sh`. On success, prints the version to stdout so the caller can
capture it for naming the output binary.

## build.sh

### [21] What this script implements and why it's one-time setup

Implements `claude-blocks/python-single-app-instance.claude.md` for this
project: a PySide6/Qt GUI app, built via `pyside6-deploy` (which drives
Nuitka's `--onefile` mode under the hood). Run with zero arguments; output
lands at `dist/clientdeck-<version>` (no extension, chmod +x).

This is a one-time-setup script per CLAUDE.md's "Deployment / packaging"
section: once it works, extend it for new needs (e.g. a new bundled asset
directory) rather than regenerating it from the blueprint from scratch.

### [22] Why `src/scripts/` is bundled via `--include-raw-dir`, not `--include-data-dir`

`src/scripts/` is a sibling of `src/clientdeck/`, not a subdirectory of
it, so `pyside6-deploy`'s own auto-bundling (which only picks up
subdirectories next to the entry point, e.g. `qml/`) never sees it — it
must be added explicitly, or `app.paths.get_scripts_dir()` finds nothing
once packaged.

Nuitka's `--include-data-dir` silently *excludes* `.py` files by default
(it treats them as source, not data) and `src/scripts/` contains only
`.py` files — confirmed by actually building with `--include-data-dir`
first: Nuitka logged "No data files in directory '.../src/scripts'" and
the scripts were silently left out entirely. `--include-raw-dir` bundles
the directory's contents verbatim.

## src/clientdeck/qml/Theme.qml

### [23] Why theme tokens are centralized here as bindings on `isDark`

Central definition of the app's dark/light glass theme (colors, corner
radius, motion timing) — per CLAUDE.md, kept centralized rather than
hardcoded per-component so the "consistent dark theme" requirement (now
"consistent theme" for either mode) is enforceable in one place.

Every color below is a *binding* on `isDark`, not a literal — flipping
`Theme.isDark` (e.g. from the main window's theme-toggle button) makes
every component using these tokens repaint reactively, with no other
code needing to know a theme switch happened.

### [24] Why light-mode `surface` isn't pure white

A soft off-white rather than literal pure white ("#ffffff" read as too
stark/full-white against the rest of the theme's muted tones).

### [25] `surfaceHover` is solid, not translucent

Solid (not translucent) hover step up from `surface` — for things like
SquareIconButton, which must stay fully opaque in every state rather than
fading with the background's own hover-driven opacity.

### [26] Why `glassPanel` is split into base color + two alpha levels

Translucent panel fill for the main window (which is itself a
transparent, borderless surface) and other glass-styled overlays like
ThemedTooltip — distinct from `surfaceGlass`, which is meant for subtle
highlights on top of an already-opaque surface.

Split into base RGB + two alpha levels (rather than one fixed
`glassPanel` color) so the main window can animate its own panel between
them on hover (see Main.qml) without needing its own copy of the base
color, and without that hover state leaking into other glassPanel users
like ThemedTooltip, which always render at the resting alpha.

### [27] What `glassPanelBottomRatio` is for

The main window's panel fades top-to-bottom (linear, top more opaque)
rather than one flat alpha — this is the bottom edge's alpha as a
fraction of whatever the top's current alpha is (resting or hovered), so
the same ratio applies in both states without needing separate top/bottom
tokens per state. Easy single knob to retune (or drop entirely) if the
linear gradient doesn't read well.

### [28] Why `dangerHover` follows the same direction as `surfaceHover`

Hover step for a `danger`-colored surface (the armed-for-delete button)
— same "push further from the background" direction as
surface/surfaceHover: lighter in dark mode, darker/more saturated in
light mode, so hovering the trash-bin button gives feedback just like
every other button state does.

### [29] The UI zoom scale factor

A single scale factor everything size-related is derived from, so "zoom
in/out" (the bottom-left +/- buttons and Ctrl+/Ctrl-) scales fonts,
button sizes, spacing, and corner radius all together, keeping the whole
layout proportionally identical, just bigger or smaller — see Main.qml
for the buttons/shortcuts and the window-growth behavior that goes with
this.

### [30] Why sizes are centralized as reusable scaled tokens

So every component that needs one of these shares the same scaling
rather than each hardcoding its own `* Theme.uiScale` (and risking
missing one on a future edit).

### [31] `iconMargin`'s role in SquareIconButton's icon sizing

SquareIconButton's own icon image now fills the button minus this margin
on every side (was a small fixed-size icon centered in a much bigger
button) — scales with zoom like every other size here.

## src/clientdeck/qml/DeleteArmState.qml

### [32] Why a global singleton tracks the armed button

Tracks which single app button (if any) is currently showing its
delete/trash-bin affordance, app-wide. Only one button may be "armed" for
delete at a time; individual SquareIconButton instances don't otherwise
know about each other, so this is the shared place that lets arming one
implicitly disarm a previously-armed different one, and lets a global
cancel (clicking empty background, pressing Escape) reach whichever
button is currently armed without the caller needing a reference to it.

## src/clientdeck/qml/ThemedButton.qml

### [33] Why this wraps `Button` instead of styling it via palette

A plain `QtQuick.Controls.Basic` `Button` never adapts to `Theme.isDark`
on its own (it has its own hardcoded default background/text colors,
independent of this app's theme entirely); confirmed the hard way as the
"button is dark on light theme" / "buttons are dark in light theme"
reports across every dialog that used a bare `Button`. Fully owns its own
background/contentItem (same approach as ValidatedTextField/
SquareIconButton) rather than trying to coax the right look out of
Controls Basic's palette, so every dialog's Cancel/Add/Apply/Browse/etc.
button reuses this instead of a bare `Button`.

## src/clientdeck/qml/ThemedTooltip.qml

### [34] Purpose

Generic, reusable themed tooltip — a small glass panel showing a title
and optional description, meant to replace the default OS/Basic-style
tooltip anywhere hover info is needed (not just the client logo), per
CLAUDE.md's "consistent dark theme" requirement.

### [35] Why it doesn't behave like a normal `Popup`

Positioned by the caller (via `parent` + x/y), shown/hidden purely by
binding `visible` to a HoverHandler — never grabs focus or participates
in click-to-dismiss like a real Popup normally would.

## src/clientdeck/qml/ValidatedTextField.qml

### [36] Why this exists as a generic component

Generic, reusable "live-validated input with themed error state". Per
CLAUDE.md this pattern must not be special-cased to the username field on
the add-client dialog — any field needing live validity feedback should
reuse this component with its own `validator`/`errorText`.

## src/clientdeck/qml/ThemedSearchField.qml

### [37] Why it's `ThemedSearchField`, not `SearchField`

Qt 6.7+'s QtQuick.Controls styles (Basic included) already ship their own
built-in `SearchField` type, and since callers of this component
explicitly `import QtQuick.Controls.Basic`, that explicit import wins any
name collision against this file's implicit same-directory availability
— using the same name silently resolved to Qt's own `SearchField`
instead of this one, which only surfaced as "Cannot assign to
non-existent property hintText" (confirmed by loading this file in
isolation, where it worked fine, versus by name from another file in the
same directory, where it didn't).

### [38] Why the icon/hint visibility isn't just `placeholderText`

Deliberately not the standard `placeholderText` behavior (which stays
visible whenever the field is empty, focused or not) — here the icon and
hint disappear the moment the field gains focus, even if nothing's been
typed yet, and only reappear once focus is lost and it's still empty.
Built once here rather than special-cased in the "add app" dialog's
search box, so any other search/filter field can reuse it.

### [39] Why `_iconReserve` padding is always reserved

Reserve room for the icon+hint at the left, in every state, so typed
text lines up in the same place whether the hint is showing or not
(rather than text jumping left the instant it disappears).

## src/clientdeck/qml/AddClientDialog.qml

### [40] Why this is a real top-level `Window`, with `flags` matching Main.qml exactly

A real top-level Window, not a Popup: `popupType: Popup.Window` (tried
first) still creates a window carrying the Qt::Popup window flag under
the hood, which window managers deliberately exempt from normal window
management — no drag-to-move via the mouse-down+Meta convention this
whole app otherwise relies on for its own frameless main window
(confirmed the hard way — it did create a genuinely separate QWindow,
just not a *movable* one).

`flags` must match Main.qml's own window flags exactly
(`Qt.FramelessWindowHint | Qt.Window`) — an earlier attempt used
`Qt.Dialog | Qt.FramelessWindowHint` instead, which still wasn't
independently movable: `Qt.Dialog` carries WM-specific semantics (many
window managers, including Mutter, can bundle a transient
`Qt::Dialog`-flagged window with its `transientParent` for move
operations, moving the parent instead of — or together with — the
dialog). Using the exact same base window type as the main window, which
is already confirmed movable, sidesteps that distinction rather than
guessing at which WM-specific quirk it triggers.

`ConfirmDialog.qml` and `EditClientDialog.qml` follow this same reasoning.

### [41] Why dialog position is set once imperatively, not as a live binding

x/y are set once here, imperatively, rather than as a live binding on
`anchorWindow`/width/height — a binding kept recentering the dialog on
the main window every time `uiScale` changed while it was open
(width/height are themselves `uiScale`-derived, so zooming re-evaluated
the centering expression too), overriding wherever the user had actually
dragged the dialog to. Size still legitimately follows zoom via the
width/height bindings; position, once set, is left alone until the
dialog is reopened.

`ConfirmDialog.qml` does the same for the same reason.

### [42] Why the logo row height is set via a Theme token, and as both `preferredHeight` and `minimumHeight`

`Theme.smallIconButtonSize * 2`, not `browseButton.height * 2`: a
`Layout.preferredHeight` binding that reads a *sibling's* live `.height`
(itself Layout-computed) turned out to be unreliable on the very first
layout pass — confirmed via headless testing, where this row measured
correctly (twice the button's height) in isolation but silently came out
equal to the button's own height whenever the main window had other
content (a client row) competing for the same initial layout pass.
Basing it on the same Theme token ThemedButton's own height already
derives from sidesteps that class of timing issue entirely — no runtime
geometry read involved.

Also set as `minimumHeight`, not just `preferredHeight`: even with the
above fix, this row's rendered height still came out equal to just the
button's height (not double) specifically when the dialog was opened via
a simulated click through SquareIconButton's full press/release gesture
chain in headless (`QT_QPA_PLATFORM=offscreen`) testing — traced as far
as the *window's own contentItem* reporting a stale 0×0 size in that
exact scenario despite `Window.height` itself already holding the
correct value, i.e. a window/scene-graph geometry sync gap below the QML
layer, not something fixable from here by changing what any single
binding reads (anchor restructuring, an explicit `Binding`, and
`Qt.callLater`-deferred rebinds were all tried and made no difference).
Opening the same dialog via a direct `.open()` call or via
EditClientDialog's TapHandler-driven path both measured correctly, so
this may well be specific to the offscreen QPA platform's handling of
that exact event-delivery path rather than a real on-screen bug —
flagging for on-host visual confirmation rather than claiming certainty
either way. `preferredHeight` is a hint the layout can shrink below when
it believes space is insufficient; `minimumHeight` is a floor it cannot
violate regardless, which is a reasonable, low-cost safeguard against
this class of issue even though its root cause isn't fully pinned down.

(See also the memory note "Offscreen contentItem geometry quirk" — this
is the investigation that produced it.)

### [43] Why the client is only persisted after Linux-user creation succeeds

Creating the Linux user requires root (pkexec) — only persist the client
once that actually succeeded, so config never references a user that
doesn't exist. `EditClientDialog.qml` follows the same rule on rename:
the config update (and the "delete old content?" prompt) only happens
once the new user was actually created.

## src/clientdeck/qml/EditClientDialog.qml

### [44] Why `fieldLabelWidth` is a fixed constant

Shared left column width for every field row's label, so "Logo", "Name",
"Description", and "Username" line up and every input starts at the same
x — a plain constant rather than a computed max-of-implicitWidths, since
these four labels are fixed, known strings.

### [45] Why `openFor` exists instead of an `onOpened` reset

Called by Main.qml right before `open()` with the client's current
values — a plain function rather than `onOpened`-driven reset (like
AddClientDialog's) since there's no other way to get per-client data
into this shared dialog instance.

### [46] Why the header preview is bound to live field values

Bigger logo + bold client name, so it's obvious at a glance which client
this dialog is editing. Bound to the same live values the fields below
edit, rather than a static snapshot, so it previews the change as you
type/browse.

### [47] Logo row height quirk, EditClientDialog-specific addendum to [42]

Same underlying issue as AddClientDialog.qml (see [42]): a
`Layout.preferredHeight` binding reading a sibling's live `.height` is
unreliable on the first layout pass when the main window has other
content competing for it. Here there's an additional wrinkle: a
separate, related quirk (`contentColumn`'s own `anchors.fill`-derived
height reading stale/negative on that same first pass) meant
`preferredHeight` alone could still get shrunk below what was asked for
— hence `minimumHeight` is set here too, same reasoning as [42].

### [48] Why the "delete old content?" confirm is anchored to this dialog, not the main window

Centered on *this* dialog's own window, not the main window — now that
dialogs are real separate windows, this reads better as appearing
directly over the dialog that spawned it.

## src/clientdeck/qml/AddAppDialog.qml

### [49] Why a `ScrollView` wraps the discovered-apps `ListView`

So a scrollbar actually appears when the discovered-apps list overflows
the visible area — a plain `ListView` shows no scroll affordance at all
on its own, same fix already applied to the client list in Main.qml.

### [50] Why the `ItemDelegate` fully overrides its background/content

Full themed override rather than relying on Controls Basic's own default
background/icon/text colors, which don't adapt to `Theme.isDark` at all
— confirmed the hard way as "text of items in the list is not visible on
light theme" (the default text color read fine in dark mode but was
effectively invisible against a light `Theme.surface` background). Same
"fully own the rendering" approach as SquareIconButton/ValidatedTextField.
The manual-entry `CheckBox` below has the same problem and fix.

### [51] Why a missing/unresolvable app icon just shows nothing

Discovered `.desktop` apps' `Icon=` value is either an absolute path to
an image file, or an icon-theme name to resolve via the platform's icon
theme — "if exists" per the request: an empty/unresolvable one just
shows no icon rather than a broken-image placeholder.

### [52] Why the pick-existing view has its own Cancel button

The pick-existing view previously had no way to back out of the dialog
at all besides Escape/clicking outside — the manual-entry view already
has its own Cancel below.

### [53] Why manual apps get a free-text icon field

Only way to get an icon on a manually-added app (e.g. Docker, which
typically has no launchable .desktop entry to discover an icon from) —
an absolute image path or an icon-theme name, same as a discovered app's
`Icon=` value.

## src/clientdeck/qml/ClientRow.qml

### [54] Why double-click uses `TapHandler`, not `MouseArea`

Double-clicking the logo opens the "modify client" dialog — see
CLAUDE.md's "Modifying a client" section. `TapHandler` (not a
`MouseArea`) since the logo needs no other pointer behavior and a
passive handler coexists cleanly with the `HoverHandler` above, same
reasoning as SquareIconButton's own tooltip HoverHandler.

### [55] Why `appsContainer` is a plain `Item` + `Repeater`, not a `Row`

Reordering needs each button's on-screen slot to sometimes differ from
its actual data index (while a drag is in progress), which means
computing `x` by hand per delegate — a positioner like `Row` always
overrides that itself.

### [56] Why `appsContainer` is hidden entirely when there are no apps

`RowLayout` still reserves spacing on *both* sides of a child even when
its `implicitWidth` is 0 — so with zero apps, the "+" button ended up one
full `Theme.spacing` further right than a row's first app button sits
when apps do exist (confirmed visually: the "+" in an empty row was
misaligned with the first app button of a populated row). Hiding this
`Item` entirely when there's nothing to show removes it from the layout
altogether, matching `RowLayout`'s documented behavior for invisible
children.

### [57] Why `implicitWidth` is computed and reported manually

Reported to the outer `RowLayout` so it can size this child correctly —
a plain `Item`, unlike Row/Layout types, does not compute this from its
children on its own.

### [58] The drop-target placeholder

A themed, accent-tinted outline sitting in the slot the drag would
currently land in — "properly colored placeholder where the drop will
potentially land." Sits behind everything else (`z: -1`) and only while
a drag is actually happening.

### [59] Why the real button stays put and a separate ghost follows the cursor

The real button never follows the cursor itself — it stays put (just
faded via `ghosted`) at its own, possibly-shifted slot the whole time;
`dragGhost` is the separate, non-interactive copy that actually follows
the cursor. Deliberately not the same item: this button's own MouseArea
is what's holding the mouse grab for the entire drag, and changing
*this* item's geometry synchronously from within that very MouseArea's
own move handler turned out to silently drop the grab after 2-3 move
events (confirmed via instrumented headless testing — `MouseArea.canceled`
fired, not a scripting artifact). Keeping this item stationary sidesteps
that entirely, and matches CLAUDE.md's spec more literally besides ("a
small translucent *copy* ... following the cursor" — not the original
button itself).

### [60] How an app button's icon is resolved

`modelData.icon` (when present — see AddAppDialog.qml, which sets it
both for a picked `.desktop` app and, now, for a manually-entered one
too) is either an absolute image path or an icon-theme name; the latter
only resolves via the `image://theme/` provider (icon_provider.py), same
resolution AddAppDialog.qml's own list uses. Letters are only a fallback
for apps with no icon at all.

### [61] Why `onDragFinished` captures locals before calling `moveAppRequested`

Capture into locals and reset the shared drag state *before* the
`moveAppRequested()` call below, not after: that call round-trips into
Python and back (`clientModel.moveApp()` -> `dataChanged` -> `Repeater`
re-evaluates `model: root.apps`), which can destroy and recreate every
delegate *synchronously* — including this very one, mid-handler.
Anything referencing `appsContainer`/`appButton` written *after* that
call would then fail with "appsContainer is not defined", confirmed by
actually triggering it.

### [62] What `dragGhost` is

The small translucent copy of the dragged button that actually follows
the cursor (see [59] for why this has to be a separate, non-interactive
item rather than the real button moving itself). Purely visual — no
MouseArea, never the target of any input.

## src/clientdeck/qml/Main.qml

### [63] Why the window is transparent with an inner rounded panel

Transparent window + an inner rounded, borderless glass panel filling it
(below) — the four corners outside that panel stay transparent, which is
what makes the window itself read as a rounded shape rather than a
rectangle with rounded content inside a square frame.

### [64] How `minimumWidth`/`minimumHeight` are derived

The window's floor size — what it actually takes to show its content
without clipping anything, i.e. "content boundaries": the bottom
toolbar's natural width AND the widest currently-rendered client row's
natural width (whichever is bigger), plus the same margin the layout
uses on every other edge (`Theme.spacing * 2`, matching the
`ColumnLayout`'s `anchors.margins` below). `clientListColumn.implicitWidth`
is the real, reactive source for the client-row side of this — see [70]
for why a Repeater in a plain ColumnLayout is used there instead of a
virtualizing ListView, specifically so this number is accurate.
Recomputed reactively as `Theme.uiScale` (or the client list) changes
either side's natural size. Binding this to `Window.minimumWidth`/
`minimumHeight` does two things at once: the window manager won't let
the user shrink the window past it interactively, and (below) it's
exactly the threshold used to grow the window only when genuinely
needed.

### [65] Why the window grows (but never shrinks) when the minimum size changes

Zoom (`Theme.uiScale`/`zoomIn()`/`zoomOut()`) never shrinks the window
back down on its own, but zooming in can raise the floor above the
window's current size — grow only exactly enough to stay at or above
that floor, and only when actually needed (never when the window is
already comfortably bigger than the toolbar requires). This also makes
rapid zoom in/out/in/out never compound: each check is against the
window's *current* size, not a remembered ratio, so a full round trip
back to the same scale leaves the window untouched.

### [66] Why the zoom shortcuts use `Qt.ApplicationShortcut`

Not the default `Qt.WindowShortcut`: a modal Popup (AddClientDialog/
AddAppDialog) capturing focus otherwise stopped these from firing at all
while a dialog was open — the default window-scoped context apparently
doesn't count a focused Popup's content as "the window" for
shortcut-matching purposes.

### [67] What the background `MouseArea` is for

Catches clicks that land on empty background (not on any button) — the
other half of "user clicks elsewhere" alongside SquareIconButton's own
`onPressed`, which handles a click landing on a *different* button.
Declared first/beneath the real content below, so any actual button's
own MouseArea still gets first claim at its own coordinates; this only
ever sees clicks at points nothing else claimed.

### [68] How the hover-driven glass opacity works

Idle: the normal resting glass translucency. Hovered (mouse anywhere
over the app): fades toward opaque so content is easier to read while
actually using it, then back to the same resting translucency the
instant the mouse leaves — never fully opaque, just "closer to" it, per
the request. `topAlpha` carries that hover behavior; `bottomAlpha` is
always a fixed fraction of it (`Theme.glassPanelBottomRatio`), so the
top-vs-bottom contrast holds in both resting and hovered states, and
animating just `topAlpha` (via `Behavior`) smoothly co-animates
`bottomAlpha` too since it's a live binding on top of it.

### [69] The panel's top-to-bottom gradient

Linear top-to-bottom opacity fade — top more opaque than bottom, per the
request. Revisit (e.g. a radial fade, or non-linear stops) if a straight
linear slope doesn't read well.

### [70] Why the client list is a plain `ColumnLayout` + `Repeater`, not a virtualizing `ListView`

Only currently-instantiated delegates report a usable `implicitWidth`,
and a virtualized `ListView` doesn't keep off-screen rows instantiated —
its own `implicitWidth` also doesn't naturally reflect delegate content
at all. A Layout, by contrast, always correctly and reactively aggregates
its children's implicit sizes (that's the whole point of the Layout
system), which is exactly what `window.minimumWidth` (see [64]) needs to
actually respect content boundaries instead of guessing. Not
virtualizing is fine here: this is a small personal client list, not a
large dynamic dataset.

### [71] Why the bottom toolbar's button count matters elsewhere

Bottom-left theme toggle + zoom in/out/reset — always present regardless
of empty-state vs. populated list, since it's the last row. Exactly
these 4 buttons is what `window._toolbarButtonCount` (see [64]) assumes
for the minimum-size calculation — keep them in sync if this row's
button count ever changes.

### [72] Why "reset zoom" doesn't also reset window size

Resets the *scale* only — window size is never forced to a fixed value
here, for the same reason zoom itself never shrinks the window: this
just becomes a scale change like any other, so it goes through the exact
same `onMinimumWidthChanged`/`onMinimumHeightChanged` grow-only-if-needed
logic (see [65]) instead of overriding whatever size the user (or a
previous session) already had the window at.

## src/clientdeck/qml/SquareIconButton.qml

### [73] `tooltipText` default

Themed hover tooltip — describes the button's function, or (for a
per-client app button) the app's name. Empty by default so a caller that
forgets to set it just gets no tooltip rather than a blank one.

### [74] `tooltipAbove`

Most buttons have room to show the tooltip below them; the bottom
toolbar (theme/zoom/reset) sits at the very bottom edge of the
borderless window, so a tooltip below it would render past the window's
own edge and never be visible — those callers set this true.

### [75] `deletable`/`draggable` default off

Opt-in behaviors — off by default, so the many non-app uses of this
component (theme toggle, zoom +/-, "+" buttons, dialog buttons) are
unaffected. ClientRow.qml turns both on for actual app buttons.

### [76] `bigLabel`

Opt-in: makes the `label` glyph always fill 75% of the button's
width/height (via `fontSizeMode: Text.Fit`) instead of the fixed
`Theme.iconGlyphSize` used by every other label (client initials, theme
toggle, zoom +/-, reset) — set at call sites that want an oversized
glyph, e.g. the per-row "add app" +. `Text.Fit` scales the glyph up to
fill the 75%-of-button box exactly, however big/small the button ends up
(window resize, `Theme.uiScale` zoom, …) — a fixed `pixelSize` couldn't
guarantee "always 75%" across those.

### [77] `cancelsOtherArmedButton`

Whether pressing *this* button counts as "clicking elsewhere" for any
other button currently armed for delete — on by default, since that's
the whole point of the click-elsewhere-cancels rule. The theme toggle is
the one exception (set false at its call site in Main.qml): switching
dark/light is an incidental display preference, not an action on any
particular app, so it shouldn't silently cancel an in-progress delete
confirmation on some other button.

### [78] `clicked` signal semantics

Fires only for a plain press+release that never armed delete and never
turned into a drag — i.e. exactly the old single-signal behavior,
unchanged for every caller that doesn't opt into the deletable/draggable
behaviors.

### [79] `armedForDelete`

True once a `deletable` button has been held (pressed, not moved away)
through the full hold schedule (see [81]). Persists after the mouse is
released (showing the trash-bin icon indefinitely); a separate, later
click is what actually deletes — see [91].

### [80] `onArmedForDeleteChanged`

Keeps `DeleteArmState.armedButton` in sync so the rest of the app can
find (and cancel) whichever button is currently armed without a direct
reference to it. Also the mechanism behind "arming a second button
disarms the first": setting a different button's `armedForDelete` to
false here re-enters this same handler on *that* button, which is
harmless since it only clears the registry when it still points at
itself.

### [81] The hold timeline (`holdSchedule`)

As a list of phase durations (ms): wait 150ms (still could just be a
click — no visual change yet), then alternate between the current
appearance and the target (opposite) one every 500ms, landing on — and
staying on — the target the 4th time it comes around. For arming, that
reads as I 150ms, D 500ms, I 500ms, D 500ms, I 500ms, D 500ms, I 500ms, D
(permanent) — three temporary blinks of the trash bin, then it commits.
Disarming an already-armed button mirrors this exactly (same schedule,
same code) since `visualArmed` just alternates between whatever
`armedForDelete` currently is and its opposite — it always ends on
"original icon" instead just because `armedForDelete` started `true`
this time.

### [82] `ghosted`

True while this specific button is the one currently being dragged (set
externally by whatever positions it, e.g. ClientRow.qml) — a dedicated
property rather than letting a caller just override `opacity` directly
at instantiation, which would silently replace (not combine with) the
enabled/disabled dimming — the exact same class of "external binding
silently wins" surprise as [83].

### [83] Why `implicitWidth`/`implicitHeight`, not `width`/`height`

This component is used both standalone (`Item.width` defaults to
`implicitWidth` there) and as a direct child of a `RowLayout` (ClientRow,
the bottom toolbar) — a Layout only reactively tracks a child's
`implicitWidth`/`implicitHeight` (or `Layout.preferredWidth`/`Height`)
for its size, not a plain `width:` binding. Using plain `width:`
here/at call sites looked fine initially but silently stopped reacting
to `Theme.uiScale` changes once placed in a Layout, while `radius` (not
Layout-managed) kept scaling — the actual cause of buttons turning
circular after zooming, confirmed by inspecting live property values.

### [84] Why the button fill is always solid/opaque

Unlike the main window's glass panel behind it, a button's own fill
never fades with hover-driven background opacity; only the background is
meant to do that. Armed-for-delete still gets its own hover feedback (a
lighter/more saturated red), same as every other state — it shouldn't be
the one state that looks static under the cursor.

### [85] Why the trash-bin glyph is 2x size

100% bigger than the normal icon/letter glyph size — a plain letter or
app icon reads fine at the normal size, but the trash bin is the one
state meant to read as an unambiguous warning at a glance.

### [86] `holdTimer`

Walks through `holdSchedule` one phase at a time (variable interval per
phase, hence manual `restart()` rather than `repeat: true`). Reaching
the end of the schedule is the actual arm/disarm moment; every phase
before that is purely visual (see `blinking`). A released-before-the-end
press is a *click* instead, handled entirely in `onReleased` via
`holdTimer.running` (see [90]).

### [87] Why `preventStealing: true`

Every app row lives inside Main.qml's ScrollView, which wraps its
content in a Flickable — Flickable steals an in-progress mouse grab from
a child MouseArea once movement exceeds its own small drag threshold,
mistaking a button drag for a scroll gesture. Confirmed by instrumented
headless testing: without this, `MouseArea.canceled` fired reliably
~15-20px into any drag (a single big instantaneous jump didn't trigger
it — Flickable's steal heuristic needs a short *sequence* of incremental
moves, which is exactly what a real mouse produces and what real users
were hitting). This is the standard, documented fix for a draggable
MouseArea nested inside a Flickable/ScrollView.

### [88] `armedAtPressStart`

Snapshot of `armedForDelete` at the start of *this* press — decides what
a short click (release before the hold timer fires) means: delete-confirm
if the button was already armed, or the normal click/launch action
otherwise. Needed because `onTriggered` may flip `armedForDelete`
mid-press, and by release time the live value no longer reflects what it
was when this press began.

### [89] Why `onPressed` disarms other buttons

Pressing anywhere else — including on another armed-for-delete button —
is a "click elsewhere", which cancels that other button's armed state
(does not affect this button) — unless this button opted out (see [77]).

### [90] `wasClick` in `onReleased`

A non-deletable button has no hold concept at all, so every release is a
click. A deletable button's `holdTimer` still *running* at release means
this press ended before the hold schedule finished — i.e. it was a plain
click too. If the schedule had already completed, `armedForDelete` was
already toggled and this release is just the end of that hold; nothing
further happens.

### [91] Why the armed-click branch resets `armedForDelete` before emitting

A click while already armed is the explicit delete confirmation — reset
first (see [80]'s ordering) since `deleteRequested()` can destroy this
delegate synchronously.

### [92] Why `onExited` only cancels an in-progress hold

Leaving the button area while a hold is in progress cancels just that
hold (per "do not move the cursor outside button area") —
`armedForDelete` itself is untouched, since a hold that never completed
never changed it. Not applied to hover-only exits (mouse not pressed) or
to an already-started drag, which is expected to roam outside this
button's own bounds.

### [93] Why there's both a `MouseArea` and a `HoverHandler`

MouseArea above already grabs press/drag; a HoverHandler is passive
(hover-only, never grabs), so the two coexist without interfering — same
pattern already used for the client logo's tooltip in ClientRow.qml.

### [94] Why the tooltip is hidden during drag/delete-arm

Never during an active drag/delete-arm sequence (including a mid-hold
blink frame that's currently *showing* the armed look) — a tooltip
fighting for attention with the ghost or the trash-bin icon would just
be noise.

## src/loader/gen_splash_header.py

### [95] Why the splash image is baked into a C header at build time, via this script

Per `claude-blocks/python-qt-startup-splash.claude.md`'s "Asset
handling": the whole point of writing the loader in plain C/Xlib instead
of a toolkit is near-zero startup cost, so it must not link a PNG/image
decoding library at runtime. Decoding happens once, at build time,
producing a plain byte array embedded directly in the source. This
script uses PySide6's `QImage` to do that decode — not because the
loader needs Qt (it doesn't, and never will at runtime), but because
PySide6 is already a mandatory *build-time* dependency of this project
(the whole app is built on it), so reusing it here avoids adding a new
dependency (e.g. Pillow) or shelling out to an external tool (e.g.
ImageMagick) that might not be present on every build host.

### [96] `constBits()` return type across PySide6 versions

PySide6 has returned both a `sip.voidptr` (needs an explicit `setsize()`
call before it reports the right length) and a plain `memoryview`
(already correctly sized) from `QImage.constBits()` across different
versions — checking for `setsize` and only calling it when present
handles both without pinning to one exact PySide6 version.

### [97] Why rows are copied individually instead of using the raw buffer directly

`Format_RGBA8888` is not guaranteed to be padding-free (`bytesPerLine()
== width * 4`) on every Qt build/platform, even though it measured
exactly that (no stride padding) for this project's actual splash image
and installed Qt version. Copying row-by-row using the real
`bytesPerLine()` stride is correct regardless of whether that padding
assumption holds.

## src/loader/main.c

### [98] Why there's no libXrender dependency for the transparent visual

A depth-32 TrueColor visual (found via plain `XMatchVisualInfo`, no
XRender call needed) is enough: the alpha channel is a de-facto X11
convention, not something that needs the XRender extension to declare —
modern compositors (picom, KWin, Mutter, xfwm4's compositor, ...) treat
any depth-32 window's top byte as alpha when reading its pixel data for
compositing. Depending only on libX11 + libXinerama (both far more
commonly preinstalled than libXrender-dev) keeps the loader's build
dependencies minimal, matching "simple" per the request that produced
this file. Untested on a real compositor — see [107] for the broader
"nothing here has been visually verified" caveat.

### [99] Why a colormap is always created fresh, for either visual

`XCreateColormap(display, root, vinfo.visual, AllocNone)` is called
unconditionally, for both the depth-32 ARGB visual and the plain
default-visual fallback — a colormap created this way is valid for any
visual class, including the default one, so using one code path for
window creation regardless of which visual was selected avoids a
branch that would otherwise have to special-case
`DefaultColormap(display, screen)` for the fallback case.

### [100] Why window pixels use premultiplied alpha

XRender-based compositing (which is how modern compositors actually
read/composite a redirected window's pixel data) expects `ARGB32`-style
content to be *premultiplied*: each color channel already multiplied by
its own alpha, not stored independently of it. Writing straight
(non-premultiplied) alpha into the window would over-brighten
partially-transparent edges once the compositor blends it against
whatever is behind. This is the same convention other systems that
produce ARGB32 X11 content (e.g. Cairo's `CAIRO_FORMAT_ARGB32`) also
require.

### [101] The no-ARGB-visual fallback: blend onto a fixed background instead

Without a depth-32 visual, the window itself cannot be made genuinely
see-through (no compositor blending against the desktop is possible) —
so instead of a transparent window, the image is alpha-blended onto a
fixed solid background color *within* an always-opaque window, using
this project's own dark-theme background color (`Theme.qml`'s
`#14161c`) for visual consistency with the rest of the app. "Fading"
the image in/out against that fixed canvas is still possible even
though the window itself never becomes transparent — this matches the
blueprint's stated fallback ("blend toward a solid background color
instead").

### [102] Why only Xinerama screen index 0 is used

Xinerama has no built-in "primary monitor" concept (that's a separate,
more complex RandR feature requiring libXrandr) — screen index 0 is
used as a practical stand-in, since Xinerama conventionally lists
monitors with the primary one first on most standard setups. This is a
deliberate simplification for a "simple" loader, not a guarantee: it
will not always match whichever monitor ClientDeck's own window
placement logic (`window_placement.py`) would restore onto, since that
reads the saved monitor *name* from config, which this minimal C loader
deliberately doesn't parse (no JSON parser, no config-format coupling,
by design — see the loader's independence rationale in
`claude-blocks/python-qt-startup-splash.claude.md`). The real window
still ends up on the correct saved monitor once ClientDeck itself opens
it; only the splash's placement uses this simplification.

### [103] The shimmer-patch animation design

A small number of rectangular patches (`NUM_PATCHES`), each covering a
random region of the image, independently pulse a luma delta (added to
R/G/B, alpha untouched) following `amplitude * sin(pi * t)` across their
own lifetime — 0 at the start, peaking at the midpoint, back to 0 at the
end — rather than a hard on/off flash, so each shimmer appears and fades
smoothly. When a patch's lifetime elapses, it immediately respawns with
a new random rectangle, duration, and amplitude (sign included, so it
can either brighten or dim). Patches are given staggered starting
phases on launch (each offset a few hundred ms into its own cycle
already) specifically so they don't all pulse in visible unison the
first time the splash appears.

### [104] Why "running" detection accumulates received bytes and does substring search

Per the blueprint's interop rule: a splash that only understands the
plain-word baseline protocol should still recognize `running` embedded
in a line from the richer optional staged/JSON form (e.g.
`{"stage": "running"}`), via substring match rather than requiring an
exact line match. Bytes are accumulated into a small fixed-size rolling
buffer (trimming from the front once it's full) rather than checked
per-`recv()`-call in isolation, so a "running" that happens to straddle
two separate reads is still detected — an unlikely but cheap-to-handle
edge case for a UNIX domain stream socket.

### [105] Why there's a single deadline covering both "never connects" and "never sends running"

Rather than separate timeouts for "no connection ever received" and
"connected but never sent running", one bounded ceiling
(`MAX_WAIT_MS`), measured from process start, covers both — simpler,
and both failure modes have the same correct outcome anyway: stop
waiting and fade out. A disconnect detected *before* that ceiling (see
[104]'s neighboring disconnect handling) still fades out immediately
rather than waiting out the rest of the ceiling, per the blueprint's
"disconnects without running" failure mode.

### [106] Standalone mode (no socket env var set)

Per the blueprint's verification checklist ("run standalone with no
channel/env var set and confirm sensible degrade"): with no
`CLIENTDECK_LOADER_SOCKET` in the environment, the loader skips socket
setup entirely, shows the splash, and dismisses on a mouse click inside
the window or after a short fixed safety timeout
(`STANDALONE_MAX_MS`), whichever comes first — rather than waiting on
the full packaged-mode ceiling for a `running` signal that can never
arrive. This is also the intended way to manually preview/tune the
splash on-host: run the built binary directly with no environment setup.

### [107] Known unverified performance/correctness tradeoffs

Nothing in this file has been built or run — see CLAUDE.md's
environment constraints (no real X server/compositor in the agent's
sandbox, and the Xinerama/XRender dev headers aren't even installed
here). Two specific tradeoffs, made without being able to measure them,
that on-host verification should pay attention to:

- Every frame re-uploads the *entire* image via a plain `XPutImage`
  call (no MIT-SHM shared-memory extension) — simpler and one fewer
  library dependency (`libXext`), at the cost of copying the full pixel
  buffer over the X connection every frame. Expected to be fine for a
  short-lived, local (UNIX-socket X11 connection) splash, but not
  benchmarked.
- Per-pixel writes use `XPutPixel()`, which handles the display's
  actual byte order/bit layout internally, rather than hand-packing
  bytes according to `ImageByteOrder()` — correct regardless of host
  endianness, at some per-pixel call overhead versus manual packing.
  If frame rate turns out to be a real problem on real hardware, this
  is the first place to optimize.

### [108] `_NET_WM_WINDOW_TYPE_SPLASH` is set best-effort, on top of `override_redirect`

`override_redirect` alone already satisfies "no border, no system
menu, no window-manager decoration" — the window manager doesn't
manage this window at all. Setting `_NET_WM_WINDOW_TYPE` to
`_NET_WM_WINDOW_TYPE_SPLASH` on top of that is an extra courtesy for
the rare tool that still introspects override-redirect windows (e.g.
some compositors' window-type-based effects); harmless to set
regardless, and not load-bearing for the "no chrome" requirement.

### [109] Feature-test-macro gotchas caught by a syntax-only compile check

`-std=c11` requests strict ISO C, which hides POSIX/BSD extensions glibc
would otherwise expose by default: `clock_gettime()`/`CLOCK_MONOTONIC`
(POSIX, needs `_POSIX_C_SOURCE >= 199309L`, defined before any
`#include` since glibc's feature-test macros only take effect that way)
and `M_PI` (a BSD/XSI `<math.h>` extension, not reliably exposed even
with `_POSIX_C_SOURCE` set) both failed to compile under this project's
`-std=c11 -Wall -Wextra` flags. Fixed by defining `_POSIX_C_SOURCE`
first thing in the file, and by defining a local `LOADER_PI` constant
instead of depending on `M_PI` at all. Caught by actually running
`gcc -fsyntax-only` against this file with stub headers standing in for
the Xinerama/XRender dev headers this sandbox doesn't have installed —
see [107]: this is the one piece of `main.c` that *has* been mechanically
checked, even though nothing here has been linked, run, or visually
verified.

### [117] Displaying at `TARGET_HEIGHT_FRACTION` of the monitor's height, not the source image's native size

Per user request, after the first on-host test confirmed the loader
works: the splash's displayed height is 25% of the target monitor's
height (aspect ratio preserved from the source image for width), rather
than always showing the full ~1254px-native splash image regardless of
screen size. Implementation:

- `disp_h`/`disp_w` are computed once, right after the target monitor's
  geometry is known (Xinerama screen 0 — see [102]) and before the
  window/XImage/buffers are created — every size-dependent piece of
  state (window dimensions, `XImage`, the `base`/`scratch` buffers, the
  shimmer patches' coordinate space) is sized off these, not off
  `SPLASH_IMAGE_WIDTH`/`HEIGHT` (which now refer only to the embedded
  *source* image's fixed dimensions, used solely inside
  `downscale_source()`).
- The embedded full-resolution source is downscaled to `disp_w x disp_h`
  exactly **once**, at startup (`downscale_source()`), into a `base`
  buffer that every animation frame then copies from — not resized
  every frame. Besides being obviously cheaper, this is also a genuine
  performance improvement for the per-frame cost the user flagged as
  untested/a possible concern: every frame's `XPutPixel` loop and
  `XPutImage` transfer now scale with the much smaller *displayed* pixel
  count instead of the full source's ~1.57M pixels regardless of how
  small the splash ends up on screen.
- `downscale_source()` is a box filter (average every source pixel that
  falls within each output pixel's footprint) weighted by each source
  pixel's own alpha, not a plain unweighted average — a plain average
  would blend the fully-transparent (RGB always `(0,0,0,0)`) pixels
  around this image's edges into a dark halo on the partially-transparent
  edge pixels of the downscaled result. Weighting by alpha (`sum(color *
  alpha) / sum(alpha)` for RGB, plain average for alpha itself) avoids
  that.

### [118] Why `PATCH_AMPLITUDE` was raised from 40 to 64

Per user feedback after the first on-host test: "the light effects...
are good exactly as I wanted, just try to make them a little bit more
contrast." The shimmer's luma swing (see [103]) is controlled by this
single constant; raising it directly increases how bright/dim each
pulsing patch gets without changing anything else about the effect's
timing, count, or shape — the simplest lever for "more contrast" that
preserves everything the user said was already right.

## src/clientdeck/loader_ipc.py

### [110] Scope of this module

Implements only the app side of the loader protocol: launch, connect,
send `starting`/`running`. The loader (splash) side lives entirely in
`src/loader/main.c`; the two only agree through the newline-delimited
protocol described in the blueprint, never by importing anything from
each other.

### [111] Why every `LoaderHandle` method is a silent no-op once `_sock` is None

Per the blueprint's "backward/forward compatibility rule": app-side code
talking to the loader must never assume anything is listening, and must
never be able to break the app if it isn't. Every public method
degrades to doing nothing the moment the socket is unusable (never
connected, or a previous send already failed) rather than raising —
callers (`app.py`) never need their own try/except around these calls.

### [112] When `maybe_launch_loader()` intentionally does nothing

Returns the shared no-op handle, without attempting anything further,
when: the loader binary isn't present at the expected path (e.g. a
packaged build that, for whatever reason, didn't bundle it), the
subprocess fails to launch, or connecting never succeeds within the
retry budget — see [115] for when it does nothing because there's
simply nothing to connect to (plain source checkout, no wrapper). Every
one of these is a normal, silent "run with no splash" outcome, not an
error — matches the blueprint's "splash fails to launch → the app must
fall back to running with no splash at all" failure mode.

### [115] Why an already-set socket env var short-circuits straight to connecting, before the packaged-build check

Per the blueprint's "App-side responsibilities" #1: "only [self-]launch
... AND no channel is already set up (avoid double-launching if a dev
wrapper script already started one for a source checkout)". A wrapper
script (e.g. `run.sh`) that starts its own `clientdeck-loader` and sets
`CLIENTDECK_LOADER_SOCKET` before invoking the app is exactly that case
— the app must still *connect* and speak the protocol (or the wrapper's
splash would never receive `running` and would just sit until its own
timeout), it just must not launch a second loader process on top of it.
Checking the env var first, before `is_packaged_build()`, is what makes
this work for a *source-checkout* dev run too, not just a packaged
build launched by something unusual — the packaged-build self-launch
path only exists for the plain "just run the binary" case, with no
wrapper involved at all.

## src/clientdeck/app.py (loader wiring)

### [113] Why `maybe_launch_loader()` is called before `QGuiApplication` is even constructed

Per the blueprint: "Connect to the channel as close to the very first
action as possible." The whole point of the splash is to cover
`QGuiApplication`/`QQmlApplicationEngine` initialization, which is the
actual slow part (see the blueprint's "core insight") — launching the
loader any later than this would leave a gap at the very start of
startup where nothing is on screen yet.

### [114] Why `running` is sent only after a couple of `processEvents()` calls

Window creation/`show()` and the first real paint are not synchronous in
Qt — sending `running` right after `engine.rootObjects()[0]` is obtained
risks the splash fading out onto a window that's technically visible but
not yet actually painted. Calling `app.processEvents()` once or twice
first (per the blueprint's Qt-specific timing note) gives the event loop
a chance to actually paint before the loader is told it's safe to fade
out.

## run.sh

### [116] Why this wrapper builds+launches the loader itself, and why not `exec`

The app only *self*-launches a loader when packaged (see [112]/[115]) —
a source checkout run via `run.sh` would otherwise never show a splash
at all. This wrapper fills that gap the same way the blueprint frames
dev-mode splash support: an external script starts the loader and sets
`CLIENTDECK_LOADER_SOCKET` before starting the app, and
`loader_ipc.maybe_launch_loader()`'s env-var-first check (see [115])
means the app just connects to it rather than launching its own.

The final `uv run python -m clientdeck "$@"` is deliberately *not*
`exec`'d (unlike this file's own previous, splash-less version, now
`run-clientdesk.sh`): `exec` replaces the shell process image outright,
which would skip the `trap cleanup EXIT` below entirely — bash never
runs EXIT traps across an `exec`, since the shell doesn't exit in the
normal sense, it *becomes* the new program. Running the app as a plain
foreground command instead lets the trap fire once it exits, which is
what kills the backgrounded loader process and removes its temp socket
directory — without that, the loader would linger as an orphaned
process (until its own `MAX_WAIT_MS` ceiling, see main.c's [105]) every
time this script's invocation ended.

Building the loader via `make` on every run (rather than requiring it
pre-built) is cheap: `make` no-ops once the binary is already up to
date, so this only costs real time the first run or after `main.c`
changes.
