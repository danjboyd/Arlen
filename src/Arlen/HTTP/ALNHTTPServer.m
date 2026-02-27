#import "ALNHTTPServer.h"

#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <netinet/in.h>
#import <openssl/sha.h>
#import <signal.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import <strings.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/uio.h>
#import <sys/time.h>
#import <unistd.h>
#ifdef __linux__
#import <sys/sendfile.h>
#endif

#import "ALNApplication.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRealtime.h"

typedef struct {
  NSUInteger maxRequestLineBytes;
  NSUInteger maxHeaderBytes;
  NSUInteger maxBodyBytes;
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

static volatile sig_atomic_t gSignalStopRequested = 0;

static void *ALNReallocWithFaults(void *pointer, size_t size);

static void ALNHandleSignal(int sig) {
  (void)sig;
  gSignalStopRequested = 1;
}

static BOOL ALNSignalStopRequested(void) {
  return (gSignalStopRequested != 0);
}

static BOOL ALNInstallSignalHandler(int sig) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = ALNHandleSignal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;
  return (sigaction(sig, &action, NULL) == 0);
}

static BOOL ALNConfigBool(NSDictionary *config, NSString *key, BOOL defaultValue) {
  id value = config[key];
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return defaultValue;
}

static double ALNNowMilliseconds(void) {
  return [[NSDate date] timeIntervalSinceReferenceDate] * 1000.0;
}

static NSUInteger ALNConfigUInt(NSDictionary *dict, NSString *key, NSUInteger defaultValue) {
  id value = dict[key];
  if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
    NSUInteger parsed = [value unsignedIntegerValue];
    if (parsed > 0) {
      return parsed;
    }
  }
  return defaultValue;
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
  return out;
}

static ALNServerSocketTuning ALNTuningFromConfig(NSDictionary *config) {
  ALNServerSocketTuning out;
  out.listenBacklog = ALNConfigUInt(config, @"listenBacklog", 128);
  out.connectionTimeoutSeconds = ALNConfigUInt(config, @"connectionTimeoutSeconds", 30);
  out.enableReusePort = ALNConfigBool(config, @"enableReusePort", NO);
  return out;
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

static void ALNApplyClientSocketTimeout(int clientFd, NSUInteger timeoutSeconds) {
  if (timeoutSeconds == 0) {
    return;
  }

  struct timeval timeout;
  timeout.tv_sec = (time_t)timeoutSeconds;
  timeout.tv_usec = 0;

  (void)setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  (void)setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
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
        contentLength = parsedContentLength;
        break;
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

static BOOL ALNRequestIsWebSocketUpgrade(ALNRequest *request) {
  if (request == nil || ![request.method isEqualToString:@"GET"]) {
    return NO;
  }
  NSString *upgrade = [request headerValueForName:@"upgrade"];
  NSString *connection = [request headerValueForName:@"connection"];
  NSString *key = [request headerValueForName:@"sec-websocket-key"];
  if (!ALNHeaderContainsToken(upgrade, @"websocket")) {
    return NO;
  }
  if (!ALNHeaderContainsToken(connection, @"upgrade")) {
    return NO;
  }
  return [key isKindOfClass:[NSString class]] && [key length] > 0;
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
  if (![clientKey isKindOfClass:[NSString class]] || [clientKey length] == 0) {
    return @"";
  }
  NSString *combined = [clientKey stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
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
  usleep(1000);
}

static ssize_t ALNRecvWithFaults(int fd, void *buffer, size_t length, int flags) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_RECV_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  return recv(fd, buffer, length, flags);
}

static ssize_t ALNSendWithFaults(int fd, const void *bytes, size_t length, int flags) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SEND_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_SEND_SHORT_ONCE") && bytes != NULL && length > 0) {
    size_t partial = (length > 1) ? 1 : length;
    return send(fd, bytes, partial, flags);
  }
  return send(fd, bytes, length, flags);
}

static ssize_t ALNWritevWithFaults(int fd, const struct iovec *iov, int iovcnt) {
  if (ALNConsumeFaultOnce("ARLEN_FAULT_WRITEV_EINTR_ONCE")) {
    errno = EINTR;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_WRITEV_EAGAIN_ONCE")) {
    errno = EAGAIN;
    return -1;
  }
  if (ALNConsumeFaultOnce("ARLEN_FAULT_WRITEV_SHORT_ONCE") && iov != NULL && iovcnt > 0 &&
      iov[0].iov_base != NULL && iov[0].iov_len > 0) {
    size_t partial = (iov[0].iov_len > 1) ? 1 : iov[0].iov_len;
    return write(fd, iov[0].iov_base, partial);
  }
  return writev(fd, iov, iovcnt);
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
  return open(path, flags);
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
  return stat(path, statBuffer);
}

#ifdef __linux__
static ssize_t ALNSendfileWithFaults(int outFd, int inFd, off_t *offset, size_t count) {
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
  return sendfile(outFd, inFd, offset, count);
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

static BOOL ALNSendAll(int fd, const void *bytes, size_t length) {
  const unsigned char *cursor = (const unsigned char *)bytes;
  size_t remaining = length;
  int transientRetries = 0;
  while (remaining > 0) {
    ssize_t written = ALNSendWithFaults(fd, cursor, remaining, 0);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      if ((errno == EAGAIN || errno == EWOULDBLOCK) && transientRetries < 32) {
        transientRetries += 1;
        ALNTransientWriteBackoff();
        continue;
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
    transientRetries = 0;
    cursor += (size_t)written;
    remaining -= (size_t)written;
  }
  return YES;
}

static BOOL ALNWritevAll(int fd, const struct iovec *iov, int iovcnt) {
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
    ssize_t written = ALNWritevWithFaults(fd, &localIOV[current], iovcnt - current);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      if ((errno == EAGAIN || errno == EWOULDBLOCK) && transientRetries < 32) {
        transientRetries += 1;
        ALNTransientWriteBackoff();
        continue;
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
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
  const char *filesystemPath = [path fileSystemRepresentation];
  if (filesystemPath == NULL) {
    return -1;
  }

  int openFlags = O_RDONLY;
#ifdef O_CLOEXEC
  openFlags |= O_CLOEXEC;
#endif

  ALNEnsureStaticFileFDCache();
  if (gALNStaticFileFDCacheCapacity == 0) {
    return ALNOpenWithRetry(filesystemPath, openFlags);
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

  int duplicated = (entry.fileDescriptor >= 0) ? dup(entry.fileDescriptor) : -1;
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

static BOOL ALNSendFileReadFallback(int clientFd, int fileFd, unsigned long long remaining) {
  if (remaining == 0) {
    return YES;
  }

  unsigned char buffer[16384];
  while (remaining > 0) {
    size_t chunk = (remaining > (unsigned long long)sizeof(buffer))
                       ? sizeof(buffer)
                       : (size_t)remaining;
    ssize_t readBytes = read(fileFd, buffer, chunk);
    if (readBytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (readBytes == 0) {
      return NO;
    }
    if (!ALNSendAll(clientFd, buffer, (size_t)readBytes)) {
      return NO;
    }
    remaining -= (unsigned long long)readBytes;
  }
  return YES;
}

static BOOL ALNSendFileAtPath(int clientFd,
                              NSString *path,
                              unsigned long long byteLength,
                              unsigned long long device,
                              unsigned long long inode,
                              long long mtimeSeconds,
                              long mtimeNanoseconds) {
  if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
    return NO;
  }
  if (byteLength == 0) {
    return YES;
  }

  int fileFd = ALNStaticFileFDForPath(path, device, inode, byteLength, mtimeSeconds, mtimeNanoseconds);
  if (fileFd < 0) {
    return NO;
  }

  BOOL ok = NO;
  unsigned long long remaining = byteLength;
#ifdef __linux__
  off_t offset = 0;
  int transientRetries = 0;
  while (remaining > 0) {
    size_t chunk = (remaining > (unsigned long long)SSIZE_MAX)
                       ? (size_t)SSIZE_MAX
                       : (size_t)remaining;
    ssize_t sent = ALNSendfileWithFaults(clientFd, fileFd, &offset, chunk);
    if (sent < 0) {
      if (errno == EINTR) {
        continue;
      }
      if ((errno == EAGAIN || errno == EWOULDBLOCK) && transientRetries < 32) {
        transientRetries += 1;
        ALNTransientWriteBackoff();
        continue;
      }
      transientRetries = 0;
      if (errno == EINVAL || errno == ENOSYS) {
        if (lseek(fileFd, offset, SEEK_SET) < 0) {
          ok = NO;
          goto cleanup;
        }
        ok = ALNSendFileReadFallback(clientFd, fileFd, remaining);
        goto cleanup;
      }
      ok = NO;
      goto cleanup;
    }
    if (sent == 0) {
      break;
    }
    transientRetries = 0;
    remaining -= (unsigned long long)sent;
  }
  ok = (remaining == 0);
  if (!ok) {
    if (lseek(fileFd, offset, SEEK_SET) < 0) {
      goto cleanup;
    }
    ok = ALNSendFileReadFallback(clientFd, fileFd, remaining);
  }
#else
  ok = ALNSendFileReadFallback(clientFd, fileFd, remaining);
#endif

cleanup:
  close(fileFd);
  return ok;
}

static BOOL ALNRecvAll(int fd, void *buffer, size_t length) {
  unsigned char *cursor = (unsigned char *)buffer;
  size_t remaining = length;
  while (remaining > 0) {
    ssize_t readBytes = ALNRecvWithFaults(fd, cursor, remaining, 0);
    if (readBytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
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

static BOOL ALNWebSocketSendFrame(int fd, uint8_t opcode, NSData *payload) {
  NSData *frame = ALNWebSocketFrameData(opcode, payload ?: [NSData data]);
  return ALNSendAll(fd, [frame bytes], [frame length]);
}

static BOOL ALNWebSocketReadFrame(int fd,
                                  uint8_t *opcode,
                                  BOOL *fin,
                                  NSData **payload,
                                  NSUInteger maxPayloadBytes) {
  unsigned char header[2];
  if (!ALNRecvAll(fd, header, sizeof(header))) {
    return NO;
  }

  BOOL final = ((header[0] & 0x80) != 0);
  uint8_t frameOpcode = (uint8_t)(header[0] & 0x0F);
  BOOL masked = ((header[1] & 0x80) != 0);
  uint64_t payloadLength = (uint64_t)(header[1] & 0x7F);
  if (payloadLength == 126) {
    unsigned char ext[2];
    if (!ALNRecvAll(fd, ext, sizeof(ext))) {
      return NO;
    }
    payloadLength = ((uint64_t)ext[0] << 8) | (uint64_t)ext[1];
  } else if (payloadLength == 127) {
    unsigned char ext[8];
    if (!ALNRecvAll(fd, ext, sizeof(ext))) {
      return NO;
    }
    payloadLength = 0;
    for (NSUInteger idx = 0; idx < 8; idx++) {
      payloadLength = (payloadLength << 8) | (uint64_t)ext[idx];
    }
  }

  if (payloadLength > (uint64_t)maxPayloadBytes) {
    return NO;
  }

  unsigned char mask[4] = {0, 0, 0, 0};
  if (masked) {
    if (!ALNRecvAll(fd, mask, sizeof(mask))) {
      return NO;
    }
  }

  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)payloadLength];
  if (payloadLength > 0) {
    if (!ALNRecvAll(fd, [data mutableBytes], (size_t)payloadLength)) {
      return NO;
    }
    if (masked) {
      unsigned char *bytes = (unsigned char *)[data mutableBytes];
      for (uint64_t idx = 0; idx < payloadLength; idx++) {
        bytes[idx] ^= mask[idx % 4];
      }
    }
  }

  if (opcode != NULL) {
    *opcode = frameOpcode;
  }
  if (fin != NULL) {
    *fin = final;
  }
  if (payload != NULL) {
    *payload = data;
  }
  return YES;
}

static NSData *ALNReadHTTPRequestDataLegacy(int clientFd,
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
      } else {
        readState->scanOffset = readState->length;
      }
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

static ALNRequest *ALNReadHTTPRequestLLHTTP(int clientFd,
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

  while (1) {
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
    }

    if (request != nil) {
      NSUInteger parsedBodyBytes = [request.body length];
      NSUInteger parsedHeaderBytes = 0;
      if (consumedLength >= parsedBodyBytes) {
        parsedHeaderBytes = consumedLength - parsedBodyBytes;
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
      ALNConnectionReadStateConsumePrefix(readState, consumedLength);
      return request;
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

static ALNRequest *ALNReadHTTPRequest(int clientFd,
                                      ALNRequestLimits limits,
                                      ALNHTTPParserBackend backend,
                                      NSInteger *statusCode,
                                      ALNConnectionReadState *readState) {
  if (backend == ALNHTTPParserBackendLLHTTP && [ALNRequest isLLHTTPAvailable]) {
    return ALNReadHTTPRequestLLHTTP(clientFd, limits, statusCode, readState);
  }

  NSInteger readStatus = 0;
  NSData *rawRequest = ALNReadHTTPRequestDataLegacy(clientFd, limits, &readStatus, readState);
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

static NSString *ALNRemoteAddressForClient(int clientFd) {
  struct sockaddr_in peer;
  socklen_t peerLen = sizeof(peer);
  memset(&peer, 0, sizeof(peer));
  if (getpeername(clientFd, (struct sockaddr *)&peer, &peerLen) != 0) {
    return @"";
  }

  char addressBuffer[INET_ADDRSTRLEN];
  const char *ok = inet_ntop(AF_INET, &peer.sin_addr, addressBuffer, sizeof(addressBuffer));
  if (ok == NULL) {
    return @"";
  }
  return [NSString stringWithUTF8String:addressBuffer] ?: @"";
}

static NSString *ALNTrimmedString(NSString *value) {
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *ALNFirstForwardedFor(NSString *value) {
  if ([value length] == 0) {
    return @"";
  }
  NSArray *parts = [value componentsSeparatedByString:@","];
  if ([parts count] == 0) {
    return @"";
  }
  return ALNTrimmedString(parts[0]);
}

static void ALNApplyProxyMetadata(ALNRequest *request, NSDictionary *config) {
  request.effectiveRemoteAddress = request.remoteAddress ?: @"";
  request.scheme = @"http";

  BOOL trustedProxy = ALNConfigBool(config, @"trustedProxy", NO);
  if (!trustedProxy) {
    return;
  }

  NSString *forwardedFor = [request headerValueForName:@"x-forwarded-for"];
  NSString *forwardedProto = [request headerValueForName:@"x-forwarded-proto"];

  NSString *effectiveAddress = ALNFirstForwardedFor(forwardedFor);
  if ([effectiveAddress length] > 0) {
    request.effectiveRemoteAddress = effectiveAddress;
  }

  NSString *proto = [[ALNTrimmedString(forwardedProto) lowercaseString] copy];
  if ([proto isEqualToString:@"http"] || [proto isEqualToString:@"https"]) {
    request.scheme = proto;
  }
}

static NSString *ALNContentTypeForFilePath(NSString *filePath) {
  NSString *extension = [[filePath pathExtension] lowercaseString];
  if ([extension isEqualToString:@"html"] || [extension isEqualToString:@"htm"]) {
    return @"text/html; charset=utf-8";
  }
  if ([extension isEqualToString:@"css"]) {
    return @"text/css; charset=utf-8";
  }
  if ([extension isEqualToString:@"js"]) {
    return @"application/javascript; charset=utf-8";
  }
  if ([extension isEqualToString:@"json"]) {
    return @"application/json; charset=utf-8";
  }
  if ([extension isEqualToString:@"txt"]) {
    return @"text/plain; charset=utf-8";
  }
  if ([extension isEqualToString:@"svg"]) {
    return @"image/svg+xml";
  }
  if ([extension isEqualToString:@"png"]) {
    return @"image/png";
  }
  if ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"]) {
    return @"image/jpeg";
  }
  return @"application/octet-stream";
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

  if ([trimmed hasPrefix:@"/"]) {
    return [trimmed stringByStandardizingPath];
  }
  NSString *base = [[publicRoot stringByDeletingLastPathComponent] stringByStandardizingPath];
  return [[base stringByAppendingPathComponent:trimmed] stringByStandardizingPath];
}

static BOOL ALNStaticCandidateWithinRoot(NSString *candidate, NSString *root) {
  if ([candidate length] == 0 || [root length] == 0) {
    return NO;
  }
  return [candidate isEqualToString:root] ||
         [candidate hasPrefix:[root stringByAppendingString:@"/"]];
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
                                              NSString *publicRoot) {
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

  if ([relativePath containsString:@".."] ||
      [relativePath hasPrefix:@"/"]) {
    return ALNStaticNotFoundResponse();
  }

  NSString *standardRoot = ALNResolvedStaticDirectory(directory, publicRoot);
  if ([standardRoot length] == 0) {
    return ALNStaticNotFoundResponse();
  }

  NSString *candidatePath = ([relativePath length] > 0)
                                ? [standardRoot stringByAppendingPathComponent:relativePath]
                                : standardRoot;
  NSString *standardCandidate = [candidatePath stringByStandardizingPath];

  if (!ALNStaticCandidateWithinRoot(standardCandidate, standardRoot)) {
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

  if (![resolvedFilePath length] || !ALNStaticExtensionAllowed(resolvedFilePath, allowExtensions)) {
    return ALNStaticNotFoundResponse();
  }

  struct stat fileStat;
  const char *resolvedFilesystemPath = [resolvedFilePath fileSystemRepresentation];
  if (resolvedFilesystemPath == NULL ||
      ALNStatWithRetry(resolvedFilesystemPath, &fileStat) != 0 ||
      !S_ISREG(fileStat.st_mode)) {
    ALNResponse *response = [[ALNResponse alloc] init];
    response.statusCode = 500;
    [response setTextBody:@"failed to read static asset\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    return response;
  }

  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = 200;
  [response setHeader:@"Content-Type" value:ALNContentTypeForFilePath(resolvedFilePath)];
  if (![request.method isEqualToString:@"HEAD"]) {
    response.fileBodyPath = resolvedFilePath;
    response.fileBodyLength = (unsigned long long)fileStat.st_size;
    response.fileBodyDevice = (unsigned long long)fileStat.st_dev;
    response.fileBodyInode = (unsigned long long)fileStat.st_ino;
    response.fileBodyMTimeSeconds = (long long)fileStat.st_mtime;
    response.fileBodyMTimeNanoseconds = ALNStaticFileMTimeNanoseconds(&fileStat);
  }
  response.committed = YES;
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

static void ALNSendFallbackInternalServerError(int clientFd) {
  static const char *response =
      "HTTP/1.1 500 Internal Server Error\r\n"
      "Content-Type: text/plain; charset=utf-8\r\n"
      "Content-Length: 22\r\n"
      "Connection: close\r\n"
      "\r\n"
      "internal server error\n";
  (void)ALNSendAll(clientFd, response, strlen(response));
}

static double ALNSendResponse(int clientFd, ALNResponse *response, BOOL performanceLogging) {
  double serializeStart = ALNNowMilliseconds();
  NSData *headerData = [response serializedHeaderData];
  double serializeMs = ALNNowMilliseconds() - serializeStart;

  if (headerData == nil || [headerData length] == 0) {
    double writeStart = ALNNowMilliseconds();
    ALNSendFallbackInternalServerError(clientFd);
    return (ALNNowMilliseconds() - writeStart) + serializeMs;
  }

  if (performanceLogging) {
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
  NSData *bodyData = response.bodyData ?: [NSData data];
  NSUInteger bodyLength = [bodyData length];
  NSString *fileBodyPath = response.fileBodyPath;
  unsigned long long fileBodyLength = response.fileBodyLength;
  unsigned long long fileBodyDevice = response.fileBodyDevice;
  unsigned long long fileBodyInode = response.fileBodyInode;
  long long fileBodyMTimeSeconds = response.fileBodyMTimeSeconds;
  long fileBodyMTimeNanoseconds = response.fileBodyMTimeNanoseconds;

  if ([fileBodyPath length] > 0 && fileBodyLength > 0) {
    if (headerLength > 0) {
      (void)ALNSendAll(clientFd, [headerData bytes], headerLength);
    }
    (void)ALNSendFileAtPath(clientFd,
                            fileBodyPath,
                            fileBodyLength,
                            fileBodyDevice,
                            fileBodyInode,
                            fileBodyMTimeSeconds,
                            fileBodyMTimeNanoseconds);
  } else if (headerLength > 0 && bodyLength > 0) {
    struct iovec iov[2];
    iov[0].iov_base = (void *)[headerData bytes];
    iov[0].iov_len = headerLength;
    iov[1].iov_base = (void *)[bodyData bytes];
    iov[1].iov_len = bodyLength;
    if (!ALNWritevAll(clientFd, iov, 2)) {
      (void)ALNSendAll(clientFd, [headerData bytes], headerLength);
      (void)ALNSendAll(clientFd, [bodyData bytes], bodyLength);
    }
  } else {
    if (headerLength > 0) {
      (void)ALNSendAll(clientFd, [headerData bytes], headerLength);
    }
    if (bodyLength > 0) {
      (void)ALNSendAll(clientFd, [bodyData bytes], bodyLength);
    }
  }
  return (ALNNowMilliseconds() - writeStart) + serializeMs;
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

@interface ALNWebSocketClientSession : NSObject <ALNRealtimeSubscriber>

@property(nonatomic, assign, readonly) int clientFd;
@property(nonatomic, strong, readonly) NSLock *sendLock;
@property(nonatomic, assign) BOOL closed;

- (instancetype)initWithClientFd:(int)clientFd;
- (BOOL)sendTextMessage:(NSString *)message;
- (BOOL)sendBinaryPayload:(NSData *)payload opcode:(uint8_t)opcode;
- (void)sendCloseFrame;
- (BOOL)isClosedSnapshot;

@end

@implementation ALNWebSocketClientSession

- (instancetype)initWithClientFd:(int)clientFd {
  self = [super init];
  if (self) {
    _clientFd = clientFd;
    _sendLock = [[NSLock alloc] init];
    _closed = NO;
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
  [self.sendLock lock];
  if (!self.closed) {
    (void)ALNWebSocketSendFrame(self.clientFd, 0x8, [NSData data]);
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
  (void)[self sendTextMessage:message ?: @""];
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
@property(atomic, assign) int serverSocketFD;
@property(nonatomic, strong) NSLock *staticMountCacheLock;
@property(nonatomic, copy) NSArray *cachedStaticMounts;

@end

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
    _serverSocketFD = -1;
    _staticMountCacheLock = [[NSLock alloc] init];
    _cachedStaticMounts = nil;
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
    }];
  }

  BOOL serveStatic = ALNConfigBool(self.application.config ?: @{}, @"serveStatic", NO);
  if (serveStatic && ![seenPrefixes containsObject:@"/static"]) {
    NSArray *configuredAllowlist =
        ALNNormalizedStaticAllowExtensions(self.application.config[@"staticAllowExtensions"]);
    NSArray *allowExtensions =
        ([configuredAllowlist count] > 0) ? configuredAllowlist : ALNDefaultStaticAllowExtensions();
    [mounts addObject:@{
      @"prefix" : @"/static",
      @"directory" : @"public",
      @"allowExtensions" : allowExtensions,
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
    fprintf(out, "%s %s -> %s#%s (%s)\n", [route[@"method"] UTF8String], [route[@"path"] UTF8String],
            [route[@"controller"] UTF8String], [route[@"action"] UTF8String],
            [route[@"name"] UTF8String]);
  }
}

- (void)requestStop {
  self.shouldRun = NO;
  int serverFd = self.serverSocketFD;
  if (serverFd >= 0) {
    (void)shutdown(serverFd, SHUT_RDWR);
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

- (BOOL)enqueueHTTPClientForWorker:(int)clientFd {
  [self.httpWorkerQueueCondition lock];
  BOOL accepted = ([self queuedHTTPClientCountLocked] < self.maxQueuedHTTPConnections);
  if (accepted) {
    [self.pendingHTTPClientFDs addObject:@(clientFd)];
    [self.httpWorkerQueueCondition signal];
  }
  [self.httpWorkerQueueCondition unlock];
  return accepted;
}

- (int)dequeueHTTPClientForWorker {
  [self.httpWorkerQueueCondition lock];
  while ([self queuedHTTPClientCountLocked] == 0 && [self shouldContinueRunning]) {
    [self.httpWorkerQueueCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
  }

  int clientFd = -1;
  NSUInteger queuedCount = [self queuedHTTPClientCountLocked];
  if (queuedCount > 0) {
    NSNumber *next = self.pendingHTTPClientFDs[self.pendingHTTPClientFDHeadIndex];
    self.pendingHTTPClientFDHeadIndex += 1;
    clientFd = [next intValue];

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
      int clientFd = [self dequeueHTTPClientForWorker];
      if (clientFd < 0) {
        continue;
      }

      @autoreleasepool {
        @try {
          [self handleClient:clientFd];
        } @finally {
          [self releaseHTTPSessionReservation];
          close(clientFd);
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
  return YES;
}

- (void)resetHTTPWorkerPoolState {
  [self.httpWorkerQueueCondition lock];
  [self.pendingHTTPClientFDs removeAllObjects];
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
  if ([mode isEqualToString:@"echo"] || [mode isEqualToString:@"channel"]) {
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

- (BOOL)sendWebSocketHandshakeForRequest:(ALNRequest *)request
                                response:(ALNResponse *)response
                                clientFd:(int)clientFd {
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
                           clientFd:(int)clientFd {
  if ([mode length] == 0 || session == nil) {
    return;
  }

  @try {
    while ([self shouldContinueRunning] && ![session isClosedSnapshot]) {
      uint8_t opcode = 0;
      BOOL fin = NO;
      NSData *payload = nil;
      if (!ALNWebSocketReadFrame(clientFd, &opcode, &fin, &payload, 1048576)) {
        break;
      }
      if (!fin) {
        break;
      }

      if (opcode == 0x8) {
        [session sendCloseFrame];
        break;
      }
      if (opcode == 0x9) {
        (void)[session sendBinaryPayload:payload ?: [NSData data] opcode:0xA];
        continue;
      }
      if (opcode == 0xA) {
        continue;
      }
      if (opcode != 0x1) {
        continue;
      }

      NSString *message = [[NSString alloc] initWithData:(payload ?: [NSData data])
                                                encoding:NSUTF8StringEncoding];
      if (message == nil) {
        message = @"";
      }

      if ([mode isEqualToString:@"channel"]) {
        (void)[[ALNRealtimeHub sharedHub] publishMessage:message onChannel:channel];
      } else {
        (void)[session sendTextMessage:message];
      }
    }
  } @finally {
    if (subscription != nil) {
      [[ALNRealtimeHub sharedHub] unsubscribe:subscription];
    }
  }
}

- (void)handleClient:(int)clientFd {
  BOOL performanceLogging =
      ALNConfigBool(self.application.config ?: @{}, @"performanceLogging", YES);
  ALNRequestLimits limits = ALNLimitsFromConfig(self.application.config ?: @{});
  ALNServerSocketTuning tuning = ALNTuningFromConfig(self.application.config ?: @{});
  ALNApplyClientSocketTimeout(clientFd, tuning.connectionTimeoutSeconds);
  NSString *connectionRemoteAddress = ALNRemoteAddressForClient(clientFd) ?: @"";
  ALNConnectionReadState readState;
  ALNConnectionReadStateInit(&readState);

  @try {
    NSUInteger requestsHandled = 0;
    while ([self shouldContinueRunning]) {
      @autoreleasepool {
        double requestStartMs = ALNNowMilliseconds();

        NSInteger readStatus = 0;
        double parseStartMs = ALNNowMilliseconds();
        ALNRequest *request = ALNReadHTTPRequest(clientFd,
                                                 limits,
                                                 self.requestParserBackend,
                                                 &readStatus,
                                                 &readState);
        double parseMs = ALNNowMilliseconds() - parseStartMs;
        if (request == nil) {
          if (readStatus == 0) {
            return;
          }
          if (requestsHandled > 0 && readStatus == 408) {
            return;
          }

          ALNResponse *errorResponse = nil;
          if (readStatus == 413) {
            errorResponse = ALNErrorResponse(413, @"payload too large\n");
          } else if (readStatus == 431) {
            errorResponse = ALNErrorResponse(431, @"request headers too large\n");
          } else if (readStatus == 408) {
            errorResponse = ALNErrorResponse(408, @"request timeout\n");
          } else {
            errorResponse = ALNErrorResponse(400, @"bad request\n");
          }
          [errorResponse setHeader:@"Connection" value:@"close"];
          ALNEnsurePerformanceHeaders(errorResponse,
                                      performanceLogging,
                                      parseMs,
                                      ALNNowMilliseconds() - requestStartMs);
          (void)ALNSendResponse(clientFd, errorResponse, performanceLogging);
          return;
        }
        request.parseDurationMilliseconds = parseMs;

        request.remoteAddress = connectionRemoteAddress;
        request.effectiveRemoteAddress = request.remoteAddress ?: @"";
        request.scheme = @"http";
        ALNApplyProxyMetadata(request, self.application.config ?: @{});

        BOOL supportsStaticMethod = [request.method isEqualToString:@"GET"] ||
                                    [request.method isEqualToString:@"HEAD"];
        BOOL handledStatic = NO;
        if (supportsStaticMethod) {
          NSArray *staticMounts = [self effectiveStaticMounts];
          for (NSDictionary *mount in staticMounts) {
            ALNResponse *staticResponse = ALNStaticResponseForMount(request, mount, self.publicRoot);
            if (staticResponse == nil) {
              continue;
            }
            // Request dispatch mode does not force connection close; keep-alive follows HTTP semantics.
            BOOL keepAlive = ALNShouldKeepAliveForRequest(request, staticResponse);
            [staticResponse setHeader:@"Connection" value:(keepAlive ? @"keep-alive" : @"close")];
            ALNEnsurePerformanceHeaders(staticResponse,
                                        performanceLogging,
                                        parseMs,
                                        ALNNowMilliseconds() - requestStartMs);
            request.responseWriteDurationMilliseconds =
                ALNSendResponse(clientFd, staticResponse, performanceLogging);
            requestsHandled += 1;
            if (!keepAlive) {
              return;
            }
            handledStatic = YES;
            break;
          }
        }
        if (handledStatic) {
          continue;
        }

        ALNResponse *response = nil;
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

        NSString *webSocketMode = [self webSocketModeFromResponse:response];
        BOOL webSocketUpgrade = ALNRequestIsWebSocketUpgrade(request) &&
                                response.statusCode == 101 &&
                                [webSocketMode length] > 0;
        if (webSocketUpgrade) {
          ALNWebSocketClientSession *webSocketSession = nil;
          ALNRealtimeSubscription *channelSubscription = nil;
          NSString *webSocketChannel = @"";

          BOOL reserved =
              [self reserveWebSocketSessionWithLimit:self.maxConcurrentWebSocketSessions];
          if (!reserved) {
            ALNResponse *busyResponse = ALNErrorResponse(503, @"server busy\n");
            [busyResponse setHeader:@"Retry-After" value:@"1"];
            [busyResponse setHeader:@"X-Arlen-Backpressure-Reason"
                              value:@"websocket_session_limit"];
            [busyResponse setHeader:@"Connection" value:@"close"];
            ALNEnsurePerformanceHeaders(busyResponse,
                                        performanceLogging,
                                        parseMs,
                                        ALNNowMilliseconds() - requestStartMs);
            (void)ALNSendResponse(clientFd, busyResponse, performanceLogging);
            return;
          }

          if ([webSocketMode isEqualToString:@"channel"]) {
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
                                          performanceLogging,
                                          parseMs,
                                          ALNNowMilliseconds() - requestStartMs);
              (void)ALNSendResponse(clientFd, busyResponse, performanceLogging);
              [self releaseWebSocketSessionReservation];
              return;
            }
          }

          @try {
            if ([self sendWebSocketHandshakeForRequest:request response:response clientFd:clientFd]) {
              if (webSocketSession == nil) {
                webSocketSession = [[ALNWebSocketClientSession alloc] initWithClientFd:clientFd];
              }
              [self runWebSocketSessionWithMode:webSocketMode
                                        channel:webSocketChannel
                                        session:webSocketSession
                                   subscription:channelSubscription
                                       clientFd:clientFd];
            } else if (channelSubscription != nil) {
              [[ALNRealtimeHub sharedHub] unsubscribe:channelSubscription];
            }
          } @finally {
            [self releaseWebSocketSessionReservation];
          }
          return;
        }

        // Request dispatch mode does not force connection close; keep-alive follows HTTP semantics.
        BOOL keepAlive = ALNShouldKeepAliveForRequest(request, response);
        [response setHeader:@"Connection" value:(keepAlive ? @"keep-alive" : @"close")];
        ALNEnsurePerformanceHeaders(response,
                                    performanceLogging,
                                    parseMs,
                                    ALNNowMilliseconds() - requestStartMs);
        request.responseWriteDurationMilliseconds =
            ALNSendResponse(clientFd, response, performanceLogging);
        requestsHandled += 1;
        if (!keepAlive) {
          return;
        }
      }
    }
  } @finally {
    ALNConnectionReadStateDestroy(&readState);
  }
}

- (int)runWithHost:(NSString *)host
      portOverride:(NSInteger)portOverride
              once:(BOOL)once {
  gSignalStopRequested = 0;
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
    fprintf(stderr, "%s: startup failed: %s\n", [self.serverName UTF8String],
            [[startupError localizedDescription] UTF8String]);
    return 1;
  }

  int exitCode = 0;
  @try {
    ALNServerSocketTuning tuning = ALNTuningFromConfig(config);
    ALNRuntimeLimits runtimeLimits = ALNRuntimeLimitsFromConfig(config);
    NSString *requestDispatchMode = ALNRequestDispatchModeFromConfig(config);
    self.requestParserBackend = ALNHTTPParserBackendFromConfig(config);
    self.serializeRequestDispatch = [requestDispatchMode isEqualToString:@"serialized"];
    self.maxConcurrentHTTPSessions = runtimeLimits.maxConcurrentHTTPSessions;
    self.maxConcurrentWebSocketSessions = runtimeLimits.maxConcurrentWebSocketSessions;
    self.maxConcurrentHTTPWorkers = runtimeLimits.maxConcurrentHTTPWorkers;
    self.maxQueuedHTTPConnections = runtimeLimits.maxQueuedHTTPConnections;
    [[ALNRealtimeHub sharedHub]
        configureLimitsWithMaxTotalSubscribers:runtimeLimits.maxRealtimeTotalSubscribers
                      maxSubscribersPerChannel:runtimeLimits.maxRealtimeChannelSubscribers];

    if (!ALNInstallSignalHandler(SIGINT) || !ALNInstallSignalHandler(SIGTERM)) {
      perror("sigaction");
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"signal handler setup failed"
                                   userInfo:nil];
    }

    int serverFd = socket(AF_INET, SOCK_STREAM, 0);
    if (serverFd < 0) {
      perror("socket");
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"socket() failed"
                                   userInfo:nil];
    }
    self.serverSocketFD = serverFd;

    int reuse = 1;
    if (setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
      perror("setsockopt");
      close(serverFd);
      self.serverSocketFD = -1;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"setsockopt(SO_REUSEADDR) failed"
                                   userInfo:nil];
    }

#ifdef SO_REUSEPORT
    if (tuning.enableReusePort) {
      if (setsockopt(serverFd, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse)) < 0) {
        perror("setsockopt(SO_REUSEPORT)");
        close(serverFd);
        self.serverSocketFD = -1;
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
    if (inet_pton(AF_INET, [bindHost UTF8String], &addr.sin_addr) != 1) {
      fprintf(stderr, "%s: invalid host address: %s\n", [self.serverName UTF8String], [bindHost UTF8String]);
      close(serverFd);
      self.serverSocketFD = -1;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"invalid bind host"
                                   userInfo:nil];
    }

    if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
      perror("bind");
      close(serverFd);
      self.serverSocketFD = -1;
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"bind() failed"
                                   userInfo:nil];
    }

    if (listen(serverFd, (int)tuning.listenBacklog) < 0) {
      perror("listen");
      close(serverFd);
      self.serverSocketFD = -1;
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
      int clientFd = accept(serverFd, NULL, NULL);
      if (clientFd < 0) {
        if (errno == EINTR) {
          if (![self shouldContinueRunning]) {
            break;
          }
          continue;
        }
        if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) {
          usleep(50000);
          continue;
        }
        perror("accept");
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
        (void)ALNSendResponse(clientFd, busyResponse, NO);
        close(clientFd);
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
          (void)ALNSendResponse(clientFd, busyResponse, NO);
          [self releaseHTTPSessionReservation];
          close(clientFd);
        }
      } else {
        @try {
          @autoreleasepool {
            [self handleClient:clientFd];
          }
        } @finally {
          [self releaseHTTPSessionReservation];
          close(clientFd);
        }
      }

      if (once) {
        break;
      }
    }

    close(serverFd);
    self.serverSocketFD = -1;
  } @catch (NSException *exception) {
    if (![exception.name isEqualToString:@"ALNServerStartFailed"]) {
      fprintf(stderr, "%s: fatal exception: %s\n", [self.serverName UTF8String],
              [[exception reason] UTF8String]);
      exitCode = 1;
    }
  } @finally {
    self.serverSocketFD = -1;
    [self requestStop];
    [self.application shutdown];
  }

  return exitCode;
}

@end
