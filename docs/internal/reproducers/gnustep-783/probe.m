#import <Foundation/Foundation.h>
#include <time.h>
#include <unistd.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec+t.tv_nsec/1e9; }
@interface Probe : NSObject <NSURLConnectionDelegate>
@property BOOL done;
@property BOOL finished;
@property NSInteger status;
@property NSUInteger callbacks;
@property(strong) NSMutableData *data;
@property(strong) NSError *error;
@end
@implementation Probe
- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r { self.callbacks++; self.status=[(NSHTTPURLResponse *)r statusCode]; }
- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)d { self.callbacks++; [self.data appendData:d]; if(self.data.length>262144) { self.error=[NSError errorWithDomain:@"Probe.Size" code:1 userInfo:nil]; self.done=YES; [c cancel]; } }
- (void)connectionDidFinishLoading:(NSURLConnection *)c { self.callbacks++; self.finished=YES; self.done=YES; }
- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)e { self.callbacks++; self.error=e; self.done=YES; }
@end
static int run(NSString *url, NSString *mode, BOOL start, NSString *expect, double timeout) {
  Probe *p=[Probe new]; p.data=[NSMutableData data];
  NSURLConnection *c=[[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout] delegate:p startImmediately:NO];
  NSRunLoop *loop=[NSRunLoop currentRunLoop];
  [c scheduleInRunLoop:loop forMode:mode];
  double began=now();
  if(start) [c start];
  while(!p.done && now()-began<timeout) [loop runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  double elapsed=now()-began;
  [c cancel]; [c unscheduleFromRunLoop:loop forMode:mode];
  NSUInteger callbacks=p.callbacks;
  double drain=now()+0.05;
  while(now()<drain) { [loop runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]]; [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]]; }
  BOOL ok=NO;
  if([expect isEqual:@"timeout"]) ok=!p.finished && elapsed>=timeout*0.85 && elapsed<timeout+0.5;
  else if([expect isEqual:@"error"]) ok=p.error!=nil && !p.finished;
  else if([expect isEqual:@"json"]) ok=p.finished && !p.error && p.status==200 && [NSJSONSerialization JSONObjectWithData:p.data options:0 error:NULL]!=nil;
  else ok=p.finished && !p.error && p.status==200 && [p.data isEqual:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
  ok=ok && callbacks==p.callbacks;
  NSDictionary *result=@{@"mode":mode,@"explicitStart":@(start),@"mainThread":@([NSThread isMainThread]),@"finished":@(p.finished),@"status":@(p.status),@"bytes":@(p.data.length),@"elapsed":@(elapsed),@"error":p.error ? [NSString stringWithFormat:@"%@:%ld",p.error.domain,(long)p.error.code] : @"",@"callbacksAfterCancel":@(p.callbacks-callbacks),@"pass":@(ok)};
  puts([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL] encoding:NSUTF8StringEncoding].UTF8String);
  if([expect isEqual:@"json"] && ok) { NSDictionary *json=[NSJSONSerialization JSONObjectWithData:p.data options:0 error:NULL]; if(json[@"jwks_uri"]) printf("JWKS=%s\n",[json[@"jwks_uri"] UTF8String]); }
  return ok?0:1;
}
int main(int argc,char **argv) { @autoreleasepool {
  if(argc!=7) return 2;
  NSString *url=@(argv[1]),*mode=strcmp(argv[2],"default")==0?NSDefaultRunLoopMode:@"Repro.Custom",*expect=@(argv[5]);
  BOOL start=atoi(argv[3]); double timeout=atof(argv[6]); __block int result=2;
  void (^work)(void)=^{ @autoreleasepool { int count=MAX(1,atoi(getenv("PROBE_REPEAT") ?: "1")); NSUInteger before=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/proc/self/fd" error:NULL] count]; result=0; for(int i=0;i<count;i++) { @autoreleasepool { result |= run(url,mode,start,expect,timeout); } } NSUInteger after=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/proc/self/fd" error:NULL] count]; if(count>1) printf("FD before=%lu after=%lu requests=%d\n",(unsigned long)before,(unsigned long)after,count); } };
  if(atoi(argv[4])) { NSOperationQueue *q=[NSOperationQueue new]; [q addOperationWithBlock:work]; [q waitUntilAllOperationsAreFinished]; } else work();
  return result;
} }
