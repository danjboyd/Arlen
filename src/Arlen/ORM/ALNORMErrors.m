#import "ALNORMErrors.h"

NSString *const ALNORMErrorDomain = @"Arlen.ORM.Error";

NSError *ALNORMMakeError(ALNORMErrorCode code,
                         NSString *message,
                         NSDictionary<NSString *, id> *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionary];
  details[NSLocalizedDescriptionKey] = message ?: @"orm error";
  if ([userInfo isKindOfClass:[NSDictionary class]]) {
    [details addEntriesFromDictionary:userInfo];
  }
  return [NSError errorWithDomain:ALNORMErrorDomain code:code userInfo:details];
}
