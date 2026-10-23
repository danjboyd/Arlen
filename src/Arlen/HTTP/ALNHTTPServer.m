// Parse llhttp enums before Foundation imports WinInet status macros.
#if !defined(ARLEN_ENABLE_LLHTTP) || ARLEN_ENABLE_LLHTTP
#import "third_party/llhttp/llhttp.h"
#endif

#import "ALNHTTPServer.h"
#import "ALNResponseHeaderInternal.h"

#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <math.h>
#import <openssl/sha.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import <strings.h>
#import <sys/stat.h>
#import <time.h>
#include <signal.h>
#include <stdatomic.h>
#import "Support/ALNPlatform.h"
#import "Support/ALNPositiveInteger.h"

#if defined(_WIN32)
#include <io.h>
#include <aclapi.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#ifndef ssize_t
typedef SSIZE_T ssize_t;
#endif
#ifndef SHUT_RDWR
#define SHUT_RDWR SD_BOTH
#endif
#else
#import <arpa/inet.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <signal.h>
#import <poll.h>
#import <sys/socket.h>
#import <sys/uio.h>
#import <unistd.h>
#endif
#if defined(__linux__)
#import <sys/sendfile.h>
#endif
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#if defined(_WIN32) && !defined(SIGTERM)
#define SIGTERM SIGINT
#endif

#import "ALNApplication.h"
#import "ALNClientAddressInternal.h"
#import "ALNEventStream.h"
#import "ALNFileResponseInternal.h"
#import "ALNLogger.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRealtime.h"
#import "ALNPgRealtimeFanout.h"
#import "Support/ALNJSONSerialization.h"

typedef struct {
  NSUInteger maxRequestLineBytes;
  NSUInteger maxHeaderBytes;
  NSUInteger maxBodyBytes;
  // Bodies larger than this stream to a file instead of the connection buffer.
  NSUInteger spoolThresholdBytes;
  // Owned by the application config, which outlives every connection.
  __unsafe_unretained NSString *spoolDirectory;
  // Per-route body limits (GitHub issue 87). When active, maxBodyBytes is the
  // largest of the default and every route override (the header-stage ceiling),
  // and each request's own limit comes from its route before any body is read.
  BOOL routeBodyLimitsActive;
  // Overall time allowed for a request head once its first byte has arrived
  // (0 = no limit). connectionTimeoutSeconds bounds each read, not the head.
  NSUInteger headTimeoutMilliseconds;
  // For a connection's first request: the head deadline measured from accept
  // (monotonic ms), so it also covers a client that never sends a byte and the
  // time the connection waited for a worker. 0 for later requests.
  uint64_t firstRequestHeadDeadline;
  // Body transfer bounds, counted from the end of the head (0 = off): a total
  // time, and after a grace period an average rate the client must sustain.
  NSUInteger bodyTimeoutMilliseconds;
  NSUInteger bodyMinBytesPerSecond;
  NSUInteger bodyMinRateGraceMilliseconds;
  __unsafe_unretained ALNApplication *application;
} ALNRequestLimits;

typedef struct {
  NSUInteger listenBacklog;
  NSUInteger connectionTimeoutSeconds;
  BOOL enableReusePort;
} ALNServerSocketTuning;

typedef struct {
  NSUInteger maxConcurrentWebSocketSessions;
  NSUInteger maxConcurrentHTTPSessions;
  NSUInteger maxConcurrentHTTPWorkers;
  NSUInteger maxQueuedHTTPConnections;
  NSUInteger keepAliveParkAfterMilliseconds;
  NSUInteger webSocketPingIntervalSeconds;
  NSUInteger maxRealtimeTotalSubscribers;
  NSUInteger maxRealtimeChannelSubscribers;
} ALNRuntimeLimits;

typedef struct {
  BOOL headerComplete;
  NSUInteger headerBytes;
  NSUInteger requestLineBytes;
  NSInteger contentLength;
  NSInteger statusCode;
} ALNRequestHeadMetadata;

typedef struct {
  uint8_t *bytes;
  size_t length;
  size_t capacity;
  size_t scanOffset;
  BOOL metadataReady;
  ALNRequestHeadMetadata metadata;
  size_t expectedTotalBytes;
} ALNConnectionReadState;

@interface ALNStaticFileFDCacheEntry : NSObject

@property(nonatomic, assign) int fileDescriptor;
@property(nonatomic, assign) unsigned long long size;
@property(nonatomic, assign) unsigned long long device;
@property(nonatomic, assign) unsigned long long inode;
@property(nonatomic, assign) long long mtimeSeconds;
@property(nonatomic, assign) long mtimeNanoseconds;

@end

@implementation ALNStaticFileFDCacheEntry
@end

typedef intptr_t ALNSocketHandle;

static const ALNSocketHandle ALNInvalidSocketHandle = (ALNSocketHandle)-1;
static _Atomic(sig_atomic_t) gSignalStopRequested = 0;
// Signal handlers may only use atomic operations that cannot acquire a lock.
_Static_assert(__atomic_always_lock_free(sizeof(gSignalStopRequested), 0),
               "HTTP signal-stop flag must always be lock-free");

static void *ALNReallocWithFaults(void *pointer, size_t size);

static NSNumber *ALNBoxSocketHandle(ALNSocketHandle handle) {
  return @((long long)handle);
}

static ALNSocketHandle ALNSocketHandleFromNumber(NSNumber *value) {
  if (![value respondsToSelector:@selector(longLongValue)]) {
    return ALNInvalidSocketHandle;
  }
  return (ALNSocketHandle)[value longLongValue];
}

static const char *ALNHTTPFilesystemPathCString(NSString *path) {
  return ALNFileResponseFilesystemPathCString(path);
}

#if defined(_WIN32)
struct iovec {
  void *iov_base;
  size_t iov_len;
};

static int ALNHTTPPlatformErrnoFromSocketError(int socketError) {
  switch (socketError) {
  case WSAEINTR:
    return EINTR;
  case WSAEWOULDBLOCK:
    return EWOULDBLOCK;
  case WSAEINVAL:
    return EINVAL;
  case WSAEMFILE:
    return EMFILE;
  case WSAENOBUFS:
    return ENOBUFS;
#ifdef WSA_NOT_ENOUGH_MEMORY
  case WSA_NOT_ENOUGH_MEMORY:
    return ENOMEM;
#endif
#ifdef WSAENOMEM
  case WSAENOMEM:
    return ENOMEM;
#endif
  case WSAEADDRINUSE:
    return EADDRINUSE;
  case WSAEADDRNOTAVAIL:
    return EADDRNOTAVAIL;
  case WSAECONNRESET:
    return ECONNRESET;
  case WSAETIMEDOUT:
    return ETIMEDOUT;
  case WSAENOTSOCK:
    return ENOTSOCK;
  default:
    return EIO;
  }
}

static SOCKET ALNNativeSocketHandle(ALNSocketHandle handle) {
  return (handle == ALNInvalidSocketHandle) ? INVALID_SOCKET : (SOCKET)handle;
}

static ALNSocketHandle ALNSocketHandleFromNative(SOCKET handle) {
  return (handle == INVALID_SOCKET) ? ALNInvalidSocketHandle : (ALNSocketHandle)handle;
}

static void ALNSyncErrnoFromWSA(void) {
  errno = ALNHTTPPlatformErrnoFromSocketError(WSAGetLastError());
}

static BOOL ALNInitializeSocketLayer(void) {
  static BOOL attempted = NO;
  static BOOL initialized = NO;
  @synchronized([ALNHTTPServer class]) {
    if (!attempted) {
      WSADATA socketData;
      attempted = YES;
      initialized = (WSAStartup(MAKEWORD(2, 2), &socketData) == 0);
    }
    return initialized;
  }
}

static void ALNReportSocketError(const char *label) {
  char *messageBuffer = NULL;
  DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                FORMAT_MESSAGE_IGNORE_INSERTS;
  DWORD errorCode = (DWORD)WSAGetLastError();
  DWORD length = FormatMessageA(flags,
                                NULL,
                                errorCode,
                                0,
                                (LPSTR)&messageBuffer,
                                0,
                                NULL);
  if (length > 0 && messageBuffer != NULL) {
    while (length > 0 &&
           (messageBuffer[length - 1] == '\r' || messageBuffer[length - 1] == '\n')) {
      messageBuffer[length - 1] = '\0';
      length -= 1;
    }
    fprintf(stderr, "%s: %s\n", label, messageBuffer);
    LocalFree(messageBuffer);
    return;
  }
  fprintf(stderr, "%s: Winsock error %lu\n", label, (unsigned long)errorCode);
}

// WINBOOL, not BOOL: ObjC BOOL is signed char, the Win32 handler returns int.
static WINBOOL WINAPI ALNConsoleControlHandler(DWORD controlType) {
  switch (controlType) {
  case CTRL_C_EVENT:
  case CTRL_BREAK_EVENT:
  case CTRL_CLOSE_EVENT:
  case CTRL_SHUTDOWN_EVENT:
    atomic_store_explicit(&gSignalStopRequested, 1, memory_order_relaxed);
    return TRUE;
  default:
    return FALSE;
  }
}

static ALNSocketHandle ALNSocketOpen(int domain, int type, int protocol) {
  SOCKET handle = socket(domain, type, protocol);
  if (handle == INVALID_SOCKET) {
    ALNSyncErrnoFromWSA();
  }
  return ALNSocketHandleFromNative(handle);
}

static int ALNSocketClose(ALNSocketHandle handle) {
  if (handle == ALNInvalidSocketHandle) {
    return 0;
  }
  int rc = closesocket(ALNNativeSocketHandle(handle));
  if (rc != 0) {
    ALNSyncErrnoFromWSA();
  }
  return rc;
}

static int ALNSocketShutdown(ALNSocketHandle handle) {
  int rc = shutdown(ALNNativeSocketHandle(handle), SD_BOTH);
  if (rc != 0) {
    ALNSyncErrnoFromWSA();
  }
  return rc;
}

static int ALNSocketSetIntOption(ALNSocketHandle handle, int level, int optionName, int value) {
  int rc = setsockopt(ALNNativeSocketHandle(handle),
                      level,
                      optionName,
                      (const char *)&value,
                      sizeof(value));
  if (rc != 0) {
    ALNSyncErrnoFromWSA();
  }
  return rc;
}

static int ALNSocketBind(ALNSocketHandle handle,
                         const struct sockaddr *address,
                         socklen_t addressLength) {
  int rc = bind(ALNNativeSocketHandle(handle), address, addressLength);
  if (rc != 0) {
    ALNSyncErrnoFromWSA();
  }
  return rc;
}

static int ALNSocketListen(ALNSocketHandle handle, int backlog) {
  int rc = listen(ALNNativeSocketHandle(handle), backlog);
  if (rc != 0) {
    ALNSyncErrnoFromWSA();
  }
  return rc;
}

static ALNSocketHandle ALNSocketAccept(ALNSocketHandle handle) {
  SOCKET accepted = accept(ALNNativeSocketHandle(handle), NULL, NULL);
  if (accepted == INVALID_SOCKET) {
    ALNSyncErrnoFromWSA();
  }
  return ALNSocketHandleFromNative(accepted);
}

static ssize_t ALNSocketRecv(ALNSocketHandle handle, void *buffer, size_t length, int flags) {
  int received = recv(ALNNativeSocketHandle(handle), (char *)buffer, (int)length, flags);
  if (received == SOCKET_ERROR) {
    ALNSyncErrnoFromWSA();
    return -1;
  }
  return (ssize_t)received;
}

static ssize_t ALNSocketSend(ALNSocketHandle handle,
                             const void *buffer,
                             size_t length,
                             int flags) {
  int sent =
      send(ALNNativeSocketHandle(handle), (const char *)buffer, (int)length, flags);
  if (sent == SOCKET_ERROR) {
    ALNSyncErrnoFromWSA();
    return -1;
  }
  return (ssize_t)sent;
}

static int ALNSocketGetPeerName(ALNSocketHandle handle,
                                struct sockaddr *address,
                                socklen_t *addressLength) {
  int nativeLength = (addressLength != NULL) ? (int)(*addressLength) : 0;
  int rc = getpeername(ALNNativeSocketHandle(handle), address, &nativeLength);
  if (addressLength != NULL) {
    *addressLength = (socklen_t)nativeLength;
  }
  if (rc != 0) {
    ALNSyncErrnoFromWSA();
  }
  return rc;
}

static int ALNInetPton(int family, const char *text, void *addressBuffer) {
  int rc = InetPtonA(family, text, addressBuffer);
  if (rc != 1) {
    errno = (rc == 0) ? EINVAL : EIO;
  }
  return rc;
}

static const char *ALNInetNtop(int family,
                               const void *addressBuffer,
                               char *textBuffer,
                               size_t textBufferLength) {
  PCSTR result = InetNtopA(family, (PVOID)addressBuffer, textBuffer, (DWORD)textBufferLength);
  if (result == NULL) {
    ALNSyncErrnoFromWSA();
  }
  return result;
}

typedef WSAPOLLFD ALNPollEntry;

static void ALNPollEntrySet(ALNPollEntry *entry, ALNSocketHandle handle) {
  entry->fd = ALNNativeSocketHandle(handle);
  entry->events = POLLIN;
  entry->revents = 0;
}

static int ALNSocketPoll(ALNPollEntry *entries, size_t count, int timeoutMilliseconds) {
  int rc = WSAPoll(entries, (ULONG)count, timeoutMilliseconds);
  if (rc == SOCKET_ERROR) {
    ALNSyncErrnoFromWSA();
    return -1;
  }
  return rc;
}

// WSAPoll only takes sockets, so the idle-connection watcher's wake channel is
// a non-blocking loopback UDP socket connected to itself; both ends are that
// one socket.
static BOOL ALNWakeChannelOpen(ALNSocketHandle *readEnd, ALNSocketHandle *writeEnd) {
  SOCKET handle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (handle == INVALID_SOCKET) {
    return NO;
  }
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  address.sin_port = 0;
  int addressLength = (int)sizeof(address);
  u_long nonBlocking = 1;
  if (bind(handle, (struct sockaddr *)&address, addressLength) != 0 ||
      getsockname(handle, (struct sockaddr *)&address, &addressLength) != 0 ||
      connect(handle, (struct sockaddr *)&address, addressLength) != 0 ||
      ioctlsocket(handle, FIONBIO, &nonBlocking) != 0) {
    closesocket(handle);
    return NO;
  }
  (void)SetHandleInformation((HANDLE)handle, HANDLE_FLAG_INHERIT, 0);
  *readEnd = ALNSocketHandleFromNative(handle);
  *writeEnd = *readEnd;
  return YES;
}

static void ALNWakeChannelSignal(ALNSocketHandle writeEnd) {
  char byte = 1;
  (void)send(ALNNativeSocketHandle(writeEnd), &byte, 1, 0);
}

static void ALNWakeChannelDrain(ALNSocketHandle readEnd) {
  char drain[64];
  while (recv(ALNNativeSocketHandle(readEnd), drain, (int)sizeof(drain), 0) > 0) {
  }
}

static void ALNWakeChannelClose(ALNSocketHandle readEnd, ALNSocketHandle writeEnd) {
  ALNSocketClose(readEnd);
  if (writeEnd != readEnd) {
    ALNSocketClose(writeEnd);
  }
}
#else
static BOOL ALNInitializeSocketLayer(void) {
  return YES;
}

static void ALNReportSocketError(const char *label) {
  perror(label);
}

static ALNSocketHandle ALNSocketOpen(int domain, int type, int protocol) {
  return (ALNSocketHandle)socket(domain, type, protocol);
}

static int ALNSocketClose(ALNSocketHandle handle) {
  return close((int)handle);
}

static int ALNSocketShutdown(ALNSocketHandle handle) {
  return shutdown((int)handle, SHUT_RDWR);
}

static int ALNSocketSetIntOption(ALNSocketHandle handle, int level, int optionName, int value) {
  return setsockopt((int)handle, level, optionName, &value, sizeof(value));
}

static int ALNSocketBind(ALNSocketHandle handle,
                         const struct sockaddr *address,
                         socklen_t addressLength) {
  return bind((int)handle, address, addressLength);
}

static int ALNSocketListen(ALNSocketHandle handle, int backlog) {
  return listen((int)handle, backlog);
}

static ALNSocketHandle ALNSocketAccept(ALNSocketHandle handle) {
  return (ALNSocketHandle)accept((int)handle, NULL, NULL);
}

static ssize_t ALNSocketRecv(ALNSocketHandle handle, void *buffer, size_t length, int flags) {
  return recv((int)handle, buffer, length, flags);
}

static ssize_t ALNSocketSend(ALNSocketHandle handle,
                             const void *buffer,
                             size_t length,
                             int flags) {
  return send((int)handle, buffer, length, flags);
}

static int ALNSocketGetPeerName(ALNSocketHandle handle,
                                struct sockaddr *address,
                                socklen_t *addressLength) {
  return getpeername((int)handle, address, addressLength);
}

static int ALNInetPton(int family, const char *text, void *addressBuffer) {
  return inet_pton(family, text, addressBuffer);
}

static const char *ALNInetNtop(int family,
                               const void *addressBuffer,
                               char *textBuffer,
                               size_t textBufferLength) {
  return inet_ntop(family, addressBuffer, textBuffer, textBufferLength);
}

typedef struct pollfd ALNPollEntry;

static void ALNPollEntrySet(ALNPollEntry *entry, ALNSocketHandle handle) {
  entry->fd = (int)handle;
  entry->events = POLLIN;
  entry->revents = 0;
}

static int ALNSocketPoll(ALNPollEntry *entries, size_t count, int timeoutMilliseconds) {
  return poll(entries, (nfds_t)count, timeoutMilliseconds);
}

static BOOL ALNWakeChannelOpen(ALNSocketHandle *readEnd, ALNSocketHandle *writeEnd) {
  int fds[2];
  if (pipe(fds) != 0) {
    return NO;
  }
  for (int idx = 0; idx < 2; idx++) {
    int flags = fcntl(fds[idx], F_GETFL, 0);
    (void)fcntl(fds[idx], F_SETFL, flags | O_NONBLOCK);
    (void)fcntl(fds[idx], F_SETFD, FD_CLOEXEC);
  }
  *readEnd = (ALNSocketHandle)fds[0];
  *writeEnd = (ALNSocketHandle)fds[1];
  return YES;
}

static void ALNWakeChannelSignal(ALNSocketHandle writeEnd) {
  uint8_t byte = 1;
  (void)write((int)writeEnd, &byte, 1);
}

static void ALNWakeChannelDrain(ALNSocketHandle readEnd) {
  uint8_t drain[64];
  while (read((int)readEnd, drain, sizeof(drain)) > 0) {
  }
}

static void ALNWakeChannelClose(ALNSocketHandle readEnd, ALNSocketHandle writeEnd) {
  close((int)readEnd);
  close((int)writeEnd);
}
#endif

static void ALNHandleSignal(int sig) {
  (void)sig;
  atomic_store_explicit(&gSignalStopRequested, 1, memory_order_relaxed);
}

static BOOL ALNSignalStopRequested(void) {
  return (atomic_load_explicit(&gSignalStopRequested, memory_order_relaxed) != 0);
}

static BOOL ALNInstallSignalHandler(int sig) {
#if defined(_WIN32)
  BOOL consoleInstalled = (SetConsoleCtrlHandler(ALNConsoleControlHandler, TRUE) != 0);
  void (*installedHandler)(int) = signal(sig, ALNHandleSignal);
  BOOL signalInstalled = (installedHandler != SIG_ERR);
  return (consoleInstalled || signalInstalled);
#else
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = ALNHandleSignal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;
  return (sigaction(sig, &action, NULL) == 0);
#endif
}

static BOOL ALNConfigBool(NSDictionary *config, NSString *key, BOOL defaultValue) {
  id value = config[key];
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return defaultValue;
}

static double ALNNowMilliseconds(void) {
  return ALNPlatformNowMilliseconds();
}

static NSUInteger ALNConfigUInt(NSDictionary *dict, NSString *key, NSUInteger defaultValue) {
  NSNumber *value = ALNPositiveInteger(dict[key]);
  return value != nil ? value.unsignedIntegerValue : defaultValue;
}

// Body clocks document zero as a disable/no-grace value. Keep strict positive
// parsing for other inputs, rather than truncating fractions or malformed text.
static NSUInteger ALNConfigClockUInt(NSDictionary *dict, NSString *key, NSUInteger defaultValue) {
  id value = dict[key];
  if ([value isKindOfClass:[NSNumber class]] && [value isEqualToNumber:@0]) return 0;
  if ([value isKindOfClass:[NSString class]]) {
    NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 0 && [text rangeOfCharacterFromSet:
        [[NSCharacterSet characterSetWithCharactersInString:@"0"] invertedSet]].location == NSNotFound) return 0;
  }
  return ALNConfigUInt(dict, key, defaultValue);
}

static NSUInteger ALNConfigUIntAllowZero(NSDictionary *dict, NSString *key, NSUInteger defaultValue) {
  id value = dict[key];
  if ([value respondsToSelector:@selector(integerValue)]) {
    NSInteger parsed = [value integerValue];
    if (parsed >= 0) {
      return (NSUInteger)parsed;
    }
  }
  return defaultValue;
}

static ALNRequestLimits ALNLimitsFromConfig(NSDictionary *config) {
  NSDictionary *limits = config[@"requestLimits"] ?: @{};
  ALNRequestLimits out;
  out.maxRequestLineBytes = ALNConfigUInt(limits, @"maxRequestLineBytes", 4096);
  out.maxHeaderBytes = ALNConfigUInt(limits, @"maxHeaderBytes", 32768);
  out.maxBodyBytes = ALNConfigUInt(limits, @"maxBodyBytes", 1048576);
  out.spoolThresholdBytes = ALNConfigUInt(limits, @"spoolThresholdBytes", 1048576);
  out.spoolDirectory = [limits[@"spoolDirectory"] isKindOfClass:[NSString class]] ? limits[@"spoolDirectory"] : nil;
  out.routeBodyLimitsActive = NO;
  NSUInteger headTimeoutSeconds = ALNConfigUInt(limits, @"requestHeadTimeoutSeconds", 15);
  out.headTimeoutMilliseconds = (headTimeoutSeconds > 86400) ? 86400000 : headTimeoutSeconds * 1000;
  out.firstRequestHeadDeadline = 0;
  NSUInteger bodyTimeoutSeconds = ALNConfigClockUInt(limits, @"requestBodyTimeoutSeconds", 300);
  out.bodyTimeoutMilliseconds = (bodyTimeoutSeconds > 86400) ? 86400000 : bodyTimeoutSeconds * 1000;
  out.bodyMinBytesPerSecond = ALNConfigClockUInt(limits, @"requestBodyMinBytesPerSecond", 1024);
  NSUInteger graceSeconds = ALNConfigClockUInt(limits, @"requestBodyMinRateGraceSeconds", 10);
  out.bodyMinRateGraceMilliseconds = (graceSeconds > 86400) ? 86400000 : graceSeconds * 1000;
  out.application = nil;
  return out;
}

static ALNServerSocketTuning ALNTuningFromConfig(NSDictionary *config) {
  ALNServerSocketTuning out;
  out.listenBacklog = ALNConfigUInt(config, @"listenBacklog", 128);
  out.connectionTimeoutSeconds = ALNConfigUInt(config, @"connectionTimeoutSeconds", 30);
  out.enableReusePort = ALNConfigBool(config, @"enableReusePort", NO);
  return out;
}

// realtime.fanout (GitHub issue 48): cross-process fanout for ALNRealtimeHub so
// live push reaches websocket subscribers on every propane worker.
static id<ALNRealtimeFanout> ALNRealtimeFanoutFromConfig(NSDictionary *config, NSString **failure) {
  NSDictionary *realtime = [config[@"realtime"] isKindOfClass:[NSDictionary class]] ? config[@"realtime"] : @{};
  NSDictionary *fanout = [realtime[@"fanout"] isKindOfClass:[NSDictionary class]] ? realtime[@"fanout"] : nil;
  NSString *adapter = [fanout[@"adapter"] isKindOfClass:[NSString class]] ? [fanout[@"adapter"] lowercaseString] : @"";
  if ([adapter length] == 0 || [adapter isEqualToString:@"memory"]) {
    return nil;
  }
  if (![adapter isEqualToString:@"postgresql"]) {
    if (failure != NULL) *failure = [NSString stringWithFormat:@"unsupported realtime.fanout.adapter '%@'", adapter];
    return nil;
  }
  NSString *dsn = [fanout[@"connectionString"] isKindOfClass:[NSString class]] ? fanout[@"connectionString"] : @"";
  const char *envDSN = getenv("ARLEN_DATABASE_URL");
  if ([dsn length] == 0 && envDSN != NULL && envDSN[0] != '\0') {
    dsn = [NSString stringWithUTF8String:envDSN];
  }
  if ([dsn length] == 0) {
    NSDictionary *database = [config[@"database"] isKindOfClass:[NSDictionary class]] ? config[@"database"] : @{};
    dsn = [database[@"connectionString"] isKindOfClass:[NSString class]] ? database[@"connectionString"] : @"";
  }
  NSError *error = nil;
  ALNPgRealtimeFanout *pgFanout =
      [[ALNPgRealtimeFanout alloc] initWithConnectionString:dsn
                                              notifyChannel:[fanout[@"channel"] isKindOfClass:[NSString class]] ? fanout[@"channel"] : nil
                                                        hub:[ALNRealtimeHub sharedHub]
                                                      error:&error];
  if (pgFanout == nil) {
    if (failure != NULL) *failure = error.localizedDescription ?: @"could not create the PostgreSQL realtime fanout";
    return nil;
  }
  if (![pgFanout startWaitingUpTo:5.0]) {
    fprintf(stderr, "arlen: realtime fanout not listening yet; it keeps retrying in the background\n");
  }
  return pgFanout;
}

// Once per process: a websocket channel under several propane workers (or a
// multi-node cluster) without a fanout only sees publishes from its own worker.
static void ALNWarnIfRealtimeIsWorkerLocal(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    const char *workers = getenv("ARLEN_PROPANE_WORKERS");
    const char *cluster = getenv("ARLEN_CLUSTER_ENABLED");
    BOOL multiProcess = (workers != NULL && atoi(workers) > 1) || (cluster != NULL && atoi(cluster) == 1);
    if (multiProcess && [ALNRealtimeHub sharedHub].fanout == nil) {
      fprintf(stderr,
              "arlen: warning: websocket channels are process-local; with multiple propane workers a publish only "
              "reaches subscribers on the same worker. Configure realtime.fanout = { adapter = \"postgresql\"; } "
              "(docs/LIVE_UI.md).\n");
    }
  });
}

static ALNRuntimeLimits ALNRuntimeLimitsFromConfig(NSDictionary *config) {
  NSDictionary *runtimeLimits = config[@"runtimeLimits"] ?: @{};
  ALNRuntimeLimits out;
  out.maxConcurrentWebSocketSessions =
      ALNConfigUInt(runtimeLimits, @"maxConcurrentWebSocketSessions", 256);
  out.maxConcurrentHTTPSessions =
      ALNConfigUInt(runtimeLimits, @"maxConcurrentHTTPSessions", 256);
  out.maxConcurrentHTTPWorkers =
      ALNConfigUInt(runtimeLimits, @"maxConcurrentHTTPWorkers", 8);
  out.maxQueuedHTTPConnections =
      ALNConfigUInt(runtimeLimits, @"maxQueuedHTTPConnections", 256);
  out.keepAliveParkAfterMilliseconds =
      ALNConfigUIntAllowZero(runtimeLimits, @"keepAliveParkAfterMilliseconds", 5);
  out.webSocketPingIntervalSeconds =
      ALNConfigUIntAllowZero(runtimeLimits, @"webSocketPingIntervalSeconds", 25);
  out.maxRealtimeTotalSubscribers =
      ALNConfigUIntAllowZero(runtimeLimits, @"maxRealtimeTotalSubscribers", 0);
  out.maxRealtimeChannelSubscribers =
      ALNConfigUIntAllowZero(runtimeLimits, @"maxRealtimeChannelSubscribers", 0);
  return out;
}

static NSString *ALNRequestDispatchModeFromConfig(NSDictionary *config) {
  id raw = config[@"requestDispatchMode"];
  if (![raw isKindOfClass:[NSString class]]) {
    return @"concurrent";
  }
  NSString *normalized = [[(NSString *)raw lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"serialized"]) {
    return @"serialized";
  }
  return @"concurrent";
}

static ALNHTTPParserBackend ALNHTTPParserBackendFromConfig(NSDictionary *config) {
  id raw = config[@"httpParserBackend"];
  if ([raw isKindOfClass:[NSString class]]) {
    NSString *normalized = [[(NSString *)raw lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized isEqualToString:@"legacy"] ||
        [normalized isEqualToString:@"manual"] ||
        [normalized isEqualToString:@"string"]) {
      return ALNHTTPParserBackendLegacy;
    }
    if ([normalized isEqualToString:@"llhttp"]) {
      return [ALNRequest isLLHTTPAvailable] ? ALNHTTPParserBackendLLHTTP
                                            : ALNHTTPParserBackendLegacy;
    }
  }
  return [ALNRequest resolvedParserBackend];
}

static NSArray *ALNWebSocketAllowedOriginsFromConfig(NSDictionary *config) {
  NSDictionary *webSocket = [config[@"webSocket"] isKindOfClass:[NSDictionary class]]
                                ? config[@"webSocket"]
                                : @{};
  return [webSocket[@"allowedOrigins"] isKindOfClass:[NSArray class]]
             ? webSocket[@"allowedOrigins"]
             : @[];
}

static void ALNApplyClientSocketTimeout(ALNSocketHandle clientFd, NSUInteger timeoutSeconds) {
  if (timeoutSeconds == 0) {
    return;
  }

#if defined(_WIN32)
  DWORD timeoutMilliseconds = (DWORD)(timeoutSeconds * 1000U);
  (void)setsockopt(ALNNativeSocketHandle(clientFd),
                   SOL_SOCKET,
                   SO_RCVTIMEO,
                   (const char *)&timeoutMilliseconds,
                   sizeof(timeoutMilliseconds));
  (void)setsockopt(ALNNativeSocketHandle(clientFd),
                   SOL_SOCKET,
                   SO_SNDTIMEO,
                   (const char *)&timeoutMilliseconds,
                   sizeof(timeoutMilliseconds));
#else
  struct timeval timeout;
  timeout.tv_sec = (time_t)timeoutSeconds;
  timeout.tv_usec = 0;

  (void)setsockopt((int)clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  (void)setsockopt((int)clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#endif
}

// File responses go out as two writes (the header, then the sendfile body).
// With Nagle on, a keep-alive connection's body waits for the client's delayed
// ACK of the header, about 40 ms per response (#243).
static void ALNApplyClientSocketNoDelay(ALNSocketHandle clientFd) {
  int enabled = 1;
#if defined(_WIN32)
  (void)setsockopt(ALNNativeSocketHandle(clientFd), IPPROTO_TCP, TCP_NODELAY, (const char *)&enabled,
                   sizeof(enabled));
#else
  (void)setsockopt((int)clientFd, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled));
#endif
}

static BOOL ALNIsWhitespaceByte(uint8_t value) {
  return value == ' ' || value == '\t' || value == '\r' || value == '\n' || value == '\f' ||
         value == '\v';
}

static BOOL ALNAsciiEqualsIgnoreCase(const uint8_t *bytes, NSUInteger length, const char *literal) {
  if (bytes == NULL || literal == NULL) {
    return NO;
  }
  NSUInteger literalLength = (NSUInteger)strlen(literal);
  if (length != literalLength) {
    return NO;
  }
  for (NSUInteger idx = 0; idx < length; idx++) {
    uint8_t left = bytes[idx];
    uint8_t right = (uint8_t)literal[idx];
    if (left >= 'A' && left <= 'Z') {
      left = (uint8_t)(left - 'A' + 'a');
    }
    if (right >= 'A' && right <= 'Z') {
      right = (uint8_t)(right - 'A' + 'a');
    }
    if (left != right) {
      return NO;
    }
  }
  return YES;
}

static BOOL ALNParseContentLengthBytes(const uint8_t *bytes,
                                       NSUInteger length,
                                       NSInteger *contentLengthOut) {
  if (contentLengthOut != NULL) {
    *contentLengthOut = 0;
  }
  if (bytes == NULL || length == 0) {
    return YES;
  }

  NSUInteger start = 0;
  while (start < length && ALNIsWhitespaceByte(bytes[start])) {
    start += 1;
  }
  NSUInteger end = length;
  while (end > start && ALNIsWhitespaceByte(bytes[end - 1])) {
    end -= 1;
  }
  if (start >= end) {
    return NO;
  }

  unsigned long long parsed = 0ULL;
  BOOL overflow = NO;
  for (NSUInteger idx = start; idx < end; idx++) {
    uint8_t ch = bytes[idx];
    if (ch < '0' || ch > '9') {
      return NO;
    }
    unsigned long long digit = (unsigned long long)(ch - '0');
    if (!overflow &&
        (parsed > (ULLONG_MAX / 10ULL) ||
         (parsed == (ULLONG_MAX / 10ULL) && digit > (ULLONG_MAX % 10ULL)))) {
      overflow = YES;
      continue;
    }
    if (overflow) {
      continue;
    }
    parsed = (parsed * 10ULL) + digit;
  }

  if (overflow || parsed > (unsigned long long)NSIntegerMax) {
    if (contentLengthOut != NULL) {
      *contentLengthOut = NSIntegerMax;
    }
    return YES;
  }
  if (contentLengthOut != NULL) {
    *contentLengthOut = (NSInteger)parsed;
  }
  return YES;
}

static void ALNConnectionReadStateResetMetadata(ALNConnectionReadState *readState) {
  if (readState == NULL) {
    return;
  }
  readState->metadataReady = NO;
  readState->scanOffset = 0;
  memset(&readState->metadata, 0, sizeof(readState->metadata));
  readState->expectedTotalBytes = 0;
}

static void ALNConnectionReadStateInit(ALNConnectionReadState *readState) {
  if (readState == NULL) {
    return;
  }
  memset(readState, 0, sizeof(*readState));
  ALNConnectionReadStateResetMetadata(readState);
}

static void ALNConnectionReadStateDestroy(ALNConnectionReadState *readState) {
  if (readState == NULL) {
    return;
  }
  if (readState->bytes != NULL) {
    free(readState->bytes);
  }
  readState->bytes = NULL;
  readState->length = 0;
  readState->capacity = 0;
  ALNConnectionReadStateResetMetadata(readState);
}

static BOOL ALNConnectionReadStateEnsureCapacity(ALNConnectionReadState *readState, size_t required) {
  if (readState == NULL) {
    return NO;
  }
  if (required <= readState->capacity) {
    return YES;
  }
  if (required > (size_t)SIZE_MAX / 2) {
    return NO;
  }

  size_t target = (readState->capacity > 0) ? readState->capacity : 8192;
  while (target < required) {
    if (target > SIZE_MAX / 2) {
      target = required;
      break;
    }
    target *= 2;
  }

  void *resized = ALNReallocWithFaults(readState->bytes, target);
  if (resized == NULL) {
    return NO;
  }
  readState->bytes = (uint8_t *)resized;
  readState->capacity = target;
  return YES;
}

static BOOL ALNConnectionReadStateAppend(ALNConnectionReadState *readState,
                                         const void *bytes,
                                         size_t length) {
  if (readState == NULL || bytes == NULL || length == 0) {
    return YES;
  }
  if (readState->length > SIZE_MAX - length) {
    return NO;
  }
  size_t required = readState->length + length;
  if (!ALNConnectionReadStateEnsureCapacity(readState, required)) {
    return NO;
  }
  memcpy(readState->bytes + readState->length, bytes, length);
  readState->length += length;
  return YES;
}

static void ALNConnectionReadStateConsumePrefix(ALNConnectionReadState *readState, size_t consumedLength) {
  if (readState == NULL || consumedLength == 0) {
    return;
  }
  if (consumedLength >= readState->length) {
    readState->length = 0;
    ALNConnectionReadStateResetMetadata(readState);
    return;
  }

  size_t remaining = readState->length - consumedLength;
  memmove(readState->bytes, readState->bytes + consumedLength, remaining);
  readState->length = remaining;
  ALNConnectionReadStateResetMetadata(readState);
}

static size_t ALNFindHeaderTerminator(const uint8_t *bytes, size_t length, size_t startOffset) {
  if (bytes == NULL || length < 4) {
    return SIZE_MAX;
  }
  size_t start = startOffset;
  if (start > 3) {
    start -= 3;
  } else {
    start = 0;
  }
  if (start + 3 >= length) {
    start = (length >= 4) ? (length - 4) : 0;
  }

  for (size_t idx = start; idx + 3 < length; idx++) {
    if (bytes[idx] == '\r' &&
        bytes[idx + 1] == '\n' &&
        bytes[idx + 2] == '\r' &&
        bytes[idx + 3] == '\n') {
      return idx;
    }
  }
  return SIZE_MAX;
}

static BOOL ALNParseRequestHeadMetadataBytes(const uint8_t *bytes,
                                             size_t headerBytes,
                                             ALNRequestLimits limits,
                                             ALNRequestHeadMetadata *metadataOut) {
  ALNRequestHeadMetadata metadata;
  metadata.headerComplete = NO;
  metadata.headerBytes = 0;
  metadata.requestLineBytes = 0;
  metadata.contentLength = 0;
  metadata.statusCode = 0;

  if (bytes == NULL || headerBytes < 4) {
    if (metadataOut != NULL) {
      *metadataOut = metadata;
    }
    return NO;
  }
  if (headerBytes > limits.maxHeaderBytes) {
    metadata.statusCode = 431;
    if (metadataOut != NULL) {
      *metadataOut = metadata;
    }
    return NO;
  }

  size_t separatorLocation = headerBytes - 4;
  NSUInteger requestLineBytes = (NSUInteger)separatorLocation;
  for (size_t idx = 0; idx + 1 < separatorLocation; idx++) {
    if (bytes[idx] == '\r' && bytes[idx + 1] == '\n') {
      requestLineBytes = (NSUInteger)idx;
      break;
    }
  }
  if (requestLineBytes > limits.maxRequestLineBytes) {
    metadata.statusCode = 431;
    if (metadataOut != NULL) {
      *metadataOut = metadata;
    }
    return NO;
  }

  NSInteger contentLength = 0;
  BOOL sawContentLength = NO;
  size_t lineStart = (size_t)requestLineBytes;
  if (lineStart + 1 < separatorLocation &&
      bytes[lineStart] == '\r' &&
      bytes[lineStart + 1] == '\n') {
    lineStart += 2;
  }
  while (lineStart < separatorLocation) {
    size_t lineEnd = lineStart;
    while (lineEnd + 1 < headerBytes &&
           !(bytes[lineEnd] == '\r' && bytes[lineEnd + 1] == '\n')) {
      lineEnd += 1;
    }
    if (lineEnd + 1 >= headerBytes || lineEnd > separatorLocation) {
      metadata.statusCode = 400;
      if (metadataOut != NULL) {
        *metadataOut = metadata;
      }
      return NO;
    }
    if (lineEnd == lineStart) {
      lineStart += 2;
      continue;
    }

    size_t colon = lineStart;
    while (colon < lineEnd && bytes[colon] != ':') {
      colon += 1;
    }
    if (colon < lineEnd) {
      size_t nameStart = lineStart;
      size_t nameEnd = colon;
      while (nameStart < nameEnd && ALNIsWhitespaceByte(bytes[nameStart])) {
        nameStart += 1;
      }
      while (nameEnd > nameStart && ALNIsWhitespaceByte(bytes[nameEnd - 1])) {
        nameEnd -= 1;
      }
      if (ALNAsciiEqualsIgnoreCase(bytes + nameStart, (NSUInteger)(nameEnd - nameStart), "content-length")) {
        if (sawContentLength) {
          metadata.statusCode = 400;
          if (metadataOut != NULL) {
            *metadataOut = metadata;
          }
          return NO;
        }
        NSInteger parsedContentLength = 0;
        if (!ALNParseContentLengthBytes(bytes + colon + 1,
                                        (NSUInteger)(lineEnd - (colon + 1)),
                                        &parsedContentLength)) {
          metadata.statusCode = 400;
          if (metadataOut != NULL) {
            *metadataOut = metadata;
          }
          return NO;
        }
        sawContentLength = YES;
        contentLength = parsedContentLength;
      } else if (ALNAsciiEqualsIgnoreCase(bytes + nameStart,
                                          (NSUInteger)(nameEnd - nameStart),
                                          "transfer-encoding")) {
        metadata.statusCode = 400;
        if (metadataOut != NULL) {
          *metadataOut = metadata;
        }
        return NO;
      }
    }
    lineStart = lineEnd + 2;
  }

  if (contentLength < 0 || (NSUInteger)contentLength > limits.maxBodyBytes) {
    metadata.statusCode = 413;
    if (metadataOut != NULL) {
      *metadataOut = metadata;
    }
    return NO;
  }
  if ((NSUInteger)contentLength > NSUIntegerMax - (NSUInteger)headerBytes) {
    metadata.statusCode = 413;
    if (metadataOut != NULL) {
      *metadataOut = metadata;
    }
    return NO;
  }

  metadata.headerComplete = YES;
  metadata.headerBytes = (NSUInteger)headerBytes;
  metadata.requestLineBytes = requestLineBytes;
  metadata.contentLength = contentLength;
  if (metadataOut != NULL) {
    *metadataOut = metadata;
  }
  return YES;
}

static BOOL ALNHeaderContainsToken(NSString *value, NSString *needleLower) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0 ||
      ![needleLower isKindOfClass:[NSString class]] || [needleLower length] == 0) {
    return NO;
  }
  NSArray *parts = [[value lowercaseString] componentsSeparatedByString:@","];
  for (NSString *candidate in parts) {
    NSString *trimmed =
        [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed isEqualToString:needleLower]) {
      return YES;
    }
  }
  return NO;
}

static NSString *ALNOriginHostDisplayString(NSString *host) {
  if (![host isKindOfClass:[NSString class]] || [host length] == 0) {
    return @"";
  }
  if ([host rangeOfString:@":"].location != NSNotFound && ![host hasPrefix:@"["]) {
    return [NSString stringWithFormat:@"[%@]", host];
  }
  return host;
}

static NSString *ALNNormalizedOriginString(NSString *origin) {
  if (![origin isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [origin stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }

  NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
  NSString *scheme = [[components scheme] lowercaseString];
  NSString *host = [[components host] lowercaseString];
  NSNumber *port = [components port];
  NSString *path = [components path];
  if ([scheme length] == 0 || [host length] == 0) {
    return nil;
  }
  if ([[components user] length] > 0 || [[components password] length] > 0 ||
      [[components query] length] > 0 || [[components fragment] length] > 0) {
    return nil;
  }
  if ([path length] > 0 && ![path isEqualToString:@"/"]) {
    return nil;
  }

  BOOL omitPort = NO;
  if (port != nil) {
    NSInteger portValue = [port integerValue];
    omitPort = ([scheme isEqualToString:@"http"] && portValue == 80) ||
               ([scheme isEqualToString:@"https"] && portValue == 443);
  }
  if (port != nil && !omitPort) {
    return [NSString stringWithFormat:@"%@://%@:%ld",
                                      scheme,
                                      ALNOriginHostDisplayString(host),
                                      (long)[port integerValue]];
  }
  return [NSString stringWithFormat:@"%@://%@", scheme, ALNOriginHostDisplayString(host)];
}

static BOOL ALNWebSocketOriginAllowed(ALNRequest *request, NSArray *allowedOrigins) {
  if ([allowedOrigins count] == 0) {
    NSString *rawOrigin = [request headerValueForName:@"origin"];
    if ([rawOrigin length] == 0) return YES; // Native clients may omit Origin.
    NSString *origin = ALNNormalizedOriginString(rawOrigin);
    NSURL *url = [NSURL URLWithString:origin];
    NSString *expected = ALNNormalizedOriginString([NSString stringWithFormat:@"%@://%@",
        url.scheme, [request headerValueForName:@"host"] ?: @""]);
    return [origin length] > 0 && [expected isEqualToString:origin];
  }
  NSString *origin = ALNNormalizedOriginString([request headerValueForName:@"origin"]);
  if ([origin length] == 0) {
    return NO;
  }
  return [allowedOrigins containsObject:origin];
}

static NSUInteger ALNWebSocketReadTimeoutMilliseconds(void) {
  const char *raw = getenv("ARLEN_WEBSOCKET_READ_TIMEOUT_MS");
  if (raw == NULL || raw[0] == '\0') {
    return 5000;
  }
  char *end = NULL;
  unsigned long parsed = strtoul(raw, &end, 10);
  if (end == raw || (end != NULL && *end != '\0')) {
    return 5000;
  }
  if (parsed < 100) {
    return 100;
  }
  if (parsed > 60000) {
    return 60000;
  }
  return (NSUInteger)parsed;
}

static BOOL ALNWebSocketClientKeyIsValid(NSString *key) {
  if (![key isKindOfClass:[NSString class]]) {
    return NO;
  }
  NSString *trimmed =
      [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return NO;
  }
  NSData *decoded = [[NSData alloc] initWithBase64EncodedString:trimmed options:0];
  return [decoded length] == 16;
}

static BOOL ALNRequestIsWebSocketUpgrade(ALNRequest *request) {
  if (request == nil || ![request.method isEqualToString:@"GET"]) {
    return NO;
  }
  NSString *upgrade = [request headerValueForName:@"upgrade"];
  NSString *connection = [request headerValueForName:@"connection"];
  NSString *key = [request headerValueForName:@"sec-websocket-key"];
  NSString *version = [request headerValueForName:@"sec-websocket-version"];
  if (!ALNHeaderContainsToken(upgrade, @"websocket")) {
    return NO;
  }
  if (!ALNHeaderContainsToken(connection, @"upgrade")) {
    return NO;
  }
  NSString *trimmedVersion =
      [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (![trimmedVersion isEqualToString:@"13"]) {
    return NO;
  }
  return ALNWebSocketClientKeyIsValid(key);
}

static BOOL ALNShouldKeepAliveForRequest(ALNRequest *request, ALNResponse *response) {
  if (request == nil || response == nil) {
    return NO;
  }

  NSString *responseConnection = [[response headerForName:@"Connection"] lowercaseString];
  if (ALNHeaderContainsToken(responseConnection, @"close")) {
    return NO;
  }
  if (ALNHeaderContainsToken(responseConnection, @"keep-alive")) {
    return YES;
  }

  NSString *requestConnection = [[request headerValueForName:@"connection"] lowercaseString];
  if (ALNHeaderContainsToken(requestConnection, @"close")) {
    return NO;
  }

  NSString *version = [[request.httpVersion ?: @"HTTP/1.1" uppercaseString] copy];
  if ([version isEqualToString:@"HTTP/1.0"]) {
    return ALNHeaderContainsToken(requestConnection, @"keep-alive");
  }
  return YES;
}

static NSString *ALNWebSocketAcceptKey(NSString *clientKey) {
  if (!ALNWebSocketClientKeyIsValid(clientKey)) {
    return @"";
  }
  NSString *trimmedKey =
      [clientKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *combined = [trimmedKey stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
  NSData *combinedData = [combined dataUsingEncoding:NSUTF8StringEncoding];
  if (combinedData == nil) {
    return @"";
  }
  unsigned char digest[SHA_DIGEST_LENGTH];
  SHA1([combinedData bytes], (unsigned long)[combinedData length], digest);
  NSData *digestData = [NSData dataWithBytes:digest length:SHA_DIGEST_LENGTH];
  return [digestData base64EncodedStringWithOptions:0] ?: @"";
}

static NSLock *gALNFaultInjectionLock = nil;
static NSMutableSet *gALNFaultInjectionConsumed = nil;

static BOOL ALNEnvFlagEnabled(const char *name) {
  if (name == NULL || name[0] == '\0') {
    return NO;
  }
  const char *raw = getenv(name);
  if (raw == NULL || raw[0] == '\0') {
    return NO;
  }
  if (strcmp(raw, "0") == 0) {
    return NO;
  }
  if (strcasecmp(raw, "false") == 0 || strcasecmp(raw, "off") == 0 ||
      strcasecmp(raw, "no") == 0) {
    return NO;
  }
  return YES;
}

static void ALNEnsureFaultInjectionState(void) {
  if (gALNFaultInjectionLock != nil && gALNFaultInjectionConsumed != nil) {
    return;
  }
  @synchronized([ALNHTTPServer class]) {
    if (gALNFaultInjectionLock == nil) {
      gALNFaultInjectionLock = [[NSLock alloc] init];
    }
    if (gALNFaultInjectionConsumed == nil) {
      gALNFaultInjectionConsumed = [NSMutableSet set];
    }
  }
}

static BOOL ALNConsumeFaultOnce(const char *name) {
  if (!ALNEnvFlagEnabled(name)) {
    return NO;
  }
  ALNEnsureFaultInjectionState();
  NSString *key = [NSString stringWithUTF8String:name];
  if ([key length] == 0) {
    return NO;
  }
  BOOL shouldInject = NO;
  [gALNFaultInjectionLock lock];
  if (![gALNFaultInjectionConsumed containsObject:key]) {
    [gALNFaultInjectionConsumed addObject:key];
    shouldInject = YES;
  }
  [gALNFaultInjectionLock unlock];
  return shouldInject;
}

static void ALNTransientWriteBackoff(void) {
  ALNPlatformSleepMilliseconds(1);
}

static ssize_t ALNRecvWithFaults(ALNSocketHandle fd, void *buffer, size_t length, int flags) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_RECV_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  return ALNSocketRecv(fd, buffer, length, flags);
}

static ssize_t ALNSendWithFaults(ALNSocketHandle fd,
                                 const void *bytes,
                                 size_t length,
                                 int flags) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SEND_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SEND_SHORT_ONCE") && bytes != NULL && length > 0) {
    size_t partial = (length > 1) ? 1 : length;
    return ALNSocketSend(fd, bytes, partial, flags);
  }
  return ALNSocketSend(fd, bytes, length, flags);
}

static ssize_t ALNWritevWithFaults(ALNSocketHandle fd, const struct iovec *iov, int iovcnt) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_WRITEV_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_WRITEV_EAGAIN_ONCE")) {
    errno = EAGAIN;
    return -1;
  }
#if defined(_WIN32)
  (void)fd;
  (void)iov;
  (void)iovcnt;
  errno = ENOTSUP;
  return -1;
#else
  if (ALNConsumeFaultOnce("ARLEN_FAULT_WRITEV_SHORT_ONCE") && iov != NULL && iovcnt > 0 &&
      iov[0].iov_base != NULL && iov[0].iov_len > 0) {
    size_t partial = (iov[0].iov_len > 1) ? 1 : iov[0].iov_len;
    return write((int)fd, iov[0].iov_base, partial);
  }
  return writev((int)fd, iov, iovcnt);
#endif
}

static void *ALNReallocWithFaults(void *pointer, size_t size) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_ALLOC_READSTATE_REALLOC_ONCE")) {
    errno = ENOMEM;
    return NULL;
  }
  return realloc(pointer, size);
}

static int ALNOpenWithFaults(const char *path, int flags) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_STATIC_OPEN_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  return ALNFileResponseOpenPath([NSString stringWithUTF8String:path], flags);
}

static int ALNFstatWithFaults(int fd, struct stat *statBuffer) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_STATIC_STAT_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  return fstat(fd, statBuffer);
}

static int ALNStatWithFaults(const char *path, struct stat *statBuffer) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_PATH_STAT_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  return ALNFileResponseStatPath([NSString stringWithUTF8String:path], statBuffer);
}

#ifdef __linux__
static ssize_t ALNSendfileWithFaults(ALNSocketHandle outFd,
                                     int inFd,
                                     off_t *offset,
                                     size_t count) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SENDFILE_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SENDFILE_EAGAIN_ONCE")) {
    errno = EAGAIN;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SENDFILE_FORCE_FALLBACK_ONCE")) {
    errno = EINVAL;
    return -1;
  }
  return sendfile((int)outFd, inFd, offset, count);
}
#endif

static int ALNOpenWithRetry(const char *path, int openFlags) {
  for (int attempt = 0; attempt < 6; attempt++) {
    int opened = ALNOpenWithFaults(path, openFlags);
    if (opened >= 0) {
      return opened;
    }
    if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
      return -1;
    }
    ALNTransientWriteBackoff();
  }
  return -1;
}

static int ALNFstatWithRetry(int fd, struct stat *statBuffer) {
  for (int attempt = 0; attempt < 6; attempt++) {
    int rc = ALNFstatWithFaults(fd, statBuffer);
    if (rc == 0) {
      return 0;
    }
    if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
      return -1;
    }
    ALNTransientWriteBackoff();
  }
  return -1;
}

static int ALNStatWithRetry(const char *path, struct stat *statBuffer) {
  for (int attempt = 0; attempt < 6; attempt++) {
    int rc = ALNStatWithFaults(path, statBuffer);
    if (rc == 0) {
      return 0;
    }
    if (errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
      return -1;
    }
    ALNTransientWriteBackoff();
  }
  return -1;
}

static uint64_t ALNMonotonicMilliseconds(void);

// One budget covers the header and body, including sendfile and fallback writes.
typedef struct {
  uint64_t started;
  uint64_t sent;
  NSUInteger timeoutMilliseconds;
  NSUInteger minBytesPerSecond;
  NSUInteger graceMilliseconds;
  BOOL expired;
} ALNResponseSendBudget;

static BOOL ALNResponseSendAllowed(ALNResponseSendBudget *budget) {
  if (budget == NULL) return YES;
  uint64_t elapsed = ALNMonotonicMilliseconds() - budget->started;
  if ((budget->timeoutMilliseconds > 0 && elapsed >= budget->timeoutMilliseconds) ||
      (budget->minBytesPerSecond > 0 && elapsed > budget->graceMilliseconds &&
       (double)budget->sent * 1000.0 < (double)budget->minBytesPerSecond * elapsed)) {
    budget->expired = YES;
    errno = ETIMEDOUT;
    return NO;
  }
  return YES;
}

static BOOL ALNSendAllWithBudget(ALNSocketHandle fd, const void *bytes, size_t length, ALNResponseSendBudget *budget) {
  const unsigned char *cursor = (const unsigned char *)bytes;
  size_t remaining = length;
  int transientRetries = 0;
  while (remaining > 0) {
    if (!ALNResponseSendAllowed(budget)) return NO;
    ssize_t written = ALNSendWithFaults(fd, cursor, remaining, 0);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      if ((errno == EAGAIN || errno == EWOULDBLOCK) && (budget != NULL || transientRetries < 32)) {
        transientRetries += 1;
        ALNTransientWriteBackoff();
        continue;
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
    if (budget != NULL) budget->sent += (uint64_t)written;
    transientRetries = 0;
    cursor += (size_t)written;
    remaining -= (size_t)written;
  }
  return YES;
}

// Realtime writes are confined to a session thread and have a total deadline.
// A non-reading peer must release its session even after partial progress.
static BOOL ALNRealtimeSendAll(ALNSocketHandle fd, const void *bytes, size_t length) {
#if defined(_WIN32)
  DWORD timeout = 1000;
  (void)setsockopt(ALNNativeSocketHandle(fd), SOL_SOCKET, SO_SNDTIMEO,
                   (const char *)&timeout, sizeof(timeout));
#else
  struct timeval timeout = {1, 0};
  (void)setsockopt((int)fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#endif
  const unsigned char *cursor = bytes;
  double deadline = ALNNowMilliseconds() + 5000.0;
  while (length > 0) {
    if (ALNNowMilliseconds() >= deadline) return NO;
    ssize_t written = ALNSendWithFaults(fd, cursor, length, 0);
    if (written <= 0) {
      if (written < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
      return NO;
    }
    cursor += written;
    length -= (size_t)written;
  }
  return YES;
}

static BOOL ALNWritevAll(ALNSocketHandle fd, const struct iovec *iov, int iovcnt, ALNResponseSendBudget *budget) {
  if (iov == NULL || iovcnt <= 0) {
    return YES;
  }

  struct iovec localIOV[8];
  if (iovcnt > (int)(sizeof(localIOV) / sizeof(localIOV[0]))) {
    return NO;
  }
  for (int idx = 0; idx < iovcnt; idx++) {
    localIOV[idx] = iov[idx];
  }

  int current = 0;
  int transientRetries = 0;
  while (current < iovcnt) {
    if (!ALNResponseSendAllowed(budget)) return NO;
    ssize_t written = ALNWritevWithFaults(fd, &localIOV[current], iovcnt - current);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      if ((errno == EAGAIN || errno == EWOULDBLOCK) && (budget != NULL || transientRetries < 32)) {
        transientRetries += 1;
        ALNTransientWriteBackoff();
        continue;
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
    if (budget != NULL) budget->sent += (uint64_t)written;
    transientRetries = 0;

    ssize_t remainingWrite = written;
    while (current < iovcnt && remainingWrite > 0) {
      size_t segmentLength = localIOV[current].iov_len;
      if ((size_t)remainingWrite >= segmentLength) {
        remainingWrite -= (ssize_t)segmentLength;
        current += 1;
        continue;
      }

      localIOV[current].iov_base = ((char *)localIOV[current].iov_base) + remainingWrite;
      localIOV[current].iov_len -= (size_t)remainingWrite;
      remainingWrite = 0;
    }
  }
  return YES;
}

static BOOL ALNSendAll(ALNSocketHandle fd, const void *bytes, size_t length) {
  return ALNSendAllWithBudget(fd, bytes, length, NULL);
}

static NSLock *gALNStaticFileFDCacheLock = nil;
static NSMutableDictionary *gALNStaticFileFDCacheEntries = nil;
static NSMutableArray *gALNStaticFileFDCacheLRU = nil;
static NSUInteger gALNStaticFileFDCacheCapacity = 64;

static long ALNStaticFileMTimeNanoseconds(const struct stat *fileStat) {
  if (fileStat == NULL) {
    return 0;
  }
#if defined(__linux__)
  return fileStat->st_mtim.tv_nsec;
#elif defined(__APPLE__)
  return fileStat->st_mtimespec.tv_nsec;
#else
  return 0;
#endif
}

static void ALNEnsureStaticFileFDCache(void) {
  static BOOL initialized = NO;
  if (initialized) {
    return;
  }
  @synchronized([ALNHTTPServer class]) {
    if (initialized) {
      return;
    }
    gALNStaticFileFDCacheLock = [[NSLock alloc] init];
    gALNStaticFileFDCacheEntries = [NSMutableDictionary dictionary];
    gALNStaticFileFDCacheLRU = [NSMutableArray array];
#if defined(_WIN32)
    gALNStaticFileFDCacheCapacity = 0;
#endif

    const char *rawCapacity = getenv("ARLEN_STATIC_FILE_FD_CACHE_CAPACITY");
    if (rawCapacity != NULL && rawCapacity[0] != '\0') {
      char *end = NULL;
      long parsed = strtol(rawCapacity, &end, 10);
      if (end != rawCapacity && parsed >= 0) {
        gALNStaticFileFDCacheCapacity = (NSUInteger)parsed;
      }
    }
    initialized = YES;
  }
}

static BOOL ALNStaticFileFDCacheEntryMatches(ALNStaticFileFDCacheEntry *entry,
                                             unsigned long long device,
                                             unsigned long long inode,
                                             unsigned long long size,
                                             long long mtimeSeconds,
                                             long mtimeNanoseconds) {
  if (entry == nil) {
    return NO;
  }
  return entry.device == device &&
         entry.inode == inode &&
         entry.size == size &&
         entry.mtimeSeconds == mtimeSeconds &&
         entry.mtimeNanoseconds == mtimeNanoseconds &&
         entry.fileDescriptor >= 0;
}

static void ALNStaticFileFDCacheTouchLocked(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return;
  }
  NSUInteger existingIndex = [gALNStaticFileFDCacheLRU indexOfObject:path];
  if (existingIndex != NSNotFound) {
    [gALNStaticFileFDCacheLRU removeObjectAtIndex:existingIndex];
  }
  [gALNStaticFileFDCacheLRU addObject:path];
}

static void ALNStaticFileFDCacheRemoveLocked(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return;
  }
  ALNStaticFileFDCacheEntry *entry =
      [gALNStaticFileFDCacheEntries[path] isKindOfClass:[ALNStaticFileFDCacheEntry class]]
          ? gALNStaticFileFDCacheEntries[path]
          : nil;
  if (entry != nil && entry.fileDescriptor >= 0) {
    close(entry.fileDescriptor);
    entry.fileDescriptor = -1;
  }
  [gALNStaticFileFDCacheEntries removeObjectForKey:path];
  [gALNStaticFileFDCacheLRU removeObject:path];
}

static void ALNStaticFileFDCacheEvictOverflowLocked(void) {
  while (gALNStaticFileFDCacheCapacity > 0 &&
         [gALNStaticFileFDCacheLRU count] > gALNStaticFileFDCacheCapacity) {
    NSString *evictedPath =
        ([gALNStaticFileFDCacheLRU count] > 0) ? gALNStaticFileFDCacheLRU[0] : nil;
    if (![evictedPath isKindOfClass:[NSString class]] || [evictedPath length] == 0) {
      break;
    }
    ALNStaticFileFDCacheRemoveLocked(evictedPath);
  }
}

static int ALNStaticFileFDForPath(NSString *path,
                                  unsigned long long device,
                                  unsigned long long inode,
                                  unsigned long long size,
                                  long long mtimeSeconds,
                                  long mtimeNanoseconds) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return -1;
  }
  const char *filesystemPath = ALNHTTPFilesystemPathCString(path);
  if (filesystemPath == NULL) {
    return -1;
  }

  int openFlags = O_RDONLY;
#if defined(_WIN32) && defined(O_BINARY)
  openFlags |= O_BINARY;
#endif
#ifdef O_CLOEXEC
  openFlags |= O_CLOEXEC;
#endif
#ifdef O_NOFOLLOW
  openFlags |= O_NOFOLLOW;
#endif

  // Some dynamic file responses only set a path + length and do not populate
  // cache-validation metadata. In that case, bypass the shared fd cache and
  // stream directly from a fresh descriptor.
  if (device == 0 || inode == 0) {
    return ALNOpenWithRetry(filesystemPath, openFlags);
  }

  ALNEnsureStaticFileFDCache();
  if (gALNStaticFileFDCacheCapacity == 0
#if defined(_WIN32)
      || YES // The Windows seek/read fallback needs an independent file position.
#endif
  ) {
    int opened = ALNOpenWithRetry(filesystemPath, openFlags);
    if (opened < 0) return -1;
    struct stat openedStat;
    if (ALNFstatWithRetry(opened, &openedStat) != 0 || !S_ISREG(openedStat.st_mode) ||
        (unsigned long long)openedStat.st_dev != device ||
        (unsigned long long)openedStat.st_ino != inode ||
        (unsigned long long)openedStat.st_size != size ||
        (long long)openedStat.st_mtime != mtimeSeconds ||
        ALNStaticFileMTimeNanoseconds(&openedStat) != mtimeNanoseconds) {
      close(opened);
      return -1;
    }
    return opened;
  }

  [gALNStaticFileFDCacheLock lock];
  ALNStaticFileFDCacheEntry *entry =
      [gALNStaticFileFDCacheEntries[path] isKindOfClass:[ALNStaticFileFDCacheEntry class]]
          ? gALNStaticFileFDCacheEntries[path]
          : nil;
  if (entry != nil &&
      !ALNStaticFileFDCacheEntryMatches(entry, device, inode, size, mtimeSeconds, mtimeNanoseconds)) {
    ALNStaticFileFDCacheRemoveLocked(path);
    entry = nil;
  }

  if (entry == nil) {
    int opened = ALNOpenWithRetry(filesystemPath, openFlags);
    if (opened < 0) {
      [gALNStaticFileFDCacheLock unlock];
      return -1;
    }

    struct stat openedStat;
    if (ALNFstatWithRetry(opened, &openedStat) != 0 || !S_ISREG(openedStat.st_mode)) {
      close(opened);
      [gALNStaticFileFDCacheLock unlock];
      return -1;
    }

    unsigned long long openedDevice = (unsigned long long)openedStat.st_dev;
    unsigned long long openedInode = (unsigned long long)openedStat.st_ino;
    unsigned long long openedSize = (unsigned long long)openedStat.st_size;
    long long openedMTimeSeconds = (long long)openedStat.st_mtime;
    long openedMTimeNanoseconds = ALNStaticFileMTimeNanoseconds(&openedStat);
    if (openedDevice != device ||
        openedInode != inode ||
        openedSize != size ||
        openedMTimeSeconds != mtimeSeconds ||
        openedMTimeNanoseconds != mtimeNanoseconds) {
      close(opened);
      [gALNStaticFileFDCacheLock unlock];
      return -1;
    }

    entry = [[ALNStaticFileFDCacheEntry alloc] init];
    entry.fileDescriptor = opened;
    entry.device = openedDevice;
    entry.inode = openedInode;
    entry.size = openedSize;
    entry.mtimeSeconds = openedMTimeSeconds;
    entry.mtimeNanoseconds = openedMTimeNanoseconds;
    gALNStaticFileFDCacheEntries[path] = entry;
    ALNStaticFileFDCacheTouchLocked(path);
    ALNStaticFileFDCacheEvictOverflowLocked();
  } else {
    ALNStaticFileFDCacheTouchLocked(path);
  }

  int duplicated = (entry.fileDescriptor >= 0) ? ALNFileResponseDuplicateReadDescriptor(entry.fileDescriptor) : -1;
  [gALNStaticFileFDCacheLock unlock];
  return duplicated;
}

static void ALNStaticFileFDCacheClear(void) {
  ALNEnsureStaticFileFDCache();
  [gALNStaticFileFDCacheLock lock];
  NSArray *allKeys = [gALNStaticFileFDCacheEntries allKeys];
  for (NSString *key in allKeys) {
    ALNStaticFileFDCacheRemoveLocked(key);
  }
  [gALNStaticFileFDCacheLock unlock];
}

static BOOL ALNSendFileReadFallback(ALNSocketHandle clientFd,
                                    int fileFd,
                                    unsigned long long remaining,
                                    off_t offset, ALNResponseSendBudget *budget) {
  if (remaining == 0) {
    return YES;
  }

  unsigned char buffer[16384];
  while (remaining > 0) {
    if (!ALNResponseSendAllowed(budget)) return NO;
    size_t chunk = (remaining > (unsigned long long)sizeof(buffer))
                       ? sizeof(buffer)
                       : (size_t)remaining;
#if defined(_WIN32)
    if (lseek(fileFd, offset, SEEK_SET) < 0) return NO;
    ssize_t readBytes = read(fileFd, buffer, chunk);
#else
    ssize_t readBytes = pread(fileFd, buffer, chunk, offset);
#endif
    if (readBytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (readBytes == 0) {
      return NO;
    }
    if (!ALNSendAllWithBudget(clientFd, buffer, (size_t)readBytes, budget)) {
      return NO;
    }
    remaining -= (unsigned long long)readBytes;
    offset += readBytes;
  }
  return YES;
}

static BOOL ALNSendFileDescriptor(ALNSocketHandle clientFd,
                                  int fileFd,
                                  unsigned long long byteLength,
                                  unsigned long long byteOffset, ALNResponseSendBudget *budget) {
  if (fileFd < 0) {
    return NO;
  }
  BOOL ok = NO;
  unsigned long long remaining = byteLength;
#ifdef __linux__
  off_t offset = (off_t)byteOffset;
  int transientRetries = 0;
  while (remaining > 0) {
    if (!ALNResponseSendAllowed(budget)) return NO;
    size_t chunk = (remaining > (unsigned long long)SSIZE_MAX)
                       ? (size_t)SSIZE_MAX
                       : (size_t)remaining;
    ssize_t sent = ALNSendfileWithFaults(clientFd, fileFd, &offset, chunk);
    if (sent < 0) {
      if (errno == EINTR) {
        continue;
      }
      if ((errno == EAGAIN || errno == EWOULDBLOCK) && (budget != NULL || transientRetries < 32)) {
        transientRetries += 1;
        ALNTransientWriteBackoff();
        continue;
      }
      if (errno == EINVAL || errno == ENOSYS) {
        ok = ALNSendFileReadFallback(clientFd, fileFd, remaining, offset, budget);
        goto cleanup;
      }
      ok = NO;
      goto cleanup;
    }
    if (sent == 0) {
      break;
    }
    transientRetries = 0;
    if (budget != NULL) budget->sent += (uint64_t)sent;
    remaining -= (unsigned long long)sent;
  }
  ok = (remaining == 0);
  if (!ok) {
    ok = ALNSendFileReadFallback(clientFd, fileFd, remaining, offset, budget);
  }
#else
  ok = ALNSendFileReadFallback(clientFd, fileFd, remaining, (off_t)byteOffset, budget);
#endif

#ifdef __linux__
cleanup:
#endif
  return ok;
}

static BOOL ALNRecvAll(ALNSocketHandle fd,
                       void *buffer,
                       size_t length,
                       NSUInteger timeoutMilliseconds) {
  unsigned char *cursor = (unsigned char *)buffer;
  size_t remaining = length;
  NSUInteger effectiveTimeoutMilliseconds = (timeoutMilliseconds > 0) ? timeoutMilliseconds : 5000;
  double deadlineMs = ALNNowMilliseconds() + (double)effectiveTimeoutMilliseconds;
  while (remaining > 0) {
    ssize_t readBytes = ALNRecvWithFaults(fd, cursor, remaining, 0);
    if (readBytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        if (ALNNowMilliseconds() >= deadlineMs) {
          return NO;
        }
        ALNTransientWriteBackoff();
        continue;
      }
      return NO;
    }
    if (readBytes == 0) {
      return NO;
    }
    cursor += (size_t)readBytes;
    remaining -= (size_t)readBytes;
    deadlineMs = ALNNowMilliseconds() + (double)effectiveTimeoutMilliseconds;
  }
  return YES;
}

static NSData *ALNWebSocketFrameData(uint8_t opcode, NSData *payload) {
  NSData *body = payload ?: [NSData data];
  NSUInteger length = [body length];
  NSMutableData *frame = [NSMutableData data];
  uint8_t first = (uint8_t)(0x80 | (opcode & 0x0F));
  [frame appendBytes:&first length:1];

  if (length <= 125) {
    uint8_t second = (uint8_t)length;
    [frame appendBytes:&second length:1];
  } else if (length <= 65535) {
    uint8_t second = 126;
    uint16_t networkLength = htons((uint16_t)length);
    [frame appendBytes:&second length:1];
    [frame appendBytes:&networkLength length:2];
  } else {
    uint8_t second = 127;
    uint64_t rawLength = (uint64_t)length;
    unsigned char extended[8];
    for (NSInteger idx = 0; idx < 8; idx++) {
      extended[7 - idx] = (unsigned char)((rawLength >> (idx * 8)) & 0xFF);
    }
    [frame appendBytes:&second length:1];
    [frame appendBytes:extended length:8];
  }

  if (length > 0) {
    [frame appendData:body];
  }
  return frame;
}

static BOOL ALNWebSocketSendFrame(ALNSocketHandle fd, uint8_t opcode, NSData *payload) {
  NSData *frame = ALNWebSocketFrameData(opcode, payload ?: [NSData data]);
  return ALNRealtimeSendAll(fd, [frame bytes], [frame length]);
}

// RFC 6455 close codes Arlen sends.
enum {
  ALNWebSocketCloseNormal = 1000,
  ALNWebSocketCloseGoingAway = 1001,
  ALNWebSocketCloseProtocolError = 1002,
  ALNWebSocketCloseInvalidPayload = 1007,
  ALNWebSocketCloseMessageTooBig = 1009,
};

typedef NS_ENUM(NSInteger, ALNWebSocketReadStatus) {
  ALNWebSocketReadOK = 0,
  // EOF, an I/O error, or a timeout mid-frame: no close frame can be sent.
  ALNWebSocketReadConnectionLost,
  // The frame breaks RFC 6455; close with *closeCode.
  ALNWebSocketReadProtocolError,
};

// Strict UTF-8 (RFC 3629): no overlong forms, surrogates or code points
// above U+10FFFF. RFC 6455 requires closing with 1007 on invalid text.
static BOOL ALNWebSocketIsValidUTF8(const unsigned char *bytes, NSUInteger length) {
  NSUInteger idx = 0;
  while (idx < length) {
    unsigned char lead = bytes[idx];
    if (lead < 0x80) {
      idx += 1;
      continue;
    }
    NSUInteger extra = 0;
    uint32_t codePoint = 0;
    uint32_t minimum = 0;
    if ((lead & 0xE0) == 0xC0) {
      extra = 1;
      codePoint = lead & 0x1F;
      minimum = 0x80;
    } else if ((lead & 0xF0) == 0xE0) {
      extra = 2;
      codePoint = lead & 0x0F;
      minimum = 0x800;
    } else if ((lead & 0xF8) == 0xF0) {
      extra = 3;
      codePoint = lead & 0x07;
      minimum = 0x10000;
    } else {
      return NO;
    }
    if (idx + extra >= length) {
      return NO;
    }
    for (NSUInteger offset = 1; offset <= extra; offset++) {
      unsigned char next = bytes[idx + offset];
      if ((next & 0xC0) != 0x80) {
        return NO;
      }
      codePoint = (codePoint << 6) | (next & 0x3F);
    }
    if (codePoint < minimum || codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      return NO;
    }
    idx += extra + 1;
  }
  return YES;
}

// 1 when the socket is readable (or hung up) within timeoutMilliseconds, 0 on
// timeout, -1 on error. poll(), not select(): FD_SET on a POSIX descriptor at
// or above FD_SETSIZE writes past the fd_set, and a busy server has those.
static int ALNWebSocketWaitReadable(ALNSocketHandle fd, NSUInteger timeoutMilliseconds) {
#if defined(_WIN32)
  WSAPOLLFD entry;
  entry.fd = ALNNativeSocketHandle(fd);
  entry.events = POLLRDNORM;
  entry.revents = 0;
  int rc = WSAPoll(&entry, 1, (INT)timeoutMilliseconds);
  if (rc == SOCKET_ERROR) {
    return -1;
  }
#else
  struct pollfd entry;
  entry.fd = (int)fd;
  entry.events = POLLIN;
  entry.revents = 0;
  int rc = poll(&entry, 1, (int)timeoutMilliseconds);
  if (rc < 0) {
    return (errno == EINTR) ? 0 : -1;
  }
#endif
  return (rc > 0) ? 1 : 0;
}

static uint64_t ALNMonotonicMilliseconds(void) {
#if defined(_WIN32)
  return (uint64_t)GetTickCount64();
#else
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (uint64_t)now.tv_sec * 1000u + (uint64_t)(now.tv_nsec / 1000000);
#endif
}

// Waits for the rest of a request head. On a connection's first request the
// deadline was set from accept (limits.firstRequestHeadDeadline), so it also
// covers a client that sends nothing; on later requests it starts when the
// head's first byte is buffered, so idle keep-alive time is not counted.
// Returns NO (and sets 408) once the deadline has passed.
static BOOL ALNAwaitRequestHeadBytes(ALNSocketHandle clientFd,
                                     ALNRequestLimits limits,
                                     size_t bufferedLength,
                                     uint64_t *deadline,
                                     NSInteger *statusCode) {
  if (limits.headTimeoutMilliseconds == 0 || deadline == NULL || (bufferedLength == 0 && *deadline == 0)) {
    return YES;
  }
  uint64_t now = ALNMonotonicMilliseconds();
  if (*deadline == 0) {
    *deadline = now + limits.headTimeoutMilliseconds;
  }
  while (1) {
    if (now >= *deadline) {
      // Past the deadline, still take bytes that have already arrived: a
      // connection that waited in the queue may hold a complete head.
      if (ALNWebSocketWaitReadable(clientFd, 0) == 1) {
        return YES;
      }
      break;
    }
    int ready = ALNWebSocketWaitReadable(clientFd, (NSUInteger)(*deadline - now));
    if (ready != 0) {
      // Readable, or an error the read itself will report.
      return YES;
    }
    now = ALNMonotonicMilliseconds();
  }
  if (statusCode != NULL) {
    *statusCode = 408;
  }
  return NO;
}

typedef struct {
  uint64_t start;
  size_t startBytes;
} ALNRequestBodyClock;

// Checks a request body's progress before each read. The clock starts at the
// first call, when the head is complete; `receivedBytes` is any count that
// grows with the body. Fails (408) once limits.bodyTimeout has passed, or once
// the average rate since the start has fallen below
// limits.bodyMinBytesPerSecond after the grace period. A silent client is
// still bounded by connectionTimeoutSeconds on the read itself; a client that
// trickles bytes makes every read return, so this check runs between them.
static BOOL ALNAwaitRequestBodyBytes(ALNSocketHandle clientFd,
                                     ALNRequestLimits limits,
                                     ALNRequestBodyClock *clock,
                                     size_t receivedBytes,
                                     NSInteger *statusCode) {
  (void)clientFd;
  if (clock == NULL || (limits.bodyTimeoutMilliseconds == 0 && limits.bodyMinBytesPerSecond == 0)) {
    return YES;
  }
  uint64_t now = ALNMonotonicMilliseconds();
  if (clock->start == 0) {
    clock->start = now;
    clock->startBytes = receivedBytes;
    return YES;
  }
  uint64_t received = (receivedBytes > clock->startBytes) ? (uint64_t)(receivedBytes - clock->startBytes) : 0;
  uint64_t elapsed = now - clock->start;
  BOOL tooSlow = (limits.bodyTimeoutMilliseconds > 0 && elapsed >= limits.bodyTimeoutMilliseconds) ||
                 (limits.bodyMinBytesPerSecond > 0 && elapsed > limits.bodyMinRateGraceMilliseconds &&
                  received * 1000u < (uint64_t)limits.bodyMinBytesPerSecond * elapsed);
  if (!tooSlow) {
    return YES;
  }
  if (statusCode != NULL) {
    *statusCode = 408;
  }
  return NO;
}

#if defined(_WIN32)
// Closing Winsock with unread pipelined bytes can reset the connection and
// truncate an error response already sent. Finish the send side and discard
// rejected input only within fixed byte/time bounds; no bytes are dispatched.
// The caller still owns and closes the socket after this best-effort shutdown.
static void ALNFinishRejectedClientOutput(ALNSocketHandle clientFd) {
  SOCKET native = ALNNativeSocketHandle(clientFd);
  u_long nonblocking = 1;
  if (ioctlsocket(native, FIONBIO, &nonblocking) != 0 || shutdown(native, SD_SEND) != 0) {
    return;
  }
  const size_t discardLimit = 65536;
  const uint64_t deadline = ALNMonotonicMilliseconds() + 100;
  size_t discarded = 0;
  char bytes[4096];
  while (discarded < discardLimit) {
    uint64_t now = ALNMonotonicMilliseconds();
    if (now >= deadline) return;
    fd_set readable;
    FD_ZERO(&readable);
    FD_SET(native, &readable);
    struct timeval timeout = {0, (long)((deadline - now) * 1000)};
    int ready = select(0, &readable, NULL, NULL, &timeout);
    if (ready <= 0) return;
    int received = recv(native, bytes, (int)MIN(sizeof(bytes), discardLimit - discarded), 0);
    if (received == 0) return;
    if (received == SOCKET_ERROR) {
      int failure = WSAGetLastError();
      if (failure == WSAEWOULDBLOCK || failure == WSAEINTR) continue;
      return;
    }
    discarded += (size_t)received;
  }
}
#endif

// Reads one frame (GitHub issue 214). Rejects, with the RFC 6455 close code:
// unmasked client frames, nonzero RSV bits (no extension is negotiated),
// reserved opcodes and control frames that are fragmented or longer than 125
// bytes (1002), and payloads over maxPayloadBytes (1009). The payload buffer
// grows as bytes arrive instead of being allocated from the header's length.
static ALNWebSocketReadStatus ALNWebSocketReadFrame(ALNSocketHandle fd,
                                                    uint8_t *opcode,
                                                    BOOL *fin,
                                                    NSData **payload,
                                                    NSUInteger maxPayloadBytes,
                                                    uint16_t *closeCode) {
  NSUInteger readTimeoutMilliseconds = ALNWebSocketReadTimeoutMilliseconds();
  unsigned char header[2];
  if (!ALNRecvAll(fd, header, sizeof(header), readTimeoutMilliseconds)) {
    return ALNWebSocketReadConnectionLost;
  }

  BOOL final = ((header[0] & 0x80) != 0);
  uint8_t frameOpcode = (uint8_t)(header[0] & 0x0F);
  BOOL masked = ((header[1] & 0x80) != 0);
  BOOL control = (frameOpcode & 0x08) != 0;
  BOOL knownOpcode = (frameOpcode <= 0x2) || (frameOpcode >= 0x8 && frameOpcode <= 0xA);
  uint64_t payloadLength = (uint64_t)(header[1] & 0x7F);
  if (!masked || (header[0] & 0x70) != 0 || !knownOpcode || (control && (!final || payloadLength > 125))) {
    *closeCode = ALNWebSocketCloseProtocolError;
    return ALNWebSocketReadProtocolError;
  }
  if (payloadLength == 126) {
    unsigned char ext[2];
    if (!ALNRecvAll(fd, ext, sizeof(ext), readTimeoutMilliseconds)) {
      return ALNWebSocketReadConnectionLost;
    }
    payloadLength = ((uint64_t)ext[0] << 8) | (uint64_t)ext[1];
  } else if (payloadLength == 127) {
    unsigned char ext[8];
    if (!ALNRecvAll(fd, ext, sizeof(ext), readTimeoutMilliseconds)) {
      return ALNWebSocketReadConnectionLost;
    }
    payloadLength = 0;
    for (NSUInteger idx = 0; idx < 8; idx++) {
      payloadLength = (payloadLength << 8) | (uint64_t)ext[idx];
    }
  }
  if (payloadLength > (uint64_t)maxPayloadBytes) {
    *closeCode = ALNWebSocketCloseMessageTooBig;
    return ALNWebSocketReadProtocolError;
  }

  unsigned char mask[4] = {0, 0, 0, 0};
  if (!ALNRecvAll(fd, mask, sizeof(mask), readTimeoutMilliseconds)) {
    return ALNWebSocketReadConnectionLost;
  }

  NSMutableData *data = [NSMutableData data];
  unsigned char chunk[16384];
  uint64_t received = 0;
  while (received < payloadLength) {
    size_t want = (size_t)MIN((uint64_t)sizeof(chunk), payloadLength - received);
    if (!ALNRecvAll(fd, chunk, want, readTimeoutMilliseconds)) {
      return ALNWebSocketReadConnectionLost;
    }
    for (size_t idx = 0; idx < want; idx++) {
      chunk[idx] ^= mask[(received + idx) % 4];
    }
    [data appendBytes:chunk length:want];
    received += want;
  }

  *opcode = frameOpcode;
  *fin = final;
  *payload = data;
  return ALNWebSocketReadOK;
}

// Streams a Content-Length body larger than limits.spoolThresholdBytes into a
// private file instead of the connection buffer (GitHub issue 64). `headerBytes`
// of complete head are buffered, possibly followed by some body. Reads never
// exceed the declared length, so a pipelined next request stays on the socket.
// The returned request owns the file; every failure removes it.
// The body limit for the request whose head is buffered: its route's
// maxBodyBytes, or the server default. Only the route table is consulted; no
// middleware or controller runs before the body is read.
static NSUInteger ALNRequestBodyLimit(ALNRequestLimits limits, const uint8_t *bytes, size_t headerBytes) {
  if (!limits.routeBodyLimitsActive || limits.application == nil || bytes == NULL) {
    return limits.maxBodyBytes;
  }
  size_t lineEnd = 0;
  while (lineEnd < headerBytes && bytes[lineEnd] != '\r' && bytes[lineEnd] != '\n') {
    lineEnd++;
  }
  size_t methodEnd = 0;
  while (methodEnd < lineEnd && bytes[methodEnd] != ' ') {
    methodEnd++;
  }
  size_t targetStart = methodEnd + 1;
  size_t targetEnd = targetStart;
  while (targetEnd < lineEnd && bytes[targetEnd] != ' ' && bytes[targetEnd] != '?' && bytes[targetEnd] != '#') {
    targetEnd++;
  }
  if (methodEnd == 0 || targetStart >= lineEnd || targetEnd <= targetStart) {
    return limits.maxBodyBytes;
  }
  NSString *method = [[NSString alloc] initWithBytes:bytes length:methodEnd encoding:NSASCIIStringEncoding];
  NSString *target = [[NSString alloc] initWithBytes:bytes + targetStart
                                              length:targetEnd - targetStart
                                            encoding:NSUTF8StringEncoding];
  if (![target hasPrefix:@"/"]) {
    // absolute-form (http://host/path): keep the path.
    NSRange scheme = [target rangeOfString:@"://"];
    NSRange slash = (scheme.location == NSNotFound)
                        ? NSMakeRange(NSNotFound, 0)
                        : [target rangeOfString:@"/" options:0
                                          range:NSMakeRange(NSMaxRange(scheme), [target length] - NSMaxRange(scheme))];
    target = (slash.location == NSNotFound) ? @"/" : [target substringFromIndex:slash.location];
  }
  if ([method length] == 0 || [target length] == 0) {
    return limits.maxBodyBytes;
  }
  return [limits.application maxBodyBytesForMethod:method path:target];
}

static ALNRequest *ALNReadSpooledRequest(ALNSocketHandle clientFd,
                                         ALNRequestLimits limits,
                                         ALNHTTPParserBackend backend,
                                         size_t headerBytes,
                                         NSUInteger contentLength,
                                         NSInteger *statusCode,
                                         ALNConnectionReadState *readState) {
  NSString *directory = [limits.spoolDirectory length] > 0 ? limits.spoolDirectory : NSTemporaryDirectory();
  NSString *path = [directory stringByAppendingPathComponent:
      [@"arlen-body-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
  NSData *head = [NSData dataWithBytes:readState->bytes length:headerBytes];
  size_t buffered = MIN(readState->length - headerBytes, (size_t)contentLength);
  FILE *file = NULL;
  NSInteger failure = 503;
  ALNRequest *request = nil;
  ALNRequestBodyClock bodyClock = {0, 0};
  @try {
    // Count all body bytes from the completed head, including bytes that
    // arrived in the head's packet. Do not reset the clock after each read.
    (void)ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock, 0, &failure);
    if ([[NSFileManager defaultManager] createFileAtPath:path contents:nil
                                              attributes:@{NSFilePosixPermissions : @0600}]) {
      file = ALNPlatformOpenFile(path, "wb");
    }
    failure = (file == NULL) ? 503 : 0;
    if (failure == 0 && buffered > 0 && fwrite(readState->bytes + headerBytes, 1, buffered, file) != buffered) {
      failure = 503;
    }
    ALNConnectionReadStateConsumePrefix(readState, headerBytes + buffered);
    NSUInteger remaining = contentLength - buffered;
    char chunk[65536];
    while (failure == 0 && remaining > 0) {
      NSInteger waitStatus = 0;
      if (!ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock, (size_t)(contentLength - remaining),
                                    &waitStatus)) {
        failure = waitStatus;
        break;
      }
      ssize_t readBytes = ALNRecvWithFaults(clientFd, chunk, MIN(sizeof(chunk), remaining), 0);
      if (readBytes < 0) {
        if (errno == EINTR) {
          continue;
        }
        failure = (errno == EAGAIN || errno == EWOULDBLOCK) ? 408 : 400;
      } else if (readBytes == 0) {
        failure = 400;  // client went away mid-body
      } else if (!ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock,
                                            (size_t)(contentLength - remaining) + (size_t)readBytes,
                                            &failure)) {
        // A final read can complete the body after its clock expired. Check
        // before writing or accepting it, even when no further read is needed.
      } else if (fwrite(chunk, 1, (size_t)readBytes, file) != (size_t)readBytes) {
        failure = 503;
      } else {
        remaining -= (NSUInteger)readBytes;
      }
    }
    if (file != NULL && fclose(file) != 0 && failure == 0) {
      failure = 503;
    }
    file = NULL;
    if (failure == 0) {
      request = [ALNRequest requestFromHeadData:head backend:backend error:NULL];
      if (request == nil) {
        failure = 400;
      } else if (![request adoptSpooledBodyAtPath:path error:NULL]) {
        request = nil;
        failure = 503;
      }
    }
  } @finally {
    // Also runs when an exception unwinds through here: never leave a spool file behind.
    if (file != NULL) {
      fclose(file);
    }
    if (request == nil) {
      [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
  }
  if (statusCode != NULL) {
    *statusCode = failure;
  }
  return request;
}

typedef NS_ENUM(NSInteger, ALNExpectation) {
  ALNExpectationNone = 0,
  ALNExpectationContinue,
  ALNExpectationUnsupported,
};

// The request head's Expect header (RFC 9110 §10.1.1). HTTP/1.0 requests and
// a missing header expect nothing; `100-continue` is the only expectation
// defined, so anything else is unsupported (417).
static ALNExpectation ALNRequestHeadExpectation(const uint8_t *bytes, size_t headLength) {
  size_t lineEnd = SIZE_MAX;
  for (size_t idx = 0; idx + 1 < headLength; idx++) {
    if (bytes[idx] == '\r' && bytes[idx + 1] == '\n') {
      lineEnd = idx;
      break;
    }
  }
  if (lineEnd == SIZE_MAX || lineEnd < 8 || memcmp(bytes + lineEnd - 8, "HTTP/1.0", 8) == 0) {
    return ALNExpectationNone;
  }
  size_t lineStart = lineEnd + 2;
  ALNExpectation expectation = ALNExpectationNone;
  while (lineStart + 1 < headLength) {
    size_t end = lineStart;
    while (end + 1 < headLength && !(bytes[end] == '\r' && bytes[end + 1] == '\n')) {
      end++;
    }
    if (end == lineStart) {
      break;
    }
    static const char name[] = "expect:";
    size_t nameLength = sizeof(name) - 1;
    if (end - lineStart > nameLength && strncasecmp((const char *)bytes + lineStart, name, nameLength) == 0) {
      size_t valueStart = lineStart + nameLength;
      size_t valueEnd = end;
      while (valueStart < valueEnd && (bytes[valueStart] == ' ' || bytes[valueStart] == '\t')) {
        valueStart++;
      }
      while (valueEnd > valueStart && (bytes[valueEnd - 1] == ' ' || bytes[valueEnd - 1] == '\t')) {
        valueEnd--;
      }
      if (valueEnd - valueStart == 12 && strncasecmp((const char *)bytes + valueStart, "100-continue", 12) == 0) {
        expectation = ALNExpectationContinue;
      } else {
        return ALNExpectationUnsupported;
      }
    }
    lineStart = end + 2;
  }
  return expectation;
}

// Sends `100 Continue` once the head passed the size checks and before the
// client sends the body, so clients that wait for it (curl, most HTTP
// libraries) don't stall for their expect timeout (#212). Returns NO with a
// 417 status for an unsupported expectation.
static BOOL ALNAnswerRequestExpectation(ALNSocketHandle clientFd,
                                        const uint8_t *bytes,
                                        size_t headLength,
                                        size_t bufferedLength,
                                        BOOL *continueSent,
                                        NSInteger *statusCode) {
  if (*continueSent) {
    return YES;
  }
  ALNExpectation expectation = ALNRequestHeadExpectation(bytes, headLength);
  if (expectation == ALNExpectationUnsupported) {
    if (statusCode != NULL) {
      *statusCode = 417;
    }
    return NO;
  }
  // Body bytes already buffered mean the client didn't wait.
  if (expectation == ALNExpectationContinue && bufferedLength <= headLength) {
    static const char continueLine[] = "HTTP/1.1 100 Continue\r\n\r\n";
    (void)ALNSendAll(clientFd, continueLine, sizeof(continueLine) - 1);
  }
  *continueSent = YES;
  return YES;
}

static NSData *ALNReadHTTPRequestDataLegacy(ALNSocketHandle clientFd,
                                            ALNRequestLimits limits,
                                            NSInteger *statusCode,
                                            ALNConnectionReadState *readState,
                                            ALNRequest **spooledRequest) {
  if (statusCode != NULL) {
    *statusCode = 0;
  }
  if (readState == NULL) {
    if (statusCode != NULL) {
      *statusCode = 400;
    }
    return nil;
  }

  BOOL continueAnswered = NO;
  uint64_t headDeadline = limits.firstRequestHeadDeadline;
  ALNRequestBodyClock bodyClock = {0, 0};
  while (1) {
    if (!readState->metadataReady) {
      if (readState->length > limits.maxHeaderBytes) {
        if (statusCode != NULL) {
          *statusCode = 431;
        }
        return nil;
      }

      size_t separatorLocation =
          ALNFindHeaderTerminator(readState->bytes, readState->length, readState->scanOffset);
      if (separatorLocation != SIZE_MAX) {
        size_t headerBytes = separatorLocation + 4;
        ALNRequestHeadMetadata parsedMetadata;
        memset(&parsedMetadata, 0, sizeof(parsedMetadata));
        if (!ALNParseRequestHeadMetadataBytes(readState->bytes,
                                              headerBytes,
                                              limits,
                                              &parsedMetadata)) {
          if (statusCode != NULL) {
            *statusCode = (parsedMetadata.statusCode != 0) ? parsedMetadata.statusCode : 400;
          }
          return nil;
        }
        readState->metadataReady = YES;
        readState->metadata = parsedMetadata;
        readState->expectedTotalBytes =
            (size_t)parsedMetadata.headerBytes + (size_t)parsedMetadata.contentLength;
        if (parsedMetadata.contentLength > 0) {
          (void)ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock,
                                        parsedMetadata.headerBytes, statusCode);
        }
      } else {
        readState->scanOffset = readState->length;
      }
    }

    if (readState->metadataReady && limits.routeBodyLimitsActive && readState->metadata.contentLength > 0 &&
        (NSUInteger)readState->metadata.contentLength >
            ALNRequestBodyLimit(limits, readState->bytes, readState->metadata.headerBytes)) {
      if (statusCode != NULL) {
        *statusCode = 413;
      }
      return nil;
    }

    if (readState->metadataReady && readState->metadata.contentLength > 0 &&
        !ALNAnswerRequestExpectation(clientFd, readState->bytes, readState->metadata.headerBytes,
                                     readState->length, &continueAnswered, statusCode)) {
      return nil;
    }

    if (readState->metadataReady && spooledRequest != NULL &&
        (NSUInteger)readState->metadata.contentLength > limits.spoolThresholdBytes) {
      *spooledRequest = ALNReadSpooledRequest(clientFd, limits, ALNHTTPParserBackendLegacy,
                                              readState->metadata.headerBytes,
                                              (NSUInteger)readState->metadata.contentLength,
                                              statusCode, readState);
      return nil;
    }

    if (readState->metadataReady) {
      NSUInteger headerBytes = readState->metadata.headerBytes;
      NSUInteger bodyBytesRead =
          (readState->length >= headerBytes) ? (readState->length - headerBytes) : 0;
      if (bodyBytesRead > limits.maxBodyBytes) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }
      if (readState->length >= readState->expectedTotalBytes) {
        // Exclude following pipelined bytes from this body's rate. A body
        // already complete with its initial head starts no earlier clock.
        if (readState->metadata.contentLength > 0 &&
            !ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock,
                                      readState->expectedTotalBytes, statusCode)) {
          return nil;
        }
        NSData *requestData =
            [NSData dataWithBytes:readState->bytes length:readState->expectedTotalBytes];
        if (requestData == nil) {
          if (statusCode != NULL) {
            *statusCode = 503;
          }
          return nil;
        }
        ALNConnectionReadStateConsumePrefix(readState, readState->expectedTotalBytes);
        return requestData;
      }
    }

    if (!readState->metadataReady &&
        !ALNAwaitRequestHeadBytes(clientFd, limits, readState->length, &headDeadline, statusCode)) {
      return nil;
    }
    if (readState->metadataReady &&
        !ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock, readState->length, statusCode)) {
      return nil;
    }
    char chunk[8192];
    ssize_t readBytes = ALNRecvWithFaults(clientFd, chunk, sizeof(chunk), 0);
    if (readBytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (statusCode != NULL) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          *statusCode = 408;
        } else {
          *statusCode = 400;
        }
      }
      return nil;
    }
    if (readBytes == 0) {
      if (readState->length == 0) {
        if (statusCode != NULL) {
          *statusCode = 0;
        }
        return nil;
      }
      if (statusCode != NULL) {
        *statusCode = 400;
      }
      return nil;
    }

    if (!ALNConnectionReadStateAppend(readState, chunk, (size_t)readBytes)) {
      if (statusCode != NULL) {
        *statusCode = (errno == ENOMEM) ? 503 : 413;
      }
      return nil;
    }
  }
}

// One decoder for this request, fed only new bytes. Body callbacks count
// decoded bytes against this route's limit and spill before the heap grows
// beyond its threshold. No callback retains pointers into the read buffer.
@interface ALNChunkedReadState : NSObject {
@public
  NSMutableData *_body;
  NSString *_path;
  FILE *_file;
  NSUInteger _decodedBytes;
  NSUInteger _bodyLimit;
  NSUInteger _threshold;
  NSInteger _status;
  BOOL _complete;
  BOOL _createdFile;
}
- (instancetype)initWithLimit:(NSUInteger)limit threshold:(NSUInteger)threshold path:(NSString *)path;
- (BOOL)appendBytes:(const void *)bytes length:(NSUInteger)length;
- (BOOL)finish;
- (void)discard;
@end
#if defined(_WIN32)
// Supply the protected token-user DACL to CREATE_NEW: a shared temp directory
// must never expose payload bytes between file creation and an ACL update.
static int ALNCreatePrivateChunkSpool(NSString *path) {
  HANDLE token = NULL;
  PACL acl = NULL;
  HANDLE file = INVALID_HANDLE_VALUE;
  NSMutableData *tokenData = nil;
  NSMutableData *wide = nil;
  SECURITY_DESCRIPTOR security;
  SECURITY_ATTRIBUTES attributes;
  EXPLICIT_ACCESSW entry;
  DWORD size = 0;
  int descriptor = -1;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) goto done;
  GetTokenInformation(token, TokenUser, NULL, 0, &size);
  if (size == 0) goto done;
  tokenData = [NSMutableData dataWithLength:size];
  if (!GetTokenInformation(token, TokenUser, tokenData.mutableBytes, size, &size)) goto done;
  memset(&entry, 0, sizeof(entry));
  entry.grfAccessPermissions = FILE_ALL_ACCESS;
  entry.grfAccessMode = SET_ACCESS;
  entry.grfInheritance = NO_INHERITANCE;
  BuildTrusteeWithSidW(&entry.Trustee, ((TOKEN_USER *)tokenData.mutableBytes)->User.Sid);
  if (SetEntriesInAclW(1, &entry, NULL, &acl) != ERROR_SUCCESS ||
      !InitializeSecurityDescriptor(&security, SECURITY_DESCRIPTOR_REVISION) ||
      !SetSecurityDescriptorDacl(&security, TRUE, acl, FALSE) ||
      !SetSecurityDescriptorControl(&security, SE_DACL_PROTECTED, SE_DACL_PROTECTED)) goto done;
  attributes.nLength = sizeof(attributes);
  attributes.lpSecurityDescriptor = &security;
  attributes.bInheritHandle = FALSE;
  wide = [[[path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
      dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  file = CreateFileW((const wchar_t *)wide.bytes, GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_DELETE, &attributes, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) goto done;
  descriptor = _open_osfhandle((intptr_t)file, _O_WRONLY | _O_BINARY | _O_NOINHERIT);
  if (descriptor >= 0) {
    file = INVALID_HANDLE_VALUE; // CRT now owns the handle.
  } else {
    // No payload was written and no existing path was opened.
    CloseHandle(file);
    file = INVALID_HANDLE_VALUE;
    DeleteFileW((const wchar_t *)wide.bytes);
  }
done:
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
  if (acl != NULL) LocalFree(acl);
  if (token != NULL) CloseHandle(token);
  return descriptor;
}
#endif

@implementation ALNChunkedReadState
- (instancetype)initWithLimit:(NSUInteger)limit threshold:(NSUInteger)threshold path:(NSString *)path {
  self = [super init];
  if (self != nil) {
    _body = [NSMutableData data];
    _bodyLimit = limit;
    _threshold = threshold;
    _path = [path copy];
  }
  return self;
}
- (BOOL)appendBytes:(const void *)bytes length:(NSUInteger)length {
  if (_status != 0) return NO;
  if (length > _bodyLimit - _decodedBytes) {
    _status = 413;
    return NO;
  }
  if (_file == NULL && _decodedBytes + length > _threshold) {
    // Exclusive creation prevents replacing an existing path or following a
    // pre-existing symlink; descriptors never pass into spawned children.
#if defined(_WIN32)
    int descriptor = ALNCreatePrivateChunkSpool(_path);
#else
    int descriptor = open([_path fileSystemRepresentation],
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
#endif
    if (descriptor >= 0) {
      _createdFile = YES;
      _file = fdopen(descriptor, "wb");
      if (_file == NULL) {
        close(descriptor);
      }
    }
    if (_file == NULL ||
        fwrite(_body.bytes, 1, _body.length, _file) != _body.length) {
      _status = 503;
      return NO;
    }
    _body = nil;
  }
  if (_file != NULL) {
    if (fwrite(bytes, 1, length, _file) != length) {
      _status = 503;
      return NO;
    }
  } else {
    [_body appendBytes:bytes length:length];
  }
  _decodedBytes += length;
  return YES;
}
- (BOOL)finish {
  if (_file != NULL) {
    if (fclose(_file) != 0) _status = 503;
    _file = NULL;
  }
  return _status == 0;
}
- (void)discard {
  [self finish];
  if (_createdFile) {
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    _createdFile = NO;
  }
}
- (void)dealloc {
  [self discard];
}
@end

#if ARLEN_ENABLE_LLHTTP
static int ALNChunkedBody(llhttp_t *parser, const char *bytes, size_t length) {
  ALNChunkedReadState *state = (__bridge ALNChunkedReadState *)parser->data;
  return [state appendBytes:bytes length:length] ? 0 : HPE_USER;
}

static int ALNChunkedComplete(llhttp_t *parser) {
  ALNChunkedReadState *state = (__bridge ALNChunkedReadState *)parser->data;
  state->_complete = YES;
  return HPE_PAUSED;
}

static ALNRequest *ALNReadChunkedRequest(ALNSocketHandle clientFd,
                                        ALNRequestLimits limits,
                                        ALNRequest *headRequest,
                                        size_t headerBytes,
                                        NSInteger *statusCode,
                                        ALNConnectionReadState *readState) {
  NSString *directory = [limits.spoolDirectory length] > 0 ? limits.spoolDirectory : NSTemporaryDirectory();
  NSString *path = [directory stringByAppendingPathComponent:
      [@"arlen-body-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
  ALNChunkedReadState *state = [[ALNChunkedReadState alloc]
      initWithLimit:ALNRequestBodyLimit(limits, readState->bytes, headerBytes)
      threshold:limits.spoolThresholdBytes path:path];
  llhttp_settings_t settings;
  llhttp_settings_init(&settings);
  settings.on_body = ALNChunkedBody;
  settings.on_message_complete = ALNChunkedComplete;
  llhttp_t parser;
  llhttp_init(&parser, HTTP_REQUEST, &settings);
  parser.data = (__bridge void *)state;
  BOOL continueSent = NO;
  ALNRequestBodyClock clock = {0, 0};
  size_t encodedBytes = 0;
  // Preserve the existing encoded envelope bound, including chunk extensions
  // and trailers; spooling does not permit unlimited framing traffic.
  size_t encodedLimit = limits.maxBodyBytes > SIZE_MAX - limits.maxHeaderBytes
                            ? SIZE_MAX : limits.maxHeaderBytes + limits.maxBodyBytes;
  ALNRequest *request = nil;
  @try {
    if (!ALNAnswerRequestExpectation(clientFd, readState->bytes, headerBytes,
                                     readState->length, &continueSent, &state->_status)) {
      return nil;
    }
    (void)ALNAwaitRequestBodyBytes(clientFd, limits, &clock, headerBytes, &state->_status);
    while (!state->_complete) {
      if (readState->length > 0) {
        const char *bytes = (const char *)readState->bytes;
        size_t available = readState->length;
        llhttp_errno_t result = llhttp_execute(&parser, bytes, available);
        size_t consumed = available;
        const char *end = llhttp_get_error_pos(&parser);
        if (result != HPE_OK && end != NULL && end >= bytes && end <= bytes + available) {
          consumed = (size_t)(end - bytes);
        }
        if (consumed > encodedLimit - encodedBytes) {
          state->_status = 413;
          break;
        }
        encodedBytes += consumed;
        ALNConnectionReadStateConsumePrefix(readState, consumed);
        if (result != HPE_OK && !(result == HPE_PAUSED && state->_complete)) {
          if (state->_status == 0) state->_status = 400;
          break;
        }
        if (state->_complete) {
          // Completion must not skip the clock that guarded the blocking read.
          // encodedBytes stops at this message, excluding a pipelined request.
          (void)ALNAwaitRequestBodyBytes(clientFd, limits, &clock, encodedBytes, &state->_status);
          break;
        }
      }
      if (!ALNAwaitRequestBodyBytes(clientFd, limits, &clock, encodedBytes, &state->_status)) {
        break;
      }
      char bytes[8192];
      ssize_t received = ALNRecvWithFaults(clientFd, bytes, sizeof(bytes), 0);
      if (received < 0 && errno == EINTR) continue;
      if (received <= 0) {
        state->_status = (received < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) ? 408 : 400;
        break;
      }
      if (!ALNConnectionReadStateAppend(readState, bytes, (size_t)received)) {
        state->_status = (errno == ENOMEM) ? 503 : 413;
        break;
      }
    }
    if (state->_complete && state->_status == 0) {
      if (state->_file != NULL) {
        [state finish];
        if (state->_status == 0 && [headRequest adoptSpooledBodyAtPath:state->_path error:NULL]) {
          state->_createdFile = NO;  // The request now owns the spool.
          request = headRequest;
        } else {
          state->_status = 503;
        }
      } else {
        request = [[ALNRequest alloc] initWithMethod:headRequest.method path:headRequest.path
            queryString:headRequest.queryString httpVersion:headRequest.httpVersion
            headers:headRequest.headers body:state->_body];
      }
    }
  } @finally {
    [state discard];
    if (statusCode != NULL) *statusCode = state->_status;
  }
  return request;
}
#endif

static ALNRequest *ALNReadHTTPRequestLLHTTP(ALNSocketHandle clientFd,
                                            ALNRequestLimits limits,
                                            NSInteger *statusCode,
                                            ALNConnectionReadState *readState) {
  if (statusCode != NULL) {
    *statusCode = 0;
  }
  if (readState == NULL) {
    if (statusCode != NULL) {
      *statusCode = 400;
    }
    return nil;
  }

#if ARLEN_ENABLE_LLHTTP
  BOOL checkedHead = NO;
#endif
  BOOL continueAnswered = NO;
  uint64_t headDeadline = limits.firstRequestHeadDeadline;
  ALNRequestBodyClock bodyClock = {0, 0};
  while (1) {
#if ARLEN_ENABLE_LLHTTP
    if (!checkedHead) {
      size_t terminator = ALNFindHeaderTerminator(readState->bytes, readState->length, 0);
      if (terminator != SIZE_MAX) {
        size_t headerBytes = terminator + 4;
        size_t lineBytes = 0;
        while (lineBytes < terminator && readState->bytes[lineBytes] != '\r' &&
               readState->bytes[lineBytes] != '\n') lineBytes++;
        if (headerBytes > limits.maxHeaderBytes || lineBytes > limits.maxRequestLineBytes) {
          if (statusCode != NULL) *statusCode = 431;
          return nil;
        }
        checkedHead = YES;
        // Initialize at the head boundary so an initial body burst is counted
        // toward its average rate, without crediting the headers themselves.
        (void)ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock, headerBytes, statusCode);
        NSData *head = [NSData dataWithBytes:readState->bytes length:headerBytes];
        ALNRequest *headRequest = [ALNRequest requestFromHeadData:head
            backend:ALNHTTPParserBackendLLHTTP error:NULL];
        if (headRequest != nil && [[headRequest headerValueForName:@"transfer-encoding"] length] > 0) {
          return ALNReadChunkedRequest(clientFd, limits, headRequest, headerBytes, statusCode, readState);
        }
      }
    }
#endif
    NSUInteger consumedLength = 0;
    BOOL headersComplete = NO;
    NSInteger contentLength = 0;
    NSError *requestError = nil;
    NSData *bufferData = (readState->length > 0)
                             ? [NSData dataWithBytesNoCopy:readState->bytes
                                                     length:readState->length
                                               freeWhenDone:NO]
                             : [NSData data];
    ALNRequest *request = [ALNRequest requestFromBufferedData:bufferData
                                                      backend:ALNHTTPParserBackendLLHTTP
                                               consumedLength:&consumedLength
                                              headersComplete:&headersComplete
                                                contentLength:&contentLength
                                                        error:&requestError];
    if (requestError != nil) {
      NSInteger mappedStatus = (readState->length > limits.maxHeaderBytes) ? 431 : 400;
      size_t separatorLocation = ALNFindHeaderTerminator(readState->bytes, readState->length, 0);
      if (separatorLocation != SIZE_MAX) {
        ALNRequestHeadMetadata parsedMetadata;
        memset(&parsedMetadata, 0, sizeof(parsedMetadata));
        if (!ALNParseRequestHeadMetadataBytes(readState->bytes,
                                              separatorLocation + 4,
                                              limits,
                                              &parsedMetadata) &&
            parsedMetadata.statusCode != 0) {
          mappedStatus = parsedMetadata.statusCode;
        }
      }
      if (statusCode != NULL) {
        *statusCode = mappedStatus;
      }
      return nil;
    }

    // llhttp counts content_length down as it parses body bytes, so take the
    // declared length from the head itself.
    if (headersComplete && requestError == nil && (request == nil || limits.routeBodyLimitsActive)) {
      size_t separatorLocation = ALNFindHeaderTerminator(readState->bytes, readState->length, 0);
      ALNRequestHeadMetadata head;
      memset(&head, 0, sizeof(head));
      if (separatorLocation != SIZE_MAX && separatorLocation + 4 <= limits.maxHeaderBytes &&
          ALNParseRequestHeadMetadataBytes(readState->bytes, separatorLocation + 4, limits, &head) &&
          head.contentLength > 0) {
        if (limits.routeBodyLimitsActive &&
            (NSUInteger)head.contentLength > ALNRequestBodyLimit(limits, readState->bytes, separatorLocation + 4)) {
          if (statusCode != NULL) {
            *statusCode = 413;
          }
          return nil;
        }
        if (request == nil && (NSUInteger)head.contentLength > limits.spoolThresholdBytes) {
          if (!ALNAnswerRequestExpectation(clientFd, readState->bytes, separatorLocation + 4, readState->length,
                                           &continueAnswered, statusCode)) {
            return nil;
          }
          return ALNReadSpooledRequest(clientFd, limits, ALNHTTPParserBackendLLHTTP, separatorLocation + 4,
                                       (NSUInteger)head.contentLength, statusCode, readState);
        }
      }
    }

    if (!headersComplete) {
      if (readState->length > limits.maxHeaderBytes) {
        if (statusCode != NULL) {
          *statusCode = 431;
        }
        return nil;
      }
    } else {
      if (contentLength < 0) {
        if (statusCode != NULL) {
          *statusCode = 400;
        }
        return nil;
      }
      if ((NSUInteger)contentLength > limits.maxBodyBytes) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }
      if (limits.maxHeaderBytes > SIZE_MAX - limits.maxBodyBytes) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }
      size_t maxTotalBuffered = limits.maxHeaderBytes + limits.maxBodyBytes;
      if (readState->length > maxTotalBuffered) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }
      if (request == nil) {
        size_t headTerminator = ALNFindHeaderTerminator(readState->bytes, readState->length, 0);
        if (headTerminator != SIZE_MAX &&
            !ALNAnswerRequestExpectation(clientFd, readState->bytes, headTerminator + 4, readState->length,
                                         &continueAnswered, statusCode)) {
          return nil;
        }
      }
    }

    if (request != nil) {
      // Measure the head itself. consumedLength minus the decoded body also
      // counted chunked framing (size lines and CRLFs) as header bytes, so a
      // body sent in many small chunks got 431 (#211). The framing stays
      // bounded by the header + body buffering cap above.
      NSUInteger parsedHeaderBytes = consumedLength;
      size_t headTerminator = ALNFindHeaderTerminator(readState->bytes, consumedLength, 0);
      if (headTerminator != SIZE_MAX) {
        parsedHeaderBytes = (NSUInteger)(headTerminator + 4);
      }
      if (parsedHeaderBytes > limits.maxHeaderBytes) {
        if (statusCode != NULL) {
          *statusCode = 431;
        }
        return nil;
      }
      if ((NSUInteger)[request.body length] > limits.maxBodyBytes) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }
      if (consumedLength == 0 || consumedLength > readState->length) {
        consumedLength = readState->length;
      }
      if ([request.body length] > 0 &&
          !ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock, consumedLength, statusCode)) {
        return nil;
      }
      ALNConnectionReadStateConsumePrefix(readState, consumedLength);
      return request;
    }

    if (!headersComplete &&
        !ALNAwaitRequestHeadBytes(clientFd, limits, readState->length, &headDeadline, statusCode)) {
      return nil;
    }
    if (headersComplete &&
        !ALNAwaitRequestBodyBytes(clientFd, limits, &bodyClock, readState->length, statusCode)) {
      return nil;
    }
    char chunk[8192];
    ssize_t readBytes = ALNRecvWithFaults(clientFd, chunk, sizeof(chunk), 0);
    if (readBytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (statusCode != NULL) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          *statusCode = 408;
        } else {
          *statusCode = 400;
        }
      }
      return nil;
    }
    if (readBytes == 0) {
      if (readState->length == 0) {
        if (statusCode != NULL) {
          *statusCode = 0;
        }
        return nil;
      }
      if (statusCode != NULL) {
        *statusCode = 400;
      }
      return nil;
    }
    if (!ALNConnectionReadStateAppend(readState, chunk, (size_t)readBytes)) {
      if (statusCode != NULL) {
        *statusCode = (errno == ENOMEM) ? 503 : 413;
      }
      return nil;
    }
  }
}

static ALNRequest *ALNReadHTTPRequest(ALNSocketHandle clientFd,
                                      ALNRequestLimits limits,
                                      ALNHTTPParserBackend backend,
                                      NSInteger *statusCode,
                                      ALNConnectionReadState *readState) {
  if (backend == ALNHTTPParserBackendLLHTTP && [ALNRequest isLLHTTPAvailable]) {
    return ALNReadHTTPRequestLLHTTP(clientFd, limits, statusCode, readState);
  }

  NSInteger readStatus = 0;
  ALNRequest *spooledRequest = nil;
  NSData *rawRequest = ALNReadHTTPRequestDataLegacy(clientFd, limits, &readStatus, readState, &spooledRequest);
  if (spooledRequest != nil) {
    if (statusCode != NULL) {
      *statusCode = 0;
    }
    return spooledRequest;
  }
  if (rawRequest == nil) {
    if (statusCode != NULL) {
      *statusCode = readStatus;
    }
    return nil;
  }

  NSError *requestError = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:rawRequest
                                               backend:backend
                                                 error:&requestError];
  if (request == nil) {
    if (statusCode != NULL) {
      *statusCode = 400;
    }
    return nil;
  }
  if (statusCode != NULL) {
    *statusCode = 0;
  }
  return request;
}

static NSString *ALNRemoteAddressForClient(ALNSocketHandle clientFd) {
  struct sockaddr_in peer;
  socklen_t peerLen = sizeof(peer);
  memset(&peer, 0, sizeof(peer));
  if (ALNSocketGetPeerName(clientFd, (struct sockaddr *)&peer, &peerLen) != 0) {
    return @"";
  }

  char addressBuffer[INET_ADDRSTRLEN];
  const char *ok =
      ALNInetNtop(AF_INET, &peer.sin_addr, addressBuffer, sizeof(addressBuffer));
  if (ok == NULL) {
    return @"";
  }
  return [NSString stringWithUTF8String:addressBuffer] ?: @"";
}

static NSString *ALNTrimmedString(NSString *value) {
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNProxyForwardingEnabled(NSDictionary *config, NSArray *trustedProxyCIDRs) {
  if ([trustedProxyCIDRs isKindOfClass:[NSArray class]] && [trustedProxyCIDRs count] > 0) {
    return YES;
  }
  return ALNConfigBool(config, @"trustedProxy", NO);
}

void ALNApplyProxyMetadata(ALNRequest *request, NSDictionary *config) {
  request.effectiveRemoteAddress = request.remoteAddress ?: @"";
  request.scheme = @"http";

  NSArray *trustedProxyCIDRs = [config[@"trustedProxyCIDRs"] isKindOfClass:[NSArray class]]
                                   ? config[@"trustedProxyCIDRs"]
                                   : @[];
  if (!ALNProxyForwardingEnabled(config, trustedProxyCIDRs)) {
    return;
  }
  if (!ALNClientAddressMatchesAnyCIDR(request.remoteAddress, trustedProxyCIDRs)) {
    return;
  }

  // The right-most hop that is not a trusted proxy, in the one header
  // security.forwardedClientIPHeader selects (route policies read the same
  // one): clients control everything to its left. When the chain can't be
  // read, the request keeps the proxy's address.
  NSString *headerName = ALNClientAddressForwardedHeaderName(config);
  NSArray *hops = ALNClientAddressHopsFromHeader(headerName, [request headerValueForName:headerName]);
  NSString *effectiveAddress = ALNClientAddressFromForwardedHops(request.remoteAddress, hops, trustedProxyCIDRs, NULL);
  if ([effectiveAddress length] > 0) {
    request.effectiveRemoteAddress = effectiveAddress;
  }

  NSString *forwardedProto = [request headerValueForName:@"x-forwarded-proto"];

  NSString *proto = [[ALNTrimmedString(forwardedProto) lowercaseString] copy];
  if ([proto isEqualToString:@"http"] || [proto isEqualToString:@"https"]) {
    request.scheme = proto;
  }
}

static NSArray *ALNDefaultStaticAllowExtensions(void) {
  return @[
    @"css",
    @"js",
    @"json",
    @"txt",
    @"html",
    @"htm",
    @"svg",
    @"png",
    @"jpg",
    @"jpeg",
    @"gif",
    @"ico",
    @"webp",
    @"woff",
    @"woff2",
    @"map",
    @"xml",
  ];
}

static NSArray *ALNNormalizedStaticAllowExtensions(NSArray *values) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *extension = [[(NSString *)value lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([extension hasPrefix:@"."]) {
      extension = [extension substringFromIndex:1];
    }
    if ([extension length] == 0 || [normalized containsObject:extension]) {
      continue;
    }
    [normalized addObject:extension];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSString *ALNNormalizeStaticPrefix(NSString *prefix) {
  if (![prefix isKindOfClass:[NSString class]] || [prefix length] == 0) {
    return nil;
  }
  NSString *normalized =
      [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  while ([normalized containsString:@"//"]) {
    normalized = [normalized stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
  }
  if (![normalized hasPrefix:@"/"]) {
    normalized = [@"/" stringByAppendingString:normalized];
  }
  while ([normalized length] > 1 && [normalized hasSuffix:@"/"]) {
    normalized = [normalized substringToIndex:[normalized length] - 1];
  }
  return ([normalized length] > 0) ? normalized : nil;
}

static NSString *ALNResolvedStaticDirectory(NSString *directory, NSString *publicRoot) {
  if (![directory isKindOfClass:[NSString class]] || [directory length] == 0) {
    return nil;
  }
  NSString *trimmed =
      [directory stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }

  if (ALNPlatformPathIsAbsolute(trimmed)) {
    return [trimmed stringByStandardizingPath];
  }
  NSString *base = [[publicRoot stringByDeletingLastPathComponent] stringByStandardizingPath];
  return [[base stringByAppendingPathComponent:trimmed] stringByStandardizingPath];
}

static NSString *ALNCanonicalStaticPath(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return nil;
  }
#if defined(_WIN32)
  NSMutableData *wide = [[[path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
      dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  HANDLE handle = CreateFileW((const wchar_t *)wide.bytes, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (handle == INVALID_HANDLE_VALUE) return nil;
  wchar_t resolved[32768];
  DWORD count = GetFinalPathNameByHandleW(handle, resolved, 32768, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
  CloseHandle(handle);
  if (count == 0 || count >= 32768) return nil;
  NSString *canonical = [[NSString alloc] initWithBytes:resolved length:count * sizeof(wchar_t)
                                              encoding:NSUTF16LittleEndianStringEncoding];
  if ([canonical hasPrefix:@"\\\\?\\UNC\\"]) canonical = [@"\\\\" stringByAppendingString:[canonical substringFromIndex:8]];
  else if ([canonical hasPrefix:@"\\\\?\\"]) canonical = [canonical substringFromIndex:4];
  return [[canonical stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] stringByStandardizingPath];
#else
  char resolvedPath[PATH_MAX];
  const char *filesystemPath = ALNHTTPFilesystemPathCString(path);
  if (filesystemPath != NULL && realpath(filesystemPath, resolvedPath) != NULL) {
    NSString *canonical = [[NSFileManager defaultManager]
        stringWithFileSystemRepresentation:resolvedPath
                                    length:strlen(resolvedPath)];
    canonical = [canonical stringByStandardizingPath];
    return ([canonical length] > 0) ? canonical : nil;
  }
#endif
  NSString *fallback = [[path stringByResolvingSymlinksInPath] stringByStandardizingPath];
  return ([fallback length] > 0) ? fallback : nil;
}

static BOOL ALNStaticPathIsSymbolicLink(NSString *path) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return NO;
  }
#if defined(_WIN32)
  NSDictionary *attributes =
      [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
  NSString *fileType = [attributes[NSFileType] isKindOfClass:[NSString class]]
                           ? attributes[NSFileType]
                           : @"";
  return [fileType isEqualToString:NSFileTypeSymbolicLink];
#else
  struct stat info;
  const char *filesystemPath = ALNHTTPFilesystemPathCString(path);
  if (filesystemPath == NULL || lstat(filesystemPath, &info) != 0) {
    return NO;
  }
  return S_ISLNK(info.st_mode);
#endif
}

static BOOL ALNStaticCandidateWithinRoot(NSString *candidate, NSString *root) {
  if ([candidate length] == 0 || [root length] == 0) {
    return NO;
  }
#if defined(_WIN32)
  candidate = [candidate lowercaseString];
  root = [root lowercaseString];
#endif
  return [candidate isEqualToString:root] ||
         [candidate hasPrefix:[root stringByAppendingString:@"/"]];
}

static BOOL ALNResolveStaticCandidateWithinRoot(NSString *candidatePath,
                                                NSString *canonicalRoot,
                                                NSString **resolvedCandidateOut) {
  NSString *canonicalCandidate = ALNCanonicalStaticPath(candidatePath);
  if ([canonicalCandidate length] == 0 ||
      !ALNStaticCandidateWithinRoot(canonicalCandidate, canonicalRoot)) {
    return NO;
  }
  if (resolvedCandidateOut != NULL) {
    *resolvedCandidateOut = canonicalCandidate;
  }
  return YES;
}

static BOOL ALNPathWithinStaticPrefix(NSString *requestPath,
                                      NSString *prefix,
                                      NSString **relativePath) {
  NSString *path = [requestPath isKindOfClass:[NSString class]] ? requestPath : @"/";
  if ([path length] == 0) {
    path = @"/";
  }

  if ([path isEqualToString:prefix]) {
    if (relativePath != NULL) {
      *relativePath = @"";
    }
    return YES;
  }

  NSString *prefixWithSlash = [prefix stringByAppendingString:@"/"];
  if (![path hasPrefix:prefixWithSlash]) {
    return NO;
  }

  NSString *relative = [path substringFromIndex:[prefixWithSlash length]];
  if (relativePath != NULL) {
    *relativePath = relative ?: @"";
  }
  return YES;
}

static BOOL ALNStaticExtensionAllowed(NSString *filePath, NSArray *allowExtensions) {
  NSArray *allowlist = [allowExtensions isKindOfClass:[NSArray class]] ? allowExtensions : @[];
  if ([allowlist count] == 0) {
    return NO;
  }
  NSString *extension = [[filePath pathExtension] lowercaseString];
  if ([extension length] == 0) {
    return NO;
  }
  return [allowlist containsObject:extension];
}

static ALNResponse *ALNStaticNotFoundResponse(void) {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = 404;
  [response setTextBody:@"not found\n"];
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  return response;
}

static ALNResponse *ALNStaticRedirectResponse(NSString *location) {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = 301;
  [response setHeader:@"Location" value:location ?: @"/"];
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [response setTextBody:@"moved permanently\n"];
  response.committed = YES;
  return response;
}

static NSString *ALNPathWithTrailingSlash(NSString *path) {
  NSString *normalized = [path isKindOfClass:[NSString class]] ? path : @"/";
  if ([normalized length] == 0) {
    normalized = @"/";
  }
  if (![normalized hasSuffix:@"/"]) {
    normalized = [normalized stringByAppendingString:@"/"];
  }
  return normalized;
}

static ALNResponse *ALNStaticResponseForMount(ALNRequest *request,
                                              NSDictionary *mount,
                                              NSString *publicRoot,
                                              NSDictionary *mimeTypes) {
  NSString *prefix = ALNNormalizeStaticPrefix(mount[@"prefix"]);
  NSString *directory = [mount[@"directory"] isKindOfClass:[NSString class]] ? mount[@"directory"] : @"";
  NSArray *allowExtensions = [mount[@"allowExtensions"] isKindOfClass:[NSArray class]]
                                 ? mount[@"allowExtensions"]
                                 : @[];
  if ([prefix length] == 0 || [directory length] == 0) {
    return nil;
  }

  NSString *relativePath = nil;
  if (!ALNPathWithinStaticPrefix(request.path, prefix, &relativePath)) {
    return nil;
  }
#if defined(_WIN32)
  if ([relativePath containsString:@":"] || [relativePath containsString:@"\\"]) return ALNStaticNotFoundResponse();
  for (NSString *component in [relativePath componentsSeparatedByString:@"/"]) {
    NSString *base = [[[component componentsSeparatedByString:@"."] firstObject] uppercaseString];
    if ([@[@"CON", @"PRN", @"AUX", @"NUL", @"CONIN$", @"CONOUT$",
           @"COM1", @"COM2", @"COM3", @"COM4", @"COM5", @"COM6", @"COM7", @"COM8", @"COM9",
           @"LPT1", @"LPT2", @"LPT3", @"LPT4", @"LPT5", @"LPT6", @"LPT7", @"LPT8", @"LPT9"] containsObject:base]) {
      return ALNStaticNotFoundResponse();
    }
  }
#endif

  if ([relativePath containsString:@".."] ||
      [relativePath hasPrefix:@"/"] ||
      ALNStaticRelativePathIsHidden(relativePath)) {
    return ALNStaticNotFoundResponse();
  }

  NSString *standardRoot = ALNResolvedStaticDirectory(directory, publicRoot);
  NSString *canonicalRoot = ALNCanonicalStaticPath(standardRoot);
  if ([canonicalRoot length] == 0) {
    return ALNStaticNotFoundResponse();
  }

  NSString *candidatePath = ([relativePath length] > 0)
                                ? [standardRoot stringByAppendingPathComponent:relativePath]
                                : standardRoot;
  if (ALNStaticPathIsSymbolicLink(candidatePath)) {
    return ALNStaticNotFoundResponse();
  }
  NSString *standardCandidate = nil;
  if (!ALNResolveStaticCandidateWithinRoot(candidatePath, canonicalRoot, &standardCandidate)) {
    return ALNStaticNotFoundResponse();
  }
  // Apply hidden-file policy to the resolved long name as well as the URL:
  // an NTFS 8.3 alias need not preserve the leading dot of its target.
  if (standardCandidate.length > canonicalRoot.length &&
      ALNStaticRelativePathIsHidden([standardCandidate substringFromIndex:canonicalRoot.length + 1])) {
    return ALNStaticNotFoundResponse();
  }

  BOOL isDirectory = NO;
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:standardCandidate
                                                      isDirectory:&isDirectory];
  if (!exists) {
    return ALNStaticNotFoundResponse();
  }

  NSString *resolvedFilePath = nil;
  if (isDirectory) {
    NSString *indexHTML = [standardCandidate stringByAppendingPathComponent:@"index.html"];
    NSString *indexHTM = [standardCandidate stringByAppendingPathComponent:@"index.htm"];
    BOOL hasIndexHTML = [[NSFileManager defaultManager] fileExistsAtPath:indexHTML];
    BOOL hasIndexHTM = [[NSFileManager defaultManager] fileExistsAtPath:indexHTM];
    if (!hasIndexHTML && !hasIndexHTM) {
      return ALNStaticNotFoundResponse();
    }

    if (![request.path hasSuffix:@"/"]) {
      return ALNStaticRedirectResponse(ALNPathWithTrailingSlash(request.path));
    }
    resolvedFilePath = hasIndexHTML ? indexHTML : indexHTM;
    if (ALNStaticPathIsSymbolicLink(resolvedFilePath)) {
      return ALNStaticNotFoundResponse();
    }
  } else {
    NSString *filename = [[standardCandidate lastPathComponent] lowercaseString];
    if ([filename isEqualToString:@"index.html"] || [filename isEqualToString:@"index.htm"]) {
      NSString *parent = [request.path stringByDeletingLastPathComponent];
      if ([parent length] == 0) {
        parent = @"/";
      }
      return ALNStaticRedirectResponse(ALNPathWithTrailingSlash(parent));
    }
    resolvedFilePath = standardCandidate;
  }

  NSString *canonicalResolvedFilePath = nil;
  if (!ALNResolveStaticCandidateWithinRoot(resolvedFilePath, canonicalRoot, &canonicalResolvedFilePath)) {
    return ALNStaticNotFoundResponse();
  }
  resolvedFilePath = canonicalResolvedFilePath;

  if (![resolvedFilePath length] || !ALNStaticExtensionAllowed(resolvedFilePath, allowExtensions)) {
    return ALNStaticNotFoundResponse();
  }

  struct stat fileStat;
  const char *resolvedFilesystemPath = ALNHTTPFilesystemPathCString(resolvedFilePath);
  if (resolvedFilesystemPath == NULL ||
      ALNStatWithRetry(resolvedFilesystemPath, &fileStat) != 0 ||
      !S_ISREG(fileStat.st_mode)) {
    ALNResponse *response = [[ALNResponse alloc] init];
    response.statusCode = 500;
    [response setTextBody:@"failed to read static asset\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    return response;
  }

  NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObject:mimeTypes ?: @{}
                                                                    forKey:ALNFileResponseMIMETypesOption];
  NSArray *cacheControlRules = [mount[@"cacheControlRules"] isKindOfClass:[NSArray class]]
                                   ? mount[@"cacheControlRules"]
                                   : nil;
  if ([cacheControlRules count] > 0) {
    // Rules match the served file's path under the mount root, so a directory
    // request is matched as its index file.
    NSString *rootPrefix = [canonicalRoot hasSuffix:@"/"] ? canonicalRoot
                                                          : [canonicalRoot stringByAppendingString:@"/"];
    NSString *mountRelativePath = [resolvedFilePath hasPrefix:rootPrefix]
                                      ? [resolvedFilePath substringFromIndex:[rootPrefix length]]
                                      : [resolvedFilePath lastPathComponent];
    NSString *cacheControl = ALNStaticCacheControlForPath(cacheControlRules, mountRelativePath);
    if ([cacheControl length] > 0) {
      options[ALNFileResponseCacheControlOption] = cacheControl;
    }
  }
  ALNResponse *response = [[ALNResponse alloc] init];
  ALNFileResponseApplyStat(response, request, resolvedFilePath, &fileStat, nil, options);
  return response;
}

static double ALNParseHeaderDoubleValue(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return 0.0;
  }
  return [value doubleValue];
}

static void ALNEnsurePerformanceHeaders(ALNResponse *response,
                                        BOOL enabled,
                                        double parseMs,
                                        double totalMs) {
  if (!enabled) {
    return;
  }
  if ([response headerForName:@"X-Arlen-Parse-Ms"] == nil) {
    [response setHeader:@"X-Arlen-Parse-Ms"
                  value:[NSString stringWithFormat:@"%.3f", parseMs >= 0.0 ? parseMs : 0.0]];
  }
  if ([response headerForName:@"X-Arlen-Total-Ms"] == nil) {
    NSString *total = [NSString stringWithFormat:@"%.3f", totalMs >= 0.0 ? totalMs : 0.0];
    [response setHeader:@"X-Arlen-Total-Ms" value:total];
    [response setHeader:@"X-Mojo-Total-Ms" value:total];
  }
  if ([response headerForName:@"X-Arlen-Response-Write-Ms"] == nil) {
    [response setHeader:@"X-Arlen-Response-Write-Ms" value:@"0.000"];
  }
}

static void ALNSendFallbackInternalServerError(ALNSocketHandle clientFd, ALNResponseSendBudget *budget) {
  static const char *response =
      "HTTP/1.1 500 Internal Server Error\r\n"
      "Content-Type: text/plain; charset=utf-8\r\n"
      "Content-Length: 22\r\n"
      "Connection: close\r\n"
      "\r\n"
      "internal server error\n";
  (void)ALNSendAllWithBudget(clientFd, response, strlen(response), budget);
}

static double ALNSendResponseWithBudget(ALNSocketHandle clientFd,
                              ALNResponse *response,
                              BOOL performanceHeaders,
                              BOOL sendBody, ALNResponseSendBudget *budget, BOOL *sentOK) {
  double serializeStart = ALNNowMilliseconds();
  NSString *fileBodyPath = response.fileBodyPath;
  unsigned long long fileBodyLength = response.fileBodyLength;
  unsigned long long fileBodyDevice = response.fileBodyDevice;
  unsigned long long fileBodyInode = response.fileBodyInode;
  long long fileBodyMTimeSeconds = response.fileBodyMTimeSeconds;
  long fileBodyMTimeNanoseconds = response.fileBodyMTimeNanoseconds;
  int fileBodyFd = -1;
  if ([fileBodyPath length] > 0 && fileBodyLength > 0) {
    fileBodyFd = response.fileBodyHandle != nil ? ALNFileResponseDuplicateReadDescriptor(response.fileBodyHandle.fileDescriptor) :
        ALNStaticFileFDForPath(fileBodyPath,
                                        fileBodyDevice,
                                        fileBodyInode,
                                        response.fileBodyFullLength ?: fileBodyLength,
                                        fileBodyMTimeSeconds,
                                        fileBodyMTimeNanoseconds);
    if (fileBodyFd < 0) {
      double writeStart = ALNNowMilliseconds();
      *sentOK = NO;
      ALNSendFallbackInternalServerError(clientFd, budget);
      return ALNNowMilliseconds() - writeStart;
    }
    if (!sendBody) {
      close(fileBodyFd);
      fileBodyFd = -1;
    }
  }

  NSData *headerData = [response serializedHeaderData];
  double serializeMs = ALNNowMilliseconds() - serializeStart;

  if (headerData == nil || [headerData length] == 0) {
    double writeStart = ALNNowMilliseconds();
    if (fileBodyFd >= 0) {
      close(fileBodyFd);
    }
    *sentOK = NO;
    ALNSendFallbackInternalServerError(clientFd, budget);
    return (ALNNowMilliseconds() - writeStart) + serializeMs;
  }

  if (performanceHeaders) {
    [response setHeader:@"X-Arlen-Response-Write-Ms"
                  value:[NSString stringWithFormat:@"%.3f", serializeMs]];
    double currentTotal = ALNParseHeaderDoubleValue([response headerForName:@"X-Arlen-Total-Ms"]);
    NSString *total = [NSString stringWithFormat:@"%.3f", (currentTotal + serializeMs)];
    [response setHeader:@"X-Arlen-Total-Ms" value:total];
    [response setHeader:@"X-Mojo-Total-Ms" value:total];
    headerData = [response serializedHeaderData];
  }

  double writeStart = ALNNowMilliseconds();
  NSUInteger headerLength = [headerData length];
  NSData *bodyData = [response bodyDataForTransmission];
  NSUInteger bodyLength = [response bodyLength];
  if (!sendBody) {
    if (headerLength > 0) {
      *sentOK = *sentOK && ALNSendAllWithBudget(clientFd, [headerData bytes], headerLength, budget);
    }
  } else if ([fileBodyPath length] > 0 && fileBodyLength > 0) {
    if (headerLength > 0) {
      *sentOK = *sentOK && ALNSendAllWithBudget(clientFd, [headerData bytes], headerLength, budget);
    }
    if (fileBodyFd >= 0) {
      *sentOK = *sentOK && ALNSendFileDescriptor(clientFd, fileBodyFd, fileBodyLength, response.fileBodyOffset, budget);
      close(fileBodyFd);
      fileBodyFd = -1;
    }
  } else if (headerLength > 0 && bodyLength > 0) {
    struct iovec iov[2];
    iov[0].iov_base = (void *)[headerData bytes];
    iov[0].iov_len = headerLength;
    iov[1].iov_base = (void *)[bodyData bytes];
    iov[1].iov_len = bodyLength;
#if defined(_WIN32)
    *sentOK = ALNSendAllWithBudget(clientFd, [headerData bytes], headerLength, budget) &&
              ALNSendAllWithBudget(clientFd, [bodyData bytes], bodyLength, budget);
#else
    // A failed writev may already have sent bytes. Never replay its prefix.
    *sentOK = ALNWritevAll(clientFd, iov, 2, budget);
#endif
  } else {
    if (headerLength > 0) {
      *sentOK = *sentOK && ALNSendAllWithBudget(clientFd, [headerData bytes], headerLength, budget);
    }
    if (bodyLength > 0) {
      *sentOK = *sentOK && ALNSendAllWithBudget(clientFd, [bodyData bytes], bodyLength, budget);
    }
  }
  if (fileBodyFd >= 0) {
    close(fileBodyFd);
  }
  return (ALNNowMilliseconds() - writeStart) + serializeMs;
}

static double ALNSendResponse(ALNSocketHandle clientFd, ALNApplication *application,
                              ALNResponse *response, BOOL performanceHeaders, BOOL sendBody) {
  NSDictionary *limits = application.config[@"requestLimits"] ?: @{};
  ALNResponseSendBudget budget = {0};
  budget.started = ALNMonotonicMilliseconds();
  budget.timeoutMilliseconds = ALNConfigUInt(limits, @"responseSendTimeoutSeconds", 300) * 1000;
  budget.minBytesPerSecond = ALNConfigUInt(limits, @"responseMinBytesPerSecond", 1024);
  budget.graceMilliseconds = ALNConfigUInt(limits, @"responseMinRateGraceSeconds", 10) * 1000;
  BOOL bounded = budget.timeoutMilliseconds > 0 || budget.minBytesPerSecond > 0;
  // Bound individual blocking calls too, so a silent reader cannot postpone
  // the total/rate check until connectionTimeoutSeconds elapses.
#if defined(_WIN32)
  DWORD previous = 0, interval = 100;
  int timeoutLength = sizeof(previous);
  getsockopt(ALNNativeSocketHandle(clientFd), SOL_SOCKET, SO_SNDTIMEO, (char *)&previous, &timeoutLength);
  if (bounded) setsockopt(ALNNativeSocketHandle(clientFd), SOL_SOCKET, SO_SNDTIMEO, (char *)&interval, sizeof(interval));
#else
  struct timeval previous = {0}, interval = {0, 100000};
  socklen_t timeoutLength = sizeof(previous);
  getsockopt((int)clientFd, SOL_SOCKET, SO_SNDTIMEO, &previous, &timeoutLength);
  if (bounded) setsockopt((int)clientFd, SOL_SOCKET, SO_SNDTIMEO, &interval, sizeof(interval));
#endif
  BOOL sentOK = YES;
  double elapsed = ALNSendResponseWithBudget(clientFd, response, performanceHeaders, sendBody,
                                             bounded ? &budget : NULL, &sentOK);
#if defined(_WIN32)
  if (bounded) setsockopt(ALNNativeSocketHandle(clientFd), SOL_SOCKET, SO_SNDTIMEO, (char *)&previous, sizeof(previous));
#else
  if (bounded) setsockopt((int)clientFd, SOL_SOCKET, SO_SNDTIMEO, &previous, sizeof(previous));
#endif
  if (!sentOK) {
    if (budget.expired) {
      [application.logger warn:@"response send limit exceeded" fields:@{ @"bytes_sent" : @(budget.sent) }];
    }
    ALNSocketShutdown(clientFd);
  }
  return elapsed;
}

static ALNResponse *ALNErrorResponse(NSInteger statusCode, NSString *body) {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = statusCode;
  [response setTextBody:body ?: @"error\n"];
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  response.committed = YES;
  return response;
}

static NSString *ALNRealtimeBackpressureReasonForSubscriptionRejection(NSString *reason) {
  if ([reason isEqualToString:@"max_total_subscribers"]) {
    return @"realtime_total_subscriber_limit";
  }
  if ([reason isEqualToString:@"max_channel_subscribers"]) {
    return @"realtime_channel_subscriber_limit";
  }
  return @"realtime_subscriber_limit";
}

static NSString *ALNEventStreamStringHeader(ALNResponse *response, NSString *name) {
  NSString *value = [response headerForName:name];
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return trimmed ?: @"";
}

static NSNumber *ALNEventStreamUnsignedHeader(ALNResponse *response, NSString *name) {
  NSString *value = ALNEventStreamStringHeader(response, name);
  if ([value length] == 0) {
    return nil;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  long long parsed = 0;
  if (![scanner scanLongLong:&parsed] || ![scanner isAtEnd] || parsed < 0) {
    return nil;
  }
  return @((unsigned long long)parsed);
}

static NSDictionary *ALNEventStreamResyncRequiredPayload(NSString *streamID,
                                                         NSNumber *requestedAfterSequence,
                                                         NSUInteger latestSequence,
                                                         NSUInteger replayLimit,
                                                         NSUInteger replayWindow) {
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"status"] = @"resync_required";
  payload[@"stream_id"] = streamID ?: @"";
  payload[@"latest_cursor"] = @{
    @"stream_id" : streamID ?: @"",
    @"sequence" : @(latestSequence),
  };
  payload[@"replay_limit"] = @(replayLimit);
  payload[@"replay_window"] = @(replayWindow);
  if (requestedAfterSequence != nil) {
    payload[@"requested_after_sequence"] = requestedAfterSequence;
  }
  return [payload copy];
}

static NSString *ALNJSONStringForEventEnvelope(ALNEventEnvelope *event) {
  NSData *data = [ALNJSONSerialization dataWithJSONObject:[event dictionaryRepresentation]
                                                  options:0
                                                    error:NULL];
  return [[NSString alloc] initWithData:(data ?: [NSData data]) encoding:NSUTF8StringEncoding] ?: @"{}";
}

// The SSE id is the stream sequence, so a reconnecting EventSource's
// Last-Event-ID resumes after it (the event_id is in the data).
static NSString *ALNSSEFrameForEventEnvelope(ALNEventEnvelope *event) {
  if ([event.eventType rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n\0"]].location != NSNotFound) return @"";
  NSMutableString *frame = [NSMutableString string];
  [frame appendFormat:@"id: %lu\n", (unsigned long)event.sequence];
  [frame appendFormat:@"event: %@\n", event.eventType ?: @"event"];
  NSString *data = ALNJSONStringForEventEnvelope(event);
  NSArray *lines = [data componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  if ([lines count] == 0) {
    [frame appendString:@"data:\n"];
  } else {
    for (NSString *line in lines) {
      [frame appendFormat:@"data: %@\n", line ?: @""];
    }
  }
  [frame appendString:@"\n"];
  return frame;
}

static BOOL ALNSendSSEHeaders(ALNSocketHandle clientFd, ALNResponse *response) {
  NSMutableString *head = [NSMutableString string];
  [head appendString:@"HTTP/1.1 200 OK\r\n"];
  [head appendString:@"Content-Type: text/event-stream; charset=utf-8\r\n"];
  [head appendString:@"Cache-Control: no-cache\r\n"];
  [head appendString:@"Connection: keep-alive\r\n"];
  [head appendString:@"X-Accel-Buffering: no\r\n"];

  NSString *requestID = [response headerForName:@"X-Request-Id"];
  if ([requestID length] > 0) {
    [head appendFormat:@"X-Request-Id: %@\r\n", requestID];
  }
  NSString *correlationID = [response headerForName:@"X-Correlation-Id"];
  if ([correlationID length] > 0) {
    [head appendFormat:@"X-Correlation-Id: %@\r\n", correlationID];
  }
  NSString *traceID = [response headerForName:@"X-Trace-Id"];
  if ([traceID length] > 0) {
    [head appendFormat:@"X-Trace-Id: %@\r\n", traceID];
  }
  NSString *traceparent = [response headerForName:@"traceparent"];
  if ([traceparent length] > 0) {
    [head appendFormat:@"traceparent: %@\r\n", traceparent];
  }
  [head appendString:@"\r\n"];
  NSData *data = [head dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  return ALNSendAll(clientFd, [data bytes], [data length]);
}

// Event-stream delivery to one client (GitHub issue 240). The session
// subscribes before it replays. Broker callbacks only enqueue here, under the
// gate's own lock: no socket I/O runs on the appender's thread or under the
// stream's publish lock. The session's own thread sends: first the replay,
// then the queue in sequence order, skipping any sequence at or below the last
// one sent (an event both replayed and published goes out once). The queue is
// bounded; on overflow the session ends, and the client resumes from its
// cursor (Last-Event-ID for SSE) instead of the server buffering without limit.
@interface ALNEventStreamDeliveryGate : NSObject

- (instancetype)initWithSender:(BOOL (^)(ALNEventEnvelope *event))sender;
- (void)startAfterSequence:(NSUInteger)sequence;
- (BOOL)deliverReplayedEvent:(ALNEventEnvelope *)event;
// Sends what is queued. NO when a send failed or the queue overflowed.
- (BOOL)drainQueued;
// Waits up to `seconds` for queued events; YES when there are some.
- (BOOL)waitForQueuedEvents:(NSTimeInterval)seconds;
- (BOOL)hasOverflowed;
- (void)receiveLiveEvent:(ALNEventEnvelope *)event;

@end

static const NSUInteger ALNEventStreamDeliveryQueueLimit = 1024;

@implementation ALNEventStreamDeliveryGate {
  BOOL (^_sender)(ALNEventEnvelope *event);
  NSCondition *_condition;
  NSMutableArray<ALNEventEnvelope *> *_queued;
  BOOL _overflowed;
  NSUInteger _queuedBytes;
  // Touched only by the session's thread.
  NSUInteger _lastSequence;
}

- (instancetype)initWithSender:(BOOL (^)(ALNEventEnvelope *event))sender {
  self = [super init];
  if (self) {
    _sender = [sender copy];
    _condition = [[NSCondition alloc] init];
    _queued = [NSMutableArray array];
  }
  return self;
}

- (void)startAfterSequence:(NSUInteger)sequence {
  _lastSequence = sequence;
}

- (BOOL)sendIfNew:(ALNEventEnvelope *)event {
  if (event.sequence <= _lastSequence) {
    return YES;
  }
  if (!_sender(event)) {
    return NO;
  }
  _lastSequence = event.sequence;
  return YES;
}

- (BOOL)deliverReplayedEvent:(ALNEventEnvelope *)event {
  return [self sendIfNew:event];
}

- (BOOL)drainQueued {
  [_condition lock];
  NSArray<ALNEventEnvelope *> *queued =
      [_queued sortedArrayUsingComparator:^NSComparisonResult(ALNEventEnvelope *a, ALNEventEnvelope *b) {
        return (a.sequence < b.sequence) ? NSOrderedAscending
                                         : ((a.sequence > b.sequence) ? NSOrderedDescending : NSOrderedSame);
      }];
  [_queued removeAllObjects];
  _queuedBytes = 0;
  BOOL overflowed = _overflowed;
  [_condition unlock];
  if (overflowed) {
    return NO;
  }
  for (ALNEventEnvelope *event in queued) {
    if (![self sendIfNew:event]) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)waitForQueuedEvents:(NSTimeInterval)seconds {
  [_condition lock];
  if ([_queued count] == 0 && !_overflowed) {
    [_condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
  }
  BOOL ready = ([_queued count] > 0) || _overflowed;
  [_condition unlock];
  return ready;
}

- (BOOL)hasOverflowed {
  [_condition lock];
  BOOL overflowed = _overflowed;
  [_condition unlock];
  return overflowed;
}

- (void)receiveLiveEvent:(ALNEventEnvelope *)event {
  NSUInteger bytes = [ALNJSONStringForEventEnvelope(event) lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  [_condition lock];
  if (!_overflowed) {
    if ([_queued count] >= ALNEventStreamDeliveryQueueLimit || bytes > 1024 * 1024 - _queuedBytes) {
      _overflowed = YES;
      [_queued removeAllObjects];
      _queuedBytes = 0;
    } else {
      [_queued addObject:event];
      _queuedBytes += bytes;
    }
  }
  [_condition signal];
  [_condition unlock];
}

@end

@interface ALNWebSocketClientSession : NSObject <ALNRealtimeSubscriber, ALNEventStreamLiveSubscriber>

@property(nonatomic, assign, readonly) ALNSocketHandle clientFd;
@property(nonatomic, strong, readonly) NSLock *sendLock;
@property(nonatomic, assign) BOOL closed;
@property(nonatomic, strong, readonly) ALNEventStreamDeliveryGate *streamGate;

@property(nonatomic, strong) NSLock *outboundLock;
@property(nonatomic, strong) NSMutableArray *outboundMessages;
@property(nonatomic, assign) NSUInteger outboundBytes;
@property(nonatomic, assign) BOOL outboundOverflowed;
- (BOOL)drainRealtimeMessages;

- (instancetype)initWithClientFd:(ALNSocketHandle)clientFd;
- (BOOL)sendTextMessage:(NSString *)message;
- (BOOL)sendBinaryPayload:(NSData *)payload opcode:(uint8_t)opcode;
- (void)sendCloseFrame;
// A close frame carrying an RFC 6455 status code (0 sends none).
- (void)sendCloseFrameWithCode:(uint16_t)code;
- (BOOL)isClosedSnapshot;

@end

@implementation ALNWebSocketClientSession

- (instancetype)initWithClientFd:(ALNSocketHandle)clientFd {
  self = [super init];
  if (self) {
    _clientFd = clientFd;
    _sendLock = [[NSLock alloc] init];
    _closed = NO;
    _outboundLock = [[NSLock alloc] init];
    _outboundMessages = [NSMutableArray array];
    __weak ALNWebSocketClientSession *weakSelf = self;
    _streamGate = [[ALNEventStreamDeliveryGate alloc] initWithSender:^BOOL(ALNEventEnvelope *event) {
      return [weakSelf sendTextMessage:ALNJSONStringForEventEnvelope(event)];
    }];
  }
  return self;
}

- (BOOL)sendBinaryPayload:(NSData *)payload opcode:(uint8_t)opcode {
  [self.sendLock lock];
  BOOL canSend = !self.closed;
  BOOL ok = canSend ? ALNWebSocketSendFrame(self.clientFd, opcode, payload ?: [NSData data]) : NO;
  if (!ok) {
    self.closed = YES;
  }
  [self.sendLock unlock];
  return ok;
}

- (BOOL)sendTextMessage:(NSString *)message {
  NSData *payload = [[message ?: @"" copy] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  return [self sendBinaryPayload:payload opcode:0x1];
}

- (void)sendCloseFrame {
  [self sendCloseFrameWithCode:0];
}

- (void)sendCloseFrameWithCode:(uint16_t)code {
  unsigned char body[2] = {(unsigned char)(code >> 8), (unsigned char)(code & 0xFF)};
  NSData *payload = (code != 0) ? [NSData dataWithBytes:body length:sizeof(body)] : [NSData data];
  [self.sendLock lock];
  if (!self.closed) {
    (void)ALNWebSocketSendFrame(self.clientFd, 0x8, payload);
    self.closed = YES;
  }
  [self.sendLock unlock];
}

- (BOOL)isClosedSnapshot {
  [self.sendLock lock];
  BOOL closed = self.closed;
  [self.sendLock unlock];
  return closed;
}

- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel {
  (void)channel;
  NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  [self.outboundLock lock];
  if (!self.outboundOverflowed) {
    if (self.outboundMessages.count >= 128 || data.length > 1024 * 1024 - self.outboundBytes) {
      self.outboundOverflowed = YES;
      [self.outboundMessages removeAllObjects];
      self.outboundBytes = 0;
    } else {
      [self.outboundMessages addObject:data];
      self.outboundBytes += data.length;
    }
  }
  [self.outboundLock unlock];
}

- (BOOL)drainRealtimeMessages {
  [self.outboundLock lock];
  BOOL overflowed = self.outboundOverflowed;
  NSArray *messages = [self.outboundMessages copy];
  [self.outboundMessages removeAllObjects];
  self.outboundBytes = 0;
  [self.outboundLock unlock];
  if (overflowed) return NO;
  for (NSData *data in messages) {
    if (![self sendBinaryPayload:data opcode:0x1]) return NO;
  }
  return YES;
}

- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID {
  (void)streamID;
  [self.streamGate receiveLiveEvent:event];
}

@end

@interface ALNSSEClientSession : NSObject <ALNEventStreamLiveSubscriber>

@property(nonatomic, assign, readonly) ALNSocketHandle clientFd;
@property(nonatomic, strong, readonly) NSLock *sendLock;
@property(nonatomic, assign) BOOL closed;
@property(nonatomic, strong, readonly) ALNEventStreamDeliveryGate *streamGate;

- (instancetype)initWithClientFd:(ALNSocketHandle)clientFd;
- (BOOL)sendFrame:(NSString *)frame;
- (BOOL)sendKeepalive;
- (BOOL)isClosedSnapshot;

@end

@implementation ALNSSEClientSession

- (instancetype)initWithClientFd:(ALNSocketHandle)clientFd {
  self = [super init];
  if (self) {
    _clientFd = clientFd;
    _sendLock = [[NSLock alloc] init];
    _closed = NO;
    __weak ALNSSEClientSession *weakSelf = self;
    _streamGate = [[ALNEventStreamDeliveryGate alloc] initWithSender:^BOOL(ALNEventEnvelope *event) {
      return [weakSelf sendFrame:ALNSSEFrameForEventEnvelope(event)];
    }];
  }
  return self;
}

- (BOOL)sendFrame:(NSString *)frame {
  NSData *payload = [frame dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  [self.sendLock lock];
  BOOL canSend = !self.closed;
  BOOL ok = canSend ? ALNRealtimeSendAll(self.clientFd, [payload bytes], [payload length]) : NO;
  if (!ok) {
    self.closed = YES;
  }
  [self.sendLock unlock];
  return ok;
}

- (BOOL)sendKeepalive {
  return [self sendFrame:@": keepalive\n\n"];
}

- (BOOL)isClosedSnapshot {
  [self.sendLock lock];
  BOOL closed = self.closed;
  [self.sendLock unlock];
  return closed;
}

- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID {
  (void)streamID;
  [self.streamGate receiveLiveEvent:event];
}

@end

@interface ALNHTTPServer ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, copy, readwrite) NSString *publicRoot;
@property(nonatomic, strong) NSLock *runtimeCountersLock;
@property(nonatomic, assign) NSUInteger activeHTTPSessions;
@property(nonatomic, assign) NSUInteger activeWebSocketSessions;
@property(nonatomic, assign) NSUInteger maxConcurrentHTTPSessions;
@property(nonatomic, assign) NSUInteger maxConcurrentWebSocketSessions;
@property(nonatomic, assign) NSUInteger maxConcurrentHTTPWorkers;
@property(nonatomic, assign) NSUInteger maxQueuedHTTPConnections;
@property(nonatomic, assign) ALNHTTPParserBackend requestParserBackend;
@property(nonatomic, strong) NSLock *requestDispatchLock;
@property(nonatomic, assign) BOOL serializeRequestDispatch;
@property(atomic, assign) BOOL shouldRun;
@property(nonatomic, strong) NSCondition *httpWorkerQueueCondition;
@property(nonatomic, strong) NSMutableArray *pendingHTTPClientFDs;
@property(nonatomic, assign) NSUInteger pendingHTTPClientFDHeadIndex;
@property(nonatomic, assign) BOOL httpWorkerPoolStarted;
@property(nonatomic, strong) NSMutableSet *resumedHTTPClientFDs;
// Monotonic accept time (ms) of each queued new connection, keyed like
// pendingHTTPClientFDs; taken by serveClient for the first head deadline.
@property(nonatomic, strong) NSMutableDictionary *httpClientAcceptTimes;
@property(nonatomic, assign) NSUInteger keepAliveParkAfterMilliseconds;
@property(nonatomic, assign) NSUInteger webSocketPingIntervalSeconds;
@property(nonatomic, assign) NSUInteger idleConnectionTimeoutSeconds;
@property(nonatomic, strong) NSLock *idleConnectionLock;
@property(nonatomic, strong) NSMutableDictionary *idleConnectionDeadlines;
@property(atomic, assign) BOOL idleConnectionWatcherRunning;
@property(nonatomic, assign) ALNSocketHandle idleConnectionWakeReadFD;
@property(nonatomic, assign) ALNSocketHandle idleConnectionWakeWriteFD;
@property(atomic, assign) ALNSocketHandle serverSocketFD;
@property(nonatomic, strong) NSLock *staticMountCacheLock;
@property(nonatomic, copy) NSArray *cachedStaticMounts;
@property(nonatomic, copy) NSArray *webSocketAllowedOrigins;

@end

void ALNReportStartupFailure(NSString *prefix, NSString *message) {
  NSString *line = [NSString stringWithFormat:@"%@: startup failed: %@", prefix ?: @"server",
                                              message ?: @"unknown error"];
  const char *failurePath = getenv("ARLEN_STARTUP_FAILURE_FILE");
  if (failurePath != NULL && failurePath[0] != '\0') {
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if ([data writeToFile:[NSString stringWithUTF8String:failurePath] atomically:NO]) {
      return;
    }
  }
  fprintf(stderr, "%s\n", [line UTF8String]);
}

@implementation ALNHTTPServer

- (instancetype)initWithApplication:(ALNApplication *)application
                         publicRoot:(NSString *)publicRoot {
  self = [super init];
  if (self) {
    _application = application;
    _publicRoot = [publicRoot copy];
    _serverName = @"server";
    _runtimeCountersLock = [[NSLock alloc] init];
    _activeHTTPSessions = 0;
    _activeWebSocketSessions = 0;
    _maxConcurrentHTTPSessions = 256;
    _maxConcurrentWebSocketSessions = 256;
    _maxConcurrentHTTPWorkers = 8;
    _maxQueuedHTTPConnections = 256;
    _requestParserBackend = [ALNRequest resolvedParserBackend];
    _requestDispatchLock = [[NSLock alloc] init];
    _serializeRequestDispatch = NO;
    _shouldRun = YES;
    _httpWorkerQueueCondition = [[NSCondition alloc] init];
    _pendingHTTPClientFDs = [NSMutableArray array];
    _pendingHTTPClientFDHeadIndex = 0;
    _httpWorkerPoolStarted = NO;
    _resumedHTTPClientFDs = [NSMutableSet set];
    _httpClientAcceptTimes = [NSMutableDictionary dictionary];
    _keepAliveParkAfterMilliseconds = 5;
    _webSocketPingIntervalSeconds = 25;
    _idleConnectionTimeoutSeconds = 30;
    _idleConnectionLock = [[NSLock alloc] init];
    _idleConnectionDeadlines = [NSMutableDictionary dictionary];
    _idleConnectionWatcherRunning = NO;
    _idleConnectionWakeReadFD = ALNInvalidSocketHandle;
    _idleConnectionWakeWriteFD = ALNInvalidSocketHandle;
    _serverSocketFD = ALNInvalidSocketHandle;
    _staticMountCacheLock = [[NSLock alloc] init];
    _cachedStaticMounts = nil;
    _webSocketAllowedOrigins = @[];
  }
  return self;
}

- (NSArray *)buildEffectiveStaticMounts {
  NSMutableArray *mounts = [NSMutableArray array];
  NSMutableSet *seenPrefixes = [NSMutableSet set];

  NSArray *configured = [self.application.staticMounts isKindOfClass:[NSArray class]]
                            ? self.application.staticMounts
                            : @[];
  for (NSDictionary *entry in configured) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *prefix = ALNNormalizeStaticPrefix(entry[@"prefix"]);
    NSString *directory = [entry[@"directory"] isKindOfClass:[NSString class]] ? entry[@"directory"] : @"";
    NSArray *allowExtensions = ALNNormalizedStaticAllowExtensions(entry[@"allowExtensions"]);
    if ([prefix length] == 0 || [directory length] == 0) {
      continue;
    }
    if ([allowExtensions count] == 0) {
      allowExtensions = ALNDefaultStaticAllowExtensions();
    }
    if ([seenPrefixes containsObject:prefix]) {
      continue;
    }
    [seenPrefixes addObject:prefix];
    [mounts addObject:@{
      @"prefix" : prefix,
      @"directory" : directory,
      @"allowExtensions" : allowExtensions,
      @"cacheControlRules" : [entry[@"cacheControlRules"] isKindOfClass:[NSArray class]]
                                 ? entry[@"cacheControlRules"]
                                 : @[],
    }];
  }

  BOOL serveStatic = ALNConfigBool(self.application.config ?: @{}, @"serveStatic", NO);
  if (serveStatic && ![seenPrefixes containsObject:@"/static"]) {
    NSArray *configuredAllowlist =
        ALNNormalizedStaticAllowExtensions(self.application.config[@"staticAllowExtensions"]);
    NSArray *allowExtensions =
        ([configuredAllowlist count] > 0) ? configuredAllowlist : ALNDefaultStaticAllowExtensions();
    NSString *cacheControlReason = nil;
    NSArray *cacheControlRules =
        ALNStaticCacheControlRules(self.application.config[@"staticCacheControl"], &cacheControlReason);
    if (cacheControlRules == nil) {
      [self.application.logger warn:@"static cache control ignored"
                             fields:@{
                               @"prefix" : @"/static",
                               @"reason" : cacheControlReason ?: @"invalid staticCacheControl",
                             }];
      cacheControlRules = @[];
    }
    [mounts addObject:@{
      @"prefix" : @"/static",
      @"directory" : @"public",
      @"allowExtensions" : allowExtensions,
      @"cacheControlRules" : cacheControlRules,
    }];
  }

  return [NSArray arrayWithArray:mounts];
}

- (NSArray *)effectiveStaticMounts {
  [self.staticMountCacheLock lock];
  NSArray *cached = self.cachedStaticMounts;
  [self.staticMountCacheLock unlock];
  if (cached != nil) {
    return cached;
  }

  NSArray *built = [self buildEffectiveStaticMounts];
  [self.staticMountCacheLock lock];
  if (self.cachedStaticMounts == nil) {
    self.cachedStaticMounts = built ?: @[];
  }
  NSArray *resolved = self.cachedStaticMounts;
  [self.staticMountCacheLock unlock];
  return resolved ?: @[];
}

- (void)invalidateStaticMountsCache {
  [self.staticMountCacheLock lock];
  self.cachedStaticMounts = nil;
  [self.staticMountCacheLock unlock];
}

- (void)printRoutesToFile:(FILE *)stream {
  FILE *out = (stream != NULL) ? stream : stdout;
  NSArray *routes = [self.application routeTable];
  for (NSDictionary *route in routes) {
    fprintf(out, "%s %s [%s] -> %s#%s (%s)\n", [route[@"method"] UTF8String], [route[@"path"] UTF8String],
            [route[@"source"] UTF8String],
            [route[@"controller"] UTF8String], [route[@"action"] UTF8String],
            [route[@"name"] UTF8String]);
  }
  NSDictionary *spaFallback = self.application.spaFallback;
  if (spaFallback != nil) {
    // Considered only after routes and built-ins decline an HTML navigation.
    fprintf(out, "GET %s/* [spa_fallback] -> ALNSPAFallbackController#shell (arlen_spa_fallback)\n",
            [[spaFallback[@"prefix"] isEqualToString:@"/"] ? @"" : spaFallback[@"prefix"] UTF8String]);
  }
}

- (void)requestStop {
  self.shouldRun = NO;
  ALNSocketHandle serverFd = self.serverSocketFD;
  if (serverFd != ALNInvalidSocketHandle) {
    (void)ALNSocketShutdown(serverFd);
  }
  [self.httpWorkerQueueCondition lock];
  [self.httpWorkerQueueCondition broadcast];
  [self.httpWorkerQueueCondition unlock];
}

- (BOOL)shouldContinueRunning {
  return self.shouldRun && !ALNSignalStopRequested();
}

- (NSUInteger)queuedHTTPClientCountLocked {
  NSUInteger queued = [self.pendingHTTPClientFDs count];
  if (self.pendingHTTPClientFDHeadIndex >= queued) {
    return 0;
  }
  return queued - self.pendingHTTPClientFDHeadIndex;
}

- (BOOL)hasQueuedHTTPClients {
  [self.httpWorkerQueueCondition lock];
  BOOL hasQueued = ([self queuedHTTPClientCountLocked] > 0);
  [self.httpWorkerQueueCondition unlock];
  return hasQueued;
}

- (BOOL)enqueueHTTPClientForWorker:(ALNSocketHandle)clientFd {
  [self.httpWorkerQueueCondition lock];
  BOOL accepted = ([self queuedHTTPClientCountLocked] < self.maxQueuedHTTPConnections);
  if (accepted) {
    NSNumber *boxed = ALNBoxSocketHandle(clientFd);
    [self.pendingHTTPClientFDs addObject:boxed];
    self.httpClientAcceptTimes[boxed] = @(ALNMonotonicMilliseconds());
    [self.httpWorkerQueueCondition signal];
  }
  [self.httpWorkerQueueCondition unlock];
  return accepted;
}

- (BOOL)enqueueResumedHTTPClientForWorker:(ALNSocketHandle)clientFd {
  [self.httpWorkerQueueCondition lock];
  BOOL accepted = ([self queuedHTTPClientCountLocked] < self.maxQueuedHTTPConnections);
  if (accepted) {
    NSNumber *boxed = ALNBoxSocketHandle(clientFd);
    [self.pendingHTTPClientFDs addObject:boxed];
    [self.resumedHTTPClientFDs addObject:boxed];
    [self.httpWorkerQueueCondition signal];
  }
  [self.httpWorkerQueueCondition unlock];
  return accepted;
}

// The accept time recorded when clientFd was queued, or now.
- (uint64_t)takeAcceptTimeForHTTPClient:(ALNSocketHandle)clientFd {
  [self.httpWorkerQueueCondition lock];
  NSNumber *boxed = ALNBoxSocketHandle(clientFd);
  NSNumber *acceptTime = self.httpClientAcceptTimes[boxed];
  [self.httpClientAcceptTimes removeObjectForKey:boxed];
  [self.httpWorkerQueueCondition unlock];
  return (acceptTime != nil) ? [acceptTime unsignedLongLongValue] : ALNMonotonicMilliseconds();
}

- (ALNSocketHandle)dequeueHTTPClientForWorker:(BOOL *)resumed {
  if (resumed != NULL) {
    *resumed = NO;
  }
  [self.httpWorkerQueueCondition lock];
  while ([self queuedHTTPClientCountLocked] == 0 && [self shouldContinueRunning]) {
    [self.httpWorkerQueueCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
  }

  ALNSocketHandle clientFd = ALNInvalidSocketHandle;
  NSUInteger queuedCount = [self queuedHTTPClientCountLocked];
  if (queuedCount > 0) {
    NSNumber *next = self.pendingHTTPClientFDs[self.pendingHTTPClientFDHeadIndex];
    self.pendingHTTPClientFDHeadIndex += 1;
    clientFd = ALNSocketHandleFromNumber(next);
    if ([self.resumedHTTPClientFDs containsObject:next]) {
      [self.resumedHTTPClientFDs removeObject:next];
      if (resumed != NULL) {
        *resumed = YES;
      }
    }

    NSUInteger totalCount = [self.pendingHTTPClientFDs count];
    if (self.pendingHTTPClientFDHeadIndex >= totalCount) {
      [self.pendingHTTPClientFDs removeAllObjects];
      self.pendingHTTPClientFDHeadIndex = 0;
    } else if (self.pendingHTTPClientFDHeadIndex >= 64 &&
               self.pendingHTTPClientFDHeadIndex * 2 >= totalCount) {
      NSRange consumed = NSMakeRange(0, self.pendingHTTPClientFDHeadIndex);
      [self.pendingHTTPClientFDs removeObjectsInRange:consumed];
      self.pendingHTTPClientFDHeadIndex = 0;
    }
  }
  [self.httpWorkerQueueCondition unlock];
  return clientFd;
}

- (void)runHTTPWorkerLoop:(NSNumber *)workerIndexObject {
  (void)workerIndexObject;
  @autoreleasepool {
    while ([self shouldContinueRunning] || [self hasQueuedHTTPClients]) {
      BOOL resumed = NO;
      ALNSocketHandle clientFd = [self dequeueHTTPClientForWorker:&resumed];
      if (clientFd == ALNInvalidSocketHandle) {
        continue;
      }

      @autoreleasepool {
        BOOL parked = NO;
        @try {
          parked = [self serveClient:clientFd resumed:resumed allowPark:YES];
        } @catch (NSException *exception) {
          // Last resort: an exception that escaped request handling closes
          // this connection only; the worker keeps serving others.
          parked = NO;
          [self.application.logger error:@"http connection exception"
                                   fields:@{ @"exception" : exception.description ?: @"" }];
        } @finally {
          // A parked connection now belongs to the idle-connection watcher.
          if (!parked) {
            [self releaseHTTPSessionReservation];
            ALNSocketClose(clientFd);
          }
        }
      }
    }
  }
}

- (BOOL)startHTTPWorkerPoolIfNeeded {
  NSUInteger workerCount = 0;
  [self.httpWorkerQueueCondition lock];
  if (!self.httpWorkerPoolStarted) {
    self.httpWorkerPoolStarted = YES;
    workerCount = self.maxConcurrentHTTPWorkers;
  }
  [self.httpWorkerQueueCondition unlock];

  for (NSUInteger idx = 0; idx < workerCount; idx++) {
    @try {
      [NSThread detachNewThreadSelector:@selector(runHTTPWorkerLoop:)
                               toTarget:self
                             withObject:@(idx)];
    } @catch (NSException *exception) {
      (void)exception;
      return NO;
    }
  }
  if (workerCount > 0) {
    [self startIdleConnectionWatcher];
  }
  return YES;
}

// Idle keep-alive connections (GitHub issue 187). A worker that has finished a
// keep-alive response and sees no next request within
// keepAliveParkAfterMilliseconds hands the connection to a single watcher
// thread, which polls all parked connections and re-queues each one for a
// worker once it becomes readable. Idle browser connections therefore no
// longer pin the fixed worker pool. Parked connections keep their HTTP session
// reservation and are closed after connectionTimeoutSeconds, as before.
- (void)startIdleConnectionWatcher {
  if (self.idleConnectionWatcherRunning) {
    return;
  }
  ALNSocketHandle readEnd = ALNInvalidSocketHandle;
  ALNSocketHandle writeEnd = ALNInvalidSocketHandle;
  if (!ALNWakeChannelOpen(&readEnd, &writeEnd)) {
    return;
  }
  self.idleConnectionWakeReadFD = readEnd;
  self.idleConnectionWakeWriteFD = writeEnd;
  self.idleConnectionWatcherRunning = YES;
  @try {
    [NSThread detachNewThreadSelector:@selector(runIdleConnectionWatcher:) toTarget:self withObject:nil];
  } @catch (NSException *exception) {
    (void)exception;
    self.idleConnectionWatcherRunning = NO;
    ALNWakeChannelClose(readEnd, writeEnd);
    self.idleConnectionWakeReadFD = ALNInvalidSocketHandle;
    self.idleConnectionWakeWriteFD = ALNInvalidSocketHandle;
  }
}

// Under idleConnectionLock, as the watcher's teardown closes the channel under
// it: a wake racing shutdown must not write to a closed, reused handle number
// (Windows reuses SOCKET values quickly). The signal never blocks.
- (void)wakeIdleConnectionWatcher {
  [self.idleConnectionLock lock];
  ALNSocketHandle wakeEnd = self.idleConnectionWakeWriteFD;
  if (wakeEnd != ALNInvalidSocketHandle) {
    ALNWakeChannelSignal(wakeEnd);
  }
  [self.idleConnectionLock unlock];
}

- (BOOL)parkIdleConnection:(ALNSocketHandle)clientFd {
  if (!self.idleConnectionWatcherRunning || ![self shouldContinueRunning]) {
    return NO;
  }
  NSUInteger timeoutSeconds = self.idleConnectionTimeoutSeconds;
  double deadline = (timeoutSeconds > 0) ? ALNNowMilliseconds() + (double)timeoutSeconds * 1000.0 : 0.0;
  [self.idleConnectionLock lock];
  self.idleConnectionDeadlines[ALNBoxSocketHandle(clientFd)] = @(deadline);
  [self.idleConnectionLock unlock];
  [self wakeIdleConnectionWatcher];
  return YES;
}

// Called after a keep-alive response. Returns YES when the connection was
// handed to the watcher and the worker should move on.
- (BOOL)parkIfIdleConnection:(ALNSocketHandle)clientFd
                   readState:(ALNConnectionReadState *)readState
                   allowPark:(BOOL)allowPark {
  if (!allowPark || !self.idleConnectionWatcherRunning || readState == NULL || readState->length > 0) {
    // Pipelined bytes are already buffered: serve them on this worker.
    return NO;
  }
  if ([self hasQueuedHTTPClients]) {
    // Other connections are waiting for a worker. Yield this one to the watcher
    // even if its next request is already here: it goes back in line behind
    // them when readable. Otherwise a handful of busy keep-alive clients held
    // every worker and new clients got no service at all (PERF-07 on #187).
    return [self parkIdleConnection:clientFd];
  }
  ALNPollEntry entry;
  ALNPollEntrySet(&entry, clientFd);
  int graceMilliseconds = (int)MIN(self.keepAliveParkAfterMilliseconds, (NSUInteger)1000);
  int rc = 0;
  do {
    rc = ALNSocketPoll(&entry, 1, graceMilliseconds);
  } while (rc < 0 && errno == EINTR);
  if (rc != 0) {
    // The next request (or EOF) is already here, or poll failed: keep reading here.
    return NO;
  }
  return [self parkIdleConnection:clientFd];
}

- (void)runIdleConnectionWatcher:(id)unused {
  (void)unused;
  @autoreleasepool {
    size_t pollCapacity = 64;
    ALNPollEntry *pollFDs = calloc(pollCapacity, sizeof(ALNPollEntry));
    ALNSocketHandle wakeFD = self.idleConnectionWakeReadFD;
    while (pollFDs != NULL && [self shouldContinueRunning]) {
      @autoreleasepool {
        [self.idleConnectionLock lock];
        NSDictionary *deadlines = [self.idleConnectionDeadlines copy];
        [self.idleConnectionLock unlock];

        NSArray *parkedFDs = [deadlines allKeys];
        size_t count = [parkedFDs count] + 1;
        if (count > pollCapacity) {
          size_t grownCapacity = MAX(count, pollCapacity * 2);
          ALNPollEntry *grown = realloc(pollFDs, grownCapacity * sizeof(ALNPollEntry));
          if (grown == NULL) {
            break;
          }
          pollFDs = grown;
          pollCapacity = grownCapacity;
        }
        ALNPollEntrySet(&pollFDs[0], wakeFD);
        double now = ALNNowMilliseconds();
        double timeoutMilliseconds = 250.0;
        for (NSUInteger idx = 0; idx < [parkedFDs count]; idx++) {
          ALNPollEntrySet(&pollFDs[idx + 1], ALNSocketHandleFromNumber(parkedFDs[idx]));
          double deadline = [deadlines[parkedFDs[idx]] doubleValue];
          if (deadline > 0.0) {
            timeoutMilliseconds = MIN(timeoutMilliseconds, MAX(0.0, deadline - now));
          }
        }

        int rc = ALNSocketPoll(pollFDs, count, (int)ceil(timeoutMilliseconds));
        if (rc < 0 && errno != EINTR) {
          break;
        }
        if (pollFDs[0].revents & POLLIN) {
          ALNWakeChannelDrain(wakeFD);
        }

        now = ALNNowMilliseconds();
        NSMutableArray *ready = [NSMutableArray array];
        NSMutableArray *expired = [NSMutableArray array];
        [self.idleConnectionLock lock];
        for (NSUInteger idx = 0; idx < [parkedFDs count]; idx++) {
          NSNumber *boxed = parkedFDs[idx];
          if (self.idleConnectionDeadlines[boxed] == nil) {
            continue;
          }
          short revents = (rc > 0) ? pollFDs[idx + 1].revents : 0;
          double deadline = [deadlines[boxed] doubleValue];
          if (revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
            [ready addObject:boxed];
            [self.idleConnectionDeadlines removeObjectForKey:boxed];
          } else if (deadline > 0.0 && now >= deadline) {
            [expired addObject:boxed];
            [self.idleConnectionDeadlines removeObjectForKey:boxed];
          }
        }
        [self.idleConnectionLock unlock];

        for (NSNumber *boxed in ready) {
          ALNSocketHandle clientFd = ALNSocketHandleFromNumber(boxed);
          if (![self enqueueResumedHTTPClientForWorker:clientFd]) {
            [self releaseHTTPSessionReservation];
            ALNSocketClose(clientFd);
          }
        }
        for (NSNumber *boxed in expired) {
          [self releaseHTTPSessionReservation];
          ALNSocketClose(ALNSocketHandleFromNumber(boxed));
        }
      }
    }

    [self.idleConnectionLock lock];
    NSArray *remaining = [self.idleConnectionDeadlines allKeys];
    [self.idleConnectionDeadlines removeAllObjects];
    [self.idleConnectionLock unlock];
    for (NSNumber *boxed in remaining) {
      [self releaseHTTPSessionReservation];
      ALNSocketClose(ALNSocketHandleFromNumber(boxed));
    }
    free(pollFDs);
    self.idleConnectionWatcherRunning = NO;
    [self.idleConnectionLock lock];
    ALNSocketHandle wakeRead = self.idleConnectionWakeReadFD;
    ALNSocketHandle wakeWrite = self.idleConnectionWakeWriteFD;
    self.idleConnectionWakeReadFD = ALNInvalidSocketHandle;
    self.idleConnectionWakeWriteFD = ALNInvalidSocketHandle;
    ALNWakeChannelClose(wakeRead, wakeWrite);
    [self.idleConnectionLock unlock];
  }
}

- (void)resetHTTPWorkerPoolState {
  [self.httpWorkerQueueCondition lock];
  [self.pendingHTTPClientFDs removeAllObjects];
  [self.resumedHTTPClientFDs removeAllObjects];
  self.pendingHTTPClientFDHeadIndex = 0;
  self.httpWorkerPoolStarted = NO;
  [self.httpWorkerQueueCondition unlock];
  [self invalidateStaticMountsCache];
  ALNStaticFileFDCacheClear();
}

- (BOOL)reserveWebSocketSessionWithLimit:(NSUInteger)limit {
  [self.runtimeCountersLock lock];
  BOOL allowed = YES;
  if (limit > 0 && self.activeWebSocketSessions >= limit) {
    allowed = NO;
  } else {
    self.activeWebSocketSessions += 1;
  }
  [self.runtimeCountersLock unlock];
  return allowed;
}

- (BOOL)reserveHTTPSessionWithLimit:(NSUInteger)limit {
  [self.runtimeCountersLock lock];
  BOOL allowed = YES;
  if (limit > 0 && self.activeHTTPSessions >= limit) {
    allowed = NO;
  } else {
    self.activeHTTPSessions += 1;
  }
  [self.runtimeCountersLock unlock];
  return allowed;
}

- (void)releaseHTTPSessionReservation {
  [self.runtimeCountersLock lock];
  if (self.activeHTTPSessions > 0) {
    self.activeHTTPSessions -= 1;
  }
  [self.runtimeCountersLock unlock];
}

- (void)releaseWebSocketSessionReservation {
  [self.runtimeCountersLock lock];
  if (self.activeWebSocketSessions > 0) {
    self.activeWebSocketSessions -= 1;
  }
  [self.runtimeCountersLock unlock];
}

- (NSString *)webSocketModeFromResponse:(ALNResponse *)response {
  NSString *mode = [[response headerForName:@"X-Arlen-WebSocket-Mode"] lowercaseString];
  if ([mode isEqualToString:@"echo"] || [mode isEqualToString:@"channel"] ||
      [mode isEqualToString:@"stream"]) {
    return mode;
  }
  return @"";
}

- (NSString *)sseModeFromResponse:(ALNResponse *)response {
  NSString *mode = [[response headerForName:@"X-Arlen-SSE-Mode"] lowercaseString];
  if ([mode isEqualToString:@"stream"]) {
    return mode;
  }
  return @"";
}

- (NSString *)webSocketChannelFromResponse:(ALNResponse *)response {
  NSString *channel = [response headerForName:@"X-Arlen-WebSocket-Channel"];
  if (![channel isKindOfClass:[NSString class]]) {
    return @"default";
  }
  NSString *normalized =
      [[channel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
          lowercaseString];
  return ([normalized length] > 0) ? normalized : @"default";
}

- (NSString *)eventStreamIdentifierFromResponse:(ALNResponse *)response {
  return ALNEventStreamStringHeader(response, @"X-Arlen-Event-Stream-Id");
}

- (NSNumber *)eventStreamAfterSequenceFromResponse:(ALNResponse *)response {
  return ALNEventStreamUnsignedHeader(response, @"X-Arlen-Event-Stream-After-Sequence");
}

- (NSUInteger)eventStreamReplayLimitFromResponse:(ALNResponse *)response {
  NSNumber *value = ALNEventStreamUnsignedHeader(response, @"X-Arlen-Event-Stream-Replay-Limit");
  NSUInteger limit = [value respondsToSelector:@selector(unsignedIntegerValue)]
                         ? [value unsignedIntegerValue]
                         : 100;
  return (limit > 0) ? limit : 100;
}

- (NSUInteger)eventStreamReplayWindowFromResponse:(ALNResponse *)response {
  NSNumber *value = ALNEventStreamUnsignedHeader(response, @"X-Arlen-Event-Stream-Replay-Window");
  NSUInteger window = [value respondsToSelector:@selector(unsignedIntegerValue)]
                          ? [value unsignedIntegerValue]
                          : 0;
  return (window > 0) ? window : [self eventStreamReplayLimitFromResponse:response];
}

- (ALNEventStreamReplayResult *)eventStreamReplayResultFromResponse:(ALNResponse *)response
                                                              error:(NSError **)error {
  id<ALNEventStreamStore> store = self.application.eventStreamStore;
  if (store == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNEventStreamErrorDomain
                                   code:ALNEventStreamErrorInvalidArgument
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Event stream transport requires a configured store",
                               }];
    }
    return nil;
  }
  ALNEventStreamService *service =
      [[ALNEventStreamService alloc] initWithStore:store broker:self.application.eventStreamBroker];
  return [service replayStream:[self eventStreamIdentifierFromResponse:response]
                 afterSequence:[self eventStreamAfterSequenceFromResponse:response]
                         limit:[self eventStreamReplayLimitFromResponse:response]
                  replayWindow:[self eventStreamReplayWindowFromResponse:response]
                         error:error];
}

- (ALNResponse *)eventStreamResyncResponseForResponse:(ALNResponse *)response
                                         replayResult:(ALNEventStreamReplayResult *)result {
  ALNResponse *resyncResponse = [[ALNResponse alloc] init];
  resyncResponse.statusCode = 409;
  NSData *bodyData =
      [ALNJSONSerialization dataWithJSONObject:ALNEventStreamResyncRequiredPayload(
                                              result.streamID,
                                              result.requestedAfterSequence,
                                              result.latestCursor.sequence,
                                              result.replayLimit,
                                              result.replayWindow)
                                       options:0
                                         error:NULL];
  [resyncResponse setDataBody:(bodyData ?: [NSData data])
                  contentType:@"application/json; charset=utf-8"];
  NSString *requestID = [response headerForName:@"X-Request-Id"];
  if ([requestID length] > 0) {
    [resyncResponse setHeader:@"X-Request-Id" value:requestID];
  }
  NSString *correlationID = [response headerForName:@"X-Correlation-Id"];
  if ([correlationID length] > 0) {
    [resyncResponse setHeader:@"X-Correlation-Id" value:correlationID];
  }
  NSString *traceID = [response headerForName:@"X-Trace-Id"];
  if ([traceID length] > 0) {
    [resyncResponse setHeader:@"X-Trace-Id" value:traceID];
  }
  return resyncResponse;
}

- (BOOL)sendWebSocketHandshakeForRequest:(ALNRequest *)request
                                response:(ALNResponse *)response
                                clientFd:(ALNSocketHandle)clientFd {
  NSString *clientKey = [request headerValueForName:@"sec-websocket-key"];
  NSString *acceptKey = ALNWebSocketAcceptKey(clientKey);
  if ([acceptKey length] == 0) {
    return NO;
  }

  NSMutableString *handshake = [NSMutableString string];
  [handshake appendString:@"HTTP/1.1 101 Switching Protocols\r\n"];
  [handshake appendString:@"Upgrade: websocket\r\n"];
  [handshake appendString:@"Connection: Upgrade\r\n"];
  [handshake appendFormat:@"Sec-WebSocket-Accept: %@\r\n", acceptKey];

  NSString *requestID = [response headerForName:@"X-Request-Id"];
  if ([requestID length] > 0) {
    [handshake appendFormat:@"X-Request-Id: %@\r\n", requestID];
  }
  NSString *correlationID = [response headerForName:@"X-Correlation-Id"];
  if ([correlationID length] > 0) {
    [handshake appendFormat:@"X-Correlation-Id: %@\r\n", correlationID];
  }
  NSString *traceID = [response headerForName:@"X-Trace-Id"];
  if ([traceID length] > 0) {
    [handshake appendFormat:@"X-Trace-Id: %@\r\n", traceID];
  }
  NSString *traceparent = [response headerForName:@"traceparent"];
  if ([traceparent length] > 0) {
    [handshake appendFormat:@"traceparent: %@\r\n", traceparent];
  }
  NSString *protocol = [response headerForName:@"Sec-WebSocket-Protocol"];
  if ([protocol length] > 0) {
    [handshake appendFormat:@"Sec-WebSocket-Protocol: %@\r\n", protocol];
  }
  [handshake appendString:@"\r\n"];

  NSData *data = [handshake dataUsingEncoding:NSUTF8StringEncoding];
  return ALNSendAll(clientFd, [data bytes], [data length]);
}

- (void)runWebSocketSessionWithMode:(NSString *)mode
                            channel:(NSString *)channel
                            session:(ALNWebSocketClientSession *)session
                       subscription:(ALNRealtimeSubscription *)subscription
               streamSubscription:(ALNEventStreamBrokerSubscription *)streamSubscription
                           clientFd:(ALNSocketHandle)clientFd {
  if ([mode length] == 0 || session == nil) {
    return;
  }

  // A message may span frames (RFC 6455 fragmentation) up to this total.
  const NSUInteger maxMessageBytes = 1048576;
  // Idle sessions (GitHub issue 239): with no frame for a ping interval the
  // server pings; a client that stays silent for another interval is closed
  // with 1001. A quiet receive-only subscriber is no longer dropped by the
  // socket read timeout.
  const double pingIntervalMs = (double)self.webSocketPingIntervalSeconds * 1000.0;
  double lastFrameMs = ALNNowMilliseconds();
  double pingSentMs = 0.0;
  NSMutableData *fragments = nil;
  uint8_t fragmentOpcode = 0;
  @try {
    while ([self shouldContinueRunning] && ![session isClosedSnapshot]) {
      if (![session drainRealtimeMessages]) break;
      int readable = ALNWebSocketWaitReadable(clientFd, 100);
      if (readable < 0) {
        break;
      }
      if (readable == 0) {
        double now = ALNNowMilliseconds();
        if (pingIntervalMs > 0.0) {
          if (pingSentMs == 0.0 && now - lastFrameMs >= pingIntervalMs) {
            if (![session sendBinaryPayload:[NSData data] opcode:0x9]) {
              break;
            }
            pingSentMs = now;
          } else if (pingSentMs > 0.0 && now - pingSentMs >= pingIntervalMs) {
            [session sendCloseFrameWithCode:ALNWebSocketCloseGoingAway];
            break;
          }
        }
        continue;
      }

      uint8_t opcode = 0;
      BOOL fin = NO;
      NSData *payload = nil;
      uint16_t closeCode = 0;
      ALNWebSocketReadStatus status =
          ALNWebSocketReadFrame(clientFd, &opcode, &fin, &payload, maxMessageBytes, &closeCode);
      if (status == ALNWebSocketReadConnectionLost) {
        break;
      }
      if (status == ALNWebSocketReadProtocolError) {
        [session sendCloseFrameWithCode:closeCode];
        break;
      }
      lastFrameMs = ALNNowMilliseconds();
      pingSentMs = 0.0;

      if (opcode == 0x8) {
        // Echo the peer's status code (RFC 6455 5.5.1).
        uint16_t peerCode = 0;
        if ([payload length] >= 2) {
          const unsigned char *bytes = (const unsigned char *)[payload bytes];
          peerCode = (uint16_t)((bytes[0] << 8) | bytes[1]);
        }
        [session sendCloseFrameWithCode:peerCode];
        break;
      }
      if (opcode == 0x9) {
        (void)[session sendBinaryPayload:payload ?: [NSData data] opcode:0xA];
        continue;
      }
      if (opcode == 0xA) {
        continue;
      }

      // Data frames: 0x1 text and 0x2 binary start a message, 0x0 continues one.
      if (opcode == 0x0) {
        if (fragments == nil) {
          [session sendCloseFrameWithCode:ALNWebSocketCloseProtocolError];
          break;
        }
        if ([fragments length] + [payload length] > maxMessageBytes) {
          [session sendCloseFrameWithCode:ALNWebSocketCloseMessageTooBig];
          break;
        }
        [fragments appendData:payload ?: [NSData data]];
        if (!fin) {
          continue;
        }
        payload = fragments;
        opcode = fragmentOpcode;
        fragments = nil;
      } else if (fragments != nil) {
        // A new message may not start inside a fragmented one.
        [session sendCloseFrameWithCode:ALNWebSocketCloseProtocolError];
        break;
      } else if (!fin) {
        fragments = [NSMutableData dataWithData:payload ?: [NSData data]];
        fragmentOpcode = opcode;
        continue;
      }
      if (opcode != 0x1) {
        continue;
      }

      if (!ALNWebSocketIsValidUTF8((const unsigned char *)[payload bytes], [payload length])) {
        [session sendCloseFrameWithCode:ALNWebSocketCloseInvalidPayload];
        break;
      }
      NSString *message = [[NSString alloc] initWithData:(payload ?: [NSData data])
                                                encoding:NSUTF8StringEncoding] ?: @"";

      if ([mode isEqualToString:@"channel"]) {
        continue; // Channel subscriptions are receive-only.
      } else if ([mode isEqualToString:@"stream"]) {
        continue;
      } else {
        (void)[session sendTextMessage:message];
      }
    }
  } @finally {
    if (subscription != nil) {
      [[ALNRealtimeHub sharedHub] unsubscribe:subscription];
    }
    if (streamSubscription != nil && self.application.eventStreamBroker != nil) {
      [self.application.eventStreamBroker unsubscribe:streamSubscription];
    }
  }
}

// Sends a websocket stream session's live events (see
// ALNEventStreamDeliveryGate) until the session closes. On a failed send or an
// overflowed queue it closes the session and shuts the socket down, which also
// ends the session's blocked read loop; the client resumes from its cursor.
- (void)runWebSocketStreamSender:(ALNWebSocketClientSession *)session {
  @autoreleasepool {
    while ([self shouldContinueRunning] && ![session isClosedSnapshot]) {
      (void)[session.streamGate waitForQueuedEvents:1.0];
      if (![session.streamGate drainQueued]) {
        [session sendCloseFrame];
        (void)ALNSocketShutdown(session.clientFd);
        break;
      }
    }
  }
}

- (void)runSSEStreamSession:(ALNSSEClientSession *)session
               subscription:(ALNEventStreamBrokerSubscription *)subscription {
  if (session == nil) {
    return;
  }
  double lastKeepaliveMs = ALNNowMilliseconds();
  @try {
    while ([self shouldContinueRunning] && ![session isClosedSnapshot]) {
      // Live events go out from this thread (see ALNEventStreamDeliveryGate).
      // An overflowed queue ends the stream; the client resumes with
      // Last-Event-ID.
      (void)[session.streamGate waitForQueuedEvents:1.0];
      if (![session.streamGate drainQueued]) {
        break;
      }
      if (ALNNowMilliseconds() - lastKeepaliveMs >= 15000.0) {
        if (![session sendKeepalive]) {
          break;
        }
        lastKeepaliveMs = ALNNowMilliseconds();
      }
    }
  } @finally {
    if (subscription != nil && self.application.eventStreamBroker != nil) {
      [self.application.eventStreamBroker unsubscribe:subscription];
    }
  }
}

- (void)handleClient:(ALNSocketHandle)clientFd {
  (void)[self serveClient:clientFd resumed:NO allowPark:NO];
}

// Returns YES when the connection was parked with the idle-connection watcher;
// the caller must then leave the socket open and keep its session reservation.
- (BOOL)serveClient:(ALNSocketHandle)clientFd resumed:(BOOL)resumed allowPark:(BOOL)allowPark {
  // The server only adds timing headers; the performance log is the application's.
  BOOL performanceHeaders =
      ALNConfigBool(self.application.config ?: @{}, @"performanceLogging", YES) &&
      ALNConfigBool(self.application.config ?: @{}, @"performanceHeaders", YES);
  ALNRequestLimits limits = ALNLimitsFromConfig(self.application.config ?: @{});
  NSUInteger largestRouteBodyLimit = [self.application largestRouteMaxBodyBytes];
  if (largestRouteBodyLimit > 0) {
    limits.routeBodyLimitsActive = YES;
    limits.application = self.application;
    limits.maxBodyBytes = MAX(limits.maxBodyBytes, largestRouteBodyLimit);
  }
  ALNServerSocketTuning tuning = ALNTuningFromConfig(self.application.config ?: @{});
  ALNApplyClientSocketTimeout(clientFd, tuning.connectionTimeoutSeconds);
  if (!resumed) {
    ALNApplyClientSocketNoDelay(clientFd);
  }
  NSString *connectionRemoteAddress = ALNRemoteAddressForClient(clientFd) ?: @"";
  ALNConnectionReadState readState;
  ALNConnectionReadStateInit(&readState);
  uint64_t acceptTime = [self takeAcceptTimeForHTTPClient:clientFd];
  uint64_t firstHeadDeadline =
      (!resumed && limits.headTimeoutMilliseconds > 0) ? acceptTime + limits.headTimeoutMilliseconds : 0;

  @try {
    // A resumed connection has already served requests, so a timeout closes it quietly.
    NSUInteger requestsHandled = resumed ? 1 : 0;
    while ([self shouldContinueRunning]) {
      @autoreleasepool {
        double requestStartMs = ALNNowMilliseconds();

        NSInteger readStatus = 0;
        double parseStartMs = ALNNowMilliseconds();
        limits.firstRequestHeadDeadline = (requestsHandled == 0) ? firstHeadDeadline : 0;
        ALNRequest *request = ALNReadHTTPRequest(clientFd,
                                                 limits,
                                                 self.requestParserBackend,
                                                 &readStatus,
                                                 &readState);
        double parseMs = ALNNowMilliseconds() - parseStartMs;
        if (request == nil) {
          if (readStatus == 0) {
            return NO;
          }
          if (requestsHandled > 0 && readStatus == 408) {
            return NO;
          }

          ALNResponse *errorResponse = nil;
          if (readStatus == 413) {
            errorResponse = ALNErrorResponse(413, @"payload too large\n");
          } else if (readStatus == 431) {
            errorResponse = ALNErrorResponse(431, @"request headers too large\n");
          } else if (readStatus == 408) {
            errorResponse = ALNErrorResponse(408, @"request timeout\n");
          } else if (readStatus == 417) {
            errorResponse = ALNErrorResponse(417, @"expectation failed\n");
          } else {
            errorResponse = ALNErrorResponse(400, @"bad request\n");
          }
          [errorResponse setHeader:@"Connection" value:@"close"];
          // These responses are written before the application runs, so add
          // the configured security headers here (#253).
          ALNApplyBaselineSecurityHeaders(self.application, errorResponse);
          ALNEnsurePerformanceHeaders(errorResponse,
                                      performanceHeaders,
                                      parseMs,
                                      ALNNowMilliseconds() - requestStartMs);
          (void)ALNSendResponse(clientFd, self.application, errorResponse, performanceHeaders, YES);
#if defined(_WIN32)
          ALNFinishRejectedClientOutput(clientFd);
#endif
          return NO;
        }
        request.parseDurationMilliseconds = parseMs;

        request.remoteAddress = connectionRemoteAddress;
        request.effectiveRemoteAddress = request.remoteAddress ?: @"";
        request.scheme = @"http";
        ALNApplyProxyMetadata(request, self.application.config ?: @{});

        BOOL supportsStaticMethod = [request.method isEqualToString:@"GET"] ||
                                    [request.method isEqualToString:@"HEAD"];
        BOOL handledStatic = NO;
        BOOL multipartValid = [request parseMultipartFormWithLimits:[self.application requestLimitsForRequest:request] error:NULL];
        if (supportsStaticMethod && multipartValid) {
          NSArray *staticMounts = [self effectiveStaticMounts];
          NSDictionary *staticMIMETypes =
              [self.application.config[@"mimeTypes"] isKindOfClass:[NSDictionary class]]
                  ? self.application.config[@"mimeTypes"]
                  : nil;
          for (NSDictionary *mount in staticMounts) {
            ALNResponse *staticResponse = ALNStaticResponseForMount(request,
                                                                      mount,
                                                                      self.publicRoot,
                                                                      staticMIMETypes);
            if (staticResponse == nil) {
              continue;
            }
            // Static responses bypass the middleware chain (GitHub issue 81).
            ALNApplyBaselineSecurityHeaders(self.application, staticResponse);
            // Request dispatch mode does not force connection close; keep-alive follows HTTP semantics.
            BOOL keepAlive = ALNShouldKeepAliveForRequest(request, staticResponse);
            [staticResponse setHeader:@"Connection" value:(keepAlive ? @"keep-alive" : @"close")];
            ALNEnsurePerformanceHeaders(staticResponse,
                                        performanceHeaders,
                                        parseMs,
                                        ALNNowMilliseconds() - requestStartMs);
            request.responseWriteDurationMilliseconds =
                ALNSendResponse(clientFd, self.application,
                                staticResponse,
                                performanceHeaders,
                                ![request.method isEqualToString:@"HEAD"]);
            requestsHandled += 1;
            if (!keepAlive) {
              return NO;
            }
            if ([self parkIfIdleConnection:clientFd readState:&readState allowPark:allowPark]) {
              return YES;
            }
            handledStatic = YES;
            break;
          }
        }
        if (handledStatic) {
          continue;
        }

        ALNResponse *response = nil;
        @try {
          if (self.serializeRequestDispatch) {
            [self.requestDispatchLock lock];
            @try {
              response = [self.application dispatchRequest:request];
            } @finally {
              [self.requestDispatchLock unlock];
            }
          } else {
            response = [self.application dispatchRequest:request];
          }
        } @finally {
          // Spooled bodies and uploads end with the handler. Do not rely on
          // dealloc: a handler exception unwinds ARC frames without releasing
          // them, which leaked the request and its spool files.
          [request removeTemporaryFiles];
        }

        NSString *webSocketMode = [self webSocketModeFromResponse:response];
        NSString *sseMode = [self sseModeFromResponse:response];
        BOOL responseWantsWebSocket = (response.statusCode == 101) && ([webSocketMode length] > 0);
        BOOL webSocketRequestValid = ALNRequestIsWebSocketUpgrade(request);
        if (responseWantsWebSocket && !webSocketRequestValid) {
          ALNResponse *invalidUpgrade = ALNErrorResponse(400, @"invalid websocket upgrade\n");
          [invalidUpgrade setHeader:@"Connection" value:@"close"];
          ALNEnsurePerformanceHeaders(invalidUpgrade,
                                      performanceHeaders,
                                      parseMs,
                                      ALNNowMilliseconds() - requestStartMs);
          (void)ALNSendResponse(clientFd, self.application, invalidUpgrade, performanceHeaders, YES);
          return NO;
        }
        BOOL webSocketUpgrade = webSocketRequestValid && responseWantsWebSocket;
        if (webSocketUpgrade) {
          if (!ALNWebSocketOriginAllowed(request, self.webSocketAllowedOrigins)) {
            ALNResponse *originDenied = ALNErrorResponse(403, @"websocket origin not allowed\n");
            [originDenied setHeader:@"Connection" value:@"close"];
            ALNEnsurePerformanceHeaders(originDenied,
                                        performanceHeaders,
                                        parseMs,
                                        ALNNowMilliseconds() - requestStartMs);
            (void)ALNSendResponse(clientFd, self.application, originDenied, performanceHeaders, YES);
            return NO;
          }
          ALNWebSocketClientSession *webSocketSession = nil;
          ALNRealtimeSubscription *channelSubscription = nil;
          ALNEventStreamBrokerSubscription *streamSubscription = nil;
          NSString *webSocketChannel = @"";
          ALNEventStreamReplayResult *streamReplayResult = nil;

          BOOL reserved =
              [self reserveWebSocketSessionWithLimit:self.maxConcurrentWebSocketSessions];
          if (!reserved) {
            ALNResponse *busyResponse = ALNErrorResponse(503, @"server busy\n");
            [busyResponse setHeader:@"Retry-After" value:@"1"];
            [busyResponse setHeader:@"X-Arlen-Backpressure-Reason"
                              value:@"websocket_session_limit"];
            [busyResponse setHeader:@"Connection" value:@"close"];
            ALNEnsurePerformanceHeaders(busyResponse,
                                        performanceHeaders,
                                        parseMs,
                                        ALNNowMilliseconds() - requestStartMs);
            (void)ALNSendResponse(clientFd, self.application, busyResponse, performanceHeaders, YES);
            return NO;
          }

          if ([webSocketMode isEqualToString:@"channel"]) {
            ALNWarnIfRealtimeIsWorkerLocal();
            webSocketChannel = [self webSocketChannelFromResponse:response];
            webSocketSession = [[ALNWebSocketClientSession alloc] initWithClientFd:clientFd];
            NSString *rejectionReason = nil;
            channelSubscription = [[ALNRealtimeHub sharedHub]
                subscribeChannel:webSocketChannel
                       subscriber:webSocketSession
                 rejectionReason:&rejectionReason];
            if (channelSubscription == nil) {
              ALNResponse *busyResponse = ALNErrorResponse(503, @"server busy\n");
              [busyResponse setHeader:@"Retry-After" value:@"1"];
              [busyResponse setHeader:@"X-Arlen-Backpressure-Reason"
                                value:ALNRealtimeBackpressureReasonForSubscriptionRejection(
                                          rejectionReason)];
              [busyResponse setHeader:@"Connection" value:@"close"];
              ALNEnsurePerformanceHeaders(busyResponse,
                                          performanceHeaders,
                                          parseMs,
                                          ALNNowMilliseconds() - requestStartMs);
              (void)ALNSendResponse(clientFd, self.application, busyResponse, performanceHeaders, YES);
              [self releaseWebSocketSessionReservation];
              return NO;
            }
          } else if ([webSocketMode isEqualToString:@"stream"]) {
            NSError *streamError = nil;
            // Subscribe before replaying (GitHub issue 240): the session's gate
            // holds live events until the 101 and the replay are sent, so none
            // is lost between the replay and the subscription, or sent ahead of
            // the handshake.
            webSocketSession = [[ALNWebSocketClientSession alloc] initWithClientFd:clientFd];
            [webSocketSession.streamGate
                startAfterSequence:[[self eventStreamAfterSequenceFromResponse:response] unsignedIntegerValue]];
            if (self.application.eventStreamBroker != nil) {
              streamSubscription = [self.application.eventStreamBroker
                  subscribeToStream:[self eventStreamIdentifierFromResponse:response]
                         subscriber:webSocketSession
                              error:&streamError];
              if (streamSubscription == nil) {
                ALNResponse *busyResponse = ALNErrorResponse(503, @"event stream live broker unavailable\n");
                [busyResponse setHeader:@"Retry-After" value:@"1"];
                [busyResponse setHeader:@"Connection" value:@"close"];
                ALNEnsurePerformanceHeaders(busyResponse,
                                            performanceHeaders,
                                            parseMs,
                                            ALNNowMilliseconds() - requestStartMs);
                (void)ALNSendResponse(clientFd, self.application, busyResponse, performanceHeaders, YES);
                [self releaseWebSocketSessionReservation];
                return NO;
              }
            }
            streamReplayResult = [self eventStreamReplayResultFromResponse:response error:&streamError];
            if (streamReplayResult == nil || streamReplayResult.resyncRequired) {
              if (streamSubscription != nil) {
                [self.application.eventStreamBroker unsubscribe:streamSubscription];
              }
              ALNResponse *failure =
                  (streamReplayResult != nil)
                      ? [self eventStreamResyncResponseForResponse:response replayResult:streamReplayResult]
                      : ALNErrorResponse((streamError.code == ALNEventStreamErrorUnauthorized) ? 403 : 500,
                                         @"event stream unavailable\n");
              [failure setHeader:@"Connection" value:@"close"];
              ALNEnsurePerformanceHeaders(failure,
                                          performanceHeaders,
                                          parseMs,
                                          ALNNowMilliseconds() - requestStartMs);
              (void)ALNSendResponse(clientFd, self.application, failure, performanceHeaders, YES);
              [self releaseWebSocketSessionReservation];
              return NO;
            }
          }

          @try {
            if ([self sendWebSocketHandshakeForRequest:request response:response clientFd:clientFd]) {
              if (webSocketSession == nil) {
                webSocketSession = [[ALNWebSocketClientSession alloc] initWithClientFd:clientFd];
              }
              if ([webSocketMode isEqualToString:@"stream"]) {
                for (ALNEventEnvelope *event in streamReplayResult.events ?: @[]) {
                  if (![webSocketSession.streamGate deliverReplayedEvent:event]) {
                    break;
                  }
                }
                // The read loop below blocks on the socket, so live events go
                // out from a sender thread.
                [NSThread detachNewThreadSelector:@selector(runWebSocketStreamSender:)
                                         toTarget:self
                                       withObject:webSocketSession];
              }
              [self runWebSocketSessionWithMode:webSocketMode
                                        channel:webSocketChannel
                                        session:webSocketSession
                                   subscription:channelSubscription
                              streamSubscription:streamSubscription
                                       clientFd:clientFd];
              // Marks the session closed even when the peer vanished without a
              // close frame, so a stream sender thread ends with it.
              [webSocketSession sendCloseFrame];
            } else {
              if (channelSubscription != nil) {
                [[ALNRealtimeHub sharedHub] unsubscribe:channelSubscription];
              }
              if (streamSubscription != nil && self.application.eventStreamBroker != nil) {
                [self.application.eventStreamBroker unsubscribe:streamSubscription];
              }
            }
          } @finally {
            [self releaseWebSocketSessionReservation];
          }
          return NO;
        }

        if ([sseMode isEqualToString:@"stream"]) {
          NSError *streamError = nil;
          // Subscribe before replaying (GitHub issue 240): the session's gate
          // holds live events until the replay is sent, so none committed in
          // between is lost; it then sends them in order, without repeats.
          ALNSSEClientSession *sseSession = [[ALNSSEClientSession alloc] initWithClientFd:clientFd];
          [sseSession.streamGate
              startAfterSequence:[[self eventStreamAfterSequenceFromResponse:response] unsignedIntegerValue]];
          ALNEventStreamBrokerSubscription *streamSubscription = nil;
          if (self.application.eventStreamBroker != nil) {
            streamSubscription = [self.application.eventStreamBroker
                subscribeToStream:[self eventStreamIdentifierFromResponse:response]
                       subscriber:sseSession
                            error:&streamError];
          }
          BOOL subscriptionHandedOff = NO;
          @try {
            ALNEventStreamReplayResult *streamReplayResult =
                (self.application.eventStreamBroker != nil && streamSubscription == nil)
                    ? nil
                    : [self eventStreamReplayResultFromResponse:response error:&streamError];
            if (streamReplayResult == nil) {
              ALNResponse *failure =
                  ALNErrorResponse((streamError.code == ALNEventStreamErrorUnauthorized) ? 403 : 500,
                                   @"event stream unavailable\n");
              [failure setHeader:@"Connection" value:@"close"];
              ALNEnsurePerformanceHeaders(failure,
                                          performanceHeaders,
                                          parseMs,
                                          ALNNowMilliseconds() - requestStartMs);
              (void)ALNSendResponse(clientFd, self.application, failure, performanceHeaders, YES);
              return NO;
            }
            if (streamReplayResult.resyncRequired) {
              ALNResponse *resyncResponse = [self eventStreamResyncResponseForResponse:response
                                                                           replayResult:streamReplayResult];
              [resyncResponse setHeader:@"Connection" value:@"close"];
              ALNEnsurePerformanceHeaders(resyncResponse,
                                          performanceHeaders,
                                          parseMs,
                                          ALNNowMilliseconds() - requestStartMs);
              (void)ALNSendResponse(clientFd, self.application, resyncResponse, performanceHeaders, YES);
              return NO;
            }

            BOOL reserved = [self reserveHTTPSessionWithLimit:self.maxConcurrentHTTPSessions];
            if (!reserved) {
              ALNResponse *busyResponse = ALNErrorResponse(503, @"server busy\n");
              [busyResponse setHeader:@"Retry-After" value:@"1"];
              [busyResponse setHeader:@"X-Arlen-Backpressure-Reason" value:@"http_session_limit"];
              [busyResponse setHeader:@"Connection" value:@"close"];
              ALNEnsurePerformanceHeaders(busyResponse,
                                          performanceHeaders,
                                          parseMs,
                                          ALNNowMilliseconds() - requestStartMs);
              (void)ALNSendResponse(clientFd, self.application, busyResponse, performanceHeaders, YES);
              return NO;
            }
            @try {
              if (!ALNSendSSEHeaders(clientFd, response)) {
                return NO;
              }
              for (ALNEventEnvelope *event in streamReplayResult.events ?: @[]) {
                if (![sseSession.streamGate deliverReplayedEvent:event]) {
                  return NO;
                }
              }
              if (![sseSession.streamGate drainQueued]) {
                return NO;
              }
              subscriptionHandedOff = YES;  // runSSEStreamSession unsubscribes
              [self runSSEStreamSession:sseSession subscription:streamSubscription];
            } @finally {
              [self releaseHTTPSessionReservation];
            }
          } @finally {
            if (!subscriptionHandedOff && streamSubscription != nil) {
              [self.application.eventStreamBroker unsubscribe:streamSubscription];
            }
          }
          return NO;
        }

        // Request dispatch mode does not force connection close; keep-alive follows HTTP semantics.
        BOOL keepAlive = ALNShouldKeepAliveForRequest(request, response);
        [response setHeader:@"Connection" value:(keepAlive ? @"keep-alive" : @"close")];
        ALNEnsurePerformanceHeaders(response,
                                    performanceHeaders,
                                    parseMs,
                                    ALNNowMilliseconds() - requestStartMs);
        request.responseWriteDurationMilliseconds =
            ALNSendResponse(clientFd, self.application,
                            response,
                            performanceHeaders,
                            ![request.method isEqualToString:@"HEAD"]);
        requestsHandled += 1;
        if (!keepAlive) {
          return NO;
        }
        if ([self parkIfIdleConnection:clientFd readState:&readState allowPark:allowPark]) {
          return YES;
        }
      }
    }
  } @finally {
    ALNConnectionReadStateDestroy(&readState);
  }
  return NO;
}

- (int)runWithHost:(NSString *)host
      portOverride:(NSInteger)portOverride
              once:(BOOL)once {
  atomic_store_explicit(&gSignalStopRequested, 0, memory_order_relaxed);
  self.shouldRun = YES;
  [self resetHTTPWorkerPoolState];

  NSDictionary *config = self.application.config ?: @{};
  [self invalidateStaticMountsCache];
  NSString *bindHost = ([host length] > 0) ? host : (config[@"host"] ?: @"127.0.0.1");
  NSInteger configPort = [config[@"port"] integerValue];
  int port = (portOverride > 0) ? (int)portOverride : (int)configPort;
  if (port <= 0) {
    port = 3000;
  }

  NSError *startupError = nil;
  if (![self.application startWithError:&startupError]) {
    ALNReportStartupFailure(self.serverName ?: @"server", [startupError localizedDescription]);
    return 1;
  }

  int exitCode = 0;
  @try {
    ALNServerSocketTuning tuning = ALNTuningFromConfig(config);
    ALNRuntimeLimits runtimeLimits = ALNRuntimeLimitsFromConfig(config);
    NSString *requestDispatchMode = ALNRequestDispatchModeFromConfig(config);
    self.requestParserBackend = ALNHTTPParserBackendFromConfig(config);
    self.webSocketAllowedOrigins = ALNWebSocketAllowedOriginsFromConfig(config);
    self.serializeRequestDispatch = [requestDispatchMode isEqualToString:@"serialized"];
    self.maxConcurrentHTTPSessions = runtimeLimits.maxConcurrentHTTPSessions;
    self.maxConcurrentWebSocketSessions = runtimeLimits.maxConcurrentWebSocketSessions;
    self.maxConcurrentHTTPWorkers = runtimeLimits.maxConcurrentHTTPWorkers;
    self.maxQueuedHTTPConnections = runtimeLimits.maxQueuedHTTPConnections;
    self.keepAliveParkAfterMilliseconds = runtimeLimits.keepAliveParkAfterMilliseconds;
    self.webSocketPingIntervalSeconds = runtimeLimits.webSocketPingIntervalSeconds;
    self.idleConnectionTimeoutSeconds = tuning.connectionTimeoutSeconds;
    [[ALNRealtimeHub sharedHub]
        configureLimitsWithMaxTotalSubscribers:runtimeLimits.maxRealtimeTotalSubscribers
                      maxSubscribersPerChannel:runtimeLimits.maxRealtimeChannelSubscribers];
    NSString *fanoutFailure = nil;
    id<ALNRealtimeFanout> fanout = ALNRealtimeFanoutFromConfig(config, &fanoutFailure);
    if ([fanoutFailure length] > 0) {
      fprintf(stderr, "%s: realtime fanout disabled: %s\n", [self.serverName UTF8String], [fanoutFailure UTF8String]);
    }
    if (fanout != nil) {
      [ALNRealtimeHub sharedHub].fanout = fanout;
    }

    if (!ALNInitializeSocketLayer()) {
      fprintf(stderr, "%s: Winsock startup failed\n", [self.serverName UTF8String]);
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"socket layer initialization failed"
                                   userInfo:nil];
    }

    if (!ALNInstallSignalHandler(SIGINT) || !ALNInstallSignalHandler(SIGTERM)) {
      fprintf(stderr, "%s: signal handler setup failed\n", [self.serverName UTF8String]);
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"signal handler setup failed"
                                   userInfo:nil];
    }

    ALNSocketHandle serverFd = ALNSocketOpen(AF_INET, SOCK_STREAM, 0);
    if (serverFd == ALNInvalidSocketHandle) {
      ALNReportSocketError("socket");
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"socket() failed"
                                   userInfo:nil];
    }
    self.serverSocketFD = serverFd;

    int reuse = 1;
#if defined(_WIN32)
    int reuseOption = SO_EXCLUSIVEADDRUSE;
#else
    int reuseOption = SO_REUSEADDR;
#endif
    if (ALNSocketSetIntOption(serverFd, SOL_SOCKET, reuseOption, reuse) < 0) {
      ALNReportSocketError("setsockopt(SO_REUSEADDR)");
      ALNSocketClose(serverFd);
      self.serverSocketFD = ALNInvalidSocketHandle;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"setsockopt(SO_REUSEADDR) failed"
                                   userInfo:nil];
    }

#ifdef SO_REUSEPORT
    if (tuning.enableReusePort) {
      if (ALNSocketSetIntOption(serverFd, SOL_SOCKET, SO_REUSEPORT, reuse) < 0) {
        ALNReportSocketError("setsockopt(SO_REUSEPORT)");
        ALNSocketClose(serverFd);
        self.serverSocketFD = ALNInvalidSocketHandle;
        exitCode = 1;
        @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                       reason:@"setsockopt(SO_REUSEPORT) failed"
                                     userInfo:nil];
      }
    }
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (ALNInetPton(AF_INET, [bindHost UTF8String], &addr.sin_addr) != 1) {
      fprintf(stderr, "%s: invalid host address: %s\n", [self.serverName UTF8String], [bindHost UTF8String]);
      ALNSocketClose(serverFd);
      self.serverSocketFD = ALNInvalidSocketHandle;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"invalid bind host"
                                   userInfo:nil];
    }

    if (ALNSocketBind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
      ALNReportSocketError("bind");
      ALNSocketClose(serverFd);
      self.serverSocketFD = ALNInvalidSocketHandle;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"bind() failed"
                                   userInfo:nil];
    }

    if (ALNSocketListen(serverFd, (int)tuning.listenBacklog) < 0) {
      ALNReportSocketError("listen");
      ALNSocketClose(serverFd);
      self.serverSocketFD = ALNInvalidSocketHandle;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"listen() failed"
                                   userInfo:nil];
    }

    fprintf(stdout, "%s listening on http://%s:%d\n", [self.serverName UTF8String], [bindHost UTF8String], port);
    fprintf(stdout, "%s http parser backend=%s llhttp=%s\n",
            [self.serverName UTF8String],
            [[ALNRequest parserBackendNameForBackend:self.requestParserBackend] UTF8String],
            [[ALNRequest llhttpVersion] UTF8String]);
    fflush(stdout);

    if (!once && !self.serializeRequestDispatch) {
      if (![self startHTTPWorkerPoolIfNeeded]) {
        exitCode = 1;
        @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                       reason:@"failed to start HTTP worker pool"
                                     userInfo:nil];
      }
    }

    while ([self shouldContinueRunning]) {
      ALNSocketHandle clientFd = ALNSocketAccept(serverFd);
      if (clientFd == ALNInvalidSocketHandle) {
        if (errno == EINTR) {
          if (![self shouldContinueRunning]) {
            break;
          }
          continue;
        }
        if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
          ALNPlatformSleepMilliseconds(50);
          continue;
        }
        ALNReportSocketError("accept");
        break;
      }

      BOOL reservedHTTPSession =
          [self reserveHTTPSessionWithLimit:self.maxConcurrentHTTPSessions];
      if (!reservedHTTPSession) {
        ALNResponse *busyResponse = ALNErrorResponse(503, @"server busy\n");
        [busyResponse setHeader:@"Retry-After" value:@"1"];
        [busyResponse setHeader:@"X-Arlen-Backpressure-Reason"
                          value:@"http_session_limit"];
        [busyResponse setHeader:@"Connection" value:@"close"];
        (void)ALNSendResponse(clientFd, self.application, busyResponse, NO, YES);
#if defined(_WIN32)
        ALNFinishRejectedClientOutput(clientFd);
#endif
        ALNSocketClose(clientFd);
        continue;
      }

      // In serialized mode, keep request handling on the accept thread and
      // avoid background queueing to maintain deterministic flow.
      BOOL runInBackground = (!once && !self.serializeRequestDispatch);
      if (runInBackground) {
        BOOL enqueued = [self enqueueHTTPClientForWorker:clientFd];
        if (!enqueued) {
          ALNResponse *busyResponse = ALNErrorResponse(503, @"server busy\n");
          [busyResponse setHeader:@"Retry-After" value:@"1"];
          [busyResponse setHeader:@"X-Arlen-Backpressure-Reason"
                            value:@"http_worker_queue_full"];
          [busyResponse setHeader:@"Connection" value:@"close"];
          (void)ALNSendResponse(clientFd, self.application, busyResponse, NO, YES);
          [self releaseHTTPSessionReservation];
#if defined(_WIN32)
          ALNFinishRejectedClientOutput(clientFd);
#endif
          ALNSocketClose(clientFd);
        }
      } else {
        @try {
          @autoreleasepool {
            [self handleClient:clientFd];
          }
        } @catch (NSException *exception) {
          [self.application.logger error:@"http connection exception"
                                   fields:@{ @"exception" : exception.description ?: @"" }];
        } @finally {
          [self releaseHTTPSessionReservation];
          ALNSocketClose(clientFd);
        }
      }

      if (once) {
        break;
      }
    }

    ALNSocketClose(serverFd);
    self.serverSocketFD = ALNInvalidSocketHandle;
  } @catch (NSException *exception) {
    if (![exception.name isEqualToString:@"ALNServerStartFailed"]) {
      fprintf(stderr, "%s: fatal exception: %s\n", [self.serverName UTF8String],
              [[exception reason] UTF8String]);
      exitCode = 1;
    }
  } @finally {
    if (self.serverSocketFD != ALNInvalidSocketHandle) {
      ALNSocketClose(self.serverSocketFD);
    }
    self.serverSocketFD = ALNInvalidSocketHandle;
    [self requestStop];
    [ALNRealtimeHub sharedHub].fanout = nil;
    [self.application shutdown];
  }

  return exitCode;
}

@end
