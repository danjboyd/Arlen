#ifndef ALN_ORM_ERRORS_H
#define ALN_ORM_ERRORS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNORMErrorDomain;

typedef NS_ENUM(NSInteger, ALNORMErrorCode) {
  ALNORMErrorInvalidArgument = 1,
  ALNORMErrorInvalidMetadata = 2,
  ALNORMErrorUnsupportedAdapter = 3,
  ALNORMErrorUnsupportedModelClass = 4,
  ALNORMErrorIdentifierCollision = 5,
  ALNORMErrorMissingField = 6,
  ALNORMErrorInvalidType = 7,
  ALNORMErrorQueryBuildFailed = 8,
  ALNORMErrorQueryExecutionFailed = 9,
  ALNORMErrorMaterializationFailed = 10,
  ALNORMErrorUnsupportedQueryShape = 11,
  ALNORMErrorReadOnlyMutation = 12,
  ALNORMErrorStrictLoadingViolation = 13,
  ALNORMErrorQueryBudgetExceeded = 14,
  ALNORMErrorValidationFailed = 15,
  ALNORMErrorOptimisticLockConflict = 16,
  ALNORMErrorTransactionRequired = 17,
  ALNORMErrorSaveFailed = 18,
  ALNORMErrorDeleteFailed = 19,
  ALNORMErrorUpsertFailed = 20,
};

FOUNDATION_EXPORT NSError *ALNORMMakeError(ALNORMErrorCode code,
                                           NSString *message,
                                           NSDictionary<NSString *, id> *_Nullable userInfo);

NS_ASSUME_NONNULL_END

#endif
