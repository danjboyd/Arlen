/* Private v0.4.0 design probe; no Arlen runtime integration. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *what) {
  fprintf(stderr, "%s: win32=%lu\n", what, GetLastError());
  ExitProcess(2);
}

int main(int argc, char **argv) {
  if (argc == 4 && (strcmp(argv[1], "leaf") == 0 || strcmp(argv[1], "stubborn-leaf") == 0)) {
    HANDLE ready = OpenEventA(EVENT_MODIFY_STATE, FALSE, argv[2]);
    HANDLE stop = OpenEventA(SYNCHRONIZE, FALSE, argv[3]);
    if (!ready || !stop) fail("open control events");
    if (!SetEvent(ready)) fail("ready");
    if (strcmp(argv[1], "stubborn-leaf") == 0) Sleep(INFINITE);
    if (WaitForSingleObject(stop, INFINITE) != WAIT_OBJECT_0) fail("wait stop");
    CloseHandle(ready);
    CloseHandle(stop);
    return 0;
  }
  if (argc != 2) return 2;
  char readyName[128], stopName[128], executable[MAX_PATH], command[2048];
  DWORD owner = GetCurrentProcessId();
  snprintf(readyName, sizeof(readyName), "Local\\ArlenPrivateReady-%lu", owner);
  snprintf(stopName, sizeof(stopName), "Local\\ArlenPrivateStop-%lu", owner);
  HANDLE ready = CreateEventA(NULL, TRUE, FALSE, readyName);
  HANDLE stop = CreateEventA(NULL, TRUE, FALSE, stopName);
  HANDLE job = CreateJobObjectW(NULL, NULL);
  if (!ready || !stop || !job) fail("create controls");
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) fail("job limits");
  DWORD length = GetModuleFileNameA(NULL, executable, sizeof(executable));
  if (!length || length >= sizeof(executable)) fail("executable path");
  snprintf(command, sizeof(command), "\"%s\" %s %s %s", executable,
           strcmp(argv[1], "stubborn") == 0 ? "stubborn-leaf" : "leaf", readyName, stopName);
  STARTUPINFOA startup = {0};
  PROCESS_INFORMATION child = {0};
  startup.cb = sizeof(startup);
  /* No inherited handles: in particular, the leaf must never retain the job. */
  if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, CREATE_SUSPENDED,
                      NULL, NULL, &startup, &child)) fail("spawn suspended");
  if (!AssignProcessToJobObject(job, child.hProcess)) {
    TerminateProcess(child.hProcess, 2);
    WaitForSingleObject(child.hProcess, 5000);
    fail("assign job");
  }
  if (strcmp(argv[1], "unready") != 0 && ResumeThread(child.hThread) == (DWORD)-1) fail("resume");
  DWORD readiness = WaitForSingleObject(ready, 1000);
  printf("%lu %lu\n", child.dwProcessId, readiness);
  fflush(stdout);
  if (readiness != WAIT_OBJECT_0) {
    CloseHandle(job);
    if (WaitForSingleObject(child.hProcess, 5000) != WAIT_OBJECT_0) fail("unready cleanup");
  } else if (strcmp(argv[1], "close") == 0) {
    CloseHandle(job);
    if (WaitForSingleObject(child.hProcess, 5000) != WAIT_OBJECT_0) fail("close cleanup");
  } else {
    if (WaitForSingleObject(stop, INFINITE) != WAIT_OBJECT_0) fail("owner wait");
    if (WaitForSingleObject(child.hProcess, 5000) != WAIT_OBJECT_0) {
      TerminateJobObject(job, 3);
      if (WaitForSingleObject(child.hProcess, 5000) != WAIT_OBJECT_0) fail("deadline cleanup");
    }
    CloseHandle(job);
  }
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  CloseHandle(ready);
  CloseHandle(stop);
  return readiness == WAIT_OBJECT_0 ? 0 : 4;
}
