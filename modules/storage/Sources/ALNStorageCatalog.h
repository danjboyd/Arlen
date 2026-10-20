#import <Foundation/Foundation.h>

// Internal transactional catalog. Each object/session/membership is a separate
// row; only changed rows are serialized and written on commit.
@interface ALNStorageCatalog : NSObject
@property(nonatomic, copy, readonly) NSString *path;
@property(nonatomic, assign, readonly) NSUInteger lastWrittenRowCount;
@property(nonatomic, assign) NSTimeInterval writeTimeoutSeconds;
- (instancetype)initWithPath:(NSString *)path legacyPath:(NSString *)legacyPath error:(NSError **)error;
- (NSDictionary *)readStateWithError:(NSError **)error;
- (BOOL)writeState:(NSDictionary *)state error:(NSError **)error;
@end
