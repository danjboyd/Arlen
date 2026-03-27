#ifndef ALN_DATABASE_ADAPTER_H
#define ALN_DATABASE_ADAPTER_H

#import <Foundation/Foundation.h>

#import "ALNSQLDialect.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNDatabaseAdapterErrorDomain;

typedef NS_ENUM(NSInteger, ALNDatabaseAdapterErrorCode) {
  ALNDatabaseAdapterErrorInvalidArgument = 1,
  ALNDatabaseAdapterErrorUnsupported = 2,
  ALNDatabaseAdapterErrorConformanceFailed = 3,
  ALNDatabaseAdapterErrorInvalidResult = 4,
};

@class ALNDatabaseRow;
@class ALNDatabaseResult;

@interface ALNDatabaseJSONValue : NSObject

@property(nonatomic, strong, readonly) id object;

+ (instancetype)valueWithObject:(nullable id)object;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithObject:(nullable id)object NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDatabaseArrayValue : NSObject

@property(nonatomic, copy, readonly) NSArray *items;

+ (instancetype)valueWithItems:(nullable NSArray *)items;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithItems:(nullable NSArray *)items NS_DESIGNATED_INITIALIZER;

@end

@interface ALNDatabaseRow : NSObject

@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *dictionaryRepresentation;
@property(nonatomic, copy, readonly) NSArray<NSString *> *columns;

+ (instancetype)rowWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;
+ (instancetype)rowWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
                    orderedColumns:(nullable NSArray<NSString *> *)orderedColumns
                     orderedValues:(nullable NSArray *)orderedValues;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary;
- (instancetype)initWithDictionary:(nullable NSDictionary<NSString *, id> *)dictionary
                    orderedColumns:(nullable NSArray<NSString *> *)orderedColumns
                     orderedValues:(nullable NSArray *)orderedValues NS_DESIGNATED_INITIALIZER;
- (nullable id)objectForColumn:(NSString *)columnName;
- (nullable id)objectAtColumnIndex:(NSUInteger)index;
- (nullable id)objectForKeyedSubscript:(NSString *)columnName;

@end

@interface ALNDatabaseResult : NSObject

@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *rows;
@property(nonatomic, assign, readonly) NSUInteger count;
@property(nonatomic, copy, readonly) NSArray<NSString *> *columns;

+ (instancetype)resultWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows;
+ (instancetype)resultWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows
                 orderedColumns:(nullable NSArray<NSString *> *)orderedColumns
                  orderedValues:(nullable NSArray<NSArray *> *)orderedValues;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows;
- (instancetype)initWithRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)rows
              orderedColumns:(nullable NSArray<NSString *> *)orderedColumns
               orderedValues:(nullable NSArray<NSArray *> *)orderedValues NS_DESIGNATED_INITIALIZER;
- (nullable ALNDatabaseRow *)first;
- (nullable ALNDatabaseRow *)rowAtIndex:(NSUInteger)index;
- (nullable ALNDatabaseRow *)one:(NSError *_Nullable *_Nullable)error;
- (nullable ALNDatabaseRow *)oneOrNil:(NSError *_Nullable *_Nullable)error;
- (nullable id)scalarValueForColumn:(nullable NSString *)columnName error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNDatabaseConnection <NSObject>

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)executeQueryOne:(NSString *)sql
                                parameters:(NSArray *)parameters
                                     error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;

@optional

- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)createSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(BOOL (^)(NSError *_Nullable *_Nullable error))block
                     error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNDatabaseAdapter <NSObject>

- (NSString *)adapterName;
- (nullable id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError *_Nullable *_Nullable)error;
- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection;

- (nullable NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError *_Nullable *_Nullable)error;

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                            error:(NSError *_Nullable *_Nullable)error;

@optional

- (nullable ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                                        parameters:(NSArray *)parameters
                                             error:(NSError *_Nullable *_Nullable)error;
- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError *_Nullable *_Nullable)error;
- (nullable id<ALNSQLDialect>)sqlDialect;
- (NSDictionary<NSString *, id> *)capabilityMetadata;

@end

FOUNDATION_EXPORT NSError *ALNDatabaseAdapterMakeError(ALNDatabaseAdapterErrorCode code,
                                                       NSString *message,
                                                       NSDictionary *_Nullable userInfo);
FOUNDATION_EXPORT BOOL ALNDatabaseErrorIsConnectivityFailure(NSError *_Nullable error);
FOUNDATION_EXPORT ALNDatabaseJSONValue *ALNDatabaseJSONParameter(id _Nullable object);
FOUNDATION_EXPORT ALNDatabaseArrayValue *ALNDatabaseArrayParameter(NSArray *_Nullable items);
FOUNDATION_EXPORT ALNDatabaseResult *_Nonnull ALNDatabaseResultFromRows(
    NSArray<NSDictionary *> *_Nullable rows);
FOUNDATION_EXPORT ALNDatabaseResult *_Nonnull ALNDatabaseResultFromRowsWithOrderedColumns(
    NSArray<NSDictionary *> *_Nullable rows,
    NSArray<NSString *> *_Nullable orderedColumns,
    NSArray<NSArray *> *_Nullable orderedValues);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *_Nullable ALNDatabaseFirstRow(
    NSArray<NSDictionary *> *_Nullable rows);
FOUNDATION_EXPORT id _Nullable ALNDatabaseScalarValueFromRow(
    NSDictionary<NSString *, id> *_Nullable row,
    NSString *_Nullable columnName,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNDatabaseScalarValueFromRows(
    NSArray<NSDictionary *> *_Nullable rows,
    NSString *_Nullable columnName,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT id _Nullable ALNDatabaseExecuteScalarQuery(id<ALNDatabaseConnection> connection,
                                                             NSString *sql,
                                                             NSArray *_Nullable parameters,
                                                             NSString *_Nullable columnName,
                                                             NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT ALNDatabaseResult *_Nullable ALNDatabaseExecuteQueryResult(
    id<ALNDatabaseConnection> connection,
    NSString *sql,
    NSArray *_Nullable parameters,
    NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT NSInteger ALNDatabaseExecuteCommandBatch(id<ALNDatabaseConnection> connection,
                                                           NSString *sql,
                                                           NSArray<NSArray *> *_Nullable parameterSets,
                                                           NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNDatabaseConnectionSupportsSavepoints(
    id<ALNDatabaseConnection> connection);
FOUNDATION_EXPORT BOOL ALNDatabaseCreateSavepoint(id<ALNDatabaseConnection> connection,
                                                  NSString *name,
                                                  NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNDatabaseRollbackToSavepoint(id<ALNDatabaseConnection> connection,
                                                      NSString *name,
                                                      NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNDatabaseReleaseSavepoint(id<ALNDatabaseConnection> connection,
                                                   NSString *name,
                                                   NSError *_Nullable *_Nullable error);
FOUNDATION_EXPORT BOOL ALNDatabaseWithSavepoint(
    id<ALNDatabaseConnection> connection,
    NSString *name,
    BOOL (^block)(NSError *_Nullable *_Nullable error),
    NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif
