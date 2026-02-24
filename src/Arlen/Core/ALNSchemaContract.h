#ifndef ALN_SCHEMA_CONTRACT_H
#define ALN_SCHEMA_CONTRACT_H

#import <Foundation/Foundation.h>

@class ALNRequest;

NS_ASSUME_NONNULL_BEGIN

NSDictionary *_Nullable ALNSchemaCoerceRequestValues(NSDictionary *schema,
                                                     ALNRequest *request,
                                                     NSDictionary *routeParams,
                                                     NSArray *_Nullable *_Nullable errors);

NSArray *_Nonnull ALNSchemaReadinessDiagnostics(NSDictionary *schema);

BOOL ALNSchemaValidateResponseValue(id _Nullable value,
                                    NSDictionary *schema,
                                    NSArray *_Nullable *_Nullable errors);

NS_ASSUME_NONNULL_END

#endif
