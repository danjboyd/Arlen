#ifndef ALN_OPS_MODULE_H
#define ALN_OPS_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNModuleSystem.h"

@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNOpsModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNOpsModuleErrorCode) {
  ALNOpsModuleErrorInvalidConfiguration = 1,
  ALNOpsModuleErrorPolicyRejected = 2,
};

@interface ALNOpsModuleRuntime : NSObject

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, copy, readonly) NSArray<NSString *> *accessRoles;
@property(nonatomic, assign, readonly) NSUInteger minimumAuthAssuranceLevel;
@property(nonatomic, strong, readonly, nullable) ALNApplication *application;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSDictionary *)dashboardSummary;

@end

@interface ALNOpsModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
