#ifndef ALN_ORM_WRITE_OPTIONS_H
#define ALN_ORM_WRITE_OPTIONS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMWriteOptions : NSObject <NSCopying>

@property(nonatomic, copy) NSString *optimisticLockFieldName;
@property(nonatomic, copy) NSString *createdAtFieldName;
@property(nonatomic, copy) NSString *updatedAtFieldName;
@property(nonatomic, copy) NSArray<NSString *> *conflictFieldNames;
@property(nonatomic, copy) NSArray<NSString *> *saveRelatedRelationNames;
@property(nonatomic, strong, nullable) NSDate *timestampValue;
@property(nonatomic, assign) BOOL overwriteAllFields;

+ (instancetype)options;

@end

NS_ASSUME_NONNULL_END

#endif
