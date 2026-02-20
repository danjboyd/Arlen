#ifndef ALN_SERVICES_H
#define ALN_SERVICES_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNServiceErrorDomain;

@interface ALNJobEnvelope : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *jobID;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSDictionary *payload;
@property(nonatomic, assign, readonly) NSUInteger attempt;
@property(nonatomic, assign, readonly) NSUInteger maxAttempts;
@property(nonatomic, strong, readonly) NSDate *notBefore;
@property(nonatomic, strong, readonly) NSDate *createdAt;
@property(nonatomic, assign, readonly) NSUInteger sequence;

- (instancetype)initWithJobID:(NSString *)jobID
                         name:(NSString *)name
                      payload:(NSDictionary *)payload
                      attempt:(NSUInteger)attempt
                  maxAttempts:(NSUInteger)maxAttempts
                    notBefore:(NSDate *)notBefore
                    createdAt:(NSDate *)createdAt
                     sequence:(NSUInteger)sequence;
- (NSDictionary *)dictionaryRepresentation;

@end

@protocol ALNJobAdapter <NSObject>

- (NSString *)adapterName;
- (nullable NSString *)enqueueJobNamed:(NSString *)name
                               payload:(nullable NSDictionary *)payload
                               options:(nullable NSDictionary *)options
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNJobEnvelope *)dequeueDueJobAt:(NSDate *)timestamp
                                        error:(NSError *_Nullable *_Nullable)error;
- (BOOL)acknowledgeJobID:(NSString *)jobID
                   error:(NSError *_Nullable *_Nullable)error;
- (BOOL)retryJob:(ALNJobEnvelope *)job
    delaySeconds:(NSTimeInterval)delaySeconds
           error:(NSError *_Nullable *_Nullable)error;
- (NSArray *)pendingJobsSnapshot;
- (NSArray *)deadLetterJobsSnapshot;
- (void)reset;

@end

@interface ALNInMemoryJobAdapter : NSObject <ALNJobAdapter>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

@protocol ALNCacheAdapter <NSObject>

- (NSString *)adapterName;
- (BOOL)setObject:(nullable id)object
           forKey:(NSString *)key
       ttlSeconds:(NSTimeInterval)ttlSeconds
            error:(NSError *_Nullable *_Nullable)error;
- (nullable id)objectForKey:(NSString *)key
                     atTime:(NSDate *)timestamp
                      error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeObjectForKey:(NSString *)key
                     error:(NSError *_Nullable *_Nullable)error;
- (BOOL)clearWithError:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNInMemoryCacheAdapter : NSObject <ALNCacheAdapter>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

@protocol ALNLocalizationAdapter <NSObject>

- (NSString *)adapterName;
- (BOOL)registerTranslations:(NSDictionary *)translations
                      locale:(NSString *)locale
                       error:(NSError *_Nullable *_Nullable)error;
- (NSString *)localizedStringForKey:(NSString *)key
                             locale:(NSString *)locale
                     fallbackLocale:(NSString *)fallbackLocale
                       defaultValue:(NSString *)defaultValue
                          arguments:(nullable NSDictionary *)arguments;
- (NSArray *)availableLocales;

@end

@interface ALNInMemoryLocalizationAdapter : NSObject <ALNLocalizationAdapter>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

@interface ALNMailMessage : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *from;
@property(nonatomic, copy, readonly) NSArray *to;
@property(nonatomic, copy, readonly) NSArray *cc;
@property(nonatomic, copy, readonly) NSArray *bcc;
@property(nonatomic, copy, readonly) NSString *subject;
@property(nonatomic, copy, readonly) NSString *textBody;
@property(nonatomic, copy, readonly) NSString *htmlBody;
@property(nonatomic, copy, readonly) NSDictionary *headers;
@property(nonatomic, copy, readonly) NSDictionary *metadata;

- (instancetype)initWithFrom:(NSString *)from
                          to:(NSArray *)to
                          cc:(nullable NSArray *)cc
                         bcc:(nullable NSArray *)bcc
                     subject:(NSString *)subject
                    textBody:(nullable NSString *)textBody
                    htmlBody:(nullable NSString *)htmlBody
                     headers:(nullable NSDictionary *)headers
                    metadata:(nullable NSDictionary *)metadata;
- (NSDictionary *)dictionaryRepresentation;

@end

@protocol ALNMailAdapter <NSObject>

- (NSString *)adapterName;
- (nullable NSString *)deliverMessage:(ALNMailMessage *)message
                                error:(NSError *_Nullable *_Nullable)error;
- (NSArray *)deliveriesSnapshot;
- (void)reset;

@end

@interface ALNInMemoryMailAdapter : NSObject <ALNMailAdapter>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

@protocol ALNAttachmentAdapter <NSObject>

- (NSString *)adapterName;
- (nullable NSString *)saveAttachmentNamed:(NSString *)name
                               contentType:(NSString *)contentType
                                      data:(NSData *)data
                                  metadata:(nullable NSDictionary *)metadata
                                     error:(NSError *_Nullable *_Nullable)error;
- (nullable NSData *)attachmentDataForID:(NSString *)attachmentID
                                metadata:(NSDictionary *_Nullable *_Nullable)metadata
                                   error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)attachmentMetadataForID:(NSString *)attachmentID
                                             error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deleteAttachmentID:(NSString *)attachmentID
                     error:(NSError *_Nullable *_Nullable)error;
- (NSArray *)listAttachmentMetadata;
- (void)reset;

@end

@interface ALNInMemoryAttachmentAdapter : NSObject <ALNAttachmentAdapter>

- (instancetype)initWithAdapterName:(nullable NSString *)adapterName;

@end

FOUNDATION_EXPORT BOOL ALNRunJobAdapterConformanceSuite(id<ALNJobAdapter> adapter,
                                                        NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNRunCacheAdapterConformanceSuite(id<ALNCacheAdapter> adapter,
                                                          NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNRunLocalizationAdapterConformanceSuite(id<ALNLocalizationAdapter> adapter,
                                                                 NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNRunMailAdapterConformanceSuite(id<ALNMailAdapter> adapter,
                                                         NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNRunAttachmentAdapterConformanceSuite(id<ALNAttachmentAdapter> adapter,
                                                               NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNRunServiceCompatibilitySuite(id<ALNJobAdapter> jobsAdapter,
                                                       id<ALNCacheAdapter> cacheAdapter,
                                                       id<ALNLocalizationAdapter> localizationAdapter,
                                                       id<ALNMailAdapter> mailAdapter,
                                                       id<ALNAttachmentAdapter> attachmentAdapter,
                                                       NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif
