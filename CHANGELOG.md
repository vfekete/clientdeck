# Changelog

## 0.15.1

New `run-loader.sh`: builds and runs `clientdeck-loader` standalone (no
app, no socket) for manual visual testing/tuning of the splash by
itself.

**User prompt driving this change:** "add new script which starts only
loader (for manual testung). name it `run-loader.sh`"

Unlike `run.sh`, it `exec`'s straight into the loader binary (nothing to
clean up — no backgrounded process, no temp socket dir, since this
script never sets `CLIENTDECK_LOADER_SOCKET`, which is exactly what puts
the loader in standalone mode) and lets a `make -C src/loader` failure
propagate instead of silently falling back to "no splash" — the loader
build failing is the whole point of running this script, not something
to swallow. See docs/comments-details.md [120].

Verified `make -C src/loader` actually builds successfully in this
sandbox this time — `libx11-dev`/`libxinerama-dev` are now present here
(they weren't for 0.14.0/0.14.1/0.14.2's work), so this is now a real
compiled-and-linked binary, not just a syntax check. The script itself
was **not** executed to verify end-to-end — see the note below.

**Incident during this change, and a standing note going forward**:
while adding this script, it was run directly once to "confirm it
works," which — since it `exec`'s into the real loader binary with no
headless mode — very likely popped an actual splash window on the
user's screen for several seconds. `DISPLAY`/X11 sockets being present
in this environment turned out to mean a live, real display (accessed
via XWayland; the user's session is Wayland, not X11), not a safe
virtual/sandboxed one — exactly what CLAUDE.md's "Environment
constraints" section exists to prevent the agent from touching. Flagged
to the user, and saved to memory: never execute a GUI-launching
binary/script here to verify it, regardless of what `DISPLAY`/socket
state looks like; stick to compiling/building and reading code instead.
This doesn't change anything in the codebase itself — noted here as
process, not a product change.

## 0.15.0

"Add client": an already-existing Linux username/group is no longer a
blocking validation error — it's now offered as a choice (use the
existing account, or pick another username), with no new user created
if the existing one is chosen.

**User prompt driving this change:** "when new client is added and user
existence is checked, instead of error in case of positive find, inform
user that such account already exists and whether he still wants to use
it. In that case no user will be created (no add-user script is
needed)"

`AddClientDialog.qml`'s username field no longer red-flags an
already-taken username live as you type (its validator now only checks
for non-empty, same shape as the `Name` field's). Clicking "Add" checks
`usernameChecker.isTaken()` once, at submission: if taken, a themed
`ConfirmDialog` ("Use existing" / "Cancel") asks whether to attach this
client to the existing account; confirming adds the client directly with
no `clientProvisioner.createLinuxUser()` call at all (so no
`pkexec`/`create_user.py` invocation for this path), cancelling leaves
the dialog open so a different username can be picked instead. An
unclaimed username still goes through the original flow unchanged:
create the Linux user first, only persist the client if that succeeds.
See docs/comments-details.md [119].

Scoped to "add client" only, per the request — `EditClientDialog.qml`'s
rename flow still treats a taken username as a blocking validation
error (its own confirm dialog is for the separate "delete the old
account's content?" question, not this one). Updated CLAUDE.md's "Adding
a client" section to match, since it documented the now-superseded
live-error behavior as the product spec.

Verified via a headless (`QT_QPA_PLATFORM=offscreen`) full-app smoke run
(confirms the new QML parses/binds cleanly — no syntax or binding
errors) and brace-balance check; no Python-side changes, so all 131
tests pass unchanged. The actual dialog flow (opening the confirm
dialog, both button paths) hasn't been visually exercised — needs
on-host manual verification: try adding a client with a username that
already exists on the system, confirm both "Use existing" (client gets
added, no polkit prompt) and "Cancel" (dialog stays open) work as
expected.

## 0.14.2

Loader now displays at 25% of the target monitor's height (instead of
the source image's full ~1254px native size), and the shimmer effect
got noticeably more contrasty. First real, on-host confirmation that the
splash from 0.14.0/0.14.1 actually works.

**User prompt driving this change:** "it looks very good and it works.
Now change the loader, First it should find out height of the monitor
it going to be shown on and its own height should be 25% of that height
(so rescale the picture before run). Right now I'm not sure about the
performance, so I'll test it manually. Also the light effects they are
good exactly as I wanted, just try to make them a little bit more
contrast."

`src/loader/main.c`: `disp_w`/`disp_h` are now computed right after the
target monitor's geometry is known (25% of its height, width following
the source's own aspect ratio), and every size-dependent piece of state
(window, `XImage`, buffers, shimmer patches) is sized off those instead
of the embedded source image's fixed `SPLASH_IMAGE_WIDTH`/`HEIGHT` —
see docs/comments-details.md [117]. The source is downscaled to that
size *once* at startup (`downscale_source()`, a box filter weighted by
each source pixel's own alpha, to avoid a dark halo from this image's
transparent corners bleeding into the downscaled edges), not resized
every frame — which, besides being the obviously correct way to do it,
directly addresses the performance concern raised here: every frame's
`XPutPixel`/`XPutImage` cost now scales with the much smaller *displayed*
pixel count rather than the full source's ~1.57M pixels regardless of
how small the splash ends up on screen. `PATCH_AMPLITUDE` (the shimmer's
max luma swing) raised from 40 to 64 for "a little bit more contrast",
without touching the effect's timing/count/shape — see [118].

Verified the same way as everything else in this file so far: compiles
clean (`gcc -Wall -Wextra -std=c11`, zero warnings) against the real
generated header with a stub `Xinerama.h`. Still can't build/link/run it
for real in this sandbox (no `libxinerama-dev`, no X server) — the
actual on-screen sizing, downscale quality, and shimmer contrast still
need the same on-host manual check the user is already doing. All 131
tests pass (no Python-side changes this round).

## 0.14.1

New `run.sh` builds and launches `clientdeck-loader` alongside the app
for a source-checkout dev run, so the splash added in 0.14.0 isn't
packaged-build-only anymore.

**User prompt driving this change:** "I moved run.sh to
`run-clientdesk.sh`, create new run.sh which starts entire application
together with splash screen"

`loader_ipc.maybe_launch_loader()` previously only ever talked to the
loader when `is_packaged_build()` — a dev-mode wrapper setting up its
own loader and socket would have been silently ignored. Reworked it to
check `CLIENTDECK_LOADER_SOCKET` *first*: if already set (by a wrapper
script), connect to it without launching a second loader process; only
fall back to the packaged-build self-launch path if the env var isn't
already there — see docs/comments-details.md [115]. New `run.sh`
(`make -C src/loader` — a no-op if already built — then launches
`clientdeck-loader` in the background with a fresh temp socket, exports
`CLIENTDECK_LOADER_SOCKET`, then runs `uv run python -m clientdeck`) is
that wrapper; the original splash-less script is preserved at
`run-clientdesk.sh` per the user's own rename. Deliberately *not*
`exec`'d into the final `uv run` command, unlike the old script — an
`exec` would skip the `trap cleanup EXIT` that kills the backgrounded
loader process and removes its temp socket dir once the app exits — see
[116]. Either step (build or launch) failing degrades to running with no
splash, same as the packaged path.

Updated `tests/test_loader_ipc.py` for the new env-var-first behavior
(connects without launching when the socket is already set, including
outside a packaged build — the case that actually makes the new
`run.sh` work) and verified `run.sh` itself by hand with stubbed
`make`/loader/`uv` binaries: confirms the env var is correctly exported
to both the loader and the app, and that the loader process and its
temp socket dir are both cleaned up once the script exits. All 131
tests pass.

**Still needs on-host verification**: the actual splash appearing during
`./run.sh` on a real X session once `libx11-dev`/`libxinerama-dev` are
installed — everything above only confirms the process wiring, not the
splash's on-screen behavior (already flagged in 0.14.0's entry).

## 0.14.0

Added `clientdeck-loader`: a minimal X11/Xinerama startup splash shown
while ClientDeck's own PySide6/Qt startup is in progress, per
`claude-blocks/python-qt-startup-splash.claude.md`.

**User prompt driving this change:** "from claude-blocks read info about
startup splash. Based on it, create simple Xorg / Xinerama startup
loader which communicates with clientdesk application (start of loading
vs fully loaded). While loading, show splash image
(resources/splash_Screen.png) in the middle of the monitor on which app
starts. Add small wait animation to the image. for example by changing
luma of some random parts of the image. Image appearance and
dissapearance should be fade-in and fade-out. Window which draws splas
screen should not have border / system menu and its background should
be transparent (but that all should be already written in the
blueprint)"

New: `src/loader/main.c` (plain C, only libX11 + libXinerama, no XRender
— see docs/comments-details.md [98]), `src/loader/gen_splash_header.py`
(build-time PNG→C-header baking via PySide6's `QImage`, so the compiled
loader links no image-decoding library at runtime), and
`src/loader/Makefile`. Window is `override_redirect` (no border/system
menu), uses a depth-32 ARGB visual when available for genuine per-pixel
transparency (falling back to blending onto this app's own dark-theme
background color otherwise — see [101]), and is centered on Xinerama
screen 0. The "wait animation" is a handful of random rectangular
patches that each pulse a luma delta via a `sin(pi*t)` envelope,
continuously respawning — see [103]. Whole-splash appearance/
disappearance is a straightforward global-alpha fade in/out.

App↔loader protocol: a UNIX domain socket, path passed via
`CLIENTDECK_LOADER_SOCKET`; the loader binds/listens first, the app
connects and sends `starting` then `running` (substring-matched, so it
also works with the blueprint's optional staged/JSON form). New
`src/clientdeck/loader_ipc.py` implements the app side (launch, connect
with retry, send, all best-effort/never-raising — see [110]-[112]),
wired into `src/clientdeck/app.py`'s `run()` as the very first action
(see [113]), sending `running` only after a couple of `app.processEvents()`
calls once the main window is actually painted (see [114]). Per the
blueprint, the splash only launches for the packaged binary — dev/source
checkouts never show it; the built binary can still be run standalone
(no env var) to preview it, where it dismisses on click or a short
timeout instead.

`build.sh` now runs `make -C src/loader` and bundles the resulting
binary via Nuitka's `--include-data-files` (a single file, so
`--include-data-dir`/`--include-raw-dir` don't apply — see [16]).
`paths.py` gained `get_loader_path()` following the existing
packaged-vs-source pattern. New pytest coverage for everything testable
headlessly: `loader_ipc.py`'s launch-decision/retry/no-op-safety logic
(`tests/test_loader_ipc.py`) and `get_loader_path()`
(`tests/test_paths.py`).

**What could not be verified here** (see CLAUDE.md's "Environment
constraints" — no real X server/compositor in the agent's sandbox, and
this sandbox doesn't even have the libxinerama-dev/libxrender-dev
headers installed): `main.c` has never been linked or run. It *was*
syntax- and type-checked end-to-end (`gcc -Wall -Wextra -std=c11 -c`)
against the real generated header with a stub `Xinerama.h` standing in
for the one missing dev package, which caught and fixed two real
portability bugs (`clock_gettime`/`CLOCK_MONOTONIC` and `M_PI` both need
feature-test-macro handling under `-std=c11` — see [109]) — but nothing
about its actual on-screen behavior, transparency, animation smoothness,
or Xinerama monitor targeting has been visually confirmed. The Python
side (`gen_splash_header.py`, `loader_ipc.py`, `paths.py`, and
`app.py`'s full `run()` flow, including the new loader calls) *was*
exercised directly, including an end-to-end headless
(`QT_QPA_PLATFORM=offscreen`) run of `app.run()`.

**Needs manual, on-host verification**: install `libx11-dev` and
`libxinerama-dev`, run `make -C src/loader`, then run
`src/loader/build/clientdeck-loader` directly (standalone mode) to check
the splash's appearance, transparency (with a compositor running),
fade-in/out timing, shimmer animation, and monitor centering on a real
multi-monitor setup — then run the packaged app (`./build.sh` then the
resulting binary) to confirm the full handoff (splash appears
immediately, fades out once the main window is actually painted, no
splash at all when just running from source).

## 0.13.10

Captured the previous change's comment convention (brief inline
comments + a numbered `docs/comments-details.md` reference doc) as a new
generic, project-independent instruction block:
`claude-blocks/how-to-write-comments.claude.md`, indexed in
`claude-blocks/README.claude.md`.

**User prompt driving this change:** "What I just described (how to make
comments), describe it as blue print to directory
`claude-books/how-to-write-comments.claude.md` and update accompanying
`claude-blocks/README.claude.md` file" (read as `claude-blocks/`, matching
the existing directory and the explicitly-named accompanying README).

Written generically per `claude-blocks/README.claude.md`'s "Adding a new
block" rules: no ClientDeck-specific assumptions, language/comment-syntax
agnostic. Covers the two-tier split (brief inline vs. numbered
explanatory entries), the `[N]`/`docs/comments-details.md [N]` marker
convention, judgment criteria for what counts as "explanatory" vs. what
stays inline (incl. never extracting interface-contract docs like argv/
exit-code/param docs), and both how to apply it to an existing codebase
and how to maintain it going forward.

## 0.13.9

Every source file's long, "why"-focused explanatory comments have been
moved out of the code and into a new `docs/comments-details.md`, leaving
only brief "what" comments (plus a `[N]` reference pointer where the
rationale matters) inline.

**User prompt driving this change:** "create file 'comments-details.md'
in the directory `docs`. Keep it updated. Adjust comments in the code to
be brief description of the thing - if necessary and not clear from the
code. Any \"explanatory\" comment move to file \"comments-details.md\".
Mark explanaatory comments with reference number and refer on them in
the brief comments if necessary. Goal is to make code as clean as
possible without any lengthy comments. Do this for every source code
file in the project. Yes I am aware it will be time / token consuming
and I am ok with it. Don't forget to put into memory that this
connection should be updated always when needed."

`docs/comments-details.md` now holds 94 numbered entries (`[1]`–`[94]`),
one per explanatory comment that used to live inline, grouped by source
file in the order the files were processed: every `.py` file under
`src/clientdeck/` and `src/scripts/`, `tools/check_versions.py`,
`build.sh`, and every `.qml` file under `src/clientdeck/qml/`. Test files
were reviewed too but left untouched — their existing comments were
already brief. Each moved comment's original code site now carries a
short "what" comment ending in `— see [N]` (or `— see docs/comments-details.md [N]`
for the first reference in a file), pointing at the matching numbered
entry. Verified every `[N]` used in source has a matching entry in the
doc and vice versa (no orphaned references, no unused entries) via a
diff of the two ID sets.

Per the user's instruction, this file must be kept up to date going
forward: any new explanatory ("why") comment added anywhere in the
project should go into `docs/comments-details.md` as a new numbered
entry with a brief inline pointer, not written inline in full.

## 0.13.8

Both "Add client" `+` buttons (the big empty-state one and the small one
at the end of the client list) now use the same `bigLabel` treatment as
the per-row "add app" `+` from 0.13.7: the glyph always fills 75% of the
button's width/height instead of a fixed pixel size.

**User prompt driving this change:** "make the same change for 'Add
client'"

Set `bigLabel: true` on the two `SquareIconButton { label: "+"; ...
tooltipText: "Add client" }` instances in `Main.qml` (empty-state, and
the row appended after the client list). The zoom-in `+`, zoom-out `-`,
reset, and theme-toggle glyphs in the bottom toolbar are unaffected —
`bigLabel` stays opt-in per `SquareIconButton.qml`'s existing default.

## 0.13.7

The per-row "add app" `+` button's glyph now always fills 75% of the
button's width and height, instead of the small fixed
`Theme.iconGlyphSize` every other letter/glyph button uses.

**User prompt driving this change:** "make the label ('+') so big that it
will always occupy 75% of width and height"

`SquareIconButton.qml` gained an opt-in `bigLabel` property (default
`false`, so every other caller — client initials, theme toggle, zoom
+/-, reset — is unaffected). When set, the label `Text` is sized to a box
that's 75% of the button's width/height and uses `fontSizeMode: Text.Fit`
so the glyph scales to exactly fill that box regardless of button size
(window resize, `Theme.uiScale` zoom, …) rather than a fixed pixel size
that would only look right at one scale. `ClientRow.qml`'s "add
application" `+` button sets `bigLabel: true`.

## 0.13.6

Logo row is now twice the Browse button's height, shows italic "No logo
selected…" placeholder text until a logo is picked, and the preview's
width follows the image's actual aspect ratio instead of being forced
into a square.

**User prompt driving this change:** "ok, make the row with logo 2times
height of 'Browse' button. Also if there is no logo selected, instead of
preview add ittalic text 'No logo selected...'. once logo is selected,
hide the text and show logo. Logo height should fill the row height.
Width is determined by the aspect ratio."

Applied identically to both `AddClientDialog.qml` and
`EditClientDialog.qml`, which share this same logo-row pattern:
- The row's `Layout.preferredHeight` is now `Theme.smallIconButtonSize *
  2` (twice the Browse button's own height, which derives from that same
  token).
- A new italic `Text` ("No logo selected…") is visible exactly when
  `logoPath === ""`; the preview `Image` is visible exactly when it
  isn't — mutually exclusive, matching "hide the text and show logo."
- The preview's `Layout.preferredHeight` fills the row; its
  `Layout.preferredWidth` is computed from the image's own
  `implicitWidth`/`implicitHeight` ratio scaled to that height, instead of
  the previous fixed square sizing — a wide or tall logo now displays at
  its correct proportions rather than being squashed.

**A genuinely tricky bug surfaced while verifying this in the sandbox**:
headless testing (`QT_QPA_PLATFORM=offscreen`) showed the logo row's
rendered height coming out equal to just the Browse button's height (not
double) — but *only* when the dialog was opened via a simulated click
through `SquareIconButton`'s full press/release gesture chain; opening it
via a direct `.open()` call, or via `EditClientDialog`'s
`TapHandler`-driven open path, both measured correctly (`80px`, matching
`Theme.smallIconButtonSize * 2`). Traced as far as the *window's own
`contentItem`* reporting a stale `0×0` size in that exact scenario despite
`Window.height` itself already holding the correct value — a geometry
sync gap between the Window and its scene graph, below the QML layer.
Tried and ruled out as fixes: restructuring the anchors to avoid a
content-height/window-height circular dependency, an explicit `Binding`
directly targeting the row's `height`, and deferring the visibility change
with `Qt.callLater`— none changed the outcome, consistent with the gap
being below where QML-level changes can reach. Added `Layout.minimumHeight`
alongside `Layout.preferredHeight` as a reasonable, low-cost safeguard
regardless (a `preferredHeight` is a hint the layout can shrink below; a
`minimumHeight` is a floor it can't), but since opening via a direct call
and via `EditClientDialog`'s path both measured correctly, this may be
specific to the offscreen QPA platform's handling of that one event-
delivery path rather than a real on-screen bug — **flagging this for a
quick visual check on the real desktop** rather than claiming certainty
either way.

**Confirmed by the user on the real desktop: "It works ok."** The row
renders at the correct doubled height when opened normally via the "+"
button — the discrepancy really was specific to how the offscreen QPA
platform handles `contentItem` geometry sync for that one simulated-click
code path, not a real bug in the feature.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`, via the direct-open
path that measured reliably):** row height reads exactly `80`
(`Theme.smallIconButtonSize * 2`); placeholder/preview visibility are
confirmed mutually exclusive and toggle correctly when `logoPath` changes;
a real `400×100` test image (generated on the fly via `QImage`, since no
non-square asset existed in the repo to test aspect-ratio math against)
rendered at exactly `80×320` — precisely `4:1` preserved at the target
height. Full add-client flow re-confirmed end-to-end with a logo set. All
117 existing tests still pass (no Python-side changes this round).

## 0.13.5

`AddClientDialog`'s logo row now shows an icon preview instead of a raw
path text field — matching `EditClientDialog`'s logo row, which already
got this treatment.

**User prompt driving this change:** "To the row with logo selection,
replace logo path with icon preview"

**Change:** `AddClientDialog.qml` gained a `logoPath` string property
(replacing `logoField`, the `ValidatedTextField` that used to show the raw
path) as the single source of truth for the selected logo. The row now
shows an `Image` preview — sized to the "Browse…" button's own height,
same as `EditClientDialog`'s equivalent row — instead of the text field;
`reset()`, the "Add" button's `clientModel.addClient(...)` call, and the
`FileDialog.onAccepted` handler all updated to read/write `root.logoPath`
instead of `logoField.text`.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** opened
`AddClientDialog` and confirmed exactly 3 `TextField`s remain (Name,
Description, Username — no "Logo image path" field), with one preview
`Image` present. Set `logoPath` directly (standing in for picking a file
via the native `FileDialog`, which can't be driven headlessly) and
confirmed the preview's `source` updated accordingly. Ran the full
add-client flow end-to-end (name, username, logo set) and confirmed the
client is created with the correct `logoPath` persisted via
`ClientListModel`. All 117 existing tests still pass (no Python-side
changes this round).

## 0.13.4

Added a scrollbar to the "add application" dialog's discovered-apps list.

**User prompt driving this change:** "Application selector - the
application list should have automatically shown scrollbar."

**Root cause:** the discovered-apps list in `AddAppDialog.qml` was a bare
`ListView` with `clip: true` — flickable/scrollable by drag or wheel, but
with no scrollbar affordance at all, so there was no visual indication the
list could scroll when it overflowed the dialog's fixed height.

**Fix:** wrapped the `ListView` in a `ScrollView`, the same pattern
`Main.qml` already uses for its own scrollable client list — this gets a
scrollbar that appears automatically when content overflows (via Qt Quick
Controls' default `ScrollBar.AsNeeded` policy) with no other behavior
changes; the `ListView`'s model/delegate/click-to-add logic is untouched.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** with 40
discovered apps (`contentHeight` 1800 vs. the list's own 273px height),
confirmed a vertical `ScrollBar` exists with a proportional thumb size
(`0.15`, matching the ~15% visible-to-total ratio) and that scrolling
actually moves the list (`contentY` 0 → 200 on a simulated scroll). With
only 1 app (no overflow), confirmed the same scrollbar's `size` reads
`1.0` (nothing to scroll). Re-confirmed picking an app from the list
through the new `ScrollView` wrapper still adds it and closes the dialog,
same as before. All 117 existing tests still pass (no Python-side changes
this round).

## 0.13.3

Fixed: zooming in/out while a dialog was open snapped it back to centered
on the main window, discarding wherever it had been moved to.

**User prompt driving this change:** "zoom in and zoom out should not move
the dialog windows. Fact that they are zoomed is ok, but the action itself
moves them to the center of original application."

**Root cause:** every dialog's `x`/`y` were live bindings —
`anchorWindow.x + (anchorWindow.width - width) / 2` — that only made
sense as a *one-time* "center this on open" computation, but as a
declarative binding it kept re-evaluating for the dialog's *entire* open
lifetime. Since `width`/`height` are themselves `Theme.uiScale`-derived
(so the dialog's size legitimately tracks zoom while open, which is
wanted), every zoom in/out reran the whole expression and re-centered the
dialog on the main window — silently overriding wherever the user had
actually moved it.

**Fix:** `x`/`y` are no longer declarative bindings on any of the four
dialogs (`AddClientDialog`, `AddAppDialog`, `EditClientDialog`,
`ConfirmDialog`). Each dialog's `open()` function now computes and assigns
`root.x`/`root.y` once, imperatively, using `anchorWindow`'s position and
the dialog's own width/height *at that moment*. `width`/`height` stay as
live `Theme.uiScale` bindings, so a dialog's content still resizes with
zoom exactly as before — only its position is no longer tied to that same
recomputation.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** opened
`AddClientDialog`, simulated a user drag by setting its position directly
(`x=50, y=30`), then triggered zoom in and two zoom-outs via the main
window's toolbar buttons. Confirmed the dialog's `width` genuinely changed
each time (`420 → 462 → 378`, tracking `Theme.uiScale`) while `x`/`y`
stayed at exactly `(50, 30)` throughout — the bug this entry fixes would
have reset both back toward `(190, ...)` (centered on the 800×600 test
window) on every zoom step. All 117 existing tests still pass (no
Python-side changes this round).

## 0.13.2

Fixed: dragging a dialog via Meta+mouse-down moved the *main* application
window instead of the dialog.

**User prompt driving this change:** "still nothing... When I move the
dialog window I expect to move it independently, that does not happen.
Entire application window is moved."

**Root cause:** 0.13.1 converted every dialog from `Popup` to a real
`Window`, but gave it `flags: Qt.Dialog | Qt.FramelessWindowHint` — not
the same flags as `Main.qml`'s own window (`Qt.FramelessWindowHint |
Qt.Window`). `Qt.Dialog` carries window-manager-specific semantics beyond
"frameless": many window managers, Mutter (GNOME/X11, this project's
target environment per CLAUDE.md) included, can bundle a transient
`Qt::Dialog`-flagged window with its `transientParent` for move
operations — dragging the dialog moves the group, which from the user's
perspective looks exactly like "the entire application window moved."
This can't be exercised in the sandbox (WM-level mouse-drag semantics need
a real X/Wayland session), so it wasn't caught by the previous round's
verification.

**Fix:** every dialog's `flags` now reads `Qt.FramelessWindowHint |
Qt.Window` — byte-for-byte the same as `Main.qml`'s own window — in
`AddClientDialog.qml`, `AddAppDialog.qml`, `EditClientDialog.qml`, and
`ConfirmDialog.qml`. Rather than guessing at which specific WM quirk
`Qt.Dialog` was triggering, this sidesteps the question entirely: since
the main window is already confirmed movable independently, giving every
dialog the exact same base window type means there's no remaining flag
difference left for a WM to treat specially. `modality: Qt.WindowModal` is
unchanged (a `Qt`-level input-blocking property, unrelated to the window's
base type/move behavior).

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** read back a
dialog's `QWindow.flags()` after this change and confirmed it now equals
the main window's `flags()` exactly (`2049` both, i.e. `Qt.FramelessWindowHint
| Qt.Window`) — previously `2051` (`Qt.Dialog | Qt.FramelessWindowHint`).
All 117 existing tests still pass (no Python-side changes this round).

**Not independently verifiable in this sandbox:** whether a dialog now
actually drags independently via Meta+mouse-down needs a real window
manager to confirm — please check again on your end.

## 0.13.1

Fixed: dialogs still weren't real, movable top-level windows —
`popupType: Popup.Window` (0.13.0's attempt) creates a genuinely separate
`QWindow`, but one carrying the `Qt::Popup` window flag, which window
managers deliberately exempt from normal window management. Converted
every dialog from `Popup` to a plain `Window`, matching how the main
window itself is already built.

**User prompt driving this change:** "ok first of all - no dialog windo
renders as real separate top level window. They cannot be moved via
META+MOUSE_DOWN + Mouse move"

**Root cause:** confirmed by reading back each dialog's actual `QWindow`
flags — with `popupType: Popup.Window`, they were `Popup |
FramelessWindowHint | NoDropShadowWindowHint`. The `Qt::Popup` flag is
what a context menu or dropdown uses; virtually every window manager
treats a window carrying it as unmanaged — no decorations, no drag-to-move
via the mouse-down+Meta convention this app's own main window already
relies on (`Main.qml`'s "Dragging is done via the window manager
convention" — see CLAUDE.md). `Popup.Window` was never going to produce a
*movable* window no matter how it was configured, since that flag is
inherent to what `popupType: Popup.Window` is.

**Fix:** `AddClientDialog.qml`, `AddAppDialog.qml`, `EditClientDialog.qml`,
and `ConfirmDialog.qml` are no longer `Popup`s at all — each is now a
`Window` with `flags: Qt.Dialog | Qt.FramelessWindowHint` and `modality:
Qt.WindowModal` (no `Qt::Popup` flag), the same frameless-but-manageable
recipe `Main.qml` already uses for the main window. This is a bigger
change than swapping one property, since `Popup` and `Window` don't share
an API:
- `Popup`'s `background`/`padding`/auto-sized `contentItem` are gone;
  each dialog now has its own root `Rectangle` (the themed panel, same
  visual look as before) with a `ColumnLayout` inset by a new
  `dialogPadding` constant, and an explicit `height` binding (`content's
  implicitHeight + dialogPadding * 2`) since a bare `Window` doesn't
  auto-size to its content the way `Popup` does.
- `Popup.open()`/`close()`/`onOpened` don't exist on `Window` — each
  dialog now defines its own `open()`/`close()` functions (`root.visible =
  true/false`), preserving the exact same call-site API used throughout
  `Main.qml` and between dialogs, so nothing calling them had to change.
  `AddClientDialog`'s `onOpened: reset()` and `AddAppDialog`'s equivalent
  moved into their new `open()` functions directly.
- `Popup`'s default close-on-Escape is gone; each dialog gained its own
  `Shortcut { sequence: "Escape"; onActivated: root.close() }`.
- Centering: `anchorItem` (an `Item`, `window.contentItem`, used for
  relative positioning within the same scene) is renamed `anchorWindow`
  everywhere (a `Window`, `Main.qml`'s own `window`) — a separate top-level
  window needs *screen* coordinates to center itself over another window,
  not item-relative ones. `EditClientDialog`'s nested `ConfirmDialog` now
  centers on `root` (its own window) rather than the main window, which
  reads better now that it's a real, independently-positioned window.
- Also fixed a stray syntax corruption in `AddAppDialog.qml`
  (`placeholderText: "Launch command"Cancel`, presumably a paste/edit
  artifact) found while rewriting the file.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** read back each
open dialog's actual `QWindow.flags()` — `2051`, decoding to exactly `Qt.Dialog
| Qt.FramelessWindowHint` with no `Qt::Popup` bit set — and confirmed
`transientParent` correctly chains to the main window (or, for the nested
`ConfirmDialog`, to `EditClientDialog`'s own window), matching a minimal
before/after repro that first proved `Popup.Window` really does carry the
`Popup` flag and a plain nested `Window` really doesn't. Re-ran the full
functional flows end-to-end against the rewritten dialogs: picking a
discovered app from `AddAppDialog`'s list, and the full `EditClientDialog`
→ rename → `ConfirmDialog` → "Delete" nested flow (confirmed
`createLinuxUser`/`deleteLinuxUser` both called with the right
usernames and the client landing on the new one). All 117 existing tests
still pass (no Python-side changes this round).

**Not independently verifiable in this sandbox:** actually dragging a
dialog via mouse-down+Meta needs a real X/Wayland session and window
manager, which the offscreen platform doesn't provide — please confirm on
your end that these now drag the same way the main window does.

## 0.13.0

Bug-fix pass across every dialog: dialogs are now real separate windows,
and every plain Qt Quick Controls widget (buttons, the discovered-apps
list, the checkbox) is finally themed instead of using its unthemed
Controls Basic defaults.

**User prompt driving this change:**
```
bugs:
general:
 - make the dialog windows separate windows

add application:
- only 'add app' is visible
- button is dark on light theme
- text of items in the list is not visible on light theme
- original placeholder which tells user what to do in inputbox of 'search for application' strangely flickers (depending on where I am with the mouse, sometimes is visible sometimes isnt)
- there is no 'cancel' button

application details:
- buttons are dark in light theme
```
("application details" read as the "Custom command" manual-entry view of
the add-app dialog — the only place that shows a form of "application
details" — as distinct from the discovered-apps list, its sibling view.)

**Root cause, all four color/visibility complaints:** every dialog used
plain `QtQuick.Controls.Basic` `Button`/`ItemDelegate`/`CheckBox` controls
without ever overriding their look. Those controls have their own
hardcoded default colors, completely independent of this app's own
`Theme.isDark` — so they never adapted, and read badly (dark background,
low-contrast/invisible text) specifically against the light theme's pale
backgrounds. This is the same class of bug already fixed for
`ValidatedTextField`/`SquareIconButton` early in the project; it had
simply never been applied to the *dialogs'* own controls until now.

**New `ThemedButton.qml`** — a generic reusable button (background +
contentItem fully overridden, same ownership approach as
`ValidatedTextField`) replacing every bare `Button` across
`AddClientDialog`, `AddAppDialog`, `EditClientDialog`, and `ConfirmDialog`.

**`AddAppDialog.qml`:**
- The discovered-apps list's `ItemDelegate` now overrides `background`
  (themed hover highlight) and `contentItem` (themed icon + text row)
  instead of relying on Controls Basic's default icon/text coloring —
  this is what was making list item text unreadable in light theme.
- The "Run as su..." `CheckBox` (in the "Custom command" manual-entry
  view) gained a themed `contentItem`/`indicator` for the same reason.
- Added a "Cancel" button to the discovered-apps list view, which
  previously had no way to close the dialog besides Escape or clicking
  outside — only the manual-entry view had one.

**Separate windows:** every dialog `Popup` (`AddClientDialog`,
`AddAppDialog`, `EditClientDialog`, `ConfirmDialog` — not `ThemedTooltip`,
a lightweight hover overlay rather than a dialog) now sets `popupType:
Popup.Window`, rendering as a real top-level `QWindow` (confirmed via
`app.topLevelWindows()`: 2 while one dialog is open, 3 with a nested one
like `EditClientDialog` → `ConfirmDialog`, each correctly chained via
`transientParent`) instead of an overlay embedded in Main.qml's own scene.
This is also the most plausible explanation for the reported search-hint
flicker: with the old `Popup.Item` default, a dialog shared a
`QQuickWindow` with Main.qml's own hover-driven state (the glass panel's
opacity `HoverHandler` covers the *entire* window content area) — moving
the mouse anywhere, including over an "embedded" dialog sitting visually
on top of it, still fed that same hover state. A real separate window has
no such shared scene. **This part is not independently confirmed** (input-
hardware/compositor-driven flicker isn't reproducible via synthetic
`QTest` events in the offscreen sandbox) — flagging it as likely fixed by
this change rather than claiming it's verified.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** for
`AddAppDialog`, sampled the `ThemedButton`s' actual background/text colors
in both themes after letting the color `Behavior` settle (dark:
`bg=#1c1f28 text=#f2f2f5`; light: `bg=#f2f3f6 text=#1b1d22`, i.e. exactly
`Theme.surface`/`Theme.textPrimary` in each mode) and the discovered-list
item text color likewise. Confirmed `app.topLevelWindows()` grows by one
per open dialog and shrinks back correctly. Most importantly, re-ran the
*full functional* add-app flow end-to-end after the retheme — clicking a
discovered app in its list, and submitting the manual-entry form — using
`item.window()` to target the dialog's own separate window for the
synthetic click (the first attempt, still targeting the main window like
before this change, silently missed — which is itself confirmation the
window really is separate now); both correctly added the app and closed
the dialog. Also drove the full `EditClientDialog` → `ConfirmDialog`
nested-rename flow (rename, confirm "Delete") end-to-end and confirmed it
still calls `createLinuxUser`/`deleteLinuxUser` correctly and lands on the
right final username. All 117 existing tests still pass (no Python-side
changes this round).

## 0.12.1

Redesigned "Modify client" dialog's layout: header preview, labeled field
rows, a logo thumbnail instead of a raw path, and renamed its submit
button.

**User prompt driving this change:** "The 'modify client' window: First
row: bigger logo followed by the name of the client. Name of the client is
bold. Beneath are the same rows but every row starts with string
representing meaning of the field (Logo, Name, Description, username). The
'logo' row additionally to new string 'Logo' also contains preview of
currently selected logo instead of path. Size of this preview is
proportionally correct to the height of the 'Browse' button. When user
selectes new logo it is changed in the preview only. Change the name of
the 'Modify' button to 'Apply'"

**`EditClientDialog.qml` changes:**
- Added a header `RowLayout` above the fields: a `Theme.hugeIconButtonSize`
  (96px) logo image next to the client's name in bold — bound live to the
  same `logoPath` property and `nameField.text` the fields below edit, so
  it previews the change as you type/browse rather than showing a static
  snapshot from when the dialog opened.
- Every field row now starts with a label `Text` ("Logo", "Name",
  "Description", "Username"), all sharing a new `fieldLabelWidth` constant
  (90 * `Theme.uiScale`) so every input starts at the same x regardless of
  its label's length.
- The logo row's raw-path `ValidatedTextField` is gone entirely, replaced
  by an `Image` thumbnail previewing the actual selected file, sized via
  `Layout.preferredHeight: browseButton.height` — i.e. exactly the Browse
  button's own height, not an approximation. Selecting a file via the
  (still-present) `FileDialog` now sets a plain `root.logoPath` string
  property instead of a text field's `.text`, which both this preview and
  the header logo above read from.
- Root gained `property string logoPath` (replacing the removed text
  field as the single source of truth for the path); `openFor()` and
  `finishUpdate()` updated to use it.
- The submit button's label changed from "Modify" to "Apply" (its
  `onClicked` logic — create-user-then-confirm-then-update — is
  unchanged).

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** double-clicked a
client's logo to open the dialog and confirmed, by reading back live
Qt objects: the header shows the client's name in bold (`font.bold`,
`Theme.fontSizeLarge`) at 96×96 next to it; exactly 3 `TextField`s remain
(Name/Description/Username — the old 4th, for the logo path, is gone);
the logo-row preview's height (40px) exactly equals the Browse button's
own height; setting `logoPath` updates *both* image sources (header and
row preview) at once; the button row reads `['Browse…', 'Cancel',
'Apply']`; and a full no-rename Apply still correctly persists an edited
name and the previewed logo path through `ClientListModel`. All 117
existing tests still pass (no Python-side changes this round).

## 0.12.0

Added "modify client" — double-click a client's logo to edit its info,
including a rename flow that creates a new Linux user and asks whether to
keep or delete the old one's content.

**User prompt driving this change:** "excellent. Next, double click on
logo opens 'modifiy client info' dialog window. Offers to change
everything. At the bototm there will be 2 buttons 'Cancel' and 'Modify'.
If the username was changed, application asks in new dialog window whether
the original content for the user should be deleted or not. If yes, it is
removed if not it is kept. But the new user is created (if name was
changed)."

**New QML:**
- `EditClientDialog.qml` — same fields as `AddClientDialog` (logo, name,
  description, username), pre-filled via a new `openFor(username, name,
  description, logoPath)` function (there's no other way to get per-client
  data into a single shared dialog instance the way `AddClientDialog`'s
  `onOpened: reset()` does for a blank one). "Cancel"/"Modify" buttons.
  The username field's live-validation reuses `ValidatedTextField` as
  usual, but its validator treats the *unchanged* username as always valid
  — otherwise editing a client without touching the username field would
  immediately show it as "already taken" (it does exist — as this same
  client), which would be wrong.
- `ConfirmDialog.qml` — small generic reusable themed yes/no popup
  (`message`/`confirmLabel`/`cancelLabel` properties, `confirmed()`/
  `cancelled()` signals), per CLAUDE.md's "favor small, composable
  components": this is the "delete the original user's content?" prompt,
  but built generic enough to reuse for any future confirm step rather
  than one-off inline in `EditClientDialog`.
- `ClientRow.qml`'s logo gained a `TapHandler { onDoubleTapped: ... }`
  (passive, coexists with the existing tooltip `HoverHandler` the same way
  every other passive-handler pairing in this codebase does) firing a new
  `editRequested()` signal, wired in `Main.qml` to
  `editClientDialog.openFor(...)`.

**Rename flow** (`EditClientDialog`'s "Modify" handler): if the username
field is unchanged, just calls the new `clientModel.updateClient(...)`
directly. If it changed: creates the new Linux user first (via
`clientProvisioner.createLinuxUser`, same "verify success before
persisting" rule `AddClientDialog` already follows) — only if that
succeeds does it open the new `ConfirmDialog` asking whether to delete the
*original* user's content. Choosing "Delete" calls a new
`clientProvisioner.deleteLinuxUser(oldUsername)`; choosing "Keep" skips it.
Either way, `clientModel.updateClient(...)` runs afterward with the new
username, so the config is only ever updated once that question has been
answered.

**Backend additions:**
- `config.py`: `ConfigStore.update_client(old_username, name, description,
  new_username, logo_path)` — mutates the existing `ClientEntry` in place
  (rather than remove+re-add) so its `apps` list stays attached across a
  rename.
- `models.py`: `ClientListModel.updateClient(...)` Slot, emitting
  `dataChanged` for `NameRole`/`DescriptionRole`/`UsernameRole`/
  `LogoPathRole`.
- `app.py`: `_ClientProvisioner.deleteLinuxUser(username)`, mirroring
  `createLinuxUser` — runs `pkexec .../delete_user.py USERNAME`.
- `src/scripts/delete_user.py` — new mock script mirroring
  `create_user.py`'s structure exactly (same root-check, same `MOCK_MODE`
  caveat, same argv/exit-code contract): `userdel --remove USERNAME`
  (`--remove` also deletes the home dir, matching "delete the original
  content" rather than just the account entry).

Updated CLAUDE.md with a new "Modifying a client" product-spec section.

**Verification:** `tests/test_config.py` (`update_client` edits fields in
place, keeps `apps` attached across a rename, raises for an unknown
username) and `tests/test_models.py` (`updateClient` Slot, same three
cases) — all pass. `tests/scripts/test_delete_user.py` mirrors
`test_create_user.py`'s full suite (root check, mock-mode command
construction, real-mode subprocess call, failure exit code) — all pass.
Headless (`QT_QPA_PLATFORM=offscreen`) end-to-end QML test: double-clicking
the logo opens the dialog pre-filled with the client's actual name/
description/username; editing just the description and clicking "Modify"
updates it without touching the username; renaming and clicking "Modify"
calls `createLinuxUser` with the new name, opens the confirm dialog, and
choosing "Delete" calls `deleteLinuxUser` with the *old* name while the
config ends up on the *new* one; repeating with "Keep" instead leaves
`deleteLinuxUser` uncalled; the validator allows submitting with the
username field untouched but rejects changing it to another already-taken
name. All 117 tests pass (16 new).

## 0.11.3

Fixed: drag-and-drop reordering of app buttons didn't actually work.

**User prompt driving this change:** "drag & drop does not work" — followed
by, mid-investigation: "more info: when icon is in-between other icons it
starts to move when I move with the mouse while button is pressed down,
but is not move after neighbours."

**Root cause:** every client row lives inside `Main.qml`'s `ScrollView`,
which wraps its content in a `Flickable`. A `Flickable` steals an
in-progress mouse grab from a child `MouseArea` once movement exceeds its
own small internal drag threshold, on the assumption that a drag inside a
scrollable area is meant to scroll it — so a real drag gesture (many small
incremental mouse-move events, exactly what an actual mouse produces) got
its grab silently stolen ~15-20px in, aborting the drag. This is why the
button visually started following the cursor and then stopped dead near a
neighbor: the grab was gone by then, not anything about proximity to
another button.

Root-caused by instrumented headless testing rather than guesswork: a
single large `QTest.mouseMove` jump never reproduced it (`Flickable`'s
steal heuristic needs a short *sequence* of incremental moves to recognize
a scroll gesture, which a single teleport doesn't produce), which is
exactly why earlier verification of this feature never caught it — but
driving the drag with many small steps (matching what dragging with a real
mouse actually generates) reproduced a genuine `MouseArea.canceled` on
every run. Bisected by testing with the tooltip `HoverHandler` removed,
the delete-arm hold-timeline disabled, `ClientRow`'s own drag-reaction
handlers stubbed to no-ops, and even down to a single app button with no
siblings at all — none of those changed the outcome, which is what pointed
at the shared ancestor (`ScrollView`) rather than anything button-local.

**Fix:** `SquareIconButton.qml`'s `MouseArea` now sets `preventStealing:
true` — the standard, documented fix for a draggable `MouseArea` nested
inside a `Flickable`/`ScrollView`.

**Also fixed while here (found by the same investigation, and closer to
CLAUDE.md's actual spec):** the dragged button used to move *itself* to
follow the cursor (`x` bound to a mouse-tracked value once dragging).
Changing an item's own geometry synchronously from within that same item's
own `MouseArea` move handler is fragile independent of the Flickable issue
above. Per CLAUDE.md's product spec — "dragging shows a small translucent
**copy** of the button following the cursor" — the real button now stays
stationary at its slot (just faded via the existing `ghosted` opacity) and
a new, separate, non-interactive `dragGhost` `Rectangle` in `ClientRow.qml`
(no `MouseArea` of its own) is what actually follows the cursor, showing
the dragged app's icon/label. `appsContainer` gained `dragVisualX`/
`dragVisualY`/`dragGhostIcon`/`dragGhostLabel` to drive it.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** reproduced the
original bug with a 30-step incremental `QTest.mouseMove` sequence (5px
per step) — `MouseArea.canceled` fired reliably at ~15-20px on the
unpatched code, both with three app buttons and with just one (ruling out
sibling interference as a factor). After the fix, the same sequence holds
`pressed=True`/`dragging=True` for the entire 155px path with zero
`canceled` events, and the end-to-end reorder (drag app "A" from the first
slot to the last, past "B" and "C") produces the correct final order
`['B', 'C', 'A']`. All 101 existing tests still pass.

## 0.11.2

Fixed: switching theme no longer cancels an armed delete button.

**User prompt driving this change:** "ok I changed the holdTime timeline
as I find it good. Now it is ok. next: - change of theme cannot change
'delete' buttton to original one" (the user had hand-tuned `holdSchedule`
in `SquareIconButton.qml` directly to `[1000, 250, 250, 250, 250]`, which
is left as-is — their own change, not reverted).

**Root cause:** the "click elsewhere cancels an armed delete button" rule
(added in 0.10.0) disarms via each `SquareIconButton`'s own `onPressed` —
pressing *any* other button counts as "elsewhere". The theme toggle is
itself a `SquareIconButton`, so clicking it to switch dark/light was
unintentionally treated the same as clicking any app button, silently
canceling whatever delete confirmation was in progress on a different
button.

**Fix:** new opt-out property `cancelsOtherArmedButton` (default `true`,
preserving the existing behavior everywhere else) — `onPressed`'s
disarm-other-buttons logic now checks it first. Set `cancelsOtherArmedButton:
false` on the theme toggle's instantiation in `Main.qml`: switching theme
is an incidental display preference, not an action on any particular app,
so it shouldn't cancel an in-progress delete confirmation elsewhere.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** armed a button
by holding it through its full `holdSchedule`, clicked the theme toggle,
and confirmed `armedForDelete` stayed `true`. As a regression check,
clicking a *different app* button afterward still correctly disarmed it
(`false`) — the general click-elsewhere rule still works for every button
except this one deliberate exception. All 101 existing tests still pass.

## 0.11.1

Replaced the arm-delay/blink-cadence pair with a single fixed timeline
that always ends in a deliberate, predictable state.

**User prompt driving this change:** "ok, I played a little bit with times
for 'delete appear' duration and 'blinking interval'. Let's change the
behavior: do not make it last 'x' seconds (1500 right now) and meanwhile
blink it, change the behavior this way: 1) wait 150 ms 2) if there is no
button down (eg we can assume user not want to click on item, but delete
it) blink 3 times with period 500 ms. So the effect timeline is: (I =
originl icon, D = delete icon): I 150ms D 500ms I 500ms D 500ms I 500ms D
500 ms I 500 ms D This way I will always 'end' on 'Delete'. The
cancellation will be mirroring this, eg it always end on original icon."
(The user had been hand-tuning the previous version's separate 1000ms
arm-timer and blink-timer intervals directly in the file — up to 1500ms —
before asking for this replacement.)

**Implementation:** replaced the previous two-timer design (a fixed-
interval `armTimer` for the real arm/disarm plus a separately-tuned
`blinkTimer` layered visually on top) with one `holdTimer` that walks a
`holdSchedule` array of phase durations: `[150, 500, 500, 500, 500, 500,
500]`. Each firing advances a `holdPhase` counter and toggles
`blinkShowTarget`; reaching the end of the array (the 7th transition) is
now the actual arm/disarm commit — not a separate fixed duration racing
against the blink cadence. `visualArmed` (unchanged from 0.11.0) already
alternates between the current `armedForDelete` value and its opposite,
so the mirrored cancellation timeline ("always ends on original icon")
falls out of the exact same code with no special-casing — only
`armedForDelete`'s starting value differs.

Net visible effect for arming (holding a normal button, `I` = normal
icon, `D` = trash bin): `I` for 150ms, then `D`/`I` alternating every
500ms three times, landing permanently on `D` at the 3.15s mark — matching
the user's timeline exactly, verified tick-by-tick (see below). Holding an
already-armed button mirrors it and lands on `I`.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** held a button
and sampled `visualArmed` at 23 checkpoints spanning the full 3150ms
schedule (just inside and just outside every phase boundary: 150, 650,
1150, 1650, 2150, 2650, 3150ms). 22 of 23 matched exactly; the one
"mismatch" was 1ms of Qt timer-scheduling jitter at the 149ms checkpoint
(fired at 149ms instead of 150ms), not a logic error. Confirmed
`armedForDelete` lands `true` at the end. All 101 existing tests still
pass.

## 0.11.0

Delete-gesture polish: hover feedback on the armed trash-bin button, a
bigger trash icon, and mid-hold blink feedback in both directions.

**User prompt driving this change:** "add 'hover on' effect even for
'delete' action - make the trashbin bigger by 60% - when the press event
takes longer than 200ms start animate the button icon to indicate that
sometthing is going on. For example the icon blinks (interval 500ms
'shown' for every icon) between itself and red delete button and when
blinking ends, it is 'ready for delete'. The same for the opposite action
(cancellation), but the end state is 'original button'"

**Hover-on-delete:** the armed (trash-bin) button previously rendered a
flat `Theme.danger` red in every state — no hover feedback at all, unlike
every other button state. Added `Theme.dangerHover` (a lighter red in dark
mode, darker/more saturated in light mode — same "push further from the
background" direction as the existing `surface`/`surfaceHover` pair), and
`SquareIconButton`'s `color` binding now uses it while the mouse is over an
armed button.

**Bigger trash icon:** the trash-bin `Text`'s `font.pixelSize` is now
`Theme.iconGlyphSize * 1.6` (60% bigger), independent of the shared token
used by the normal letter-fallback glyph, which is unchanged.

**Mid-hold blink feedback:** two new `Timer`s — `blinkDelayTimer` (200ms,
one-shot) and `blinkTimer` (500ms, repeating) — plus `blinking`/
`blinkShowTarget` properties driving a new `visualArmed` computed property.
The first 200ms of any hold on a deletable button show nothing special
(still could just be a quick click); past that, the button alternates
every 500ms between its current appearance and the one it's heading
toward, in *either* direction — arming (normal -> trash bin) or the
"opposite action" of disarming (trash bin -> normal) — since both are
driven by the same symmetric `visualArmed = blinkShowTarget ?
!armedForDelete : armedForDelete` while blinking. Every appearance-driving
binding (button color, icon/label/trash-bin visibility, tooltip
suppression) now reads `visualArmed` instead of `armedForDelete` directly,
so the blink actually shows on screen. `armTimer`'s own completion (the
real 1-second arm/disarm) stops the blink and lands on the correct steady
end state — "ready for delete" or "original button" — with no extra
wiring, since `visualArmed` collapses back to the plain `armedForDelete`
value once `blinking` is false. Moving off the button mid-hold, releasing
early, a canceled gesture, or a drag starting all stop the blink the same
way they already stopped `armTimer`.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** held a button
and sampled `blinking`/`visualArmed`/`armedForDelete` every 50ms across a
full 1100ms hold in both directions (arming from unarmed, then disarming
from armed): confirmed no blinking before 200ms, alternation every ~500ms
after that, and the timer landing on the correct final state at the
1000ms mark in each direction. Read back the trash icon's actual `QFont`
pixel size (32) against the letter glyph's (20) — exactly 60% bigger.
Compared the button's live `color` while hovering an armed button
(`#ff7088`, `Theme.dangerHover`) against not hovering it (`#ff5470`,
`Theme.danger`) after letting the color `Behavior` animation settle. All
101 existing tests still pass.

## 0.10.0

Delete gesture is now a deliberate two-step confirm instead of
release-to-delete, with explicit cancel paths.

**User prompt driving this change:** "the delete operation. When button
changes to delete and user release the mouse button, do not immediately
delete the item. Operation needs to be actually executed by mouse click.
So the scenario is: 1. Button 2. User presses mouse (mouse down) but it is
not click 3. after 1 second, button is changed to 'delete' button 4. User
releases mouse 5. user clicks on button -> item is removed (no dialog
window, user should know what he is doing) 'Delete cancel operations' A)
user clicks elswhere -> button is changed back to its original, it is no
longer delete button. B) user presses ESC (and application has focus) ->
same as 5.1 C) user presses mouse (mouse down) byt it is not click -> after
1 second (while the mouse curosor is on the button) button is turned back
to its original state"

**Behavior change:** `SquareIconButton.armedForDelete` now persists past
mouse release instead of only meaning "release now to delete." The
1-second hold `Timer` toggles it (`root.armedForDelete = !root.armedForDelete`)
rather than only ever setting it `true`, so holding a second time while
already armed disarms it again (cancel C) — the same timer naturally
implements both directions. A short click (release before the timer fires)
now means two different things depending on whether the button was already
armed at the moment the press started (captured in a new
`armedAtPressStart` snapshot, since the live value can flip mid-press):
delete-confirm if it was armed, or the normal click/launch action
otherwise.

**New: `DeleteArmState.qml`** — a small singleton (registered in `qmldir`
next to `Theme`) holding `armedButton`, the one app button (if any)
currently showing its trash-bin icon app-wide. `SquareIconButton` keeps it
in sync via `onArmedForDeleteChanged`. This is what makes "click elsewhere"
work without every button needing a reference to every other one:

- Clicking a *different* button: each button's own `onPressed` disarms
  whatever `DeleteArmState.armedButton` currently is (if it isn't itself)
  — covers cancel A for clicks landing on another button.
- Clicking empty background: `Main.qml` gained a background `MouseArea`
  (filling `glassPanel`, declared beneath the real content so any button's
  own `MouseArea` still wins at its own coordinates) that calls
  `DeleteArmState.disarmAny()` — the other half of cancel A.
- Pressing Escape: a new `Shortcut { sequence: "Escape"; context:
  Qt.ApplicationShortcut }` in `Main.qml` calls `DeleteArmState.disarmAny()`
  — cancel B.
- Holding the same button again for a second: the toggling timer above —
  cancel C.

`SquareIconButton.qml`'s `onExited` no longer resets `armedForDelete` on
its own — moving off mid-hold now only cancels *that specific hold*
(stops the timer) without touching whatever the button's armed state
already was, since hovering away with no press active isn't one of the
three cancel rules above.

Updated `CLAUDE.md`'s "Main window" spec (previously described immediate
release-to-delete) to document the armed state, the click-to-confirm step,
and all three cancel paths.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** built a
two-client model, drove real press/wait/move/release/click sequences via
`QTest`, and read back `armedForDelete` plus the model's actual app list
after each step. Confirmed: (1) holding 1s then releasing arms the button
without deleting anything; (2) a subsequent click on the still-armed
button deletes it and the delegate is gone from the tree; (3) clicking a
different button (theme toggle) disarms an armed one; (4) Escape disarms
it; (5) holding the same button a second time disarms it without deleting;
(6) a plain quick click on a non-armed button still launches the app
normally; (7) clicking empty background disarms it; (8) moving off mid-hold
cancels only that hold, leaving the button unarmed as it started. All 8
scenarios matched expectations, and all 101 existing tests still pass.

## 0.9.2

Added a top-level `README.md`.

**User prompt driving this change:** "Create short README file which
describes intention of the application (not how it is used). At the
beggining add title ClientDeck and beneath 2 screenshots in a row:
`docs/cd-dark.png` and `docs/cd-light.png`"

Written for: anyone landing on the repo who wants to know *why* ClientDeck
exists before reading any code — deliberately about intent/motivation
(the client-isolation problem it solves and why a per-user launcher instead
of VMs/containers) rather than setup or usage instructions, per the
request. Screenshots (`docs/cd-dark.png`, `docs/cd-light.png`, both already
present in the repo) are placed side by side right under the title via a
two-column `<img width="49%">` pair.

## 0.9.1

Fixed misaligned first button on rows with zero apps.

**User prompt driving this change:** "first buttons after company logo in
different rows should be left aligned. Currently application button is
little bit more left than '+' button (see screenshot)" — a screenshot
showed a row with 3 apps and a row with none, and the empty row's "+" sat
visibly further right than the first app button of the populated row.

**Root cause:** `ClientRow.qml`'s `appsContainer` (the `Item` wrapping the
per-app `Repeater`) reports `implicitWidth: 0` when a client has no apps,
but it's still a normal `RowLayout` child — `RowLayout` reserves its
`spacing` on *both* sides of every child regardless of that child's size,
even a zero-width one. So an empty row got logo → spacing → (0-width
container) → spacing → "+", i.e. two spacings' worth of gap, while a
populated row got logo → spacing → first app button, i.e. one. That extra
reserved spacing was the "little bit more left" offset.

**Fix:** `appsContainer` now sets `visible: root.apps.length > 0`.
`RowLayout` excludes invisible children from layout entirely (no reserved
spacing at all), which is exactly what's needed for the zero-apps case —
confirmed in Qt's own Layout docs, not assumed.

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** built a model
with one client with 3 apps and one with none, loaded `Main.qml`, and read
back each button's actual scene-space `x` via `mapToScene`. Before the fix
this wasn't run (bug came from a user screenshot); after the fix, the first
button after the logo lands at the same `scene_x` (84.0) in both rows —
app button "A" in the populated row and the "+" in the empty row are now
pixel-exact aligned. All 101 existing tests still pass.

## 0.9.0

Themed hover tooltips on every icon button — function buttons describe what
they do, app-launcher buttons show the app's name.

**User prompt driving this change:** "Add custom tooltips for every button
describing either its function or application name if it is application
starter."

**Implementation:** reused the existing `ThemedTooltip.qml` component
(already used for the client logo's hover tooltip in `ClientRow.qml`)
rather than building a second tooltip mechanism. Gave `SquareIconButton`
(the shared component behind every icon button in the app) two new opt-in
properties:

- `tooltipText` — the text to show; empty by default, so a caller that
  doesn't set it just gets no tooltip.
- `tooltipAbove` — flips the tooltip to render above the button instead of
  below. The bottom toolbar (theme toggle, zoom +/-, reset) sits at the very
  bottom edge of the borderless window, so a tooltip below it would render
  past the window's own edge and never actually be visible; every other
  button has room below it, so this defaults to `false`.

A `HoverHandler` (passive, doesn't grab events — coexists with the button's
existing `MouseArea` the same way it already does for the logo tooltip)
drives `ThemedTooltip.visible`, additionally suppressed while the button is
armed-for-delete or mid-drag so the tooltip never fights the trash-bin icon
or drag ghost for attention.

Wired at each call site:

- `Main.qml`: both "add client" `+` buttons ("Add client"), theme toggle
  ("Switch to light/dark theme", dynamic on current state), zoom `+`/`-`
  ("Zoom in"/"Zoom out"), reset ("Reset zoom") — the four toolbar buttons
  set `tooltipAbove: true`.
- `ClientRow.qml`: each per-app `SquareIconButton` gets `tooltipText:
  modelData.name` (the "application name if it is application starter"
  case), and the row's "+" gets "Add application".

**Scoped deliberately to icon-only buttons:** the dialogs' plain text
`Button`s (Cancel/Add/Browse/"Custom command") already show their function
as their own visible label, so a tooltip there would just repeat text
already on screen — left alone rather than adding redundant UI per
CLAUDE.md's "don't add features beyond what's needed."

**Verification (headless, `QT_QPA_PLATFORM=offscreen`):** loaded `Main.qml`
with a mocked client/app list and confirmed, via direct property
inspection, that all 8 live `SquareIconButton`s in the tree carry the
expected `tooltipText`/`tooltipAbove` values (including the dynamic theme
label). Located each button's `QQuickHoverHandler` and `ThemedTooltip`
child by `metaObject().className()` (plain `type(obj).__name__` reports a
generic `QObject` for these — PySide6 doesn't expose an internal-QML-type
wrapper class, but the meta-object still carries the real QML type name)
and drove them with `QTest.mouseMove`: hovering the "Terminal" app button's
center flips its `HoverHandler.hovered` to `True` and its tooltip's
`visible` to `True` with `title == "Terminal"`; moving away flips both back
to `False`; hovering the "Zoom in" toolbar button confirms its tooltip
renders at a negative `y` (above the button, not below, per
`tooltipAbove`). All 101 existing tests still pass.

## 0.8.0

Major client-row overhaul: no more hardcoded/builtin apps, icons fill
their buttons, hold-to-delete, and full drag-and-drop reordering.

**User prompt driving this change:** "- make the icon fill the button with
margin 4px. - also add icons for terminal (use gnome-terminal icon),
visual studio code, codex and docker - when mouse button down (push) is
pressed on the button and mouse does not move away from the area of
button, turn the icon into trash bin and change the color to visually
appealing red. If the user presses this button now (trsah bin) application
is erased from the list (row). - User can drag & drop the the button and
rearrange the buttons in the row - While 'dragging' the small transparent
icon of the application is shown and when moved, existing buttons shifts
to show with priperly colored placeholder where the drop will potentially
land. - Remember that application (button) can be moved to be first or
last too"

**Scope clarified before implementing** (asked, since two readings were
genuinely consequential): the user confirmed there should be **no
hardcoded/builtin apps at all** — "Every application should come from
'add application' menu, no builtins." Terminal, VS Code, Claude Code,
Codex, Docker are just examples of apps a user adds, not fixed buttons.
Also confirmed the delete gesture is long-press (~1s, not instant) so a
plain click still launches, and drag-and-drop only ever applies to app
buttons (there being no other kind left in the row).

**Architecture change — no more builtins:**

- Removed `app.py`'s `BUILTIN_COMMANDS` dict and `_AppLauncher.launchBuiltin`
  entirely; `launchCustomApp` renamed to `launchApp` (no more "custom" vs.
  builtin distinction to name around).
- Removed `ClientRow.qml`'s three hardcoded terminal/VS Code/Claude
  `SquareIconButton`s and the `launchBuiltin` signal — every app button now
  comes from the same `Repeater` over `client.apps`.
- Updated `CLAUDE.md`'s product spec (main window + launching-apps
  sections) to match — it previously described terminal/VS Code/Claude as
  fixed row buttons, which is now wrong; CLAUDE.md is supposed to be the
  durable source of truth, so a live correction like this gets written
  back into it, not left stale.

**Icon fills the button (4px margin):** `SquareIconButton`'s icon `Image`
now uses `anchors.fill: parent; anchors.margins: Theme.iconMargin` (a new
token, `4 * uiScale`) instead of a small fixed size centered in the
button. The fallback letter glyph is unchanged (a giant single letter
filling the whole button wasn't asked for and looked worse in a quick
visual check).

**Manual entry gets an icon field:** since there are no builtins, an app
like Docker (which typically has no launchable `.desktop` entry) can now
only get an icon by being added manually with one — `AddAppDialog.qml`'s
custom-command form gained an "Icon name or path (optional)" field,
closing the gap flagged as "known, not addressed" in 0.7.3.

**Hold-to-delete:** `SquareIconButton` gained opt-in `deletable`
(off by default — only `ClientRow.qml`'s app buttons turn it on, so
nothing else like the theme/zoom/dialog buttons is affected). Holding the
mouse down in place for 1 second arms it: the icon becomes 🗑 and the
button turns `Theme.danger` red; releasing while still hovering removes
the app (`ClientListModel.removeAppFromClient`, backed by a new
`ConfigStore.remove_app`); moving off before releasing cancels with no
effect (or becomes a drag instead — see below, since these buttons are
also draggable).

**Drag-and-drop reordering:** also opt-in (`draggable`) on
`SquareIconButton`, which now reports `dragStarted`/`dragPositionChanged`/
`dragFinished` signals once mouse movement exceeds an 8px threshold
(distinguishing a drag from a plain click or a delete-hold). `ClientRow.qml`
replaced its app-button `Repeater` (previously inside a `RowLayout`) with
one inside a plain `Item`, computing each delegate's `x` by hand — needed
because reordering means a button's on-screen slot must sometimes differ
from its data index (while a drag is in progress), and a real `RowLayout`
would just override any such positioning itself. While dragging: the
dragged button follows the cursor continuously at 50% opacity ("small
transparent icon"), the other buttons animate into the slots they'd
occupy if dropped now, and an accent-tinted, rounded placeholder
`Rectangle` marks the target slot — including the very first or very last
position. On drop, `ConfigStore.move_app`/`ClientListModel.moveApp`
commits the new order.

**Two real bugs found and fixed while verifying this (not caught by
just re-reading the QML):**

1. **`findChildren()` cannot see `Repeater`-created delegates at all** —
   discovered while writing the verification script for this change, not
   a bug in the shipped app, but worth recording since it invalidated the
   *test methodology* used successfully in several earlier changelog
   entries for anything *not* inside a `Repeater`. Confirmed with a
   minimal reproduction: `Repeater { model: 3; delegate: Rectangle {} }`
   directly inside a `Window` produces zero results from
   `window.findChildren(QQuickItem)` even after processing events and
   waiting, while `window.contentItem()`'s `childItems()` (the *visual*
   tree, walked recursively) finds all of them correctly. Every
   verification script in this session from this point on that needs to
   locate a Repeater-generated item uses `childItems()` instead.
2. **`ReferenceError: appsContainer is not defined` inside
   `onDragFinished`**, a real bug, only surfaced by actually completing a
   drag end-to-end: calling `root.moveAppRequested(...)` round-trips
   synchronously into Python and back (`clientModel.moveApp()` →
   `dataChanged` → the `Repeater`'s `model: root.apps` binding
   re-evaluates), which can destroy and recreate every delegate —
   *including the one whose own handler is still executing* — before that
   handler's remaining statements run. Fixed by capturing the needed
   values into local variables and resetting `appsContainer`'s shared
   drag state *before* the `moveAppRequested()` call, so nothing runs
   afterward that could reference a since-destroyed delegate.

**Verified end-to-end**, using the `childItems()`-based technique above,
against a client with 4 apps (3 with real resolvable icons, 1 without):

1. Icon-fill: screenshot confirms icons now visibly fill their buttons
   (vs. a small centered icon before).
2. Hold-to-delete: held a button for 1.2s, confirmed
   `armedForDelete === true` and a screenshot showing the red trash-bin
   state, released while still hovering, confirmed the app was actually
   removed from the client's data (`store.get_client(...).apps`).
3. Drag-and-reorder: performed two separate drags via simulated
   press → move → move → release sequences, confirming the underlying app
   order changed correctly both times (checked against the real
   `ConfigStore` data, not just visually) — including landing a dragged
   button in a new first/middle/last position.
4. Confirmed no QML errors/warnings across multiple repeated headless runs
   of the real app after all these changes.

**Not fully captured, flagged rather than assumed correct:** the
intermediate "ghost following the cursor + placeholder at the target slot"
visual, *while* a drag is actively in progress, wasn't cleanly
frozen mid-motion by the scripted `QTest` event sequence used here (by
the time a screenshot/property check ran, the simulated drag had already
resolved) — the underlying `displaySlot`/`dropIndex` binding logic was
hand-verified against worked examples and the *before/after* reordering
was confirmed correct twice, but the live mid-drag visual specifically
needs a real mouse to confirm.

Scripts and screenshots were throwaway — deleted after verification, not
committed.

**Needs manual, on-host verification:** the mid-drag ghost/placeholder
visual specifically (per the note above), and general "does this feel
good" polish for the hold-to-delete timing and drag responsiveness that
only a real trackpad/mouse can judge.

## 0.7.3

Client-row app buttons now actually show the app's icon — the display
logic for this already existed (letters only as a fallback), but the
icon was never being saved when an app got added, so every button always
fell into the fallback.

**User prompt driving this change:** "Now, when application is added, use
letters on the button only for those without icon. For the rest use the
application icon for the button content."

**Root cause:** `ClientRow.qml`'s `Repeater` delegate already had
`iconSource: modelData.icon || ""` / `label: modelData.icon ? "" : ...`
— the icon-vs-letter fallback logic — and `AppEntry`/the model's
`AppsRole` already carried an `icon` field. But
`ClientListModel.addAppToClient()` never set it on the new `AppEntry` at
all, and `AddAppDialog.qml`'s call to it never passed one — so `icon` was
always `None` for every app ever added, regardless of whether the source
`.desktop` file had one.

What changed:

- `ClientListModel.addAppToClient()`: added an `icon: str = ""` parameter,
  stored on the new `AppEntry` (`icon=icon or None`).
- `AddAppDialog.qml`: the "pick existing" click handler now passes
  `modelData.icon` through (the manual/custom-command path still passes
  none, since that form has no icon field — letters remain correct there,
  matching "only for those without icon").
- `ClientRow.qml`: the `iconSource` binding now resolves a bare icon-theme
  name the same way `AddAppDialog.qml`'s own list already does
  (`"image://theme/" + icon` when it's not an absolute path) — needed
  because `SquareIconButton`'s icon is a plain `Image`, not routed through
  Qt Quick Controls' icon system, so it never automatically picked up the
  `image://theme/` scheme on its own.

**Verified end-to-end**, not just re-reading the code: called
`clientModel.addAppToClient(...)` (the exact call the dialog makes) with
one app carrying a real icon name ("gwenview") and one without, then
screenshotted the resulting `ClientRow` — the Gwenview button shows its
actual pink/white icon, the icon-less "Custom Script" button shows "C".
Script and screenshot were throwaway — deleted after verification, not
committed.

**Known, pre-existing gap, not addressed here** (out of scope for this
request): CLAUDE.md's original "add app" spec calls for a manual
custom-command entry to include "plus an icon" — that field was never
built, so manual entries will always show a letter. Flagging it here in
case it's wanted later, rather than silently leaving it unexplained.

## 0.7.2

Three real bugs in the "Add app" dialog, found from actual on-host usage:
white-only icons, zoom not working while the dialog is open, and
non-Application `.desktop` entries leaking into the list.

**User prompt driving this change:** "The 'Add application' dialog: -
icons (most of them, it seems those which were missing) are white and
only white - zoom in does not work on that dialog - also items which were
not actuall applications were on the list (I expected to see only entries
which .desktop Type equals to 'Application')"

**Bug 1 — icons rendering as solid white silhouettes.** Qt Quick
Controls' `icon.color` grouped property, when not `"transparent"`,
treats the icon as a single-tone "symbolic" mask and recolors every
non-transparent pixel to that one color — the Basic style's `ItemDelegate`
default isn't transparent, so every real multi-color app icon (0.7.1's
fix, which made icons resolve at all) was being flattened to a solid
silhouette. Fixed with one line: `icon.color: "transparent"` on the
delegate in `AddAppDialog.qml`. Confirmed via screenshot: Granatier's
black bomb, Gsmartcontrol's gray drive, Gummi's green "G", Gwenview's
pink eye — all now render in their real colors, not white blobs.

**Bug 2 — Ctrl+/Ctrl- not working while the dialog is open.** The zoom
`Shortcut` items in `Main.qml` used the default `Qt.WindowShortcut`
context, which apparently doesn't count a focused modal `Popup`'s content
as "the window" for shortcut matching — so the shortcuts silently did
nothing while `AddAppDialog`/`AddClientDialog` had focus. Changed both to
`context: Qt.ApplicationShortcut` (fires regardless of which window/popup
currently has focus, as long as the app itself is active). Confirmed via
screenshot: two `Ctrl++` presses sent via `QTest.keyClick` while the
dialog was open and focused visibly grew its title, search field, icons,
and text.

**Bug 3 — non-Application entries in the discovered-apps list.**
`desktop_apps.py`'s `_parse_desktop_file` used
`section.get("Type", "Application")` — defaulting a *missing* `Type=` key
to `"Application"`. `Type=` is a required key per the Desktop Entry
Specification; a file that omits it isn't a valid, well-formed
Application entry and shouldn't be treated as one just because it's the
common case. Changed to `section.get("Type") != "Application"` (no
default) — a `.desktop` file must explicitly declare
`Type=Application` to be listed now. Added a test for a `.desktop` file
with no `Type=` line at all, confirming it's now excluded (previously it
would have been wrongly admitted).

Script and screenshots for bugs 1 and 2 were throwaway — deleted after
verification, not committed.

## 0.7.1

Real fix for `image://theme/<name>` icon resolution — 0.7.0 correctly
guessed this mechanism but never actually verified it worked, and on a
real host it didn't.

**User prompt driving this change** (pasted real error output from running
the app): "I see errors like: ... QML IconImage: Invalid image provider:
image://theme/granatier ... gsmartcontrol ... gummi ... gwenview ...
help-browser"

**Root cause, found in two layers:**

1. Qt does not register a `"theme"` image provider automatically for a
   plain `QGuiApplication`/`QQmlApplicationEngine` app — 0.7.0's
   `AddAppDialog.qml` referenced `image://theme/<name>` assuming one
   existed, which was never actually confirmed (flagged as an assumption
   in that entry, and it was wrong).
2. Even after registering a real provider backed by `QIcon.fromTheme()`,
   icons still failed: `QIcon.themeSearchPaths()` defaults to just
   `[":/icons"]` (an empty Qt resource path) — real filesystem
   directories like `/usr/share/icons` are only added by Qt's own
   platform-theme integration, which isn't guaranteed to run. Confirmed
   by direct experiment in this sandbox: `QIcon.fromTheme("gsmartcontrol")`
   came back null even though `/usr/share/icons/hicolor/48x48/apps/gsmartcontrol.png`
   exists on disk, until the standard search paths were added explicitly.

What changed:

- New `clientdeck/icon_provider.py`:
  - `ThemeIconProvider` (a real `QQuickImageProvider`), registered via
    `engine.addImageProvider("theme", ...)` in `app.py`.
  - `ensure_icon_theme_configured()`, called once at startup: additively
    appends the standard XDG icon directories
    (`/usr/share/icons`, `/usr/local/share/icons`, `~/.local/share/icons`,
    `~/.icons`) to whatever Qt already had, and sets the theme name to
    `"hicolor"` (the universal freedesktop base theme) only if nothing
    was already auto-detected — never overrides a correctly-detected
    real theme.
  - `resolve_theme_pixmap()` additionally falls back to
    `/usr/share/pixmaps/<name>.{png,xpm,svg}` (the legacy freedesktop
    fallback location, outside the theme-directory hierarchy) when the
    theme lookup itself comes back empty — found by testing with the
    user's own exact reported names: "gummi" only ships an icon there,
    nowhere in the theme hierarchy at all.
- 8 new unit tests covering `ensure_icon_theme_configured()`'s
  additive/non-destructive behavior and `resolve_theme_pixmap()`'s
  fallback chain, all via mocked `QIcon` static methods (no real Qt
  image/theme machinery touched, so no QPA platform needed to run them).

**Verified with the user's own exact reported icon names**, not
synthetic ones — "granatier", "gsmartcontrol", "gummi", "gwenview",
"help-browser" — via the same offscreen-screenshot technique as previous
entries, plus direct `QIcon.fromTheme()` experiments to find the actual
root cause rather than guessing:

- Before any fix: all 5 failed with "Invalid image provider" (no
  provider registered at all — the 0.7.0 bug).
- Provider registered alone: "Invalid image provider" gone, replaced by
  "Failed to get image from provider" for all 5 (provider found, but
  `QIcon.themeSearchPaths()` was still just `[":/icons"]`).
- Provider + search paths + hicolor fallback: 3/5 render
  ("granatier", "gsmartcontrol", "gwenview" — confirmed via a real
  screenshot showing their actual icon thumbnails).
- Provider + search paths + hicolor fallback + pixmaps-dir fallback: 4/5
  render (adds "gummi", confirmed via screenshot).
- "help-browser" remains unresolved in *this sandbox specifically* — it
  exists only in richer themes (breeze, Humanity), not in the bare
  "hicolor" fallback this sandbox has no live desktop session to improve
  on, and has no pixmaps-dir fallback either. On a real desktop session
  (which the user is actually running), Qt's platform integration should
  auto-detect the real active theme (e.g. breeze on KDE Plasma) — which
  does have "help-browser" — making this a sandbox-only gap, not
  something expected to reproduce for the user. Documented here rather
  than silently left unexplained.

Script and screenshots were throwaway — deleted after verification, not
committed.

**Needs manual, on-host verification:** confirm all 5 of the originally
reported icon names (and others) now render correctly in the real app on
the user's actual KDE Plasma session — the sandbox verification above is
strong evidence but was run without a live desktop session/theme, which
is exactly the gap this fix targets.

## 0.7.0

"Add application" dialog: app icons in the discovered-apps list, and a
search/filter box below the title.

**User prompt driving this change:** "The \"Add application\" dialog
window - put application (if exists) icon in front of the name and bellow
'add application' add input box for context search. Put little lup into
it and text 'Application name\" (both will serve as help / placeholder.
once focused they'll disappear and reapear when lost focus and nothing
else is written)"

What changed:

- `AddAppDialog.qml`: each discovered `.desktop` app's row now sets
  `icon.source` (using `ItemDelegate`'s built-in icon+text layout, not a
  custom one) from its `Icon=` value — used directly as a file path when
  it's absolute, otherwise resolved via `image://theme/<name>`. When the
  icon is empty or doesn't resolve, no icon shows (no broken-image
  placeholder) — matches "if exists."
- New reusable `ThemedSearchField.qml` (registered in `qmldir`): a themed
  text field with a magnifying-glass icon + hint text ("Application
  name" here) that hide the moment the field gains focus — even while
  still empty — and only reappear once focus is lost *and* the field is
  still empty. This is deliberately different from the standard
  `placeholderText` behavior (which stays visible whenever a field is
  empty, focused or not), per the exact behavior requested.
- **Named `ThemedSearchField`, not `SearchField`**: Qt 6.7+'s
  `QtQuick.Controls` styles (Basic included) already ship their own
  built-in `SearchField` type. Since `AddAppDialog.qml` explicitly
  `import`s `QtQuick.Controls.Basic`, that explicit import silently won
  the name collision over this file's implicit same-directory
  availability — the failure mode was "Cannot assign to non-existent
  property hintText" (Qt's own `SearchField` obviously has no such
  property), which only made sense once traced to two different
  `SearchField` types existing in the same lookup. Confirmed by loading
  the file directly by path (worked fine) versus resolving it by name
  from `AddAppDialog.qml` (failed) — same file, different outcome,
  which is what pinned down the collision as the actual cause rather
  than a bug in the component itself.
- Typing in the search field filters the discovered-apps list by a
  case-insensitive substring match on name.

**Verified visually, including the actual failure/fallback paths, not
just the happy path** — built a fake `desktopAppsProvider.discover()`
returning 4 apps: two with a real icon file path, one with an empty
`icon`, and one with a bogus icon-theme name that doesn't resolve.
Screenshots confirmed: the two real-path apps show their icon, the empty
one shows none, and the unresolvable theme name logs Qt's own "Invalid
image provider" warning but renders with no icon and no crash — exactly
the "if exists" fallback. Also confirmed: hint (icon+text) visible when
empty and unfocused; disappears the instant the field is clicked into,
while still empty; typing "FIRE" filters the 4 apps down to the two
Firefox entries (case-insensitive match confirmed); hint stays hidden
with text present. The one combination not directly screenshotted
(unfocused *and* empty *after* having been focused) follows from the same
`visible: !activeFocus && text.length === 0` binding already confirmed
correct in both of its terms individually via the other three states —
not tested via an actual blur event because forcing focus away from a
`Popup`'s content in this offscreen test harness didn't behave like a
real click-elsewhere would. Script and screenshots were throwaway —
deleted after verification, not committed.

**Needs manual, on-host verification:** confirm the magnifying-glass
emoji (🔍) renders reasonably (not as a "missing glyph" box) on the
target system's fonts, and confirm the untested blur-while-empty
combination for real by clicking into the search field, then clicking
elsewhere in the dialog while it's still empty.

## 0.6.3

Light theme softened — no more literal pure white.

**User prompt driving this change:** "The light theme, make a little bit
less \"full white\""

What changed (`Theme.qml`, light-mode values only — dark theme
untouched):

- `surface` (buttons, dialog backgrounds): `#ffffff` → `#f2f3f6`.
- `surfaceHover`: `#eef0f4` → `#e6e8ed` (nudged down to stay a visibly
  distinct step from the now-slightly-darker `surface`).
- `glassPanelBase` (the main window's own translucent panel):
  `rgba(0.965, 0.972, 0.984)` → `rgba(0.93, 0.938, 0.953)`.

**Verified visually**: grabbed screenshots of both themes (dark
unaffected, confirmed side-by-side) — light now reads as a soft muted
gray rather than stark white, buttons remain clearly distinguishable from
the background, text stays readable. Screenshot script deleted after
verification, not committed.

## 0.6.2

Window sizing now actually respects content boundaries — the client
rows, not just the toolbar — and the reset button no longer force-resizes
the window.

**User prompt driving this change:** "zoom in does not expand the window.
zoom out, makes the icons smaller which is ok, but hit on reset button
expands the window albeit there is no reason too. active window resizing
does not respect content boundaries."

**Root cause:** 0.6.1's `minimumWidth` only accounted for the bottom
toolbar's 4 fixed buttons — it never looked at the actual client rows at
all. So zooming in on a client with enough buttons to need more horizontal
room never grew the window (nothing was watching that), while the reset
button unconditionally forced the window to a hardcoded 900×500 default
regardless of whether that was actually needed — which could *look like*
unwanted growth if the window happened to be smaller than 900 at the time
(e.g. after a manual resize) for reasons unrelated to what content
actually required.

What changed:

- **Client list is no longer a virtualizing `ListView`** — switched to a
  `Repeater` inside a plain `ColumnLayout`, wrapped in a `ScrollView` for
  scrolling. This isn't cosmetic: a `ListView` only instantiates
  currently-visible delegates and doesn't propagate their natural size to
  its own `implicitWidth` at all, so there was no reliable way to ask "how
  wide does the widest visible client row actually need to be" — a
  `ColumnLayout`'s `implicitWidth` correctly and reactively aggregates its
  children's implicit sizes, which is exactly what's needed here. Not
  virtualizing is fine for this app's actual scale (a personal/small-team
  client list, not a large dataset).
- `Main.qml`'s `minimumWidth` is now `Math.max(toolbar width, widest
  client row's implicitWidth) + margins` — actually reactive to content,
  not just the toolbar. `minimumHeight` stays toolbar-only deliberately:
  vertical overflow scrolls (that's what the `ScrollView` is for), there's
  no equivalent horizontal scrolling for an over-wide row, so only width
  needs the window itself to grow.
- **Reset button no longer touches window size at all** — it now only
  calls `Theme.resetZoom()`. Window size changes go through the exact same
  `onMinimumWidthChanged`/`onMinimumHeightChanged` grow-only-if-needed
  logic as any other zoom change, so resetting scale can grow the window
  if the scale-1.0 minimum genuinely exceeds the current size, but never
  forces it to some unrelated fixed value the way the removed
  `Math.max(defaultWidth, ...)` call did. Removed the now-unused
  `defaultWidth`/`defaultHeight` context properties from `app.py` — the
  reset button no longer needs a notion of "the app's default size"
  separate from whatever's actually needed.
- Reset button's `enabled` simplified to `Theme.uiScale !== 1.0` (was also
  comparing window size against the now-removed default-size properties).

**Verified empirically with content specifically constructed to exercise
this** — a client with 14 apps, wide enough to need real growth (not the
earlier tests' single terminal/vscode/claude buttons, which never came
close to needing extra room and so couldn't have caught this class of
bug):

1. Started at a deliberately small `initialWidth=500` — the window
   immediately grew to `1476` on first layout, before any zoom at all,
   confirming content-driven `minimumWidth` works from a cold start, not
   just reactively after a change.
2. 6× `Ctrl++`: grew further to `2372` — zoom-in now genuinely expands the
   window when the (now-bigger) content needs it.
3. 6× `Ctrl+-` back to scale 1.0: stayed at `2372` — no shrinking.
4. Clicked the reset button (`QTest.mouseClick` at its real on-screen
   position, not calling the QML function directly) while already at
   scale 1.0 — button correctly disabled, no-op, window unchanged.
5. 6× `Ctrl++` again, then clicked reset for real (scale was `!= 1.0`,
   button enabled) — window **stayed at `2372`**, confirming reset no
   longer force-resizes anything. A screenshot at this point shows the
   buttons visibly back at their small scale-1.0 size (still correctly
   rounded, not circular) inside the still-large window, and the reset
   button visibly dimmed/disabled again.

Script and screenshots were throwaway — deleted after verification, not
committed.

## 0.6.1

Three real bugs found in 0.6.0's zoom feature, fixed and empirically
re-verified (not just re-read) — plus the requested reset-to-default
button.

**User prompt driving this change:** "- zoom in expands window even if the
content is well within the window. you can test this by zooming in, out,
in, out, in, out quite fast you get the result - zoom in breaks roundness,
so after several zooms buttons in row are almost circles as well as butotns
at the bottom. The only button that remains correct is 'Add new client' -
main window minimal size should contain all the buttons + same margin /
padding as is on the left or top from first control - right next to
buttons '+' and '-' at the bottom add button to reset the view to default
size together with window size"

**Bug 1 — spurious/compounding window growth.** The 0.6.0 growth logic
resized the window by `newScale/lastScale` on *every* zoom-in step,
unconditionally — so it grew even when the content was nowhere near the
window's edges, and rapid zoom in/out/in/out/in/out (net zero scale
change) compounded growth on every "in" transition regardless of whether
that scale had already been reached before. Reproduced exactly as
described: scripted 3 rapid in/out cycles net-zero, window still grew
900×500 → 1089×605.

**Bug 2 — buttons turning circular at higher zoom ("buttons in row" and
the bottom toolbar, but not "Add new client").** Root-caused by directly
inspecting live QML property values (not guessed): `SquareIconButton`
declared `width:`/`height:` (plain property bindings) both internally and
at several call sites. Qt Quick Layouts only reactively track a child's
`implicitWidth`/`implicitHeight` (or `Layout.preferredWidth/Height`) for
sizing — a plain `width:` binding on a direct child of a `RowLayout`
applies once but stops being respected after that. Confirmed directly:
after 8 zoom-ins, a toolbar button's `radius` had scaled correctly
(14 → 25.2) while its `width`/`height` were frozen at the original `40`
— exactly matching the reported symptom precisely, including why the
empty-state "Add new client" button was unaffected (it's positioned with
`anchors.centerIn` inside a plain `Item`, never inside a `RowLayout`, so
it never hit the conflict). Fixed by switching every
`SquareIconButton`-related size binding from `width:`/`height:` to
`implicitWidth:`/`implicitHeight:`, which both a bare `Item` (as its
actual size, when not otherwise bound) and a `Layout` (as the reactive
fallback for `Layout.preferredWidth/Height`) respect correctly.

**Point 3 — minimum window size.** `Main.qml`'s `Window` now binds
`minimumWidth`/`minimumHeight` to exactly what's needed to show the
bottom toolbar's 4 buttons in full, plus the same `Theme.spacing * 2`
margin used on every other edge (matching the `ColumnLayout`'s own
`anchors.margins`). This does two things: the window manager won't let
the user shrink the window past it interactively, and it's the same
threshold bug 1's fix uses to decide whether to grow at all — `width <
minimumWidth` is a simple current-state check, not a remembered
ratio/delta, which is what makes it immune to the rapid-toggle compounding
in bug 1. Scoped deliberately to the toolbar only (not, say, the widest
currently-rendered client row), since the toolbar is the one fixed,
always-present, exactly-known set of controls — noted here in case a
wider per-content minimum turns out to matter later.

**Reset button.** A 4th `SquareIconButton` (same size as the theme/zoom
ones) added to the same bottom-left row, labeled "↺", disabled when
already at the default scale and window size. Resets `Theme.uiScale` to
`1.0` and the window to the app's actual default size (900×500, exposed
from `app.py` as new `defaultWidth`/`defaultHeight` context properties —
deliberately separate from `initialWidth`/`initialHeight`, which reflect
whatever was restored from a previous session, not the hardcoded
default).

**Verified empirically, same technique as 0.5.2/0.6.0 — re-ran the exact
reported repro steps against the fix, not just visual inspection:**

1. Scripted the *exact* rapid in/out/in/out/in/out sequence via
   `QTest.keyClick` (real `Ctrl++`/`Ctrl+-` events): window stayed at
   900×500 throughout — no compounding.
2. Same script, 8 more zoom-ins after that (reaching ~1.8× scale): window
   *still* stayed at 900×500 — confirms it no longer grows unless the
   toolbar actually wouldn't fit (at 900×500 it comfortably does, even at
   high zoom).
3. Grabbed a screenshot at that same ~1.8× zoom level: every button —
   client-row buttons, both toolbar rows, all 4 bottom buttons including
   the new reset button — renders as a correctly-proportioned rounded
   rectangle, none circular.
4. Found the width/height-freeze root cause by inspecting real
   `SquareIconButton` instances' live `width`/`height`/`radius` property
   values before and after zoom (not by reasoning about the QML in the
   abstract), which is what actually revealed the Layout/`width:` conflict
   rather than a guess.

Diagnostic scripts and screenshots were throwaway — deleted after
verification, not committed.

**Needs manual, on-host verification:** confirm the window manager
actually refuses to resize the window below `minimumWidth`/`minimumHeight`
interactively (platform/WM-dependent enforcement of `Window.minimumWidth`/
`minimumHeight`, not something the offscreen platform plugin exercises the
same way — it logged "This plugin does not support propagateSizeHints()"
during this session's testing, which is expected/benign for that platform
but means the real interactive-resize-floor behavior specifically needs a
real WM to confirm).

## 0.6.0

UI zoom: +/- buttons next to the theme toggle, Ctrl+/Ctrl- shortcuts,
proportional scaling of the whole layout, and grow-only window resizing.

**User prompt driving this change:** "on the right of theme selector add
buttons + and - visually similar size as theme changer. The '+' zooms in
the application conent, and '-' zooms out. Same functionality should work
with CTRL+'+' and CTRL+'-'. Zoom in means change of fonts and button sizes
/ positions so the entire layout will remain proportionally same (but
bigger / smaller). Zoom changes only content of the main window, not its
size. Main window size can potentially only grow and that when the
re-size of buttons during zoom 'in' could cause they'll ocupy more space
than size of the window."

What changed:

- `Theme.qml`: added `uiScale` (default `1.0`, bounds `0.75`–`2.0`, step
  `0.1`) with `zoomIn()`/`zoomOut()` functions, and made every
  size-related token derive from it — `cornerRadius`, `spacing`, plus new
  reusable scaled tokens (`iconButtonSize`, `smallIconButtonSize`,
  `hugeIconButtonSize`, `iconGlyphSize`, `iconImageSize`, `logoSize`,
  `rowHeight`, `fontSizeSmall/Body/Medium/Large`, `fieldPadding`,
  `fieldRightPadding`). `animationDuration` deliberately does *not* scale
  — timing, not size.
- Went through every QML file replacing hardcoded pixel literals
  (`font.pixelSize: 15`, `width: 64`, `height: 72`, dialog widths, etc.)
  with these tokens, so the *entire* layout — client rows, buttons,
  dialogs, the tooltip, input fields — scales together, per "entire
  layout will remain proportionally same."
- `Main.qml`: two new `SquareIconButton`s (same `smallIconButtonSize` as
  the theme toggle) to its right, labeled "+"/"-", calling
  `Theme.zoomIn()`/`zoomOut()`; each disables itself at the respective
  bound (`enabled: Theme.uiScale < Theme.maxUiScale` / `>
  Theme.minUiScale`) via a new `opacity`-based disabled state added to
  `SquareIconButton.qml`. Two `Shortcut` items bound to
  `StandardKey.ZoomIn`/`ZoomOut` call the same two functions, so buttons
  and Ctrl+/Ctrl- are one code path, never two.
- **Window growth, grow-only**: a `Connections { target: Theme }` watches
  `uiScale`. On every *increase* (zoom in), it resizes the window by the
  same ratio the content just grew by (`window.width *= newScale /
  lastScale`, likewise height); on a decrease (zoom out) it does nothing
  to the window at all — per "Main window size can potentially only
  grow." `_lastUiScale` tracks the scale the window was last sized for,
  so a fresh launch (always starting at `1.0`) never triggers a spurious
  resize.

**Verified for real, not just "no QML errors"** — same offscreen-grab
technique as 0.5.2, extended into a full scripted scenario: loaded the
real `Main.qml` with a populated client row, grabbed a screenshot, then
used `QTest.keyClick` to send *actual* `Ctrl++`/`Ctrl+-` key events
(exercising the real `Shortcut` items, not just calling the QML functions
directly) and grabbed screenshots after each phase. Confirmed all of:

1. Two `Ctrl++` presses visibly grew every button and all text
   proportionally, and grew the window itself (700×400 → 764×436).
2. Four subsequent `Ctrl+-` presses (enough to swing past the original
   scale, clamped at the `0.75` floor) shrank the buttons back down
   below their original size — but the **window stayed at exactly
   764×436**, unchanged by any of the four zoom-out presses. This is the
   "can potentially only grow" requirement confirmed directly, not
   assumed.
3. The zoom buttons render at the same visual size as the theme toggle,
   positioned to its right, in both screenshots.

Script and screenshots were throwaway — deleted after verification, not
committed.

**Needs manual, on-host verification:** the +/- buttons' disabled
(dimmed) appearance at the zoom bounds wasn't specifically screenshotted
at exactly `minUiScale`/`maxUiScale`; confirm they visibly dim and stop
responding to clicks at the extremes. Also confirm `Ctrl++`/`Ctrl+-` feel
right on the real keyboard layout in use (`StandardKey.ZoomIn`/`ZoomOut`
resolve to the platform default, which the `QTest.keyClick` simulation
above matched, but a real physical keypress is the actual claim to
verify).

## 0.5.2

Linear top-to-bottom opacity gradient on the main window's glass panel.

**User prompt driving this change:** "the background, if possible add it
gradient opacity top is more opaque than bottom, slope should be linear
(for now), if it wont look good we change it to something else"

What changed:

- `Theme.qml`: added `glassPanelBottomRatio` (`0.5`) — the bottom edge's
  alpha as a fraction of whatever the top's current alpha is, so the same
  ratio holds in both resting and hovered states without needing separate
  top/bottom tokens per state.
- `Main.qml`: the glass panel's flat `color` became a 2-stop
  `Gradient`/`GradientStop` pair (`position: 0.0` top, `position: 1.0`
  bottom, `Gradient.Vertical`) — a straight linear interpolation between
  them by construction, matching "slope should be linear." The existing
  hover-driven fade-toward-opaque behavior (0.4.0) still animates via a
  `topAlpha` property (with its `Behavior`); `bottomAlpha` is a plain
  binding derived from it (`topAlpha * Theme.glassPanelBottomRatio`), so
  it co-animates automatically without its own separate `Behavior`.

**Verified visually, not just "no errors"**: Qt's `offscreen` platform
plugin does real software rendering (not just a no-op), so
`QQuickWindow.grabWindow()` can capture an actual rendered frame without a
real display — used a temporary script to load the real `Main.qml` with a
populated client row, grab a screenshot, and view it. Confirms: the
gradient is visibly darker/more opaque at top fading to lighter/more
transparent at bottom, the rounded corners render correctly with the
gradient in place, and the buttons stay crisply solid/opaque against it
(matching 0.5.1's fix, checked together with this change) rather than
picking up any of the gradient's translucency. Screenshot/script deleted
after verification — not committed, it was throwaway.

**Needs manual, on-host verification:** confirm the gradient still reads
well against a real (possibly blurred, if on KWin) desktop behind it, not
just the plain gray offscreen-framebuffer backdrop used above — and that
the linear slope looks intentional rather than muddy; the user flagged
upfront this might need revisiting if it doesn't look good.

## 0.5.1

Buttons solid/opaque in every state; the hover-driven opacity change stays
scoped to the background only.

**User prompt driving this change:** "make the buttons solid, change the
opacity only on background"

What changed:

- `SquareIconButton.qml`: idle fill was literally `"transparent"` (letting
  whatever glass-panel color sat behind it show straight through, which is
  what made buttons look like they were fading along with the
  background's own hover-opacity animation, even though nothing was
  actually animating the button itself) — changed to `Theme.surface`
  (fully opaque). Hover was `Theme.surfaceGlass` (translucent) — changed
  to a new solid `Theme.surfaceHover` token, so hover reads as a clear
  solid step up rather than another translucent layer. Pressed stays
  `Theme.accent` (already solid).
- `Theme.qml`: added `surfaceHover` (`#262a37` dark / `#eef0f4` light) —
  a solid, theme-aware hover color distinct from the existing translucent
  `surfaceGlass` (which remains for actually-translucent uses like
  `ValidatedTextField`'s and dialog borders).
- No change to `Main.qml`'s hover-driven glass-panel opacity animation
  from 0.4.0 — that was already scoped to the background `Rectangle`
  only; buttons were never bound to it, they just visually looked
  affected because their own idle fill was transparent.

**Why:** direct feedback — buttons blending into/fading with the
translucent background made them hard to read and looked unintentional;
the background's own translucency/hover-brightening effect should be a
background-only visual, not something buttons inherit by being
transparent themselves.

## 0.5.0

Real compositor backdrop blur (KWin), with correct detection-based
fallback for everything else — including the user's actual environment
(GNOME/Mutter on X11).

**User prompt driving this change:** "first, background is just
transparent, does not make the glass effect (does not blurs the
background)" — followed by clarifying (via a question about which
compositor to target) "I'm running gnome on x11, check the compositor from
actually running components."

What changed:

- New `clientdeck/compositor.py`: `detect_window_manager_name()` queries
  the *actually running* X11 window manager via the standard EWMH
  `_NET_SUPPORTING_WM_CHECK` mechanism (not `XDG_CURRENT_DESKTOP` or any
  other env var, which describe the session rather than what's actually
  compositing), `is_kwin()` checks the result, and
  `set_kwin_blur_behind()` sets KWin's documented
  `_KDE_NET_WM_BLUR_BEHIND_REGION` X11 property to request a real blurred
  backdrop. `enable_blur_behind_if_supported()` ties these together:
  applies the hint only when KWin is actually detected, otherwise a no-op.
  Added `python-xlib` as a real runtime dependency (pure Python, packages
  fine via Nuitka same as anything else).
- `clientdeck/app.py`: calls `enable_blur_behind_if_supported(window.winId())`
  once the main window exists, guarded by `app.platformName() == "xcb"`
  (X11 only — this mechanism doesn't apply under Wayland at all, which
  would need the entirely different `org_kde_kwin_blur` Wayland protocol,
  not implemented). The existing alpha-transparency glass look in
  `Main.qml`/`Theme.qml` is unchanged and remains the fallback everywhere
  this doesn't apply.
- Unit tested via an injectable `display_factory` (fake Xlib display/window
  objects simulating the EWMH property-query protocol) — 13 new tests
  covering: KWin detected → name matched case/whitespace-insensitively;
  Mutter/other names → rejected; missing `_NET_SUPPORTING_WM_CHECK` or
  `_NET_WM_NAME` property → `None`; any exception (no X11, no Xlib, etc.)
  → `None`, never raises; the display connection is always closed;
  `enable_blur_behind_if_supported` only calls the blur-setting function
  when KWin is actually detected.

**Why GNOME/Mutter doesn't get real blur:** unlike KWin, Mutter has no
standard per-app "blur behind this window" hint at all — achieving it
there would require a GNOME Shell extension installed at the desktop
level (something outside this app's control, e.g. "Blur my Shell", which
works by the *user* configuring it to match this app's window class in
the extension's own settings — not something `compositor.py` can trigger
itself). Rather than silently doing nothing with no explanation, or
guessing at solutions that don't actually work on Mutter, this was
scoped by asking which compositor to target; detection-based fallback
means the code is still correct (and gets real blur for free) if the
target ever becomes/includes KDE Plasma.

**Verified for real, not just mocked** (this sandbox turned out to have a
live X11 connection, read-only property queries only — no window was
created or shown, consistent with CLAUDE.md's "can't launch a GUI"
constraint): ran `compositor.detect_window_manager_name()` unmocked and it
correctly identified `"GNOME Shell"` as the actually-running compositor —
matching exactly what the user reported — and
`enable_blur_behind_if_supported()` correctly returned `False` (skipped,
as it should for Mutter) in under 2ms, with no hang or exception.

**Needs manual, on-host verification:**

1. On a real KDE Plasma (KWin, X11) session: confirm the window actually
   renders with a blurred backdrop, not just alpha transparency.
2. Confirm this remains a harmless no-op (today's alpha-only glass look,
   nothing more) on the user's actual GNOME/X11 setup — the automated
   check above only confirmed detection + skip-logic, not a full app
   launch.
3. Confirm it's also a harmless no-op under Wayland (any compositor),
   since `app.platformName() == "xcb"` should skip it there entirely.

## 0.4.0

Light theme + a bottom-left toggle button, and hover-driven glass opacity
on the main window.

**User prompt driving this change:** "ok now 1) add button (bottom left) to
change dark theme to light. add light theme too. 2) when mouse is over
application change opacity closer to opaque, when it is left, set it to
one there is now"

What changed:

1. **Light theme** (`Theme.qml`): every color token is now a binding on a
   new `property bool isDark: true`, e.g. `readonly property color
   background: isDark ? "#14161c" : "#f4f5f7"` — flipping `isDark` makes
   every component using these tokens repaint reactively, since none of
   them hardcode colors (checked: no hardcoded hex colors exist anywhere
   outside `Theme.qml`, confirmed by grep before making this change, so
   the light theme applies everywhere automatically — dialogs, tooltip,
   buttons, text).
2. **Theme toggle button** (`Main.qml`): a small (40×40) `SquareIconButton`
   as the last row of the main `ColumnLayout`, left-aligned — sits at the
   bottom-left of the window regardless of empty-state vs. populated list,
   since it's simply the final row rather than free-floating anchors (no
   overlap risk with the list). Shows a sun/moon glyph depending on the
   current mode; click toggles `Theme.isDark`. Not persisted across
   restarts — runtime-only, as asked.
3. **Hover-driven glass opacity** (`Main.qml`, `Theme.qml`): the main
   window's glass panel now animates its alpha between
   `Theme.glassPanelAlpha` (resting — the same translucency introduced in
   0.3.0) and `Theme.glassPanelHoverAlpha` (closer to opaque, not fully
   opaque) via a `HoverHandler` covering the whole panel, so it's "hovered"
   whenever the mouse is anywhere over the app — buttons, list, dialogs
   included, not just empty space. `Theme.glassPanel` itself (used by
   `ThemedTooltip` and anything else wanting the plain resting color) is
   unaffected — the hover-swap only touches the main window's own
   `Rectangle`, built from the new `Theme.glassPanelBase` (RGB) +
   `Theme.glassPanelAlpha`/`glassPanelHoverAlpha` split.

**Why:** direct feature requests, not spec-driven — continuing the same
UI/UX iteration as 0.3.0/0.3.1.

**A real bug found and partially addressed while verifying this (not
caused by this change — pre-existing, first noticed in 0.3.0):** stress-
testing Ctrl+C headlessly properly this time (many runs, comparing
invocation styles instead of a handful of ad hoc attempts) pinned down
that the `TypeError: Cannot read property 'count' of null` for
`clientModel.count` in `Main.qml` is **not** a startup race as 0.3.0
guessed — it is specifically tied to the `app.quit()`-triggered shutdown
path:

- 25/25 runs killed via `timeout N cmd` (which sends an unhandled
  `SIGTERM`, killing the process abruptly with no Qt shutdown sequence at
  all) were clean.
- 8/8 runs killed via `SIGINT` (which goes through our handler → `app.quit()`
  → Qt's normal shutdown/object-teardown sequence) reproduced the error.

So it happens somewhere during window/engine teardown after quit is
requested — most likely PySide6/Qt destroying the Python-side
`ClientListModel` before every QML binding referencing it has finished
being torn down. Added defensive reference-pinning in `app.py`
(`engine._retained_context_objects = [...]`) for all context-property
QObjects, which is good practice regardless (a genuinely well-known
PySide6/PyQt gotcha: such objects aren't otherwise Python-refcounted
through the QML side) — but it did **not** eliminate this specific
occurrence when retested (still reproduced). Kept the fix anyway since
it's correct defensive practice independent of this bug, but the shutdown-
order issue itself remains unresolved.
**Practically, this looks harmless**: `config.json`'s `window_state` is
confirmed still written correctly every time (the `aboutToQuit` save runs
*before* whatever later teardown step triggers this), and the error occurs
after the user has already asked to quit, once the window is on its way
out — not during normal use. Correcting 0.3.0's changelog entry, which
speculated it might be a persistent/user-visible startup issue; it isn't.

## 0.3.1

Scope the Ctrl+C/SIGINT handler to source-mode only.

**User prompt driving this change:** "I see, yes, that's good observation.
For now, let's keep the CTRL+C event handler only in python app (when
run.sh is run)."

What changed:

- `clientdeck/paths.py`'s private `_is_nuitka_onefile_build()` became a
  public `is_packaged_build()` (same logic, now used outside this module
  too), with a docstring explaining why `app.py` needs it.
- `clientdeck/app.py`'s `run()` now only installs the `signal.signal(SIGINT,
  ...)` handler and its `QTimer` pump when `not is_packaged_build()` —
  responding to 0.3.0's finding that the handler doesn't work correctly
  against the packaged onefile binary's two-process structure. Rather than
  leave code installed that's known not to behave correctly in that mode,
  it's now simply skipped there.
- Added `tests/test_paths.py` coverage for `is_packaged_build()` itself
  (source mode: `False`; mocked compiled marker: `True`).

**Why:** confirms the previous entry's scoping decision explicitly in code
rather than leaving the non-functional-when-packaged handler installed
regardless of mode — this was user-confirmed direction, not a guess.

**Re-verified** (source mode, headless): Ctrl+C via `SIGINT` still exits
cleanly and saves `config.json`'s `window_state` after this change — the
guard only skips the packaged-build code path, doesn't affect source mode.

## 0.3.0

UI/UX pass from a review of the running app: clean Ctrl+C, glass main
window, left-aligned dialog action buttons, logos-only client rows with a
themed hover tooltip.

**User prompt driving this change:** "after quick evaluation of the work
done, changes: 1) Add support to CTRL+C reaction (proper closure) in
terminal 2) background is dark solid, make it glass-transparent, without
border, round rectangles, keep the rest 3) The Action buttons, make them
left aligned, not right aligned 4) Remove name and descriptions from second
column, keep only logos. 5) mouse hover on logo shows custom tooltip
(custom in theme sense) with name and description"

What changed:

1. **Ctrl+C** (`clientdeck/app.py`): Qt's C++ event loop never gives Python
   a chance to run its own `SIGINT` handler, so Ctrl+C in a terminal was
   previously either ignored or required a second forceful kill. Installed
   a `signal.signal(SIGINT, ...)` handler that calls `app.quit()`, paired
   with a 200ms repeating `QTimer` whose only job is to force Python to
   regain control often enough for that handler to actually fire — the
   standard fix for this well-known PySide/PyQt gap. Quitting this way
   still goes through the normal `aboutToQuit` path, so window state is
   saved exactly like any other quit ("proper closure"). Verified headlessly
   for the dev-mode case this request is about — running via `run.sh`/`uv
   run python -m clientdeck` in a terminal: `QT_QPA_PLATFORM=offscreen`,
   send a real `SIGINT`, confirmed exit code 0 and that `config.json`'s
   `window_state` was actually written, rather than just written to spec.
   **Does not (yet) work the same way for the packaged single-file binary**
   from `build.sh`: it turns out to be two processes (a Nuitka onefile
   bootstrap process plus the actual extracted payload process it execs),
   and sending `SIGINT` to that process group did eventually kill both
   (~7s later) but without going through our `aboutToQuit` handler —
   `config.json` was never written. Not investigated further since the
   request was specifically about terminal/dev-mode usage; flagging as a
   known gap rather than silently leaving it unmentioned.
2. **Glass main window** (`Main.qml`, `Theme.qml`): the `Window` itself is
   now `color: "transparent"` with a new `Theme.glassPanel` (translucent
   dark) `Rectangle` filling it — rounded (`Theme.cornerRadius * 1.5`),
   `border.width: 0`. The window's actual corners stay transparent outside
   that rounded rectangle, which is what makes the window read as a rounded
   shape rather than a rounded panel inside a square frame. True
   desktop-backdrop blur (compositor-level) was not attempted — out of
   scope for a QML-only change and not verifiable without a real
   compositor; this is alpha-blended translucency only.
3. **Dialog action buttons left-aligned** (`AddClientDialog.qml`,
   `AddAppDialog.qml`): the Cancel/Add button rows were `Layout.alignment:
   Qt.AlignRight`, changed to `Qt.AlignLeft`.
4. **Logos-only client rows** (`ClientRow.qml`): removed the name/
   description `ColumnLayout` (the "second column") entirely — the action
   buttons now start right after the logo.
5. **Themed hover tooltip** (`ThemedTooltip.qml`, new; wired into
   `ClientRow.qml`): a new generic, reusable glass-styled tooltip component
   (bold title + secondary-colored description, `Theme.glassPanel`
   background, no border, rounded) shown via a `HoverHandler` on the logo
   `Image`, replacing the removed inline name/description text. Registered
   in `qmldir` alongside the other reusable components, same pattern as
   `ValidatedTextField`/`SquareIconButton`.

**Why:** direct feedback from reviewing the running app/code, not a new
requirement from the product spec — CLAUDE.md's dark/glass/rounded theme
intent already called for this look, this pass just corrects concrete
deviations from it (solid opaque background, right-aligned actions, a
non-custom tooltip that didn't exist yet) and fixes a real terminal-ergonomics
gap (Ctrl+C).

**Verification note:** while testing Ctrl+C headlessly, some runs printed
`TypeError: Cannot read property 'count' of null` for the two
`clientModel.count` bindings in `Main.qml`, then kept running normally with
no further errors and exited cleanly. Narrowed down (not fully root-caused):
it only ever appeared on the *first* `uv run python -m clientdeck` after
editing a source file — i.e. the run where `uv run` rebuilds/reinstalls the
editable `clientdeck` package before launching — and never on a repeat run
with no file changes in between (tested 3 clean runs in a row after
observing it, twice). Best guess is a timing artifact of that rebuild step
racing the QML engine's first binding evaluation, not a logic bug in the
app itself, and not something an installed/packaged binary's user would
ever hit (they're not rebuilding on every launch) — but not confirmed, so
flagging it here rather than silently ignoring it. If it recurs during
manual on-host testing (e.g. the empty-state "+" or the client list both
fail to appear on some launches), that's the lead to chase.

**Needs manual, on-host verification:**

1. Confirm the window actually renders as a translucent glass rounded
   rectangle with visible desktop/whatever's-behind-it showing through —
   `color: "transparent"` on a QtQuick `Window` needs a compositing window
   manager to actually look right; on a non-compositing setup it may
   render as opaque black or behave oddly instead.
2. Confirm hovering a client logo shows the themed tooltip with the
   correct name/description, positioned sensibly below the logo, and that
   it disappears when the mouse leaves.
3. Confirm the Cancel/Add buttons in both dialogs now visually sit on the
   left.
4. Re-confirm the intermittent `clientModel.count` null error noted above
   doesn't recur, or find what actually triggers it if it does.
5. Confirm Ctrl+C from a real terminal (not `kill -INT`, an actual
   keypress in a real TTY) cleanly quits and saves state when run via
   `run.sh`. If the packaged binary's Ctrl+C behavior ever matters, that
   needs its own investigation (see point 1 above) — it's currently
   unresolved.

## 0.2.1

`src/scripts/create_user.py` and `src/scripts/launch_as_user.py` now mock
their real system actions instead of performing them.

**User prompt driving this change:** "For now, make sure the scripts which
add user, start the app, etc. are just mocks and do not actually start any
action, for now we are prototyping the UI and UX."

What changed:

- Both scripts gained a `MOCK_MODE = True` module constant. When set (the
  current default), they print the command they *would* have run
  (`useradd ...` / `xhost ...` / `su ...`) and return success, without
  calling `subprocess.run` at all.
- `create_user.py` still requires root even in mock mode, so the real
  `pkexec` authentication dialog is still exercised from the "add client"
  flow — only the `useradd` step itself is faked. `launch_as_user.py`'s
  mock skips `su`/`xhost` and any real app process entirely.
- Both real code paths (the actual `useradd`/`su`/`xhost` calls) are kept,
  not deleted — tests cover both branches (mock-mode default, and the real
  behavior with `MOCK_MODE` monkeypatched to `False`), so flipping the
  constant back once prototyping is done is a one-line change with
  existing test coverage, not a rewrite.

**Why:** the product's real behavior (`su`/`xhost`/`pkexec`/`useradd`)
can't be exercised in this sandbox anyway, and the user is currently
iterating on the app's UI/UX rather than its system-integration behavior —
mocking these means clicking through "add client"/launch buttons on a real
host doesn't create actual Linux users or spawn real processes while that's
being tested.

**Needs manual, on-host verification:** click through add-client and the
various launch buttons and confirm nothing real happens (no user actually
created, no terminal/app actually opens) while the UI still behaves and
transitions correctly — e.g. "add client" should still succeed and add the
client to the grid, because the mock returns success.

## 0.2.0

`run.sh` (dev-mode launcher) and the single-file packaging build script,
implementing `claude-blocks/python-single-app-instance.claude.md`.

**User prompt driving this change:** "create run.sh script which runs the
client deck. Also implement blueprint for single application together with
build script. Output directory is 'dist'."

What changed:

- `run.sh`: thin wrapper around `uv run python -m clientdeck`, for running
  the app from a source checkout.
- `build.sh`: one-time-setup packaging script per the blueprint, driving
  `pyside6-deploy` (PySide6's own Nuitka-onefile wrapper, since this is a
  Qt/QML app) to produce `dist/clientdeck-<version>` — a single
  self-sufficient executable, no separate install step. Adds a `build` uv
  dependency group (`nuitka`, `pip`) that plain `uv sync`/`uv run pytest`
  never touches.
- `tools/check_versions.py`: fails loudly on drift between
  `pyproject.toml`'s version and `clientdeck.__version__` before a build
  proceeds, per the blueprint's Step 2 and this project's own "Versioning &
  changelog" rule. Unit tested (including a guard test against the real
  repo's current versions).

**Why:** the app needed both an easy way to run it from source and an
actual reproducible path to the single-binary distribution target described
in CLAUDE.md's "Deployment / packaging" section — and the blueprint exists
specifically so this isn't designed from scratch each time.

**This was not just written to spec — it was actually built and run, and
that caught three real bugs no amount of reading would have found:**

1. **`__main__.py`'s relative import broke the compiled binary.**
   `from .app import main` fails with `ImportError: attempted relative
   import with no known parent package` once Nuitka compiles `__main__.py`
   as a bare top-level module (no parent package context). Fixed to an
   absolute `from clientdeck.app import main` — works identically in both
   source and packaged mode.
2. **The QML `import ClientDeck 1.0` module statement never actually
   worked** — not even from source, this was latent from the first
   implementation pass. Path-based QML module imports require a directory
   literally named after the module; ours just declared `module ClientDeck`
   in a `qmldir` sitting in a plain `qml/` folder. Removed the explicit
   import from every `.qml` file — Qt's automatic local-directory import
   already gives sibling files in that folder access to it, including the
   `Theme` singleton.
3. **`src/scripts/` (the `su`/`xhost`/`pkexec` launch scripts) was silently
   left out of the packaged binary.** Nuitka's `--include-data-dir`
   excludes `.py` files by default (treats them as source, not data), and
   that directory contains only `.py` files. Switched to
   `--include-raw-dir`, which bundles verbatim. Also added
   `clientdeck/paths.py`, replacing `app.py`'s old `__file__`-relative
   path constants: those resolved correctly from a source checkout but
   would have pointed at nonexistent locations once packaged (Nuitka
   onefile self-extracts to a temp directory with a different layout).
   `paths.py` is unit tested for both the source-checkout and (mocked)
   packaged-build cases.
4. (Related, not a bug but worth recording:) once packaged,
   `sys.executable` is the compiled ClientDeck binary itself, not a Python
   interpreter — `_ClientProvisioner`/`_spawn_launch_script` were changed
   to invoke the scripts directly via their own `#!/usr/bin/env python3`
   shebang instead of prefixing `sys.executable`.

**How this was verified** (compiling isn't a GUI/`su`/`xhost`/`pkexec`
action, so it was safe to actually do in this sandbox, unlike running the
app normally): ran `build.sh` for real (network + a C compiler were both
available), producing an actual `dist/clientdeck-<version>` binary, then
ran that binary with `QT_QPA_PLATFORM=offscreen` (Qt's headless platform
plugin — never opens a window, so it doesn't violate the "can't launch a
GUI" constraint) and confirmed it starts, loads its QML successfully, and
stays running with no errors. Separately confirmed, by inspecting the
onefile extraction directory while the process was alive, that `qml/` and
`scripts/` are both bundled correctly and the scripts kept their executable
bit.

**Still needs manual, on-host verification** (this sandbox has no real
display/`su`/`xhost`/`pkexec`):

1. Run the actual packaged `dist/clientdeck-<version>` binary on a real
   desktop session (not `QT_QPA_PLATFORM=offscreen`) and confirm it looks
   and behaves like the source-mode app — the offscreen check proves it
   *starts*, not that it renders/looks correct.
2. Exercise `create_user.py`/`launch_as_user.py` from the *packaged*
   binary specifically (add a client, launch an app) — confirmed they're
   bundled with the right permissions, but not confirmed `pkexec`/`su`
   actually finds and executes them correctly from that extracted temp
   location on a real system.
3. Known unresolved gap, flagged rather than silently left in: `pkexec`
   authorizes by *exact path*, but Nuitka onefile self-extracts to a new
   random temp directory on every single run — so
   `resources/com.clientdeck.app.policy`'s `exec.path` annotation can't
   point at a stable location for the packaged `create_user.py` the way it
   can for a normal system install. This needs the self-update-registration
   step from CLAUDE.md's "Deployment / packaging" section (still not
   implemented) to install the scripts to a fixed system path and generate
   the polkit policy against *that* path, rather than the onefile temp
   extraction.

## 0.1.0

First implementation of ClientDeck, scaffolded from `CLAUDE.md`'s product
spec.

**User prompt driving this change:** "ok, try to create first implementation
based on claude.md"

What changed:

- Project scaffold: `pyproject.toml` (uv-managed, PySide6 + pytest), `src/`
  layout with `clientdeck` as the app package and `src/scripts/` for the
  privileged/host-mutating helpers, `tests/` mirroring `src/`.
- Config persistence (`clientdeck/config.py`): clients, their apps, and
  window position/monitor state, stored as JSON under
  `$XDG_CONFIG_HOME/clientdeck/config.json`, written atomically, no explicit
  "save" step. Fully unit tested.
- `.desktop` launcher discovery (`clientdeck/desktop_apps.py`), following
  the XDG search-path/override precedence rules, for the "add app" dialog's
  "pick an existing registered application" list. Unit tested.
- Window placement logic (`clientdeck/window_placement.py`): pure function
  deciding whether to restore the exact saved geometry on the saved
  monitor, or fall back to centering on the first available monitor when
  that monitor is gone — kept separate from real `QScreen` calls so it's
  testable without a display. Unit tested.
- Shared username/group-exists check (`clientdeck/username.py`), used by
  both the QML live-validation input and `create_user.py`'s own safety
  check, so the two never disagree. Unit tested.
- Qt model layer (`clientdeck/models.py`): `ClientListModel` exposing the
  client list (and per-client apps) to QML, with `addClient`/
  `addAppToClient`/`removeClient` mutators. Unit tested.
- QML UI (`clientdeck/qml/`): borderless main window, empty-state "+",
  per-client row (logo, terminal/VS Code/Claude buttons, custom apps, "+"),
  a centrally-defined `Theme` singleton, a generic reusable
  `ValidatedTextField` (the "live-validated input with themed error state"
  component required to be built once and reused, not special-cased to the
  username field), `AddClientDialog`, and `AddAppDialog` (existing
  `.desktop` picker + manual custom-command entry). **Not verifiable by the
  agent — needs manual, on-host testing** (see below).
- Standalone scripts (`src/scripts/`): `launch_as_user.py` (the
  `su -`/`xhost` impersonation + GUI X-access grant/revoke wrapper, robust
  to the launched app crashing or `su` itself failing) and `create_user.py`
  (the root-side user-creation script, run under `pkexec` from
  `AddClientDialog.qml`'s "Add" button — the client is only persisted to
  config once user creation actually succeeds). Both have a clear
  argv/exit-code contract and are unit tested via subprocess-mocking, per
  CLAUDE.md's working conventions.
- `resources/clientdeck.desktop` and `resources/com.clientdeck.app.policy`
  (polkit action) templates — placeholders, need real install paths and a
  real reverse-DNS id filled in at packaging time.

**Why:** this is the first end-to-end pass at the app described in
`CLAUDE.md`, prioritizing the pieces that can be written and verified
headlessly (config, models, discovery, window-placement logic, the launch
scripts' command-building/robustness) with full test coverage, while
writing the GUI/QML and the actual `su`/`xhost`/`pkexec` integration to spec
without being able to run or verify them in this sandboxed environment.

**Explicitly out of scope for this pass** (left for follow-up, per
CLAUDE.md's own guidance not to build ahead of what's asked):

- The single-file packaging build script (`claude-blocks/python-single-app-instance.claude.md`)
  and the startup self-update-registration check — no build/deploy step
  exists yet to make either one meaningful.
- Real verification that `su`, `xhost`, and `pkexec` integration actually
  behaves correctly on a live desktop session — this needs to be done
  manually, on a real host, by the user.

**Needs manual, on-host verification (cannot be exercised in this sandbox):**

1. Run `uv run python -m clientdeck` on a real desktop session and confirm
   the borderless window appears, shows the empty-state "+", and opens
   the "add client" dialog.
2. Add a client with a username that already exists on the system and
   confirm the username field goes red with the warning indicator live as
   you type, and that "Add" is disabled while it's invalid.
3. Add a client with a fresh username, confirm it's added to the grid, and
   restart the app to confirm it persists.
4. Click the "+" on a client row, confirm discovered `.desktop` apps are
   listed, and that "Custom command" mode lets you add a manual entry.
5. Click terminal/VS Code/Claude/a custom app button and confirm it
   actually runs `launch_as_user.py`, which should `su` into that user and
   (for GUI apps) grant/revoke `xhost` access around the launch — including
   confirming the `xhost` grant gets revoked if the launched app is killed
   or crashes.
6. Move the window to a second monitor, close the app, unplug that
   monitor, and relaunch — confirm it falls back to centering on the
   remaining monitor instead of erroring or appearing off-screen.
7. Verify the `pkexec` authentication dialog actually appears when adding a
   client, that it runs `create_user.py` and only persists the client to
   config on success (leaving it out and showing the red error text on
   failure), and that this works once a real install path is filled into
   `resources/com.clientdeck.app.policy`'s `exec.path` annotation (it's a
   placeholder pointing at `/usr/bin/python3` for now).
