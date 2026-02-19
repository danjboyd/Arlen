#ifndef ALN_CONTROLLER_H
#define ALN_CONTROLLER_H

#import <Foundation/Foundation.h>

@class ALNContext;

NS_ASSUME_NONNULL_BEGIN

@interface ALNController : NSObject

@property(nonatomic, strong) ALNContext *context;

+ (NSJSONWritingOptions)jsonWritingOptions;

- (BOOL)renderTemplate:(NSString *)templateName
               context:(nullable NSDictionary *)context
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renderTemplate:(NSString *)templateName
               context:(nullable NSDictionary *)context
                layout:(nullable NSString *)layoutName
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renderJSON:(id)object error:(NSError *_Nullable *_Nullable)error;
- (void)renderText:(NSString *)text;
- (void)redirectTo:(NSString *)location status:(NSInteger)statusCode;
- (void)setStatus:(NSInteger)statusCode;
- (BOOL)hasRendered;
- (NSMutableDictionary *)session;
- (nullable NSString *)csrfToken;
- (void)markSessionDirty;

@end

NS_ASSUME_NONNULL_END

#endif
