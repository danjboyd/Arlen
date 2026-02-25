#import "ALNHTTPServer.h"

#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <openssl/sha.h>
#import <signal.h>
#import <stdio.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <unistd.h>

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
} ALNRuntimeLimits;

static volatile sig_atomic_t gShouldRun = 1;

static void ALNHandleSignal(int sig) {
  (void)sig;
  gShouldRun = 0;
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

static NSInteger ALNParseContentLength(NSString *headerText) {
  NSArray *lines = [headerText componentsSeparatedByString:@"\r\n"];
  for (NSUInteger idx = 1; idx < [lines count]; idx++) {
    NSString *line = lines[idx];
    NSRange colon = [line rangeOfString:@":"];
    if (colon.location == NSNotFound) {
      continue;
    }

    NSString *name = [[[line substringToIndex:colon.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if (![name isEqualToString:@"content-length"]) {
      continue;
    }

    NSString *value = [[line substringFromIndex:colon.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([value length] == 0) {
      return -1;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([value rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
      return -1;
    }
    long long parsed = [value longLongValue];
    if (parsed < 0) {
      return -1;
    }
    return (NSInteger)parsed;
  }
  return 0;
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
  NSString *upgrade = request.headers[@"upgrade"];
  NSString *connection = request.headers[@"connection"];
  NSString *key = request.headers[@"sec-websocket-key"];
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

  NSString *requestConnection = [request.headers[@"connection"] lowercaseString];
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

static BOOL ALNSendAll(int fd, const void *bytes, size_t length) {
  const unsigned char *cursor = (const unsigned char *)bytes;
  size_t remaining = length;
  while (remaining > 0) {
    ssize_t written = send(fd, cursor, remaining, 0);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
    cursor += (size_t)written;
    remaining -= (size_t)written;
  }
  return YES;
}

static BOOL ALNRecvAll(int fd, void *buffer, size_t length) {
  unsigned char *cursor = (unsigned char *)buffer;
  size_t remaining = length;
  while (remaining > 0) {
    ssize_t readBytes = recv(fd, cursor, remaining, 0);
    if (readBytes < 0) {
      if (errno == EINTR) {
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

static NSData *ALNReadHTTPRequestData(int clientFd, ALNRequestLimits limits, NSInteger *statusCode) {
  if (statusCode != NULL) {
    *statusCode = 0;
  }

  NSMutableData *buffer = [NSMutableData data];
  NSData *headerSeparator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger headerBytes = 0;
  NSUInteger expectedTotalBytes = NSNotFound;

  while (gShouldRun) {
    char chunk[8192];
    ssize_t readBytes = recv(clientFd, chunk, sizeof(chunk), 0);
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
      if ([buffer length] == 0) {
        if (statusCode != NULL) {
          *statusCode = 0;
        }
        return nil;
      }
      break;
    }

    [buffer appendBytes:chunk length:(NSUInteger)readBytes];

    if (headerBytes == 0) {
      if ([buffer length] > limits.maxHeaderBytes) {
        if (statusCode != NULL) {
          *statusCode = 431;
        }
        return nil;
      }

      NSRange separatorRange =
          [buffer rangeOfData:headerSeparator options:0 range:NSMakeRange(0, [buffer length])];
      if (separatorRange.location == NSNotFound) {
        continue;
      }

      headerBytes = separatorRange.location + separatorRange.length;
      if (headerBytes > limits.maxHeaderBytes) {
        if (statusCode != NULL) {
          *statusCode = 431;
        }
        return nil;
      }

      NSData *headerData = [buffer subdataWithRange:NSMakeRange(0, separatorRange.location)];
      NSString *headerText = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
      if (headerText == nil) {
        if (statusCode != NULL) {
          *statusCode = 400;
        }
        return nil;
      }

      NSRange requestLineEnd = [headerText rangeOfString:@"\r\n"];
      NSUInteger requestLineBytes =
          (requestLineEnd.location == NSNotFound) ? [headerData length] : requestLineEnd.location;
      if (requestLineBytes > limits.maxRequestLineBytes) {
        if (statusCode != NULL) {
          *statusCode = 431;
        }
        return nil;
      }

      NSInteger contentLength = ALNParseContentLength(headerText);
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

      expectedTotalBytes = headerBytes + (NSUInteger)contentLength;
      if (expectedTotalBytes < headerBytes) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }
    }

    if (headerBytes > 0) {
      NSUInteger bodyBytesRead = ([buffer length] >= headerBytes) ? ([buffer length] - headerBytes) : 0;
      if (bodyBytesRead > limits.maxBodyBytes) {
        if (statusCode != NULL) {
          *statusCode = 413;
        }
        return nil;
      }

      if (expectedTotalBytes != NSNotFound && [buffer length] >= expectedTotalBytes) {
        if ([buffer length] == expectedTotalBytes) {
          return buffer;
        }
        return [buffer subdataWithRange:NSMakeRange(0, expectedTotalBytes)];
      }
    }
  }

  if (statusCode != NULL) {
    *statusCode = 400;
  }
  return nil;
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

  NSString *forwardedFor = request.headers[@"x-forwarded-for"];
  NSString *forwardedProto = request.headers[@"x-forwarded-proto"];

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

  NSData *fileData = [NSData dataWithContentsOfFile:resolvedFilePath];
  if (fileData == nil) {
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
    [response appendData:fileData];
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

static double ALNSendResponse(int clientFd, ALNResponse *response, BOOL performanceLogging) {
  double serializeStart = ALNNowMilliseconds();
  NSData *raw = [response serializedData];
  double serializeMs = ALNNowMilliseconds() - serializeStart;

  if (performanceLogging) {
    [response setHeader:@"X-Arlen-Response-Write-Ms"
                  value:[NSString stringWithFormat:@"%.3f", serializeMs]];
    double currentTotal = ALNParseHeaderDoubleValue([response headerForName:@"X-Arlen-Total-Ms"]);
    NSString *total = [NSString stringWithFormat:@"%.3f", (currentTotal + serializeMs)];
    [response setHeader:@"X-Arlen-Total-Ms" value:total];
    [response setHeader:@"X-Mojo-Total-Ms" value:total];
    raw = [response serializedData];
  }

  double writeStart = ALNNowMilliseconds();
  (void)ALNSendAll(clientFd, [raw bytes], [raw length]);
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

@interface ALNWebSocketClientSession : NSObject <ALNRealtimeSubscriber>

@property(nonatomic, assign, readonly) int clientFd;
@property(nonatomic, strong, readonly) NSLock *sendLock;
@property(nonatomic, assign) BOOL closed;

- (instancetype)initWithClientFd:(int)clientFd;
- (BOOL)sendTextMessage:(NSString *)message;
- (BOOL)sendBinaryPayload:(NSData *)payload opcode:(uint8_t)opcode;
- (void)sendCloseFrame;

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
@property(nonatomic, strong) NSLock *requestDispatchLock;
@property(nonatomic, assign) BOOL serializeRequestDispatch;

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
    _requestDispatchLock = [[NSLock alloc] init];
    _serializeRequestDispatch = NO;
  }
  return self;
}

- (NSArray *)effectiveStaticMounts {
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
  gShouldRun = 0;
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
  NSString *clientKey = request.headers[@"sec-websocket-key"];
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

- (void)runWebSocketSessionForRequest:(ALNRequest *)request
                             response:(ALNResponse *)response
                             clientFd:(int)clientFd {
  (void)request;
  NSString *mode = [self webSocketModeFromResponse:response];
  if ([mode length] == 0) {
    return;
  }

  ALNWebSocketClientSession *session = [[ALNWebSocketClientSession alloc] initWithClientFd:clientFd];
  ALNRealtimeSubscription *subscription = nil;
  NSString *channel = @"";
  if ([mode isEqualToString:@"channel"]) {
    channel = [self webSocketChannelFromResponse:response];
    subscription = [[ALNRealtimeHub sharedHub] subscribeChannel:channel subscriber:session];
  }

  while (gShouldRun && !session.closed) {
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

  if (subscription != nil) {
    [[ALNRealtimeHub sharedHub] unsubscribe:subscription];
  }
}

- (void)handleClientOnBackgroundThread:(NSNumber *)clientFDObject {
  @autoreleasepool {
    int clientFd = [clientFDObject intValue];
    @try {
      [self handleClient:clientFd];
    } @finally {
      [self releaseHTTPSessionReservation];
      close(clientFd);
    }
  }
}

- (void)handleClient:(int)clientFd {
  BOOL performanceLogging =
      ALNConfigBool(self.application.config ?: @{}, @"performanceLogging", YES);
  ALNRequestLimits limits = ALNLimitsFromConfig(self.application.config ?: @{});
  ALNServerSocketTuning tuning = ALNTuningFromConfig(self.application.config ?: @{});
  ALNApplyClientSocketTimeout(clientFd, tuning.connectionTimeoutSeconds);

  NSUInteger requestsHandled = 0;
  while (gShouldRun) {
    double requestStartMs = ALNNowMilliseconds();

    NSInteger readStatus = 0;
    double parseStartMs = ALNNowMilliseconds();
    NSData *rawRequest = ALNReadHTTPRequestData(clientFd, limits, &readStatus);
    double parseMs = ALNNowMilliseconds() - parseStartMs;
    if (rawRequest == nil) {
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

    NSError *requestError = nil;
    double requestParseStartMs = ALNNowMilliseconds();
    ALNRequest *request = [ALNRequest requestFromRawData:rawRequest error:&requestError];
    parseMs += (ALNNowMilliseconds() - requestParseStartMs);
    if (request == nil) {
      ALNResponse *errorResponse = ALNErrorResponse(400, @"bad request\n");
      [errorResponse setHeader:@"Connection" value:@"close"];
      ALNEnsurePerformanceHeaders(errorResponse,
                                  performanceLogging,
                                  parseMs,
                                  ALNNowMilliseconds() - requestStartMs);
      (void)ALNSendResponse(clientFd, errorResponse, performanceLogging);
      return;
    }
    request.parseDurationMilliseconds = parseMs;

    request.remoteAddress = ALNRemoteAddressForClient(clientFd);
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
        BOOL keepAlive = (!self.serializeRequestDispatch) &&
                         ALNShouldKeepAliveForRequest(request, staticResponse);
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

      @try {
        if ([self sendWebSocketHandshakeForRequest:request response:response clientFd:clientFd]) {
          [self runWebSocketSessionForRequest:request response:response clientFd:clientFd];
        }
      } @finally {
        [self releaseWebSocketSessionReservation];
      }
      return;
    }

    BOOL keepAlive = (!self.serializeRequestDispatch) &&
                     ALNShouldKeepAliveForRequest(request, response);
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

- (int)runWithHost:(NSString *)host
      portOverride:(NSInteger)portOverride
              once:(BOOL)once {
  gShouldRun = 1;

  NSDictionary *config = self.application.config ?: @{};
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
    self.serializeRequestDispatch = [requestDispatchMode isEqualToString:@"serialized"];
    self.maxConcurrentHTTPSessions = runtimeLimits.maxConcurrentHTTPSessions;
    self.maxConcurrentWebSocketSessions = runtimeLimits.maxConcurrentWebSocketSessions;

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

    int reuse = 1;
    if (setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
      perror("setsockopt");
      close(serverFd);
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
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"invalid bind host"
                                   userInfo:nil];
    }

    if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
      perror("bind");
      close(serverFd);
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"bind() failed"
                                   userInfo:nil];
    }

    if (listen(serverFd, (int)tuning.listenBacklog) < 0) {
      perror("listen");
      close(serverFd);
      exitCode = 1;
      @throw [NSException exceptionWithName:@"ALNServerStartFailed"
                                     reason:@"listen() failed"
                                   userInfo:nil];
    }

    fprintf(stdout, "%s listening on http://%s:%d\n", [self.serverName UTF8String], [bindHost UTF8String], port);
    fflush(stdout);

    while (gShouldRun) {
      int clientFd = accept(serverFd, NULL, NULL);
      if (clientFd < 0) {
        if (errno == EINTR) {
          if (!gShouldRun) {
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

      BOOL runInBackground = (!once && !self.serializeRequestDispatch);
      if (runInBackground) {
        @try {
          [NSThread detachNewThreadSelector:@selector(handleClientOnBackgroundThread:)
                                   toTarget:self
                                 withObject:@(clientFd)];
        } @catch (NSException *exception) {
          (void)exception;
          [self releaseHTTPSessionReservation];
          close(clientFd);
          continue;
        }
      } else {
        @try {
          [self handleClient:clientFd];
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
  } @catch (NSException *exception) {
    if (![exception.name isEqualToString:@"ALNServerStartFailed"]) {
      fprintf(stderr, "%s: fatal exception: %s\n", [self.serverName UTF8String],
              [[exception reason] UTF8String]);
      exitCode = 1;
    }
  } @finally {
    [self.application shutdown];
  }

  return exitCode;
}

@end
