#ifndef ALN_JOBS_MODULE_H
#define ALN_JOBS_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNModuleSystem.h"
#import "ALNServices.h"

@class ALNApplication;
@class ALNContext;
@class ALNJobsModuleRuntime;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNJobsModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNJobsModuleErrorCode) {
  ALNJobsModuleErrorInvalidConfiguration = 1,
  ALNJobsModuleErrorValidationFailed = 2,
  ALNJobsModuleErrorNotFound = 3,
  ALNJobsModuleErrorExecutionFailed = 4,
  ALNJobsModuleErrorUnsupported = 5,
};

@protocol ALNJobsJobDefinition <NSObject>

- (NSString *)jobsModuleJobIdentifier;
- (NSDictionary *)jobsModuleJobMetadata;
- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload
                            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload
                         context:(NSDictionary *)context
                           error:(NSError *_Nullable *_Nullable)error;

@optional
- (NSDictionary *)jobsModuleDefaultEnqueueOptions;

@end

@protocol ALNJobsJobProvider <NSObject>

- (nullable NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:
    (ALNJobsModuleRuntime *)runtime
                                                                   error:
                                                                       (NSError *_Nullable *_Nullable)error;

@end

@protocol ALNJobsScheduleProvider <NSObject>

- (nullable NSArray<NSDictionary *> *)jobsModuleScheduleDefinitionsForRuntime:
    (ALNJobsModuleRuntime *)runtime
                                                                    error:
                                                                        (NSError *_Nullable *_Nullable)error;

@end

@interface ALNJobsModuleRuntime : NSObject <ALNJobWorkerRuntime>

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, assign, readonly) NSUInteger defaultWorkerRunLimit;
@property(nonatomic, assign, readonly) NSTimeInterval defaultRetryDelaySeconds;
@property(nonatomic, strong, readonly, nullable) ALNApplication *application;
@property(nonatomic, strong, readonly, nullable) id<ALNJobAdapter> jobsAdapter;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSArray<NSDictionary *> *)registeredJobDefinitions;
- (NSArray<NSDictionary *> *)registeredSchedules;
- (nullable NSDictionary *)jobDefinitionMetadataForIdentifier:(NSString *)identifier;
- (BOOL)registerSystemJobDefinition:(id<ALNJobsJobDefinition>)definition
                              error:(NSError *_Nullable *_Nullable)error;
- (BOOL)registerSystemScheduleDefinition:(NSDictionary *)schedule
                                   error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)enqueueJobIdentifier:(NSString *)identifier
                                    payload:(nullable NSDictionary *)payload
                                    options:(nullable NSDictionary *)options
                                      error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)runSchedulerAt:(nullable NSDate *)timestamp
                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)runWorkerAt:(nullable NSDate *)timestamp
                                 limit:(NSUInteger)limit
                                 error:(NSError *_Nullable *_Nullable)error;
- (NSArray<NSDictionary *> *)pendingJobs;
- (NSArray<NSDictionary *> *)leasedJobs;
- (NSArray<NSDictionary *> *)deadLetterJobs;
- (nullable NSDictionary *)replayDeadLetterJobID:(NSString *)jobID
                                    delaySeconds:(NSTimeInterval)delaySeconds
                                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)pauseQueueNamed:(NSString *)queueName
                  error:(NSError *_Nullable *_Nullable)error;
- (BOOL)resumeQueueNamed:(NSString *)queueName
                   error:(NSError *_Nullable *_Nullable)error;
- (BOOL)isQueuePaused:(NSString *)queueName;
- (NSDictionary *)dashboardSummary;

@end

@interface ALNJobsModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
