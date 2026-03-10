#ifndef ALN_SEARCH_MODULE_H
#define ALN_SEARCH_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNModuleSystem.h"

@class ALNApplication;
@class ALNSearchModuleRuntime;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNSearchModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNSearchModuleErrorCode) {
  ALNSearchModuleErrorInvalidConfiguration = 1,
  ALNSearchModuleErrorValidationFailed = 2,
  ALNSearchModuleErrorNotFound = 3,
  ALNSearchModuleErrorExecutionFailed = 4,
};

@protocol ALNSearchResourceDefinition <NSObject>

- (NSString *)searchModuleResourceIdentifier;
- (NSDictionary *)searchModuleResourceMetadata;
- (nullable NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                                error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNSearchResourceProvider <NSObject>

- (nullable NSArray<id<ALNSearchResourceDefinition>> *)searchModuleResourcesForRuntime:
    (ALNSearchModuleRuntime *)runtime
                                                                           error:
                                                                               (NSError *_Nullable *_Nullable)error;

@end

@interface ALNSearchModuleRuntime : NSObject

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, copy, readonly) NSArray<NSString *> *accessRoles;
@property(nonatomic, assign, readonly) NSUInteger minimumAuthAssuranceLevel;
@property(nonatomic, strong, readonly, nullable) ALNApplication *application;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSArray<NSDictionary *> *)registeredResources;
- (nullable NSDictionary *)resourceMetadataForIdentifier:(NSString *)identifier;
- (nullable NSDictionary *)queueReindexForResourceIdentifier:(nullable NSString *)identifier
                                                       error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)processReindexJobPayload:(NSDictionary *)payload
                                              error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchQuery:(nullable NSString *)query
                    resourceIdentifier:(nullable NSString *)resourceIdentifier
                               filters:(nullable NSDictionary *)filters
                                  sort:(nullable NSString *)sort
                                 limit:(NSUInteger)limit
                                offset:(NSUInteger)offset
                                 error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)dashboardSummary;

@end

@interface ALNSearchModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
