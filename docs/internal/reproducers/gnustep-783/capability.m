#import <Foundation/Foundation.h>
int main(void) { @autoreleasepool {
 printf("schedulerClass=%d connectionSchedulingMethod=%d\n", NSClassFromString(@"GSRunLoopScheduler") != Nil, [NSURLConnection instancesRespondToSelector:NSSelectorFromString(@"_scheduled")]);
} }
