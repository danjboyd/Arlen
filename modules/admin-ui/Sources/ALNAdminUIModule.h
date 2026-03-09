#ifndef ALN_ADMIN_UI_MODULE_H
#define ALN_ADMIN_UI_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNModuleSystem.h"

@class ALNApplication;
@class ALNContext;
@class ALNPg;
@class ALNAdminUIModuleRuntime;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNAdminUIModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNAdminUIModuleErrorCode) {
  ALNAdminUIModuleErrorInvalidConfiguration = 1,
  ALNAdminUIModuleErrorDatabaseUnavailable = 2,
  ALNAdminUIModuleErrorNotFound = 3,
  ALNAdminUIModuleErrorValidationFailed = 4,
  ALNAdminUIModuleErrorMountFailed = 5,
  ALNAdminUIModuleErrorPolicyRejected = 6,
};

@protocol ALNAdminUIResource <NSObject>

- (NSString *)adminUIResourceIdentifier;
- (NSDictionary *)adminUIResourceMetadata;
- (nullable NSArray<NSDictionary *> *)adminUIListRecordsMatching:(nullable NSString *)query
                                                           limit:(NSUInteger)limit
                                                          offset:(NSUInteger)offset
                                                           error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                                      error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                                  parameters:(NSDictionary *)parameters
                                                       error:(NSError *_Nullable *_Nullable)error;

@optional
- (nullable NSDictionary *)adminUIDashboardSummaryWithError:(NSError *_Nullable *_Nullable)error;
- (BOOL)adminUIResourceAllowsOperation:(NSString *)operation
                            identifier:(nullable NSString *)identifier
                               context:(ALNContext *)context
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                          identifier:(NSString *)identifier
                                          parameters:(NSDictionary *)parameters
                                               error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNAdminUIResourceProvider <NSObject>

- (nullable NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                                   error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNAdminUIModuleRuntime : NSObject

@property(nonatomic, strong, readonly, nullable) ALNPg *database;
@property(nonatomic, copy, readonly) NSString *mountPrefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, copy, readonly) NSString *dashboardTitle;
@property(nonatomic, strong, readonly, nullable) ALNApplication *mountedApplication;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSString *)mountedPathForChildPath:(NSString *)childPath;
- (NSArray<NSDictionary *> *)registeredResources;
- (nullable NSDictionary *)resourceMetadataForIdentifier:(NSString *)identifier;
- (nullable NSDictionary *)resourceDescriptorForIdentifier:(NSString *)identifier;
- (nullable NSArray<NSDictionary *> *)listRecordsForResourceIdentifier:(NSString *)identifier
                                                                 query:(nullable NSString *)query
                                                                 limit:(NSUInteger)limit
                                                                offset:(NSUInteger)offset
                                                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)recordDetailForResourceIdentifier:(NSString *)identifier
                                                 recordID:(NSString *)recordID
                                                     error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)updateRecordForResourceIdentifier:(NSString *)identifier
                                                    recordID:(NSString *)recordID
                                                  parameters:(NSDictionary *)parameters
                                                       error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)performActionNamed:(NSString *)actionName
                        forResourceIdentifier:(NSString *)identifier
                                     recordID:(NSString *)recordID
                                   parameters:(NSDictionary *)parameters
                                        error:(NSError *_Nullable *_Nullable)error;
- (BOOL)resourceIdentifier:(NSString *)identifier
             allowsOperation:(NSString *)operation
                   recordID:(nullable NSString *)recordID
                    context:(ALNContext *)context
                      error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)dashboardSummaryWithError:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray<NSDictionary *> *)listUsersMatching:(nullable NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)userDetailForSubject:(NSString *)subject
                                          error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)updateUserForSubject:(NSString *)subject
                                    displayName:(NSString *)displayName
                                          error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNAdminUIModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
