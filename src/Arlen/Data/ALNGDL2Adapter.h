#ifndef ALN_GDL2_ADAPTER_H
#define ALN_GDL2_ADAPTER_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNPg;

@interface ALNGDL2Adapter : NSObject <ALNDatabaseAdapter>

@property(nonatomic, strong, readonly) ALNPg *fallbackAdapter;
@property(nonatomic, copy, readonly) NSString *migrationMode;

+ (NSDictionary<NSString *, id> *)capabilityMetadata;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    maxConnections:(NSUInteger)maxConnections
                                             error:(NSError *_Nullable *_Nullable)error;

- (instancetype)initWithFallbackAdapter:(ALNPg *)fallbackAdapter;

+ (BOOL)isNativeGDL2RuntimeAvailable;

@end

NS_ASSUME_NONNULL_END

#endif
