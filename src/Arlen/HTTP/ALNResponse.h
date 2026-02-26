#ifndef ALN_RESPONSE_H
#define ALN_RESPONSE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNResponseErrorDomain;

@interface ALNResponse : NSObject

@property(nonatomic, assign) NSInteger statusCode;
@property(nonatomic, strong, readonly) NSMutableDictionary *headers;
@property(nonatomic, strong, readonly) NSMutableData *bodyData;
@property(nonatomic, assign) BOOL committed;

- (void)setHeader:(NSString *)name value:(NSString *)value;
- (nullable NSString *)headerForName:(NSString *)name;
- (void)appendData:(NSData *)data;
- (void)appendText:(NSString *)text;
- (void)setTextBody:(NSString *)text;
- (BOOL)setJSONBody:(id)object
            options:(NSJSONWritingOptions)options
              error:(NSError *_Nullable *_Nullable)error;
- (NSData *)serializedHeaderData;
- (NSData *)serializedData;

@end

NS_ASSUME_NONNULL_END

#endif
