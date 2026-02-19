#ifndef ALN_PAGE_STATE_H
#define ALN_PAGE_STATE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ALNContext;

@interface ALNPageState : NSObject

@property(nonatomic, copy, readonly) NSString *pageKey;

- (instancetype)initWithContext:(ALNContext *)context
                        pageKey:(NSString *)pageKey;

- (NSDictionary *)allValues;
- (nullable id)valueForKey:(NSString *)key;
- (void)setValue:(nullable id)value forKey:(NSString *)key;
- (void)clear;

@end

NS_ASSUME_NONNULL_END

#endif
