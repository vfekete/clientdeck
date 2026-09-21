/* clientdeck-loader: minimal X11/Xinerama startup splash.
 *
 * Shown while ClientDeck's real (PySide6/Qt) startup is in progress.
 * Implements claude-blocks/python-qt-startup-splash.claude.md; see
 * docs/comments-details.md [98]-[109] and [117]-[118] for the specific
 * choices below. Nothing in this file has been built or run by the
 * agent that wrote it — see [107].
 */

/* Must precede every #include: exposes clock_gettime()/CLOCK_MONOTONIC
 * under -std=c11's strict mode — see docs/comments-details.md [109]. */
#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xinerama.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/select.h>
#include <sys/time.h>

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "splash_image_data.h"

/* ---- tunables ---- */
#define FADE_IN_MS 300
#define FADE_OUT_MS 300
#define MAX_WAIT_MS 120000L      /* packaged mode: give up waiting for "running" after this */
#define STANDALONE_MAX_MS 10000L /* standalone mode: see [106] */
#define FRAME_INTERVAL_MS 40     /* ~25fps */

/* Displayed height as a fraction of the target monitor's height, width
 * following the source image's own aspect ratio — see [117]. */
#define TARGET_HEIGHT_FRACTION 0.25

#define NUM_PATCHES 5
#define PATCH_MIN_DURATION_MS 1200
#define PATCH_MAX_DURATION_MS 2600
#define PATCH_MIN_FRACTION 0.10
#define PATCH_MAX_FRACTION 0.22
#define PATCH_AMPLITUDE 64 /* max +/- luma delta — see [103], [118] */

/* Matches Theme.qml's dark-mode background (#14161c) — see [101]. */
#define FALLBACK_BG_R 0x14
#define FALLBACK_BG_G 0x16
#define FALLBACK_BG_B 0x1c

#define SOCKET_ENV_VAR "CLIENTDECK_LOADER_SOCKET"
#define RECV_ACCUM_CAP 512

/* Not <math.h>'s M_PI — not guaranteed visible under -std=c11 either — see [109]. */
#define LOADER_PI 3.14159265358979323846

typedef enum { STATE_FADE_IN, STATE_HOLD, STATE_FADE_OUT, STATE_DONE } LoaderState;

typedef struct {
    int x, y, w, h;
    long start_ms;
    long duration_ms;
    int amplitude; /* signed: brighten or dim */
} Patch;

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static int clampi(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static int rand_range(int lo, int hi) {
    if (hi <= lo) return lo;
    return lo + (int)(rand() % (hi - lo + 1));
}

/* Random rect + lifetime + signed amplitude — see [103]. Sized against
 * the actual displayed image dimensions (disp_w/disp_h), not the
 * embedded source's — see [117]. */
static void respawn_patch(Patch *p, long t, int disp_w, int disp_h) {
    int min_w = (int)(disp_w * PATCH_MIN_FRACTION);
    int max_w = (int)(disp_w * PATCH_MAX_FRACTION);
    int min_h = (int)(disp_h * PATCH_MIN_FRACTION);
    int max_h = (int)(disp_h * PATCH_MAX_FRACTION);
    p->w = rand_range(min_w, max_w > min_w ? max_w : min_w + 1);
    p->h = rand_range(min_h, max_h > min_h ? max_h : min_h + 1);
    p->x = rand_range(0, disp_w - p->w);
    p->y = rand_range(0, disp_h - p->h);
    p->start_ms = t;
    p->duration_ms = rand_range(PATCH_MIN_DURATION_MS, PATCH_MAX_DURATION_MS);
    {
        int magnitude = PATCH_AMPLITUDE / 2 + rand_range(0, PATCH_AMPLITUDE / 2);
        int sign = (rand() % 2 == 0) ? 1 : -1;
        p->amplitude = sign * magnitude;
    }
}

/* Copies the (already downscaled — see [117]) `base` image into
 * `scratch`, then applies each patch's current luma delta (sin(pi*t)
 * pulse envelope) within its rectangle, respawning any patch whose
 * lifetime has elapsed — see [103]. */
static void apply_patches(Patch patches[], int n, long t, const unsigned char *base, unsigned char *scratch,
                           int disp_w, int disp_h) {
    memcpy(scratch, base, (size_t)disp_w * disp_h * 4);

    for (int i = 0; i < n; i++) {
        Patch *p = &patches[i];
        long elapsed = t - p->start_ms;
        if (elapsed < 0) elapsed = 0;
        double frac = (double)elapsed / (double)p->duration_ms;
        if (frac >= 1.0) {
            respawn_patch(p, t, disp_w, disp_h);
            frac = 0.0;
        }
        double envelope = sin(LOADER_PI * frac);
        int delta = (int)((double)p->amplitude * envelope);
        if (delta == 0) continue;

        for (int y = p->y; y < p->y + p->h; y++) {
            unsigned char *row = scratch + (size_t)y * disp_w * 4;
            for (int x = p->x; x < p->x + p->w; x++) {
                unsigned char *px = row + (size_t)x * 4;
                px[0] = (unsigned char)clampi(px[0] + delta, 0, 255);
                px[1] = (unsigned char)clampi(px[1] + delta, 0, 255);
                px[2] = (unsigned char)clampi(px[2] + delta, 0, 255);
                /* px[3] (alpha) is untouched — luma only, never shape. */
            }
        }
    }
}

static int compute_global_alpha(LoaderState state, long state_start, long t) {
    long elapsed = t - state_start;
    if (state == STATE_FADE_IN) {
        double frac = (double)elapsed / (double)FADE_IN_MS;
        if (frac > 1.0) frac = 1.0;
        if (frac < 0.0) frac = 0.0;
        return (int)(frac * 255.0);
    }
    if (state == STATE_FADE_OUT) {
        double frac = (double)elapsed / (double)FADE_OUT_MS;
        if (frac > 1.0) frac = 1.0;
        if (frac < 0.0) frac = 0.0;
        return (int)((1.0 - frac) * 255.0);
    }
    if (state == STATE_HOLD) return 255;
    return 0;
}

/* Writes `scratch` into `ximage` at the given global alpha. `have_argb`
 * selects premultiplied-ARGB writes ([100]) vs. flat-background blending
 * ([101]). XPutPixel, not manual byte packing — see [108]. */
static void draw_frame(XImage *ximage, const unsigned char *scratch, int global_alpha, int have_argb, int disp_w,
                        int disp_h) {
    for (int y = 0; y < disp_h; y++) {
        const unsigned char *row = scratch + (size_t)y * disp_w * 4;
        for (int x = 0; x < disp_w; x++) {
            const unsigned char *px = row + (size_t)x * 4;
            int r = px[0], g = px[1], b = px[2], a = px[3];
            unsigned long pixel;

            if (have_argb) {
                int out_a = a * global_alpha / 255;
                int pr = r * out_a / 255;
                int pg = g * out_a / 255;
                int pb = b * out_a / 255;
                pixel = ((unsigned long)out_a << 24) | ((unsigned long)pr << 16) |
                        ((unsigned long)pg << 8) | (unsigned long)pb;
            } else {
                int mix_a = a * global_alpha / 255;
                int out_r = (r * mix_a + FALLBACK_BG_R * (255 - mix_a)) / 255;
                int out_g = (g * mix_a + FALLBACK_BG_G * (255 - mix_a)) / 255;
                int out_b = (b * mix_a + FALLBACK_BG_B * (255 - mix_a)) / 255;
                pixel = ((unsigned long)out_r << 16) | ((unsigned long)out_g << 8) | (unsigned long)out_b;
            }
            XPutPixel(ximage, x, y, pixel);
        }
    }
}

/* One-time alpha-weighted box-filter downscale of the embedded source
 * image into `dst` (disp_w x disp_h x 4, RGBA8) — see [117]. Weighting
 * each source pixel's color contribution by its own alpha avoids fully
 * transparent source pixels (color always (0,0,0,0) at the image's
 * corners here) dragging dark fringes into partially-transparent edge
 * pixels of the downscaled result. */
static void downscale_source(unsigned char *dst, int disp_w, int disp_h) {
    for (int dy = 0; dy < disp_h; dy++) {
        int sy0 = (int)((long long)dy * SPLASH_IMAGE_HEIGHT / disp_h);
        int sy1 = (int)((long long)(dy + 1) * SPLASH_IMAGE_HEIGHT / disp_h);
        if (sy1 <= sy0) sy1 = sy0 + 1;
        if (sy1 > SPLASH_IMAGE_HEIGHT) sy1 = SPLASH_IMAGE_HEIGHT;

        for (int dx = 0; dx < disp_w; dx++) {
            int sx0 = (int)((long long)dx * SPLASH_IMAGE_WIDTH / disp_w);
            int sx1 = (int)((long long)(dx + 1) * SPLASH_IMAGE_WIDTH / disp_w);
            if (sx1 <= sx0) sx1 = sx0 + 1;
            if (sx1 > SPLASH_IMAGE_WIDTH) sx1 = SPLASH_IMAGE_WIDTH;

            long sum_r = 0, sum_g = 0, sum_b = 0, sum_a = 0, count = 0;
            for (int sy = sy0; sy < sy1; sy++) {
                const unsigned char *row = splash_image_rgba + (size_t)sy * SPLASH_IMAGE_WIDTH * 4;
                for (int sx = sx0; sx < sx1; sx++) {
                    const unsigned char *px = row + (size_t)sx * 4;
                    int a = px[3];
                    sum_r += px[0] * a;
                    sum_g += px[1] * a;
                    sum_b += px[2] * a;
                    sum_a += a;
                    count++;
                }
            }

            unsigned char *out = dst + ((size_t)dy * disp_w + dx) * 4;
            if (sum_a > 0) {
                out[0] = (unsigned char)(sum_r / sum_a);
                out[1] = (unsigned char)(sum_g / sum_a);
                out[2] = (unsigned char)(sum_b / sum_a);
            } else {
                out[0] = out[1] = out[2] = 0;
            }
            out[3] = (unsigned char)(sum_a / (count > 0 ? count : 1));
        }
    }
}

static int buf_contains(const char *hay, size_t hay_len, const char *needle) {
    size_t needle_len = strlen(needle);
    if (needle_len == 0 || hay_len < needle_len) return 0;
    for (size_t i = 0; i + needle_len <= hay_len; i++) {
        if (memcmp(hay + i, needle, needle_len) == 0) return 1;
    }
    return 0;
}

/* Rolling accumulation buffer for "running" substring detection — see [104]. */
static char g_recv_buf[RECV_ACCUM_CAP];
static size_t g_recv_len = 0;

static int accumulate_and_check_running(const char *data, size_t n) {
    if (n == 0) return 0;
    if (n > RECV_ACCUM_CAP) {
        data += (n - RECV_ACCUM_CAP);
        n = RECV_ACCUM_CAP;
    }
    if (g_recv_len + n > RECV_ACCUM_CAP) {
        size_t overflow = g_recv_len + n - RECV_ACCUM_CAP;
        memmove(g_recv_buf, g_recv_buf + overflow, g_recv_len - overflow);
        g_recv_len -= overflow;
    }
    memcpy(g_recv_buf + g_recv_len, data, n);
    g_recv_len += n;
    return buf_contains(g_recv_buf, g_recv_len, "running");
}

static int setup_listen_socket(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(addr.sun_path)) {
        close(fd);
        return -1;
    }
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    unlink(path); /* stale file from a previous run at this path, if any */
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    if (listen(fd, 1) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int main(void) {
    srand((unsigned int)(time(NULL) ^ getpid()));

    const char *socket_path = getenv(SOCKET_ENV_VAR);
    int standalone = (socket_path == NULL || socket_path[0] == '\0');
    int listen_fd = -1;
    int client_fd = -1;
    if (!standalone) {
        listen_fd = setup_listen_socket(socket_path);
        if (listen_fd < 0) {
            /* Can't talk to the app at all — still show the splash and
             * degrade to the standalone timeout rather than hanging or
             * bailing out silently. */
            standalone = 1;
        }
    }

    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "clientdeck-loader: cannot open X display\n");
        return 1;
    }

    int screen_num = DefaultScreen(display);
    Window root = RootWindow(display, screen_num);

    /* Target monitor: Xinerama screen 0 — see [102]. */
    int mon_x = 0, mon_y = 0;
    int mon_w = DisplayWidth(display, screen_num);
    int mon_h = DisplayHeight(display, screen_num);
    {
        int xin_event_base = 0, xin_error_base = 0;
        if (XineramaQueryExtension(display, &xin_event_base, &xin_error_base) && XineramaIsActive(display)) {
            int n = 0;
            XineramaScreenInfo *screens = XineramaQueryScreens(display, &n);
            if (screens != NULL && n > 0) {
                mon_x = screens[0].x_org;
                mon_y = screens[0].y_org;
                mon_w = screens[0].width;
                mon_h = screens[0].height;
                XFree(screens);
            }
        }
    }
    /* Displayed size: TARGET_HEIGHT_FRACTION of the target monitor's
     * height, width following the source's own aspect ratio — see [117]. */
    int disp_h = (int)((double)mon_h * TARGET_HEIGHT_FRACTION + 0.5);
    if (disp_h < 1) disp_h = 1;
    int disp_w = (int)((double)disp_h * SPLASH_IMAGE_WIDTH / (double)SPLASH_IMAGE_HEIGHT + 0.5);
    if (disp_w < 1) disp_w = 1;

    int win_x = mon_x + (mon_w - disp_w) / 2;
    int win_y = mon_y + (mon_h - disp_h) / 2;

    /* Depth-32 TrueColor visual if available, else the default — see [98]. */
    int have_argb = 0;
    XVisualInfo vinfo;
    memset(&vinfo, 0, sizeof(vinfo));
    if (XMatchVisualInfo(display, screen_num, 32, TrueColor, &vinfo)) {
        have_argb = 1;
    } else {
        vinfo.visual = DefaultVisual(display, screen_num);
        vinfo.depth = DefaultDepth(display, screen_num);
    }

    /* Colormap created unconditionally for whichever visual was picked — see [99]. */
    Colormap cmap = XCreateColormap(display, root, vinfo.visual, AllocNone);

    XSetWindowAttributes attrs;
    memset(&attrs, 0, sizeof(attrs));
    attrs.colormap = cmap;
    attrs.border_pixel = 0;
    attrs.background_pixel = 0;
    attrs.override_redirect = True;
    attrs.event_mask = ExposureMask | ButtonPressMask;
    unsigned long valuemask = CWColormap | CWBorderPixel | CWBackPixel | CWOverrideRedirect | CWEventMask;

    Window window = XCreateWindow(display, root, win_x, win_y, (unsigned int)disp_w, (unsigned int)disp_h, 0,
                                   vinfo.depth, InputOutput, vinfo.visual, valuemask, &attrs);

    /* Best-effort courtesy on top of override_redirect — see [108]. */
    {
        Atom type_atom = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
        Atom splash_atom = XInternAtom(display, "_NET_WM_WINDOW_TYPE_SPLASH", False);
        XChangeProperty(display, window, type_atom, XA_ATOM, 32, PropModeReplace, (unsigned char *)&splash_atom, 1);
    }

    XMapRaised(display, window);
    XFlush(display);

    GC gc = XCreateGC(display, window, 0, NULL);

    XImage *ximage =
        XCreateImage(display, vinfo.visual, (unsigned int)vinfo.depth, ZPixmap, 0, NULL, disp_w, disp_h, 32, 0);
    ximage->data = malloc((size_t)ximage->bytes_per_line * disp_h);

    /* Downscaled once at startup, then reused as the per-frame base — see [117]. */
    unsigned char *base = malloc((size_t)disp_w * disp_h * 4);
    downscale_source(base, disp_w, disp_h);

    unsigned char *scratch = malloc((size_t)disp_w * disp_h * 4);

    Patch patches[NUM_PATCHES];
    long start_t = now_ms();
    for (int i = 0; i < NUM_PATCHES; i++) {
        respawn_patch(&patches[i], start_t, disp_w, disp_h);
        patches[i].start_ms -= (long)i * 400L; /* stagger phases — see [103] */
    }

    LoaderState state = STATE_FADE_IN;
    long state_start = start_t;
    long process_start = start_t;

    for (;;) {
        long t = now_ms();

        if (state == STATE_FADE_IN && t - state_start >= FADE_IN_MS) {
            state = STATE_HOLD;
            state_start = t;
        }
        if (state == STATE_HOLD) {
            long ceiling = standalone ? STANDALONE_MAX_MS : MAX_WAIT_MS;
            if (t - process_start >= ceiling) {
                state = STATE_FADE_OUT;
                state_start = t;
            }
        }
        if (state == STATE_FADE_OUT && t - state_start >= FADE_OUT_MS) {
            state = STATE_DONE;
        }
        if (state == STATE_DONE) break;

        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = -1;
        int xfd = ConnectionNumber(display);
        FD_SET(xfd, &rfds);
        if (xfd > maxfd) maxfd = xfd;
        if (listen_fd >= 0) {
            FD_SET(listen_fd, &rfds);
            if (listen_fd > maxfd) maxfd = listen_fd;
        }
        if (client_fd >= 0) {
            FD_SET(client_fd, &rfds);
            if (client_fd > maxfd) maxfd = client_fd;
        }

        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = FRAME_INTERVAL_MS * 1000;
        int rv = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (rv < 0) {
            if (errno == EINTR) continue;
            break; /* unexpected select() failure — bail out rather than spin */
        }

        if (rv > 0) {
            if (listen_fd >= 0 && FD_ISSET(listen_fd, &rfds)) {
                int fd = accept(listen_fd, NULL, NULL);
                if (fd >= 0) {
                    client_fd = fd;
                    close(listen_fd);
                    listen_fd = -1;
                }
            }
            if (client_fd >= 0 && FD_ISSET(client_fd, &rfds)) {
                char buf[256];
                ssize_t n = recv(client_fd, buf, sizeof(buf), 0);
                if (n <= 0) {
                    close(client_fd);
                    client_fd = -1;
                    /* Peer gone before "running" — same ceiling-reached outcome — see [105]. */
                    if (state == STATE_HOLD) {
                        state = STATE_FADE_OUT;
                        state_start = t;
                    }
                } else if (accumulate_and_check_running(buf, (size_t)n)) {
                    if (state == STATE_HOLD) {
                        state = STATE_FADE_OUT;
                        state_start = t;
                    }
                }
            }
            if (FD_ISSET(xfd, &rfds)) {
                while (XPending(display) > 0) {
                    XEvent ev;
                    XNextEvent(display, &ev);
                    if (ev.type == ButtonPress && standalone) {
                        /* Click-to-dismiss in standalone mode — see [106]. */
                        if (state == STATE_FADE_IN || state == STATE_HOLD) {
                            state = STATE_FADE_OUT;
                            state_start = t;
                        }
                    }
                }
            }
        }

        apply_patches(patches, NUM_PATCHES, t, base, scratch, disp_w, disp_h);
        int global_alpha = compute_global_alpha(state, state_start, t);
        draw_frame(ximage, scratch, global_alpha, have_argb, disp_w, disp_h);
        XPutImage(display, window, gc, ximage, 0, 0, 0, 0, (unsigned int)disp_w, (unsigned int)disp_h);
        XFlush(display);
    }

    if (client_fd >= 0) close(client_fd);
    if (listen_fd >= 0) close(listen_fd);
    if (!standalone && socket_path != NULL) unlink(socket_path);

    XDestroyImage(ximage); /* also frees ximage->data, allocated via malloc above */
    free(scratch);
    free(base);
    XFreeGC(display, gc);
    XDestroyWindow(display, window);
    XFreeColormap(display, cmap);
    XCloseDisplay(display);
    return 0;
}
