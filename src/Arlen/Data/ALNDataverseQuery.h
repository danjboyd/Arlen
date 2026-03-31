#ifndef ALN_DATAVERSE_QUERY_H
#define ALN_DATAVERSE_QUERY_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDataverseQueryErrorDomain;

typedef NS_ENUM(NSInteger, ALNDataverseQueryErrorCode) {
  ALNDataverseQueryErrorInvalidArgument = 1,
  ALNDataverseQueryErrorUnsupportedPredicate = 2,
  ALNDataverseQueryErrorInvalidExpand = 3,
};

@interface ALNDataverseQuery : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *entitySetName;
@property(nonatomic, copy, readonly) NSArray<NSString *> *selectFields;
@property(nonatomic, strong, readonly, nullable) id predicate;
@property(nonatomic, strong, readonly, nullable) id orderBy;
@property(nonatomic, copy, readonly, nullable) NSNumber *top;
@property(nonatomic, copy, readonly, nullable) NSNumber *skip;
@property(nonatomic, copy, readonly, nullable) NSDictionary<NSString *, id> *expand;
@property(nonatomic, assign, readonly) BOOL includeCount;
@property(nonatomic, assign, readonly) BOOL includeFormattedValues;

+ (nullable instancetype)queryWithEntitySetName:(NSString *)entitySetName
                                          error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)filterStringFromPredicate:(nullable id)predicate
                                           error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)orderByStringFromSpec:(nullable id)orderBy
                                       error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)expandStringFromSpec:(nullable NSDictionary<NSString *, id> *)expand
                                      error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary<NSString *, NSString *> *)queryParametersWithSelectFields:
                                                  (nullable NSArray<NSString *> *)selectFields
                                                                           where:(nullable id)predicate
                                                                         orderBy:(nullable id)orderBy
                                                                             top:(nullable NSNumber *)top
                                                                            skip:(nullable NSNumber *)skip
                                                                       countFlag:(BOOL)countFlag
                                                                          expand:(nullable NSDictionary<NSString *, id> *)expand
                                                                           error:(NSError *_Nullable *_Nullable)error;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithEntitySetName:(NSString *)entitySetName
                                         error:(NSError *_Nullable *_Nullable)error NS_DESIGNATED_INITIALIZER;
- (ALNDataverseQuery *)queryBySettingSelectFields:(nullable NSArray<NSString *> *)selectFields;
- (ALNDataverseQuery *)queryBySettingPredicate:(nullable id)predicate;
- (ALNDataverseQuery *)queryBySettingOrderBy:(nullable id)orderBy;
- (ALNDataverseQuery *)queryBySettingTop:(nullable NSNumber *)top;
- (ALNDataverseQuery *)queryBySettingSkip:(nullable NSNumber *)skip;
- (ALNDataverseQuery *)queryBySettingExpand:(nullable NSDictionary<NSString *, id> *)expand;
- (ALNDataverseQuery *)queryBySettingIncludeCount:(BOOL)includeCount;
- (ALNDataverseQuery *)queryBySettingIncludeFormattedValues:(BOOL)includeFormattedValues;
- (nullable NSDictionary<NSString *, NSString *> *)queryParameters:(NSError *_Nullable *_Nullable)error;

@end

FOUNDATION_EXPORT NSError *ALNDataverseQueryMakeError(ALNDataverseQueryErrorCode code,
                                                      NSString *message,
                                                      NSDictionary *_Nullable userInfo);

NS_ASSUME_NONNULL_END

#endif
