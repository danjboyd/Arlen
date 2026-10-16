#ifndef ALN_TEST_POSIX_COMPAT_H
#define ALN_TEST_POSIX_COMPAT_H

// POSIX environment calls the tests use, for MinGW (Windows CLANG64), which
// only has _putenv_s. _putenv_s updates the CRT and Win32 environments, and an
// empty value removes the variable.
#if defined(_WIN32)
#include <stdlib.h>

static inline int ALNTestCompatSetenv(const char *name, const char *value, int overwrite) {
  if (!overwrite && getenv(name) != NULL) {
    return 0;
  }
  return (_putenv_s(name, value ?: "") == 0) ? 0 : -1;
}

static inline int ALNTestCompatUnsetenv(const char *name) {
  return (_putenv_s(name, "") == 0) ? 0 : -1;
}

#define setenv(name, value, overwrite) ALNTestCompatSetenv((name), (value), (overwrite))
#define unsetenv(name) ALNTestCompatUnsetenv((name))
#endif

#endif
