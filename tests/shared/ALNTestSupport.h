#ifndef ALN_TEST_SUPPORT_H
#define ALN_TEST_SUPPORT_H

#import <Foundation/Foundation.h>

#import "ALNTestPOSIXCompat.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNTestRepoRoot(void);
FOUNDATION_EXPORT NSString *ALNTestPathFromRepoRoot(NSString *relativePath);
FOUNDATION_EXPORT NSString *ALNTestShellQuote(NSString *value);
FOUNDATION_EXPORT NSString *ALNTestGNUstepSourceCommandForRepoRoot(NSString *_Nullable repoRoot);
FOUNDATION_EXPORT NSData *_Nullable ALNTestDataAtRelativePath(NSString *relativePath,
                                                              NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNTestJSONObjectAtRelativePath(NSString *relativePath,
                                                               NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNTestJSONObjectFromString(NSString *string,
                                                           NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryAtRelativePath(
    NSString *relativePath,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSDictionary *_Nullable ALNTestJSONDictionaryFromString(
    NSString *string,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSString *_Nullable ALNTestEnvironmentString(NSString *name);
FOUNDATION_EXPORT NSString *ALNTestUniqueIdentifier(NSString *prefix);
FOUNDATION_EXPORT NSString *_Nullable ALNTestTemporaryDirectory(NSString *prefix);
FOUNDATION_EXPORT BOOL ALNTestWriteUTF8File(NSString *path,
                                            NSString *content,
                                            NSError *_Nullable *_Nullable error);
// Shell command that builds the named framework tools (`arlen`, `eocc`,
// `boomhauer`, `smoke-render`) from the current directory, which must be a
// framework root. GNUstep runs `make <targets>`. Apple runs
// `./bin/build-apple --with-boomhauer`, which builds the first three
// incrementally; tools/build_apple_xctest.sh builds eoc-smoke-render and the
// example servers with the integration bundle.
FOUNDATION_EXPORT NSString *ALNTestFrameworkBuildCommand(NSString *targets);
// Where `boomhauer --prepare-only` leaves an app's binary, relative to the app
// root: .boomhauer/build/ (GNUstep) or .boomhauer/apple/ (Apple). Packaged
// releases keep the .boomhauer/build/ layout on every platform.
FOUNDATION_EXPORT NSString *ALNTestAppBinaryRelativePath(void);
// path with the .exe suffix the linker adds on Windows; unchanged elsewhere.
FOUNDATION_EXPORT NSString *ALNTestExecutablePath(NSString *path);
FOUNDATION_EXPORT NSString *ALNTestClientCompileCommand(NSArray<NSString *> *sources,
                                                        NSString *includeDirectory,
                                                        NSString *output);
// Separate file-backed streams avoid pipe deadlocks and preserve JSON stdout.
FOUNDATION_EXPORT NSDictionary *ALNTestRunShellCaptureStreams(NSString *command);
// The task must own the server PID (launch with exec, without a shell wrapper).
FOUNDATION_EXPORT BOOL ALNTestStopServerTask(NSTask *_Nullable task);
FOUNDATION_EXPORT NSString *ALNTestRunShellCapture(NSString *command, int *_Nullable exitCode);
// Shell prefix that kills the following command after `seconds`: GNU timeout
// when on PATH, else a perl alarm (macOS ships no timeout). See
// ALNTestShellTimeoutExitedByTimeout for the exit status each one reports.
FOUNDATION_EXPORT NSString *ALNTestShellTimeoutPrefix(NSUInteger seconds);
FOUNDATION_EXPORT BOOL ALNTestShellTimeoutExitedByTimeout(int exitCode);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *ALNTestShellEnvironment(
    NSDictionary<NSString *, NSString *> *environment);
// pipe() for log/stderr capture: _pipe with a 1 MiB binary buffer on Windows,
// which has no pipe(). nonBlockingRead sets O_NONBLOCK on the read end where
// the platform has it (POSIX); Windows anonymous pipes have no such mode.
FOUNDATION_EXPORT BOOL ALNTestCreatePipe(int fds[_Nonnull 2], BOOL nonBlockingRead);
// A uniform random value in [0, upperBound), for ports and unique names.
// arc4random_uniform is not available on Windows (MinGW).
FOUNDATION_EXPORT uint32_t ALNTestRandomUniform(uint32_t upperBound);
// bash for NSTask launches: /bin/bash on POSIX, MSYS2 usr/bin/bash.exe on
// Windows (ALNPlatformBashPath). Use for /bin/sh launches too.
FOUNDATION_EXPORT NSString *ALNTestBashPath(void);
// Absolute path of a tool on PATH (tool.exe on Windows), for NSTask launches
// that would otherwise go through /usr/bin/env. Launch tools directly: on
// Windows MSYS2 env.exe spawns the tool as a child instead of exec-ing it, so
// -terminate on the env task would orphan the tool. Returns the bare name when
// it is not found.
FOUNDATION_EXPORT NSString *ALNTestToolPath(NSString *tool);
// Extra compile flags and link libraries for test-built probes, matching the
// GNUmakefile (FEATURE_FLAGS, ARLEN_PLATFORM_LINK_LIBS): on Windows CLANG64
// the toolchain needs HAVE_MODE_T and static GNUstep linkage, and there is no
// libdl but Winsock and BCrypt. Empty / -ldl elsewhere.
FOUNDATION_EXPORT NSString *ALNTestPlatformObjCFlags(void);
FOUNDATION_EXPORT NSString *ALNTestPlatformLinkLibraries(void);
// YES while a process with this pid exists (kill(pid, 0) on POSIX).
FOUNDATION_EXPORT BOOL ALNTestProcessExists(int pid);

NS_ASSUME_NONNULL_END

#endif
