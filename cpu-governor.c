#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <glob.h>

/* ===== 配置 ===== */
#define MIN_FREQ        1400000L
#define TARGET_UTIL     88
#define CEILING_UTIL    93
#define FLOOR_UTIL      70
#define INTERVAL_NS     20000000L    /* 20ms */
#define STEP_DOWN_NEAR  1
#define STEP_DOWN_FAR   3
#define STEP_UP_SLOW    4
#define HYSTERESIS      10000L

/* PSI 配置 */
#define PSI_CPU_FILE    "/proc/pressure/cpu"
#define PSI_SOME_THRESHOLD  2.0      /* some avg10 超过 2.0% 视为卡顿 */
#define PSI_CHECK_UTIL_MIN  40       /* 利用率低于此值不读 PSI */
#define PSI_CHECK_UTIL_MAX  92       /* 利用率高于此值直接走常规升频 */
/* ================ */

static volatile sig_atomic_t stop_flag = 0;
static void on_signal(int sig) { (void)sig; stop_flag = 1; }

static char **policy_paths = NULL;
static long  *orig_max     = NULL;
static int    policy_count = 0;

static int read_cpu(unsigned long long *idle_out, unsigned long long *total_out) {
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return -1;
    char line[256];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return -1; }
    fclose(f);
    unsigned long long user, nice, system, idle, iowait, irq, softirq, steal;
    if (sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
        &user, &nice, &system, &idle, &iowait,
        &irq, &softirq, &steal) != 8) return -1;
    *idle_out  = idle + iowait;
    *total_out = user + nice + system + idle + iowait + irq + softirq + steal;
    return 0;
}

/* 读取 /proc/pressure/cpu 的 some avg10，返回百分比 (0.0 - 100.0)，失败返回 -1 */
static double read_psi_cpu_some_avg10(void) {
    FILE *f = fopen(PSI_CPU_FILE, "r");
    if (!f) return -1.0;
    char line[256];
    double avg10 = -1.0;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "some ", 5) != 0) continue;
        char *p = strstr(line, "avg10=");
        if (!p) break;
        if (sscanf(p, "avg10=%lf", &avg10) != 1) avg10 = -1.0;
        break;
    }
    fclose(f);
    return avg10;
}

static void write_freq(const char *path, long freq) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return;
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%ld\n", freq);
    ssize_t n = write(fd, buf, len);
    (void)n;
    close(fd);
}

static void restore(void) {
    for (int i = 0; i < policy_count; i++) {
        if (orig_max[i] > 0) {
            char p[512];
            snprintf(p, sizeof(p), "%s/scaling_max_freq", policy_paths[i]);
            write_freq(p, orig_max[i]);
        }
    }
}

int main(void) {
    if (geteuid() != 0) {
        fprintf(stderr, "cpu-governor: must run as root\n");
        return 1;
    }

    glob_t g;
    if (glob("/sys/devices/system/cpu/cpufreq/policy*", 0, NULL, &g) != 0) {
        fprintf(stderr, "cpu-governor: no cpufreq policies found\n");
        return 1;
    }
    policy_count = (int)g.gl_pathc;
    policy_paths = calloc(policy_count, sizeof(char *));
    orig_max     = calloc(policy_count, sizeof(long));

    long global_max = 0;
    for (int i = 0; i < policy_count; i++) {
        policy_paths[i] = strdup(g.gl_pathv[i]);
        char p[512];
        snprintf(p, sizeof(p), "%s/scaling_max_freq", policy_paths[i]);
        FILE *f = fopen(p, "r");
        if (f) {
            long v = 0;
            if (fscanf(f, "%ld", &v) == 1) {
                orig_max[i] = v;
                if (v > global_max) global_max = v;
            }
            fclose(f);
        }
    }
    globfree(&g);

    if (global_max <= 0) {
        fprintf(stderr, "cpu-governor: failed to read original max freq\n");
        return 1;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGHUP,  &sa, NULL);

    unsigned long long prev_idle, prev_total;
    if (read_cpu(&prev_idle, &prev_total) != 0) {
        fprintf(stderr, "cpu-governor: failed to read /proc/stat\n");
        return 1;
    }

    long current = global_max;

    while (!stop_flag) {
        struct timespec ts = { .tv_sec = 0, .tv_nsec = INTERVAL_NS };
        struct timespec rem;
        while (nanosleep(&ts, &rem) == -1 && errno == EINTR) {
            if (stop_flag) break;
            ts = rem;
        }
        if (stop_flag) break;

        unsigned long long idle, total;
        if (read_cpu(&idle, &total) != 0) continue;

        unsigned long long dt = total - prev_total;
        unsigned long long di = idle  - prev_idle;
        prev_idle  = idle;
        prev_total = total;
        if (dt == 0) continue;

        int util = (int)((dt - di) * 100ULL / dt);

        long target;

        /* ---- PSI 检查：仅在利用率中间区间读取，避免不必要的文件开销 ---- */
        double psi_pressure = -1.0;
        if (util >= PSI_CHECK_UTIL_MIN && util < PSI_CHECK_UTIL_MAX) {
            psi_pressure = read_psi_cpu_some_avg10();
        }

        /* ---- 决策逻辑 ---- */
        if (psi_pressure >= PSI_SOME_THRESHOLD) {
            /* PSI 显示真实卡顿：立刻拉满 */
            target = global_max;
        } else if (util >= CEILING_UTIL) {
            /* 利用率过高：立刻拉满 */
            target = global_max;
        } else if (util >= TARGET_UTIL) {
            /* 略高于目标：小幅升频 */
            target = current + global_max * STEP_UP_SLOW / 100;
        } else if (util < FLOOR_UTIL) {
            /* 远低于目标：加速降频 */
            target = current - global_max * STEP_DOWN_FAR / 100;
        } else {
            /* 接近目标：缓慢降频 */
            target = current - global_max * STEP_DOWN_NEAR / 100;
        }

        if (target > global_max) target = global_max;
        if (target < MIN_FREQ)   target = MIN_FREQ;

        long diff = target - current;
        if (diff < 0) diff = -diff;

        if (diff > HYSTERESIS) {
            for (int i = 0; i < policy_count; i++) {
                char p[512];
                snprintf(p, sizeof(p), "%s/scaling_max_freq", policy_paths[i]);
                write_freq(p, target);
            }
            current = target;
        }
    }

    restore();
    return 0;
}
