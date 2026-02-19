#import "ALNDatabaseAdapter.h"

NSString *const ALNDatabaseAdapterErrorDomain = @"Arlen.Data.Adapter.Error";

NSError *ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorCode code,
                                     NSString *message,
                                     NSDictionary *userInfo) {
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:userInfo ?: @{}];
  details[NSLocalizedDescriptionKey] = message ?: @"database adapter error";
  return [NSError errorWithDomain:ALNDatabaseAdapterErrorDomain
                             code:code
                         userInfo:details];
}
