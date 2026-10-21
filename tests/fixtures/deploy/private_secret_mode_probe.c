#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

/* Linux-only fault injection. Never inspect or log the payload bytes. */
static int fixture_path(const char *path) {
  const char *root = getenv("ARLEN_PRIVATE_MODE_PROBE_ROOT");
  return root && path && strncmp(path, root, strlen(root)) == 0 && strstr(path, "/env/");
}

static int fixture_fd(int fd, struct stat *info) {
  char link[64], path[4096];
  snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  ssize_t length = readlink(link, path, sizeof(path) - 1);
  if (length < 0) return 0;
  path[length] = 0;
  return fixture_path(path) && fstat(fd, info) == 0 && S_ISREG(info->st_mode);
}

static void record(const char *event) {
  const char *path = getenv("ARLEN_PRIVATE_MODE_PROBE_LOG");
  if (!path) return;
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
  if (fd < 0) return;
  (void)syscall(SYS_write, fd, event, strlen(event));
  close(fd);
}

ssize_t write(int fd, const void *bytes, size_t length) {
  int saved = errno;
  struct stat info;
  if (length > 0 && fixture_fd(fd, &info)) {
    record("private-write\n");
    if (info.st_mode & 0077) record("unsafe-write\n");
  }
  errno = saved;
  return syscall(SYS_write, fd, bytes, length);
}

int chmod(const char *path, mode_t mode) {
  int saved = errno;
  struct stat info;
  if (fixture_path(path) && stat(path, &info) == 0 && S_ISREG(info.st_mode)) {
    if (info.st_size > 0 && (info.st_mode & 0077)) record("unsafe-chmod\n");
    if (getenv("ARLEN_PRIVATE_MODE_PROBE_DENY")) {
      record("permission-denied\n");
      errno = EACCES;
      return -1;
    }
  }
  errno = saved;
  return syscall(SYS_chmod, path, mode);
}

int fchmod(int fd, mode_t mode) {
  int saved = errno;
  struct stat info;
  if (fixture_fd(fd, &info) && getenv("ARLEN_PRIVATE_MODE_PROBE_DENY")) {
    record("permission-denied\n");
    errno = EACCES;
    return -1;
  }
  errno = saved;
  return syscall(SYS_fchmod, fd, mode);
}
