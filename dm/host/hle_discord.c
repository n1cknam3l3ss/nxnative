// Discord Rich Presence client for nxnative via Discord IPC socket.
// Supports macOS / Linux Unix domain sockets (/tmp/discord-ipc-0..9) and Windows named pipes.
// Runs completely on a background thread so host startup, game loop, and rendering are never delayed.
#include "hle_discord.h"
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#endif

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
extern void dm_discord_ios_start(const char *name, const char *id);
extern void dm_discord_ios_set_status(const char *desc);
extern void dm_discord_ios_stop(void);
extern bool dm_discord_ios_has_token(void);
#endif

// Default public Nintendo Switch Discord Client ID containing rich game presence.
// Override via environment variable DM_DISCORD_CLIENT_ID.
#define DEFAULT_CLIENT_ID "1249119754522857616"

#define RPC_OP_HANDSHAKE 0
#define RPC_OP_FRAME     1
#define RPC_OP_CLOSE     2
#define RPC_OP_PING      3
#define RPC_OP_PONG      4

static struct {
    char game_name[256];
    char game_id[32];
    char game_id_lower[32];
    char desc[256];
    char pending_desc[256];
    char client_id[64];
    char image_override[512];
    int64_t start_time;
    _Atomic int initialized;
    _Atomic int stopped;
    _Atomic int dirty;
    _Atomic int desc_dirty;
    int logging;
    pthread_mutex_t mu;
    pthread_cond_t cond;
    pthread_t thread;
#ifdef _WIN32
    HANDLE pipe;
#else
    int sock;
#endif
} g_rpc = {
    .mu = PTHREAD_MUTEX_INITIALIZER,
    .cond = PTHREAD_COND_INITIALIZER,
#ifdef _WIN32
    .pipe = INVALID_HANDLE_VALUE,
#else
    .sock = -1,
#endif
};

static void rpc_log(const char *fmt, ...) {
    if (!g_rpc.logging) return;
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[discord-rpc] ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

static void escape_json_string(const char *src, char *dst, size_t dst_cap) {
    size_t j = 0;
    for (size_t i = 0; src && src[i] && j + 4 < dst_cap; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c == '"') { dst[j++] = '\\'; dst[j++] = '"'; }
        else if (c == '\\') { dst[j++] = '\\'; dst[j++] = '\\'; }
        else if (c == '\n') { dst[j++] = '\\'; dst[j++] = 'n'; }
        else if (c == '\r') { dst[j++] = '\\'; dst[j++] = 'r'; }
        else if (c == '\t') { dst[j++] = '\\'; dst[j++] = 't'; }
        else if (c >= 0x20) { dst[j++] = (char)c; }
    }
    dst[j] = '\0';
}

static void rpc_close_socket(void) {
#ifdef _WIN32
    if (g_rpc.pipe != INVALID_HANDLE_VALUE) {
        CloseHandle(g_rpc.pipe);
        g_rpc.pipe = INVALID_HANDLE_VALUE;
    }
#else
    if (g_rpc.sock >= 0) {
        close(g_rpc.sock);
        g_rpc.sock = -1;
    }
#endif
}

static bool rpc_write_all(const void *buf, size_t len) {
#ifdef _WIN32
    if (g_rpc.pipe == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    return WriteFile(g_rpc.pipe, buf, (DWORD)len, &written, NULL) && (written == (DWORD)len);
#else
    if (g_rpc.sock < 0) return false;
    const uint8_t *p = (const uint8_t *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t n = write(g_rpc.sock, p, left);
        if (n <= 0) {
            if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
                struct timespec ts = {0, 10000000L}; // 10ms
                nanosleep(&ts, NULL);
                continue;
            }
            return false;
        }
        p += n;
        left -= (size_t)n;
    }
    return true;
#endif
}

static bool rpc_read_all(void *buf, size_t len) {
#ifdef _WIN32
    if (g_rpc.pipe == INVALID_HANDLE_VALUE) return false;
    DWORD read_bytes = 0;
    return ReadFile(g_rpc.pipe, buf, (DWORD)len, &read_bytes, NULL) && (read_bytes == (DWORD)len);
#else
    if (g_rpc.sock < 0) return false;
    uint8_t *p = (uint8_t *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t n = read(g_rpc.sock, p, left);
        if (n <= 0) {
            if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
                struct timespec ts = {0, 10000000L};
                nanosleep(&ts, NULL);
                continue;
            }
            return false;
        }
        p += n;
        left -= (size_t)n;
    }
    return true;
#endif
}

static bool rpc_send_packet(uint32_t opcode, const char *json) {
    uint32_t len = (uint32_t)strlen(json);
    uint32_t header[2] = { opcode, len };
    if (!rpc_write_all(header, sizeof(header))) return false;
    if (len > 0 && !rpc_write_all(json, len)) return false;
    return true;
}

static bool rpc_recv_packet(uint32_t *opcode_out, char *buf, size_t buf_cap) {
    uint32_t header[2];
    if (!rpc_read_all(header, sizeof(header))) return false;
    *opcode_out = header[0];
    uint32_t len = header[1];
    if (len >= buf_cap) len = (uint32_t)(buf_cap - 1);
    if (len > 0 && !rpc_read_all(buf, len)) return false;
    buf[len] = '\0';
    return true;
}

static bool rpc_connect(void) {
#ifdef _WIN32
    for (int i = 0; i < 10; i++) {
        char pipe_path[128];
        snprintf(pipe_path, sizeof(pipe_path), "\\\\.\\pipe\\discord-ipc-%d", i);
        HANDLE h = CreateFileA(pipe_path, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        if (h != INVALID_HANDLE_VALUE) {
            g_rpc.pipe = h;
            rpc_log("connected to Discord IPC pipe %s", pipe_path);
            return true;
        }
    }
    return false;
#else
    const char *env_dirs[] = {
        getenv("XDG_RUNTIME_DIR"),
        getenv("TMPDIR"),
        getenv("TMP"),
        getenv("TEMP"),
        "/tmp",
        NULL
    };

    for (int d = 0; env_dirs[d]; d++) {
        const char *base = env_dirs[d];
        if (!base || !*base) continue;
        for (int i = 0; i < 10; i++) {
            char sock_path[1024];
            snprintf(sock_path, sizeof(sock_path), "%s/discord-ipc-%d", base, i);
            int s = socket(AF_UNIX, SOCK_STREAM, 0);
            if (s < 0) continue;

            struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
            setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

            if (connect(s, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
                g_rpc.sock = s;
                rpc_log("connected to Discord IPC socket %s", sock_path);
                return true;
            }
            close(s);
        }
    }
    return false;
#endif
}

static bool rpc_handshake(void) {
    char payload[256];
    snprintf(payload, sizeof(payload), "{\"v\":1,\"client_id\":\"%s\"}", g_rpc.client_id);
    if (!rpc_send_packet(RPC_OP_HANDSHAKE, payload)) return false;

    char resp[2048];
    uint32_t op = 0;
    if (!rpc_recv_packet(&op, resp, sizeof(resp))) return false;
    rpc_log("handshake response: %s", resp);
    return op == RPC_OP_FRAME;
}

static bool rpc_send_activity(void) {
    char esc_game_name[256];
    char esc_details[256];
    char esc_state[256];
    char esc_large_image[512];

    pthread_mutex_lock(&g_rpc.mu);
    escape_json_string(g_rpc.game_name, esc_game_name, sizeof(esc_game_name));
    if (*g_rpc.desc) {
        // Dynamic presence from game (e.g. "Exploring Hyrule Surface", "Results: Hero 1...")
        escape_json_string(g_rpc.desc, esc_details, sizeof(esc_details));
        snprintf(esc_state, sizeof(esc_state), "Title ID: %s", g_rpc.game_id);
    } else {
        // Default presence before or without UserPresence::SetDescription
        strncpy(esc_details, esc_game_name, sizeof(esc_details) - 1);
        esc_details[sizeof(esc_details) - 1] = '\0';
        snprintf(esc_state, sizeof(esc_state), "Title ID: %s", g_rpc.game_id);
    }

    if (*g_rpc.image_override) {
        escape_json_string(g_rpc.image_override, esc_large_image, sizeof(esc_large_image));
    } else if (*g_rpc.game_id && strcmp(g_rpc.game_id, "0000000000000000") != 0) {
        // Universal raw artwork URL ending in .jpg (required by Discord Media Proxy)
        char url[256];
        snprintf(url, sizeof(url), "https://raw.githubusercontent.com/n1cknam3l3ss/nxnative/main/dm/games/%s/icon.jpg", g_rpc.game_id);
        escape_json_string(url, esc_large_image, sizeof(esc_large_image));
    } else {
        escape_json_string("nintendoswitch", esc_large_image, sizeof(esc_large_image));
    }
    int64_t start_time = g_rpc.start_time;
    pthread_mutex_unlock(&g_rpc.mu);

    char payload[2048];
    snprintf(payload, sizeof(payload),
        "{"
          "\"cmd\":\"SET_ACTIVITY\","
          "\"args\":{"
            "\"pid\":%d,"
            "\"activity\":{"
              "\"details\":\"%s\","
              "\"state\":\"%s\","
              "\"timestamps\":{\"start\":%lld},"
              "\"assets\":{"
                "\"large_image\":\"%s\","
                "\"large_text\":\"%s\","
                "\"small_image\":\"switch\","
                "\"small_text\":\"nxnative\""
              "}"
            "}"
          "},"
          "\"nonce\":\"1\""
        "}",
        (int)getpid(),
        esc_details,
        esc_state,
        (long long)start_time,
        esc_large_image,
        esc_game_name
    );

    rpc_log("sending activity: %s", payload);
    if (!rpc_send_packet(RPC_OP_FRAME, payload)) return false;

    char resp[1024];
    uint32_t op = 0;
    if (rpc_recv_packet(&op, resp, sizeof(resp))) {
        rpc_log("set_activity response: %s", resp);
    }
    return true;
}

static void rpc_clear_activity(void) {
    char payload[256];
    snprintf(payload, sizeof(payload),
        "{"
          "\"cmd\":\"SET_ACTIVITY\","
          "\"args\":{"
            "\"pid\":%d,"
            "\"activity\":null"
          "},"
          "\"nonce\":\"2\""
        "}",
        (int)getpid()
    );
    rpc_send_packet(RPC_OP_FRAME, payload);
}

static void *rpc_worker_thread(void *arg) {
    (void)arg;
    rpc_log("Discord RPC thread started for %s (%s)", g_rpc.game_name, g_rpc.game_id);

    while (!atomic_load(&g_rpc.stopped)) {
        bool connected = false;
        if (rpc_connect()) {
            if (rpc_handshake()) {
                connected = true;
                atomic_store(&g_rpc.dirty, 1);
            } else {
                rpc_close_socket();
            }
        }

        while (connected && !atomic_load(&g_rpc.stopped)) {
            // Apply pending description if dirty
            if (atomic_exchange(&g_rpc.desc_dirty, 0)) {
                pthread_mutex_lock(&g_rpc.mu);
                strncpy(g_rpc.desc, g_rpc.pending_desc, sizeof(g_rpc.desc) - 1);
                g_rpc.desc[sizeof(g_rpc.desc) - 1] = '\0';
                pthread_mutex_unlock(&g_rpc.mu);
                atomic_store(&g_rpc.dirty, 1);
            }

            if (atomic_exchange(&g_rpc.dirty, 0)) {
                if (!rpc_send_activity()) {
                    rpc_log("connection lost while sending activity");
                    rpc_close_socket();
                    connected = false;
                    break;
                }
            }

            // Wait up to 5 seconds for new activity updates or stop signal
            pthread_mutex_lock(&g_rpc.mu);
            if (!atomic_load(&g_rpc.stopped) && !atomic_load(&g_rpc.dirty) && !atomic_load(&g_rpc.desc_dirty)) {
                struct timespec ts;
                clock_gettime(CLOCK_REALTIME, &ts);
                ts.tv_sec += 5;
                pthread_cond_timedwait(&g_rpc.cond, &g_rpc.mu, &ts);
            }
            pthread_mutex_unlock(&g_rpc.mu);
        }

        if (atomic_load(&g_rpc.stopped)) break;

        // Discord client not found or disconnected; retry after 5 seconds
        pthread_mutex_lock(&g_rpc.mu);
        if (!atomic_load(&g_rpc.stopped)) {
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_sec += 5;
            pthread_cond_timedwait(&g_rpc.cond, &g_rpc.mu, &ts);
        }
        pthread_mutex_unlock(&g_rpc.mu);
    }

    rpc_clear_activity();
    rpc_close_socket();
    rpc_log("Discord RPC thread ended");
    return NULL;
}

void dm_discord_rpc_init(const char *game_name, const char *game_id) {
    if (atomic_exchange(&g_rpc.initialized, 1)) return;

    const char *rpc_env = getenv("DM_DISCORD_RPC");
    if (rpc_env && (!strcmp(rpc_env, "0") || !strcasecmp(rpc_env, "off") || !strcasecmp(rpc_env, "no"))) {
        return;
    }

    const char *log_env = getenv("DM_DISCORD_LOG");
    g_rpc.logging = (log_env && strcmp(log_env, "0") != 0);

    const char *client_id_env = getenv("DM_DISCORD_CLIENT_ID");
    if (client_id_env && *client_id_env) {
        strncpy(g_rpc.client_id, client_id_env, sizeof(g_rpc.client_id) - 1);
    } else {
        strncpy(g_rpc.client_id, DEFAULT_CLIENT_ID, sizeof(g_rpc.client_id) - 1);
    }

    const char *img_env = getenv("DM_DISCORD_IMAGE");
    if (img_env && *img_env) {
        strncpy(g_rpc.image_override, img_env, sizeof(g_rpc.image_override) - 1);
    }

    if (game_name && *game_name) {
        strncpy(g_rpc.game_name, game_name, sizeof(g_rpc.game_name) - 1);
    } else {
        strncpy(g_rpc.game_name, "Nintendo Switch Game", sizeof(g_rpc.game_name) - 1);
    }

    if (game_id && *game_id) {
        strncpy(g_rpc.game_id, game_id, sizeof(g_rpc.game_id) - 1);
    } else {
        strncpy(g_rpc.game_id, "0000000000000000", sizeof(g_rpc.game_id) - 1);
    }

    // Lowercase title ID for asset matching
    for (size_t i = 0; i < sizeof(g_rpc.game_id_lower) - 1 && g_rpc.game_id[i]; i++) {
        g_rpc.game_id_lower[i] = (char)tolower((unsigned char)g_rpc.game_id[i]);
        g_rpc.game_id_lower[i + 1] = '\0';
    }

    g_rpc.start_time = (int64_t)time(NULL);
    atomic_store(&g_rpc.stopped, 0);
    atomic_store(&g_rpc.dirty, 1);
    atomic_store(&g_rpc.desc_dirty, 0);

    atexit(dm_discord_rpc_stop);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (dm_discord_ios_has_token()) {
        rpc_log("Starting iOS Discord Gateway WebSocket");
        dm_discord_ios_start(g_rpc.game_name, g_rpc.game_id);
        return;
    }
#endif

    pthread_create(&g_rpc.thread, NULL, rpc_worker_thread, NULL);
}

void dm_discord_rpc_set_status(const char *desc) {
    if (!atomic_load(&g_rpc.initialized) || atomic_load(&g_rpc.stopped) || !desc) return;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (dm_discord_ios_has_token()) {
        dm_discord_ios_set_status(desc);
        return;
    }
#endif
    pthread_mutex_lock(&g_rpc.mu);
    strncpy(g_rpc.pending_desc, desc, sizeof(g_rpc.pending_desc) - 1);
    g_rpc.pending_desc[sizeof(g_rpc.pending_desc) - 1] = '\0';
    pthread_mutex_unlock(&g_rpc.mu);
    atomic_store(&g_rpc.desc_dirty, 1);
}

void dm_discord_rpc_commit(void) {
    if (!atomic_load(&g_rpc.initialized) || atomic_load(&g_rpc.stopped)) return;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (dm_discord_ios_has_token()) {
        return;
    }
#endif
    atomic_store(&g_rpc.desc_dirty, 1);
    pthread_mutex_lock(&g_rpc.mu);
    pthread_cond_signal(&g_rpc.cond);
    pthread_mutex_unlock(&g_rpc.mu);
}

void dm_discord_rpc_stop(void) {
    if (!atomic_load(&g_rpc.initialized) || atomic_exchange(&g_rpc.stopped, 1)) return;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (dm_discord_ios_has_token()) {
        dm_discord_ios_stop();
        return;
    }
#endif
    pthread_mutex_lock(&g_rpc.mu);
    pthread_cond_broadcast(&g_rpc.cond);
    pthread_mutex_unlock(&g_rpc.mu);
    pthread_join(g_rpc.thread, NULL);
}
