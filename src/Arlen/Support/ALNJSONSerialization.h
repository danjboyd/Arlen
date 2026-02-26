#ifndef ALN_JSON_SERIALIZATION_H
#define ALN_JSON_SERIALIZATION_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ALNJSONBackend) {
  ALNJSONBackendFoundation = 0,
  ALNJSONBackendYYJSON = 1,
};

@interface ALNJSONSerialization : NSObject

+ (nullable id)JSONObjectWithData:(NSData *)data
                          options:(NSJSONReadingOptions)options
                            error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSData *)dataWithJSONObject:(id)obj
                                options:(NSJSONWritingOptions)options
                                  error:(NSError *_Nullable *_Nullable)error;

+ (BOOL)isValidJSONObject:(id)obj;

+ (ALNJSONBackend)backend;
+ (NSString *)backendName;
+ (NSString *)yyjsonVersion;
+ (NSString *)foundationFallbackDeprecationDate;

// Testing helpers. Runtime code should rely on env-based backend selection.
+ (void)setBackendForTesting:(ALNJSONBackend)backend;
+ (void)resetBackendForTesting;

@end

NS_ASSUME_NONNULL_END

#endif
