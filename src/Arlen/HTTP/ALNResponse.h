#ifndef ALN_RESPONSE_H
#define ALN_RESPONSE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNResponseErrorDomain;

@interface ALNResponse : NSObject

@property(nonatomic, assign) NSInteger statusCode;
// Legacy first-value view. Use header methods for validated, cache-aware mutations.
@property(nonatomic, strong, readonly) NSMutableDictionary *headers;
@property(nonatomic, strong, readonly) NSMutableData *bodyData;
@property(nonatomic, assign) BOOL committed;
@property(nonatomic, copy, nullable) NSString *fileBodyPath;
@property(nonatomic, assign) unsigned long long fileBodyLength;
@property(nonatomic, assign) unsigned long long fileBodyDevice;
@property(nonatomic, assign) unsigned long long fileBodyInode;
@property(nonatomic, assign) long long fileBodyMTimeSeconds;
@property(nonatomic, assign) long fileBodyMTimeNanoseconds;

// Replaces all values for the case-insensitive name.
- (void)setHeader:(NSString *)name value:(NSString *)value;
// Appends a separate field line for supported repeatable headers; NO leaves state unchanged.
- (BOOL)appendHeader:(NSString *)name value:(NSString *)value;
- (NSArray<NSString *> *)headerValuesForName:(NSString *)name;
- (void)removeHeaderForName:(NSString *)name;
- (void)setHeadersIfMissing:(NSDictionary<NSString *, NSString *> *)headers;
- (nullable NSString *)headerForName:(NSString *)name;
- (void)appendData:(NSData *)data;
- (void)appendText:(NSString *)text;
- (void)clearBody;
- (NSUInteger)bodyLength;
- (NSData *)bodyDataForTransmission;
- (void)setTextBody:(NSString *)text;
- (void)setDataBody:(NSData *)data contentType:(nullable NSString *)contentType;
- (BOOL)setJSONBody:(id)object
            options:(NSJSONWritingOptions)options
              error:(NSError *_Nullable *_Nullable)error;
- (nullable NSData *)serializedHeaderData;
- (NSData *)serializedData;

@end

NS_ASSUME_NONNULL_END

#endif
