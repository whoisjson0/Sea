/* spawn_time.c -- the exec-and-wait helper of the workload benchmark (DESIGN.md 6.5, 2.17.4).
 *
 * usage: spawn_time DIR OUT ERR -- PROG [ARG...]      (DIR, OUT, ERR and PROG absolute paths)
 *
 * Changes to DIR (the child inherits the working directory), spawns PROG with ARG... through
 * posix_spawn with OUT and ERR (O_WRONLY|O_CREAT|O_TRUNC, mode 0644) as its standard output and
 * standard error and /dev/null as its standard input (posix_spawn_file_actions_addopen), passing
 * this process's environment unchanged, and waits for it with wait4. CLOCK_MONOTONIC is read
 * immediately before posix_spawn and immediately after wait4 returns, so the wall time contains
 * everything the system does to create, load, run and end the process. Prints one line
 *     wall %.9f cpu %.9f status %d
 * on standard output: cpu is the child's user + system CPU time (ru_utime + ru_stime of wait4's
 * rusage), status its exit status, or 128 + the signal number when a signal ended it.
 *
 * Exit status: 0 when it measured (whatever the child's status); 2 on its own failure (usage, a
 * relative path, a failed chdir, posix_spawn or wait4), with a message on standard error and
 * nothing on standard output.
 *
 * Built with `xcrun cc -O2 -ffp-contract=off` (Mac) and `gcc -O2 -ffp-contract=off` (Linux). A
 * measuring tool, never part of Sea. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/* die: report the helper's own failure and exit 2 (nothing has been written to stdout) */
static void die(const char *what, const char *arg, int err) {
    if (err)
        fprintf(stderr, "spawn_time: %s '%s': %s\n", what, arg, strerror(err));
    else
        fprintf(stderr, "spawn_time: %s%s\n", what, arg);
    exit(2);
}

/* usage: the usage error */
static void usage(void) {
    die("usage: spawn_time DIR OUT ERR -- PROG [ARG...] (absolute paths)", "", 0);
}

/* now: CLOCK_MONOTONIC in seconds */
static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* secs: a timeval in seconds */
static double secs(struct timeval tv) {
    return (double)tv.tv_sec + (double)tv.tv_usec / 1e6;
}

int main(int argc, char **argv) {
    if (argc < 6 || strcmp(argv[4], "--") != 0) usage();
    const char *dir = argv[1], *out = argv[2], *err = argv[3], *prog = argv[5];
    /* every path absolute: the child's working directory is DIR, so a relative path would mean
     * two different things for the helper and the child */
    if (dir[0] != '/' || out[0] != '/' || err[0] != '/' || prog[0] != '/') usage();

    if (chdir(dir) != 0) die("cannot change to directory", dir, errno);

    /* the child's three standard streams, opened in the child by posix_spawn */
    posix_spawn_file_actions_t fa;
    int rc = posix_spawn_file_actions_init(&fa);
    if (rc != 0) die("posix_spawn_file_actions_init failed", "", rc);
    rc = posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    if (rc == 0) rc = posix_spawn_file_actions_addopen(&fa, 1, out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (rc == 0) rc = posix_spawn_file_actions_addopen(&fa, 2, err, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (rc != 0) die("posix_spawn_file_actions_addopen failed", "", rc);

    /* the timed region: from just before the process is created to just after its exit is
     * collected */
    pid_t pid;
    int status = 0;
    struct rusage ru;
    double t0 = now();
    rc = posix_spawn(&pid, prog, &fa, NULL, &argv[5], environ);
    if (rc != 0) die("cannot spawn", prog, rc);
    pid_t w;
    do {
        w = wait4(pid, &status, 0, &ru);
    } while (w < 0 && errno == EINTR);
    double t1 = now();
    if (w < 0) die("wait4 failed for", prog, errno);
    posix_spawn_file_actions_destroy(&fa);

    int st;
    if (WIFEXITED(status))
        st = WEXITSTATUS(status);
    else if (WIFSIGNALED(status))
        st = 128 + WTERMSIG(status);
    else
        die("unexpected wait status for ", prog, 0);
    printf("wall %.9f cpu %.9f status %d\n", t1 - t0, secs(ru.ru_utime) + secs(ru.ru_stime), st);
    if (fflush(stdout) != 0) die("cannot write the result line", "", errno);
    return 0;
}
