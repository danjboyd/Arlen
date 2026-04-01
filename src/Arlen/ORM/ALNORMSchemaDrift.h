#ifndef ALN_ORM_SCHEMA_DRIFT_H
#define ALN_ORM_SCHEMA_DRIFT_H

#import <Foundation/Foundation.h>

#import "ALNORMDescriptorSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMSchemaDrift : NSObject

+ (NSArray<NSDictionary<NSString *, id> *> *)diagnosticsByComparingSnapshotDocument:
                                               (NSDictionary<NSString *, id> *)snapshotDocument
                                                            toModelDescriptors:
                                                                (NSArray<ALNORMModelDescriptor *> *)descriptors;
+ (BOOL)validateModelDescriptors:(NSArray<ALNORMModelDescriptor *> *)descriptors
          againstSnapshotDocument:(NSDictionary<NSString *, id> *)snapshotDocument
                      diagnostics:(NSArray<NSDictionary<NSString *, id> *> *_Nullable *_Nullable)diagnostics
                            error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
