// Internal boomhauer watch helper. Keep the native child in a kill-on-close
// job and watch the original bash process, even if MSYS reparents a child.
#if defined(_WIN32)
#include <windows.h>

static NSString *ALNWatchQuoteArgument(NSString *argument) {
  NSMutableString *quoted = [NSMutableString stringWithString:@"\""];
  NSUInteger slashes = 0;
  for (NSUInteger index = 0; index < [argument length]; index++) {
    unichar character = [argument characterAtIndex:index];
    if (character == '\\') {
      slashes++;
      continue;
    }
    NSUInteger count = (character == '"') ? slashes * 2 + 1 : slashes;
    for (NSUInteger n = 0; n < count; n++) [quoted appendString:@"\\"];
    slashes = 0;
    [quoted appendFormat:@"%C", character];
  }
  for (NSUInteger n = 0; n < slashes * 2; n++) [quoted appendString:@"\\"];
  [quoted appendString:@"\""];
  return quoted;
}

static int ALNRunWindowsWatchChild(NSArray *arguments) {
  if ([arguments count] < 4) {
    fprintf(stderr, "boomhauer: missing Windows watch parent or child\n");
    return 2;
  }
  const char *parentText = [arguments[2] UTF8String];
  char *end = NULL;
  unsigned long parentID = strtoul(parentText, &end, 10);
  if (!parentText[0] || *end || parentID == 0 || parentID > MAXDWORD) return 2;
  HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, (DWORD)parentID);
  HANDLE job = CreateJobObjectW(NULL, NULL);
  if (parent == NULL || job == NULL) {
    if (parent != NULL) CloseHandle(parent);
    if (job != NULL) CloseHandle(job);
    fprintf(stderr, "boomhauer: cannot supervise Windows watch child\n");
    return 1;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
  ZeroMemory(&limits, sizeof(limits));
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
    CloseHandle(job);
    CloseHandle(parent);
    return 1;
  }
  NSMutableArray *parts = [NSMutableArray array];
  for (NSUInteger index = 3; index < [arguments count]; index++) {
    [parts addObject:ALNWatchQuoteArgument(arguments[index])];
  }
  NSString *command = [parts componentsJoinedByString:@" "];
  wchar_t *wideCommand = calloc([command length] + 1, sizeof(wchar_t));
  if (wideCommand == NULL) {
    CloseHandle(job);
    CloseHandle(parent);
    return 1;
  }
  [command getCharacters:(unichar *)wideCommand range:NSMakeRange(0, [command length])];
  STARTUPINFOW startup;
  ZeroMemory(&startup, sizeof(startup));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION child;
  ZeroMemory(&child, sizeof(child));
  BOOL started = WaitForSingleObject(parent, 0) == WAIT_TIMEOUT &&
      CreateProcessW(NULL, wideCommand, NULL, NULL, TRUE, CREATE_SUSPENDED,
                     NULL, NULL, &startup, &child);
  free(wideCommand);
  int status = 1;
  if (started) {
    // Fail closed: a child must never execute outside the job.
    if (!AssignProcessToJobObject(job, child.hProcess) || ResumeThread(child.hThread) == (DWORD)-1) {
      TerminateProcess(child.hProcess, 1);
      WaitForSingleObject(child.hProcess, INFINITE);
    } else {
      HANDLE waits[] = {parent, child.hProcess};
      DWORD completed = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
      if (completed == WAIT_OBJECT_0 + 1) {
        DWORD exitCode = 1;
        GetExitCodeProcess(child.hProcess, &exitCode);
        status = (int)exitCode;
      } else {
        TerminateJobObject(job, 1);
        WaitForSingleObject(child.hProcess, INFINITE);
      }
    }
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
  }
  CloseHandle(job);
  CloseHandle(parent);
  return status;
}
#endif
