#import "ALNHTTPServer.h"

#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <signal.h>
#import <stdio.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <unistd.h>

#import "ALNApplication.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

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

static ALNResponse *ALNStaticResponseForRequest(ALNRequest *request, NSString *publicRoot) {
  ALNResponse *response = [[ALNResponse alloc] init];

  if (![request.path hasPrefix:@"/static/"]) {
    return nil;
  }

  NSString *relativePath = [request.path substringFromIndex:[@"/static/" length]];
  if ([relativePath length] == 0 || [relativePath containsString:@".."] ||
      [relativePath hasPrefix:@"/"]) {
    response.statusCode = 404;
    [response setTextBody:@"not found\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    return response;
  }

  NSString *standardRoot = [publicRoot stringByStandardizingPath];
  NSString *candidatePath = [standardRoot stringByAppendingPathComponent:relativePath];
  NSString *standardCandidate = [candidatePath stringByStandardizingPath];

  BOOL validRoot = [standardCandidate isEqualToString:standardRoot] ||
                   [standardCandidate hasPrefix:[standardRoot stringByAppendingString:@"/"]];
  if (!validRoot) {
    response.statusCode = 404;
    [response setTextBody:@"not found\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    return response;
  }

  BOOL isDirectory = NO;
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:standardCandidate
                                                      isDirectory:&isDirectory];
  if (!exists || isDirectory) {
    response.statusCode = 404;
    [response setTextBody:@"not found\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    return response;
  }

  NSData *fileData = [NSData dataWithContentsOfFile:standardCandidate];
  if (fileData == nil) {
    response.statusCode = 500;
    [response setTextBody:@"failed to read static asset\n"];
    [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    return response;
  }

  response.statusCode = 200;
  [response setHeader:@"Content-Type" value:ALNContentTypeForFilePath(standardCandidate)];
  if (![request.method isEqualToString:@"HEAD"]) {
    [response appendData:fileData];
  }
  response.committed = YES;
  return response;
}

static void ALNSendResponse(int clientFd, ALNResponse *response) {
  NSData *raw = [response serializedData];
  (void)send(clientFd, [raw bytes], [raw length], 0);
}

static ALNResponse *ALNErrorResponse(NSInteger statusCode, NSString *body) {
  ALNResponse *response = [[ALNResponse alloc] init];
  response.statusCode = statusCode;
  [response setTextBody:body ?: @"error\n"];
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  response.committed = YES;
  return response;
}

@interface ALNHTTPServer ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, copy, readwrite) NSString *publicRoot;

@end

@implementation ALNHTTPServer

- (instancetype)initWithApplication:(ALNApplication *)application
                         publicRoot:(NSString *)publicRoot {
  self = [super init];
  if (self) {
    _application = application;
    _publicRoot = [publicRoot copy];
    _serverName = @"server";
  }
  return self;
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

- (void)handleClient:(int)clientFd {
  ALNRequestLimits limits = ALNLimitsFromConfig(self.application.config ?: @{});
  ALNServerSocketTuning tuning = ALNTuningFromConfig(self.application.config ?: @{});
  ALNApplyClientSocketTimeout(clientFd, tuning.connectionTimeoutSeconds);

  NSInteger readStatus = 0;
  NSData *rawRequest = ALNReadHTTPRequestData(clientFd, limits, &readStatus);
  if (rawRequest == nil) {
    if (readStatus == 413) {
      ALNSendResponse(clientFd, ALNErrorResponse(413, @"payload too large\n"));
    } else if (readStatus == 431) {
      ALNSendResponse(clientFd, ALNErrorResponse(431, @"request headers too large\n"));
    } else if (readStatus == 408) {
      ALNSendResponse(clientFd, ALNErrorResponse(408, @"request timeout\n"));
    } else {
      ALNSendResponse(clientFd, ALNErrorResponse(400, @"bad request\n"));
    }
    return;
  }

  NSError *requestError = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:rawRequest error:&requestError];
  if (request == nil) {
    ALNSendResponse(clientFd, ALNErrorResponse(400, @"bad request\n"));
    return;
  }

  request.remoteAddress = ALNRemoteAddressForClient(clientFd);
  request.effectiveRemoteAddress = request.remoteAddress ?: @"";
  request.scheme = @"http";
  ALNApplyProxyMetadata(request, self.application.config ?: @{});

  BOOL serveStatic = ALNConfigBool(self.application.config ?: @{}, @"serveStatic", NO);
  BOOL supportsStaticMethod = [request.method isEqualToString:@"GET"] ||
                              [request.method isEqualToString:@"HEAD"];
  if (serveStatic && supportsStaticMethod && [request.path hasPrefix:@"/static/"]) {
    ALNResponse *staticResponse = ALNStaticResponseForRequest(request, self.publicRoot);
    if (staticResponse != nil) {
      ALNSendResponse(clientFd, staticResponse);
      return;
    }
  }

  ALNResponse *response = [self.application dispatchRequest:request];
  ALNSendResponse(clientFd, response);
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

  ALNServerSocketTuning tuning = ALNTuningFromConfig(config);

  if (!ALNInstallSignalHandler(SIGINT) || !ALNInstallSignalHandler(SIGTERM)) {
    perror("sigaction");
    return 1;
  }

  int serverFd = socket(AF_INET, SOCK_STREAM, 0);
  if (serverFd < 0) {
    perror("socket");
    return 1;
  }

  int reuse = 1;
  if (setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
    perror("setsockopt");
    close(serverFd);
    return 1;
  }

#ifdef SO_REUSEPORT
  if (tuning.enableReusePort) {
    if (setsockopt(serverFd, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse)) < 0) {
      perror("setsockopt(SO_REUSEPORT)");
      close(serverFd);
      return 1;
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
    return 1;
  }

  if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    perror("bind");
    close(serverFd);
    return 1;
  }

  if (listen(serverFd, (int)tuning.listenBacklog) < 0) {
    perror("listen");
    close(serverFd);
    return 1;
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

    [self handleClient:clientFd];
    close(clientFd);

    if (once) {
      break;
    }
  }

  close(serverFd);
  return 0;
}

@end
