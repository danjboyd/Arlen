#import <Foundation/Foundation.h>

#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <signal.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>

#import "ALNEOCRuntime.h"

static volatile sig_atomic_t gShouldRun = 1;

static void HandleSignal(int sig) {
  (void)sig;
  gShouldRun = 0;
}

static BOOL InstallSignalHandler(int sig) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = HandleSignal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;
  return (sigaction(sig, &action, NULL) == 0);
}

static NSDictionary *BuildRequestContext(NSString *path) {
  return @{
    @"title" : @"Arlen Boomhauer Dev Server",
    @"items" : @[
      @"render pipeline ok",
      [NSString stringWithFormat:@"request path: %@", path ?: @"/"],
      @"unsafe sample: <unsafe>"
    ]
  };
}

static void SendResponse(int clientFd, NSInteger statusCode, NSString *statusText,
                         NSString *contentType, NSString *body) {
  NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
  if (bodyData == nil) {
    bodyData = [NSData data];
  }

  NSString *headers = [NSString
      stringWithFormat:
          @"HTTP/1.1 %ld %@\r\n"
           "Content-Type: %@\r\n"
           "Content-Length: %lu\r\n"
           "Connection: close\r\n"
           "\r\n",
          (long)statusCode, statusText, contentType, (unsigned long)[bodyData length]];

  NSData *headerData = [headers dataUsingEncoding:NSUTF8StringEncoding];
  if (headerData != nil) {
    (void)send(clientFd, [headerData bytes], [headerData length], 0);
  }
  (void)send(clientFd, [bodyData bytes], [bodyData length], 0);
}

static NSString *PathFromRequest(NSString *requestText) {
  NSArray *lines = [requestText componentsSeparatedByString:@"\r\n"];
  if ([lines count] == 0) {
    return nil;
  }

  NSString *requestLine = lines[0];
  NSArray *parts = [requestLine componentsSeparatedByString:@" "];
  if ([parts count] < 2) {
    return nil;
  }

  NSString *method = parts[0];
  if (![method isEqualToString:@"GET"]) {
    return @"__METHOD_NOT_ALLOWED__";
  }

  NSString *pathWithQuery = parts[1];
  NSRange query = [pathWithQuery rangeOfString:@"?"];
  if (query.location != NSNotFound) {
    pathWithQuery = [pathWithQuery substringToIndex:query.location];
  }
  if ([pathWithQuery length] == 0) {
    return @"/";
  }
  return pathWithQuery;
}

static void HandleClient(int clientFd) {
  char buffer[8192];
  ssize_t readBytes = recv(clientFd, buffer, sizeof(buffer) - 1, 0);
  if (readBytes <= 0) {
    return;
  }
  buffer[readBytes] = '\0';

  NSString *requestText = [NSString stringWithUTF8String:buffer];
  if (requestText == nil) {
    SendResponse(clientFd, 400, @"Bad Request", @"text/plain; charset=utf-8",
                 @"bad request");
    return;
  }

  NSString *path = PathFromRequest(requestText);
  if (path == nil) {
    SendResponse(clientFd, 400, @"Bad Request", @"text/plain; charset=utf-8",
                 @"bad request");
    return;
  }
  if ([path isEqualToString:@"__METHOD_NOT_ALLOWED__"]) {
    SendResponse(clientFd, 405, @"Method Not Allowed", @"text/plain; charset=utf-8",
                 @"method not allowed");
    return;
  }
  if ([path isEqualToString:@"/healthz"]) {
    SendResponse(clientFd, 200, @"OK", @"text/plain; charset=utf-8", @"ok\n");
    return;
  }

  if ([path isEqualToString:@"/"]) {
    NSError *renderError = nil;
    NSString *body = ALNEOCRenderTemplate(@"index.html.eoc", BuildRequestContext(path),
                                           &renderError);
    if (body == nil) {
      NSString *msg = [NSString stringWithFormat:@"render failed: %@",
                                                 [renderError localizedDescription]];
      SendResponse(clientFd, 500, @"Internal Server Error",
                   @"text/plain; charset=utf-8", msg);
      return;
    }
    SendResponse(clientFd, 200, @"OK", @"text/html; charset=utf-8", body);
    return;
  }

  SendResponse(clientFd, 404, @"Not Found", @"text/plain; charset=utf-8",
               @"not found\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    int port = 3000;
    BOOL once = NO;

    for (int idx = 1; idx < argc; idx++) {
      NSString *arg = [NSString stringWithUTF8String:argv[idx]];
      if ([arg isEqualToString:@"--port"]) {
        if (idx + 1 >= argc) {
          fprintf(stderr, "Usage: boomhauer [--port <port>] [--once]\n");
          return 2;
        }
        port = atoi(argv[++idx]);
      } else if ([arg isEqualToString:@"--once"]) {
        once = YES;
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        fprintf(stdout, "Usage: boomhauer [--port <port>] [--once]\n");
        return 0;
      } else {
        fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
        return 2;
      }
    }

    if (!InstallSignalHandler(SIGINT) || !InstallSignalHandler(SIGTERM)) {
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

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)port);

    if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
      perror("bind");
      close(serverFd);
      return 1;
    }

    if (listen(serverFd, 16) < 0) {
      perror("listen");
      close(serverFd);
      return 1;
    }

    fprintf(stdout, "boomhauer listening on http://127.0.0.1:%d\n", port);
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
        perror("accept");
        break;
      }

      HandleClient(clientFd);
      close(clientFd);

      if (once) {
        break;
      }
    }

    close(serverFd);
    return 0;
  }
}
