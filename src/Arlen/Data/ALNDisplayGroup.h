#ifndef ALN_DISPLAY_GROUP_H
#define ALN_DISPLAY_GROUP_H

#import <Foundation/Foundation.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNDisplayGroup : NSObject

@property(nonatomic, strong, readonly) id<ALNDatabaseAdapter> adapter;
@property(nonatomic, copy, readonly) NSString *tableName;
@property(nonatomic, copy) NSArray<NSString *> *fetchFields;
@property(nonatomic, assign) NSUInteger batchSize;
@property(nonatomic, assign) NSUInteger batchIndex;
@property(nonatomic, copy, readonly) NSDictionary *filters;
@property(nonatomic, copy, readonly) NSArray *sortOrder;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *objects;

- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter
                      tableName:(NSString *)tableName;

- (void)setFilterValue:(nullable id)value forField:(NSString *)field;
- (void)removeFilterForField:(NSString *)field;
- (void)clearFilters;

- (void)addSortField:(NSString *)field descending:(BOOL)descending;
- (void)clearSortOrder;

- (BOOL)fetch:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
