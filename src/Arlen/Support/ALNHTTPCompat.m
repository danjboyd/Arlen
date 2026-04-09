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
