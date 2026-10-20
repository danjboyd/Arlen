#import <Foundation/Foundation.h>

// Internal transactional catalog. Each outbox/inbox/fanout entry or recipient preference is a separate
// row; only changed rows are serialized and written on commit.
@interface ALNNotificationsCatalog : NSObject
@property(nonatomic, copy, readonly) NSString *path;
@property(nonatomic, assign, readonly) NSUInteger lastWrittenRowCount;
@property(nonatomic, assign, readonly) NSUInteger lastWrittenByteCount;
@property(nonatomic, assign, readonly) NSUInteger lastReadRowCount;
@property(nonatomic, assign) NSTimeInterval writeTimeoutSeconds;
- (instancetype)initWithPath:(NSString *)path legacyPath:(NSString *)legacyPath error:(NSError **)error;
- (NSDictionary *)readStateWithError:(NSError **)error;
- (BOOL)writeState:(NSDictionary *)state error:(NSError **)error;
@end
