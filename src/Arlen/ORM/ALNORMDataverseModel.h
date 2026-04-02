#ifndef ALN_ORM_DATAVERSE_MODEL_H
#define ALN_ORM_DATAVERSE_MODEL_H

#import <Foundation/Foundation.h>

#import "../Data/ALNDataverseClient.h"
#import "../Data/ALNDataverseQuery.h"
#import "ALNORMDataverseModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMDataverseContext;
@class ALNORMDataverseRepository;

@protocol ALNORMDataverseModelClass <NSObject>
+ (nullable ALNORMDataverseModelDescriptor *)dataverseModelDescriptor;
@optional
+ (nullable instancetype)modelFromRecord:(ALNDataverseRecord *)record
                                   error:(NSError *_Nullable *_Nullable)error;
@end

@interface ALNORMDataverseModel : NSObject <ALNORMDataverseModelClass>

@property(nonatomic, strong, readonly) ALNORMDataverseModelDescriptor *descriptor;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *fieldValues;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *relationValues;
@property(nonatomic, copy, readonly) NSSet<NSString *> *dirtyFieldNames;
@property(nonatomic, copy, readonly) NSSet<NSString *> *loadedRelationNames;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *rawDictionary;
@property(nonatomic, copy, readonly) NSString *etag;
@property(nonatomic, weak, readonly, nullable) ALNORMDataverseContext *context;
@property(nonatomic, assign, readonly, getter=isPersisted) BOOL persisted;

- (instancetype)init;
- (instancetype)initWithDescriptor:(ALNORMDataverseModelDescriptor *)descriptor NS_DESIGNATED_INITIALIZER;

+ (nullable ALNORMDataverseModelDescriptor *)dataverseModelDescriptor;
+ (nullable ALNDataverseQuery *)query;
+ (nullable ALNORMDataverseRepository *)repositoryWithContext:(ALNORMDataverseContext *)context;
+ (nullable instancetype)modelFromRecord:(ALNDataverseRecord *)record
                                   error:(NSError *_Nullable *_Nullable)error;

- (nullable id)objectForFieldName:(NSString *)fieldName;
- (BOOL)setObject:(nullable id)value
     forFieldName:(NSString *)fieldName
            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)applyRecord:(ALNDataverseRecord *)record
              error:(NSError *_Nullable *_Nullable)error;
- (void)markClean;
- (void)attachToContext:(nullable ALNORMDataverseContext *)context;
- (nullable id)relationObjectForName:(NSString *)relationName;
- (BOOL)markRelationLoaded:(NSString *)relationName
                     value:(nullable id)value
                     error:(NSError *_Nullable *_Nullable)error;
- (nullable id)primaryIDValue;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
