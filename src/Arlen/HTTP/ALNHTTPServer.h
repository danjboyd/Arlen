#ifndef ALN_HTTP_SERVER_H
#define ALN_HTTP_SERVER_H

#import <Foundation/Foundation.h>

@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

@interface ALNHTTPServer : NSObject

@property(nonatomic, strong, readonly) ALNApplication *application;
@property(nonatomic, copy, readonly) NSString *publicRoot;
@property(nonatomic, copy) NSString *serverName;

- (instancetype)initWithApplication:(ALNApplication *)application
                         publicRoot:(NSString *)publicRoot;

- (void)printRoutesToFile:(FILE *)stream;
- (int)runWithHost:(nullable NSString *)host
      portOverride:(NSInteger)portOverride
              once:(BOOL)once;
- (void)requestStop;

@end

NS_ASSUME_NONNULL_END

#endif
