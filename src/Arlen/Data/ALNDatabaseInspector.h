#ifndef ALN_DATABASE_INSPECTOR_H
#define ALN_DATABASE_INSPECTOR_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDatabaseInspectorErrorDomain;

typedef NS_ENUM(NSInteger, ALNDatabaseInspectorErrorCode) {
  ALNDatabaseInspectorErrorInvalidArgument = 1,
  ALNDatabaseInspectorErrorUnsupportedAdapter = 2,
  ALNDatabaseInspectorErrorInspectionFailed = 3,
  ALNDatabaseInspectorErrorInvalidResult = 4,
};

@interface ALNDatabaseInspector : NSObject

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)inspectSchemaColumnsForAdapter:(id<ALNDatabaseAdapter>)adapter
                                                                               error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary<NSString *, id> *)inspectSchemaMetadataForAdapter:(id<ALNDatabaseAdapter>)adapter
                                                                     error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNPostgresInspector : ALNDatabaseInspector

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)inspectSchemaColumnsWithAdapter:(id<ALNDatabaseAdapter>)adapter
                                                                                error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)normalizedColumnsFromInspectionRows:(NSArray<NSDictionary *> *)rows
                                                                                     error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary<NSString *, id> *)inspectSchemaMetadataWithAdapter:(id<ALNDatabaseAdapter>)adapter
                                                                      error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
