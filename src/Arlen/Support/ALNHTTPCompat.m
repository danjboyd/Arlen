#import "ALNHTTPCompat.h"

#if defined(__APPLE__)
#import <dispatch/dispatch.h>
#endif

NSData *ALNSynchronousURLRequest(NSURLRequest *request,
                                 NSURLResponse *__autoreleasing _Nullable *_Nullable response,
                                 NSError *__autoreleasing _Nullable *_Nullable error) {
  if (error != NULL) {
    *error = nil;
  }
  if (response != NULL) {
    *response = nil;
  }
  if (request == nil) {
    return nil;
  }

#if defined(__APPLE__)
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSData *resultData = nil;
  __block NSURLResponse *resultResponse = nil;
  __block NSError *resultError = nil;

  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
  NSURLSessionDataTask *task =
      [session dataTaskWithRequest:request
                 completionHandler:^(NSData *data, NSURLResponse *taskResponse, NSError *taskError) {
                   resultData = data;
                   resultResponse = taskResponse;
                   resultError = taskError;
                   dispatch_semaphore_signal(semaphore);
                 }];
  [task resume];
  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
  [session finishTasksAndInvalidate];

  if (response != NULL) {
    *response = resultResponse;
  }
  if (error != NULL) {
    *error = resultError;
  }
  return resultData;
#else
  return [NSURLConnection sendSynchronousRequest:request returningResponse:response error:error];
#endif
}

// Keep metadata fetching on Foundation's TLS stack while bounding memory and time.
@interface ALNMetadataConnection : NSObject <NSURLConnectionDelegate>
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, assign) NSUInteger limit;
@property(nonatomic, assign) BOOL done;
@property(nonatomic, assign) BOOL accepted;
@end
@implementation ALNMetadataConnection
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response {
  if (response) { self.accepted = NO; self.done = YES; [connection cancel]; return nil; }
  return request;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  self.accepted = [response isKindOfClass:[NSHTTPURLResponse class]] &&
      [(NSHTTPURLResponse *)response statusCode] == 200 &&
      (response.expectedContentLength < 0 || (unsigned long long)response.expectedContentLength <= self.limit);
  if (!self.accepted) { self.done = YES; [connection cancel]; }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
  if (data.length > self.limit - self.data.length) {
    self.accepted = NO; self.done = YES; [connection cancel]; return;
  }
  [self.data appendData:data];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection { self.done = YES; }
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  self.accepted = NO; self.done = YES;
}
@end
NSData *ALNBoundedMetadataGET(NSURL *url, NSUInteger maxBytes, NSTimeInterval timeout) {
  if (!url || !maxBytes || timeout <= 0) return nil;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
  [request setHTTPShouldHandleCookies:NO];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  ALNMetadataConnection *delegate = [ALNMetadataConnection new];
  delegate.limit = maxBytes; delegate.data = [NSMutableData data];
  NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:delegate startImmediately:NO];
  if (!connection) return nil;
  NSString *mode = @"Arlen.MetadataFetch";
  [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
  [connection start];
  NSTimeInterval deadline = [NSProcessInfo processInfo].systemUptime + timeout;
  while (!delegate.done && [NSProcessInfo processInfo].systemUptime < deadline) {
    [[NSRunLoop currentRunLoop] runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  }
  [connection cancel];
  [connection unscheduleFromRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
  return delegate.done && delegate.accepted ? [delegate.data copy] : nil;
}
