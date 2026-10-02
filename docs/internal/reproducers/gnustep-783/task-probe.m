#import <Foundation/Foundation.h>
#include <signal.h>
#include <unistd.h>
static void work(void) { @autoreleasepool {
 NSTask *t=[NSTask new]; t.launchPath=@"/bin/sleep"; t.arguments=@[@"60"]; [t launch];
 NSString *status=[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"/proc/%d/status",t.processIdentifier] encoding:NSUTF8StringEncoding error:NULL];
 for(NSString *line in [status componentsSeparatedByString:@"\n"]) if([line hasPrefix:@"SigBlk:"]) printf("main=%d child %s\n",[NSThread isMainThread],line.UTF8String);
 [t terminate];
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:0.5];
 while(t.isRunning && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 printf("main=%d exitedAfterTERM=%d\n",[NSThread isMainThread],!t.isRunning);
 if(t.isRunning) kill(t.processIdentifier,SIGKILL);
 [t waitUntilExit];
} }
int main(void) { @autoreleasepool { work(); NSOperationQueue *q=[NSOperationQueue new]; [q addOperationWithBlock:^{ work(); }]; [q waitUntilAllOperationsAreFinished]; } }
