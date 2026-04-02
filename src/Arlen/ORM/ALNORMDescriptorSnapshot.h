#ifndef ALN_ORM_DESCRIPTOR_SNAPSHOT_H
#define ALN_ORM_DESCRIPTOR_SNAPSHOT_H

#import <Foundation/Foundation.h>

#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMDescriptorSnapshot : NSObject

+ (NSString *)formatVersion;
+ (NSDictionary<NSString *, id> *)snapshotDocumentWithModelDescriptors:
                                    (NSArray<ALNORMModelDescriptor *> *)descriptors
                                                     databaseTarget:(nullable NSString *)databaseTarget
                                                              label:(nullable NSString *)label;
+ (nullable NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSnapshotDocument:
                                            (NSDictionary<NSString *, id> *)document
                                                                                  error:
                                                                                      (NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
