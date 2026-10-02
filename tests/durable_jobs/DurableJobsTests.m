#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNPostgresJobAdapter.h"
#import "ALNJobsModule.h"
#import "ALNApplication.h"
#include <signal.h>
#include <poll.h>
#include <dispatch/dispatch.h>
#include <sys/stat.h>
#include <unistd.h>

@interface DJRuntime : NSObject <ALNJobWorkerRuntime>
@property(nonatomic, assign) NSTimeInterval duration;
@property(nonatomic, assign) BOOL fail;
@property(nonatomic, copy) void (^duringHandler)(ALNJobEnvelope *job);
@end
@implementation DJRuntime
- (ALNJobWorkerDisposition)handleJob:(ALNJobEnvelope *)job error:(NSError **)error {
  if (self.duringHandler) self.duringHandler(job);
  [NSThread sleepForTimeInterval:self.duration];
  if (self.fail) {
    if (error) *error = [NSError errorWithDomain:@"synthetic" code:1 userInfo:@{NSLocalizedDescriptionKey:@"synthetic failure"}];
    return ALNJobWorkerDispositionRetry;
  }
  return ALNJobWorkerDispositionAcknowledge;
}
- (id)jobWorker:(ALNJobWorker *)worker resultForJob:(ALNJobEnvelope *)job { return @{@"answer":@42}; }
@end

@interface DJDefinition : NSObject <ALNJobsJobDefinition>
@end
@implementation DJDefinition
- (NSString *)jobsModuleJobIdentifier { return @"synthetic.module"; }
- (NSDictionary *)jobsModuleJobMetadata { return @{@"queue":@"mail",@"maxAttempts":@2}; }
- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error { return YES; }
- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error { return NO; }
- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context result:(id *)result error:(NSError **)error {
  *result = @{@"queue":context[@"queue"],@"input":payload};
  return YES;
}
@end

@interface DurableJobsTests : XCTestCase
@property(nonatomic, strong) ALNPg *db;
@property(nonatomic, strong) ALNPostgresJobAdapter *adapter;
@property(nonatomic, copy) NSString *namespaceName;
@end
@implementation DurableJobsTests
- (void)setUp {
  [super setUp];
  NSString *dsn = [NSProcessInfo processInfo].environment[@"ARLEN_PG_TEST_DSN"];
  XCTAssertTrue((dsn.length > 0),@"run tools/ci/run_durable_jobs.sh (requires an isolated PostgreSQL cluster)");
  NSError *error = nil;
  self.db = [[ALNPg alloc] initWithConnectionString:dsn ?: @"" maxConnections:4 error:&error];
  XCTAssertNotNil((self.db),@"%@",(error));
  self.namespaceName = [[NSUUID UUID] UUIDString];
  self.adapter = [[ALNPostgresJobAdapter alloc] initWithDatabase:self.db namespace:self.namespaceName leaseDurationSeconds:0.6 error:&error];
  XCTAssertNotNil((self.adapter),@"%@",(error));
  XCTAssertTrue(([self.adapter installSchemaWithError:&error]),@"%@",(error));
}
- (void)tearDown {
  NSError *error = nil;
  XCTAssertTrue(([self.adapter resetWithError:&error]),@"%@",(error));
  [super tearDown];
}
- (ALNPostgresJobAdapter *)newAdapter {
  NSError *error = nil;
  ALNPg *db = [[ALNPg alloc] initWithConnectionString:self.db.connectionString maxConnections:3 error:&error];
  ALNPostgresJobAdapter *adapter = [[ALNPostgresJobAdapter alloc] initWithDatabase:db namespace:self.namespaceName leaseDurationSeconds:0.6 error:&error];
  XCTAssertNotNil((adapter),@"%@",(error));
  return adapter;
}
- (void)expire:(NSString *)jobID {
  NSError *error = nil;
  XCTAssertEqual(([self.db executeCommand:@"UPDATE arlen_jobs SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE namespace=$1 AND job_id=$2"
      parameters:@[self.namespaceName,jobID] error:&error]),(1),@"%@",(error));
}
- (NSString *)enqueue:(NSDictionary *)options {
  NSError *error = nil;
  NSString *jobID = [self.adapter enqueueJobNamed:@"synthetic" payload:@{@"nested":@[@1,@"two"]} options:options error:&error];
  XCTAssertNotNil((jobID),@"%@",(error));
  return jobID;
}
- (void)testTransactionalEnqueueRollbackAndCommit {
  NSError *error = nil;
  __block NSString *rolledBack = nil;
  XCTAssertFalse(([self.db withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c,NSError **txError) {
    rolledBack = [self.adapter enqueueJobNamed:@"transaction" payload:@{} options:nil onConnection:c error:txError];
    return NO;
  } error:&error]));
  XCTAssertNotNil((rolledBack));
  error = nil;
  XCTAssertNil(([self.adapter jobStatusForID:rolledBack error:&error]));
  XCTAssertNil((error));
  __block NSString *committed = nil;
  XCTAssertTrue(([self.db withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c,NSError **txError) {
    committed = [self.adapter enqueueJobNamed:@"transaction" payload:@{} options:nil onConnection:c error:txError];
    return committed != nil;
  } error:&error]),@"%@",(error));
  XCTAssertEqualObjects(([[self newAdapter] jobStatusForID:committed error:&error][@"state"]),@"pending");
}
- (void)testLeaseRecoveryFencesEveryMutationAndUsesDatabaseClock {
  NSString *jobID = [self enqueue:@{@"maxAttempts":@3}];
  NSError *error = nil;
  ALNJobLease *first = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertNotNil((first),@"%@",(error));
  XCTAssertEqualObjects((((ALNJobLease *)[first copy]).leaseToken),(first.leaseToken));
  ALNPostgresJobAdapter *secondAdapter = [self newAdapter];
  XCTAssertNil(([secondAdapter dequeueDueJobAt:[NSDate dateWithTimeIntervalSinceNow:30*86400] error:&error]));
  XCTAssertNil((error));
  XCTAssertTrue(([self.adapter renewJob:first error:&error]),@"%@",(error));
  [self expire:jobID];
  XCTAssertFalse(([self.adapter renewJob:first error:&error]));
  error = nil;
  ALNJobLease *second = (ALNJobLease *)[secondAdapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertEqualObjects((second.jobID),(first.jobID));
  XCTAssertNotEqualObjects((second.leaseToken),(first.leaseToken));
  XCTAssertEqual((second.attempt),(2u));
  XCTAssertFalse(([self.adapter completeJob:first result:@{} error:&error]));
  XCTAssertEqual((error.code),(604));
  error = nil;
  XCTAssertFalse(([self.adapter retryJob:first delaySeconds:0 error:&error]));
  error = nil;
  XCTAssertFalse(([self.adapter acknowledgeJobID:jobID error:&error]));
  XCTAssertEqual((error.code),(603));
  error = nil;
  XCTAssertTrue(([secondAdapter completeJob:second result:@{@"success":@YES} error:&error]),@"%@",(error));
  NSDictionary *status = [[self newAdapter] jobStatusForID:jobID error:&error];
  XCTAssertEqualObjects((status[@"state"]),@"completed");
  XCTAssertEqualObjects((status[@"result"]),(@{@"success":@YES}));
  XCTAssertNil((status[@"leaseToken"]));
}
- (void)testRetryBudgetBackoffAndReplayDeduplication {
  NSString *jobID = [self enqueue:@{@"maxAttempts":@2}];
  NSError *error = nil;
  ALNJobEnvelope *job = [self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertTrue(([self.adapter retryJob:job delaySeconds:60 failureMessage:@"try again" error:&error]));
  XCTAssertNil(([self.adapter dequeueDueJobAt:[NSDate date] error:&error]));
  job = [self.adapter dequeueDueJobAt:[NSDate dateWithTimeIntervalSinceNow:61] error:&error];
  XCTAssertEqual((job.attempt),(2u));
  XCTAssertTrue(([self.adapter retryJob:job delaySeconds:0 failureMessage:@"terminal" error:&error]));
  XCTAssertEqualObjects(([self.adapter jobStatusForID:jobID error:&error][@"failureMessage"]),@"terminal");
  XCTAssertEqual(([self.adapter deadLetterJobsSnapshot].count),(1u));
  NSString *replay = [self.adapter replayJobID:jobID idempotencyKey:@"replay-request" delaySeconds:0 error:&error];
  XCTAssertNotNil((replay),@"%@",(error));
  XCTAssertNotEqualObjects((replay),(jobID));
  job = [self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertEqual((job.attempt),(1u));
  XCTAssertTrue(([self.adapter completeJob:(ALNJobLease *)job result:@"done" error:&error]));
  XCTAssertEqualObjects(([[self newAdapter] replayJobID:jobID idempotencyKey:@"replay-request" delaySeconds:0 error:&error]),(replay));
  XCTAssertEqualObjects(([self.adapter jobStatusForID:replay error:&error][@"replayOf"]),(jobID));
}
- (void)testCrashedFinalAttemptBecomesTerminal {
  NSString *jobID = [self enqueue:@{@"maxAttempts":@1}];
  NSError *error = nil;
  XCTAssertNotNil(([self.adapter dequeueDueJobAt:[NSDate date] error:&error]));
  [self expire:jobID];
  XCTAssertNil(([[self newAdapter] dequeueDueJobAt:[NSDate date] error:&error]));
  XCTAssertNil((error));
  XCTAssertEqualObjects(([self.adapter jobStatusForID:jobID error:&error][@"state"]),@"failed");
}
- (void)testActiveAndRetainedDeduplicationAcrossRestart {
  NSError *error = nil;
  NSString *first = [self enqueue:@{@"idempotencyKey":@"active"}];
  XCTAssertEqualObjects(([[self newAdapter] enqueueJobNamed:@"synthetic" payload:@{} options:@{@"idempotencyKey":@"active"} error:&error]),(first));
  ALNJobLease *job = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertTrue(([self.adapter completeJob:job result:nil error:&error]));
  XCTAssertNotEqualObjects(([self enqueue:@{@"idempotencyKey":@"active"}]),(first));
  NSString *retained = [self enqueue:@{@"idempotencyKey":@"retained",@"retainDeduplication":@YES}];
  while ((job = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error])) {
    XCTAssertTrue(([self.adapter completeJob:job result:nil error:&error]));
  }
  XCTAssertEqualObjects(([[self newAdapter] enqueueJobNamed:@"synthetic" payload:@{} options:@{@"idempotencyKey":@"retained"} error:&error]),(retained));
}
- (void)testSharedPauseDrainAndNamespaceIsolation {
  NSError *error = nil;
  NSString *jobID = [self enqueue:@{@"queue":@"mail"}];
  ALNPostgresJobAdapter *other = [self newAdapter];
  XCTAssertTrue(([other setQueue:@"mail" state:@"paused" error:&error]));
  XCTAssertNil(([self.adapter dequeueDueJobAt:[NSDate date] error:&error]));
  XCTAssertEqualObjects(([self.adapter queueStatesWithError:&error][0][@"state"]),@"paused");
  XCTAssertTrue(([other setQueue:@"mail" state:@"draining" error:&error]));
  XCTAssertNil(([self.adapter enqueueJobNamed:@"mail" payload:@{} options:@{@"queue":@"mail"} error:&error]));
  XCTAssertEqual((error.code),(602));
  error = nil;
  ALNJobLease *job = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertEqualObjects((job.jobID),(jobID));
  XCTAssertTrue(([self.adapter completeJob:job result:nil error:&error]));
  XCTAssertNil(([self.adapter dequeueDueJobAt:[NSDate date] error:&error]));
  XCTAssertTrue(([other setQueue:@"mail" state:@"active" error:&error]));
  ALNPostgresJobAdapter *isolated = [[ALNPostgresJobAdapter alloc] initWithDatabase:self.db namespace:@"empty-other-namespace" leaseDurationSeconds:1 error:&error];
  XCTAssertNil(([isolated jobStatusForID:jobID error:&error]));
}
- (void)testWorkerHeartbeatsAndDurableResults {
  NSString *jobID = [self enqueue:nil];
  DJRuntime *runtime = [[DJRuntime alloc] init];
  runtime.duration = 1.8;
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:self.adapter];
  NSError *error = nil;
  ALNJobWorkerRunSummary *summary = [worker runDueJobsAt:[NSDate date] runtime:runtime error:&error];
  XCTAssertNotNil((summary),@"%@",(error));
  XCTAssertEqual((summary.acknowledgedCount),(1u));
  XCTAssertEqualObjects(([[self newAdapter] jobStatusForID:jobID error:&error][@"result"]),(@{@"answer":@42}));
}
- (void)testWorkerLeaseLossDoesNotComplete {
  NSString *jobID = [self enqueue:nil];
  DJRuntime *runtime = [[DJRuntime alloc] init];
  runtime.duration = 0.4;
  runtime.duringHandler = ^(ALNJobEnvelope *job) { [self expire:job.jobID]; };
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:self.adapter];
  NSError *error = nil;
  XCTAssertNil(([worker runDueJobsAt:[NSDate date] runtime:runtime error:&error]));
  XCTAssertEqual((error.code),(505));
  error = nil;
  XCTAssertEqualObjects(([self.adapter jobStatusForID:jobID error:&error][@"state"]),@"leased");
}
- (NSTask *)startProbe:(NSString *)action {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"build/durable-job-probe"];
  task.arguments = @[action,self.namespaceName];
  task.standardOutput = [NSPipe pipe];
  [task launch];
  return task;
}
- (NSArray *)finishProbe:(NSTask *)task {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
  while (task.isRunning && [deadline timeIntervalSinceNow] > 0) [NSThread sleepForTimeInterval:0.02];
  if (task.isRunning) { kill(task.processIdentifier,SIGKILL); XCTFail(@"job probe timed out"); }
  [task waitUntilExit];
  XCTAssertEqual((task.terminationStatus),(0));
  NSData *data = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSMutableArray *ids = [[output componentsSeparatedByString:@"\n"] mutableCopy];
  [ids removeObject:@""];
  return ids;
}
- (void)testIndependentProducersConsumersAndDuplicateEnqueue {
  NSMutableArray *tasks = [NSMutableArray array];
  for (int i=0;i<4;i++) [tasks addObject:[self startProbe:@"produce"]];
  NSMutableArray *accepted = [NSMutableArray array];
  for (NSTask *task in tasks) [accepted addObjectsFromArray:[self finishProbe:task]];
  XCTAssertEqual((accepted.count),(100u));
  XCTAssertEqual(([NSSet setWithArray:accepted].count),(100u));
  NSError *error = nil;
  NSArray *pending = [self.adapter jobsWithState:@"pending" error:&error];
  XCTAssertEqualObjects(([NSSet setWithArray:[pending valueForKey:@"jobID"]]),([NSSet setWithArray:accepted]));
  [tasks removeAllObjects];
  for (int i=0;i<4;i++) [tasks addObject:[self startProbe:@"consume"]];
  NSMutableArray *completed = [NSMutableArray array];
  for (NSTask *task in tasks) [completed addObjectsFromArray:[self finishProbe:task]];
  XCTAssertEqual((completed.count),(100u));
  XCTAssertEqualObjects(([NSSet setWithArray:completed]),([NSSet setWithArray:accepted]));
  XCTAssertEqual(([self.adapter jobsWithState:@"completed" error:&error].count),(100u));
  [tasks removeAllObjects];
  for (int i=0;i<4;i++) [tasks addObject:[self startProbe:@"duplicate"]];
  NSMutableArray *duplicates = [NSMutableArray array];
  for (NSTask *task in tasks) [duplicates addObjectsFromArray:[self finishProbe:task]];
  XCTAssertEqual((duplicates.count),(4u));
  XCTAssertEqual(([NSSet setWithArray:duplicates].count),(1u));
}
- (void)testKilledWorkerRecovery {
  NSString *jobID = [self enqueue:nil];
  NSTask *task = [self startProbe:@"crash"];
  struct pollfd readiness = { .fd = [[task.standardOutput fileHandleForReading] fileDescriptor], .events = POLLIN };
  int readyCount = poll(&readiness, 1, 20000);
  if (readyCount <= 0) {
    kill(task.processIdentifier,SIGKILL);
    [task waitUntilExit];
    XCTFail(@"worker failed to report its lease within 20 seconds");
    return;
  }
  NSData *ready = [[task.standardOutput fileHandleForReading] availableData];
  XCTAssertTrue((ready.length > 0));
  kill(task.processIdentifier,SIGKILL);
  [task waitUntilExit];
  [self expire:jobID];
  NSArray *completed = [self finishProbe:[self startProbe:@"consume"]];
  XCTAssertEqualObjects((completed),(@[jobID]));
  NSError *error = nil;
  XCTAssertEqualObjects(([self.adapter jobStatusForID:jobID error:&error][@"attempt"]),(@2));
}
- (void)testFileQueuePrivateInitializationAndRestart {
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *path = [root stringByAppendingPathComponent:@"nested/queue.plist"];
  NSError *error = nil;
  ALNFileJobAdapter *file = [[ALNFileJobAdapter alloc] initWithStoragePath:path adapterName:@"private" error:&error];
  XCTAssertNotNil((file),@"%@",(error));
  NSString *jobID = [file enqueueJobNamed:@"private" payload:@{} options:nil error:&error];
  XCTAssertNotNil((jobID),@"%@",(error));
  struct stat info;
  XCTAssertEqual((stat([[path stringByDeletingLastPathComponent] fileSystemRepresentation],&info)),(0));
  XCTAssertEqual((info.st_mode & 0777),(0700u));
  XCTAssertEqual((stat([path fileSystemRepresentation],&info)),(0));
  XCTAssertEqual((info.st_mode & 0777),(0600u));
  file = [[ALNFileJobAdapter alloc] initWithStoragePath:path adapterName:@"private" error:&error];
  XCTAssertEqualObjects((((ALNJobEnvelope *)[file.pendingJobsSnapshot firstObject]).jobID),(jobID));
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}
- (void)testModuleTransactionalPayloadQueuesAndResults {
  NSDictionary *config = @{@"environment":@"test", @"jobsModule":@{@"persistence":@{@"enabled":@NO}}};
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  [app setJobsAdapter:self.adapter];
  ALNJobsModuleRuntime *runtime = [[ALNJobsModuleRuntime alloc] init];
  NSError *error = nil;
  XCTAssertTrue([runtime configureWithApplication:app error:&error], @"%@",error);
  XCTAssertTrue([runtime registerSystemJobDefinition:[[DJDefinition alloc] init] error:&error], @"%@",error);
  __block NSString *jobID = nil;
  XCTAssertTrue(([self.db withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c,NSError **txError) {
    jobID = [runtime enqueueJobIdentifier:@"synthetic.module" payload:@{@"value":@7} options:nil onConnection:c error:txError];
    return jobID != nil;
  } error:&error]), @"%@",error);
  ALNPostgresJobAdapter *other = [self newAdapter];
  XCTAssertTrue([other setQueue:@"mail" state:@"paused" error:&error]);
  XCTAssertTrue([runtime isQueuePaused:@"mail"]);
  XCTAssertNotNil([runtime runWorkerAt:[NSDate date] limit:1 error:&error]);
  XCTAssertEqualObjects([self.adapter jobStatusForID:jobID error:&error][@"state"],@"pending");
  XCTAssertTrue([runtime resumeQueueNamed:@"mail" error:&error]);
  NSDictionary *run = [runtime runWorkerAt:[NSDate date] limit:1 error:&error];
  XCTAssertNotNil(run,@"%@",error);
  XCTAssertEqualObjects(run[@"acknowledgedCount"],@1);
  NSDictionary *status = [other jobStatusForID:jobID error:&error];
  XCTAssertEqualObjects((status[@"result"]),(@{@"queue":@"mail",@"input":@{@"value":@7}}));
}
- (void)testWorkerRetryPreservesFailureAndAttemptLimit {
  NSString *jobID = [self enqueue:@{@"maxAttempts":@1}];
  DJRuntime *runtime = [[DJRuntime alloc] init];
  runtime.fail = YES;
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:self.adapter];
  NSError *error = nil;
  XCTAssertNotNil([worker runDueJobsAt:[NSDate date] runtime:runtime error:&error],@"%@",error);
  NSDictionary *status = [self.adapter jobStatusForID:jobID error:&error];
  XCTAssertEqualObjects(status[@"state"],@"failed");
  XCTAssertEqualObjects(status[@"failureMessage"],@"synthetic failure");
}
- (int)pgControl:(NSArray *)arguments {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = [[NSProcessInfo processInfo].environment[@"ARLEN_JOBS_TEST_PG_BIN"] stringByAppendingPathComponent:@"pg_ctl"];
  task.arguments = [arguments arrayByAddingObjectsFromArray:@[@"-t",@"10"]];
  task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
  [task launch];
  [task waitUntilExit];
  return task.terminationStatus;
}
- (void)testDatabaseOutageAndRestartPreserveWork {
  NSString *data = [NSProcessInfo processInfo].environment[@"ARLEN_JOBS_TEST_PG_DATA"];
  // Never stop a caller's application database. This test only accepts our disposable cluster.
  XCTAssertTrue([data hasPrefix:@"/tmp/arlen-jobs-pg."]);
  if (![data hasPrefix:@"/tmp/arlen-jobs-pg."]) return;
  NSString *jobID = [self enqueue:@{@"idempotencyKey":@"outage",@"retainDeduplication":@YES}];
  NSError *error = nil;
  ALNJobLease *lease = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertNotNil(lease);
  XCTAssertEqual(([self pgControl:@[@"-D",data,@"-m",@"immediate",@"-w",@"stop"]]),0);
  @try {
    error = nil;
    XCTAssertNil([self.adapter dequeueDueJobAt:[NSDate date] error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertNil([self.adapter jobStatusForID:jobID error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse([self.adapter completeJob:lease result:@{} error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertFalse([self.adapter renewJob:lease error:&error]);
    XCTAssertNotNil(error);
    error = nil;
    XCTAssertNil([self.adapter enqueueJobNamed:@"outage" payload:@{} options:nil error:&error]);
    XCTAssertNotNil(error);
  } @finally {
    NSString *log = [[data stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"server.log"];
    NSString *socket = [[data stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"socket"];
    NSString *options = [NSString stringWithFormat:@"-k %@ -c listen_addresses=''",socket];
    XCTAssertEqual(([self pgControl:@[@"-D",data,@"-l",log,@"-o",options,@"-w",@"start"]]),0);
  }
  // Recreate the client as a restarted worker would; retained key resolves ambiguous enqueue outcomes.
  self.adapter = [self newAdapter];
  error = nil;
  [self expire:jobID];
  ALNJobLease *recovered = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertNotNil(recovered,@"%@",error);
  XCTAssertEqualObjects(recovered.jobID,jobID);
  XCTAssertTrue([self.adapter completeJob:recovered result:@"recovered" error:&error],@"%@",error);
  XCTAssertEqualObjects(([self.adapter enqueueJobNamed:@"outage" payload:@{} options:@{@"idempotencyKey":@"outage"} error:&error]),jobID);
}
- (void)testFileQueueRejectsSymlinkDirectory {
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *target = [root stringByAppendingPathComponent:@"target"];
  NSError *error = nil;
  // Create the target through the fixed adapter, then attempt initialization through a symlink.
  ALNFileJobAdapter *file = [[ALNFileJobAdapter alloc] initWithStoragePath:[target stringByAppendingPathComponent:@"queue"] adapterName:@"target" error:&error];
  XCTAssertNotNil(file,@"%@",error);
  NSString *link = [root stringByAppendingPathComponent:@"link"];
  XCTAssertEqual(symlink(target.fileSystemRepresentation,link.fileSystemRepresentation),0);
  error = nil;
  XCTAssertNil([[ALNFileJobAdapter alloc] initWithStoragePath:[link stringByAppendingPathComponent:@"queue"] adapterName:@"link" error:&error]);
  XCTAssertNotNil(error);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}
- (void)testSchemaMigrationMatchesProgrammaticInstaller {
  NSString *path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"tools/migrations/jobs/001_postgres_jobs.sql"];
  NSError *error = nil;
  NSString *sql = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(sql,@"%@",error);
  NSString *expected = [NSString stringWithFormat:
      @"-- Arlen durable jobs schema v1. Keep in sync with +schemaStatements.\nBEGIN;\nSELECT pg_advisory_xact_lock(714182639041);\n%@;\nCOMMIT;\n",
      [[ALNPostgresJobAdapter schemaStatements] componentsJoinedByString:@";\n"]];
  XCTAssertEqualObjects(sql,expected);
  XCTAssertTrue([self.adapter installSchemaWithError:&error],@"%@",error);
}
- (void)testInvalidOptionsAndResultsFailWithoutCompletingWork {
  NSArray *invalidOptions = @[@{@"maxAttempts":@0},@{@"maxAttempts":@1.5},@{@"maxAttempts":@[]},
      @{@"notBefore":@"tomorrow"},@{@"queue":@[]},@{@"retainDeduplication":@[]}];
  for (NSDictionary *options in invalidOptions) {
    NSError *error = nil;
    XCTAssertNil([self.adapter enqueueJobNamed:@"bad" payload:@{} options:options error:&error]);
    XCTAssertNotNil(error);
  }
  XCTAssertEqual([self.adapter pendingJobsSnapshot].count,0u);
  NSString *jobID = [self enqueue:nil];
  NSError *error = nil;
  ALNJobLease *job = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertFalse([self.adapter completeJob:job result:[NSDate date] error:&error]);
  XCTAssertNotNil(error);
  error = nil;
  XCTAssertEqualObjects([self.adapter jobStatusForID:jobID error:&error][@"state"],@"leased");
}
- (void)testReplayKeyCannotResolveAnotherSource {
  NSString *first = [self enqueue:nil];
  NSString *second = [self enqueue:nil];
  NSError *error = nil;
  for (int i=0;i<2;i++) {
    ALNJobLease *job = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
    XCTAssertTrue([self.adapter completeJob:job result:nil error:&error]);
  }
  XCTAssertNotNil([self.adapter replayJobID:first idempotencyKey:@"same-replay" delaySeconds:0 error:&error]);
  XCTAssertNil([self.adapter replayJobID:second idempotencyKey:@"same-replay" delaySeconds:0 error:&error]);
  XCTAssertEqual(error.code,606);
}
- (void)testLeaseExpirationIsCheckedAfterWaitingForRowLock {
  NSString *jobID = [self enqueue:nil];
  NSError *error = nil;
  ALNJobLease *job = (ALNJobLease *)[self.adapter dequeueDueJobAt:[NSDate date] error:&error];
  ALNPgConnection *blocker = [self.db acquireConnection:&error];
  XCTAssertTrue([blocker beginTransaction:&error]);
  XCTAssertNotNil(([blocker executeQuery:@"SELECT job_id FROM arlen_jobs WHERE namespace=$1 AND job_id=$2 FOR UPDATE"
      parameters:@[self.namespaceName,jobID] error:&error]));
  ALNPostgresJobAdapter *other = [self newAdapter];
  __block BOOL completed = YES;
  __block NSError *completionError = nil;
  dispatch_group_t group = dispatch_group_create();
  dispatch_group_async(group,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
    @autoreleasepool { completed = [other completeJob:job result:@"too late" error:&completionError]; }
  });
  @try {
    BOOL waiting = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!waiting && [deadline timeIntervalSinceNow] > 0) {
      NSArray *rows = [self.db executeQuery:@"SELECT count(*) AS waiting FROM pg_stat_activity WHERE wait_event_type='Lock' AND query LIKE '%arlen_jobs%'"
          parameters:@[] error:&error];
      waiting = [rows[0][@"waiting"] integerValue] > 0;
      if (!waiting) [NSThread sleepForTimeInterval:0.01];
    }
    XCTAssertTrue(waiting,@"completion must encounter the held row lock");
    [NSThread sleepForTimeInterval:0.8];
  } @finally {
    XCTAssertTrue([blocker commitTransaction:&error]);
    [self.db releaseConnection:blocker];
  }
  XCTAssertEqual(dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC)),0L);
  XCTAssertFalse(completed);
  XCTAssertEqual(completionError.code,604);
}
- (void)testDurableOperatorRoutesRequireAdminAndStepUp {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test",
      @"jobsModule":@{@"persistence":@{@"enabled":@NO}}}];
  [app setJobsAdapter:self.adapter];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error],@"%@",error);
  NSSet *names = [NSSet setWithArray:@[@"jobs_api_status",@"jobs_api_queue_drain",@"jobs_api_dead_letter_replay"]];
  NSUInteger found = 0;
  for (NSDictionary *route in [app routeTable]) {
    if (![names containsObject:route[@"name"]]) continue;
    found++;
    XCTAssertEqualObjects(route[@"requiredRoles"],(@[@"admin"]));
    XCTAssertEqualObjects(route[@"minimumAuthAssuranceLevel"],@2);
  }
  XCTAssertEqual(found,names.count);
}
// OT's review reproducer, extended to verify eventual terminal cleanup and
// to exercise both same-queue and cross-queue isolation while the lock is held.
- (void)assertPendingWorkSkipsLockedExpiredFinalAttemptInQueue:(NSString *)queue {
  NSString *expired = [self enqueue:@{@"maxAttempts":@1}];
  NSError *error = nil;
  XCTAssertNotNil([self.adapter dequeueDueJobAt:[NSDate date] error:&error]);
  [self expire:expired];
  NSString *pending = [self enqueue:@{@"queue":queue}];
  ALNPgConnection *blocker = [self.db acquireConnection:&error];
  XCTAssertTrue([blocker beginTransaction:&error]);
  XCTAssertNotNil(([blocker executeQuery:@"SELECT job_id FROM arlen_jobs WHERE namespace=$1 AND job_id=$2 FOR UPDATE"
      parameters:@[self.namespaceName,expired] error:&error]));
  ALNPostgresJobAdapter *other = [self adapterWithShortLockTimeout];
  @try {
    error = nil;
    ALNJobEnvelope *claimed = [other dequeueDueJobAt:[NSDate date] error:&error];
    XCTAssertNil(error,@"locked cleanup must not fail the claim: %@",error);
    XCTAssertNotNil(claimed,@"unrelated work must remain claimable while the blocker is open");
    XCTAssertEqualObjects(claimed.jobID,pending);
    error = nil;
    XCTAssertEqualObjects([other jobStatusForID:expired error:&error][@"state"],@"leased");
  } @finally {
    NSError *cleanup = nil;
    XCTAssertTrue([blocker rollbackTransaction:&cleanup],@"%@",cleanup);
    [self.db releaseConnection:blocker];
  }
  error = nil;
  [other dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertNil(error,@"%@",error);
  XCTAssertEqualObjects([other jobStatusForID:expired error:&error][@"state"],@"failed");
}
- (ALNPostgresJobAdapter *)adapterWithShortLockTimeout {
  NSError *error = nil;
  NSString *dsn = [self.db.connectionString stringByAppendingString:@" options='-c lock_timeout=250ms'"];
  ALNPg *db = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];
  ALNPostgresJobAdapter *adapter = [[ALNPostgresJobAdapter alloc] initWithDatabase:db
      namespace:self.namespaceName leaseDurationSeconds:60 error:&error];
  XCTAssertNotNil(adapter,@"%@",error);
  return adapter;
}
- (void)testUnrelatedPendingWorkSkipsLockedExpiredFinalAttempt {
  [self assertPendingWorkSkipsLockedExpiredFinalAttemptInQueue:@"default"];
}
- (void)testOtherQueueSkipsLockedExpiredFinalAttempt {
  [self assertPendingWorkSkipsLockedExpiredFinalAttemptInQueue:@"other"];
}
- (void)testTerminalCleanupIsBoundedAndEventuallyDrainsBacklog {
  ALNPostgresJobAdapter *other = [self adapterWithShortLockTimeout];
  NSError *error = nil;
  // Longer leases keep setup independent of elapsed time; expire them together.
  for (NSUInteger i = 0; i < 205; i++) {
    NSString *jobID = [other enqueueJobNamed:@"synthetic" payload:@{}
        options:@{@"queue":@"cleanup",@"maxAttempts":@1} error:&error];
    XCTAssertNotNil(jobID,@"%@",error);
    ALNJobEnvelope *lease = [other dequeueDueJobAt:[NSDate date] error:&error];
    XCTAssertEqualObjects(lease.jobID,jobID);
  }
  XCTAssertTrue([other setQueue:@"cleanup" state:@"paused" error:&error]);
  XCTAssertEqual(([self.db executeCommand:@"UPDATE arlen_jobs SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE namespace=$1"
      parameters:@[self.namespaceName] error:&error]),205);
  NSString *pending = [self enqueue:@{@"queue":@"work"}];
  ALNJobLease *claimed = (ALNJobLease *)[other dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertNil(error,@"%@",error);
  XCTAssertEqualObjects(claimed.jobID,pending);
  XCTAssertEqual([other jobsWithState:@"failed" error:&error].count,100u);
  XCTAssertTrue([other completeJob:claimed result:nil error:&error],@"%@",error);
  XCTAssertNil([other dequeueDueJobAt:[NSDate date] error:&error]);
  XCTAssertEqual([other jobsWithState:@"failed" error:&error].count,200u);
  XCTAssertNil([other dequeueDueJobAt:[NSDate date] error:&error]);
  XCTAssertNil(error,@"%@",error);
  XCTAssertEqual([other jobsWithState:@"failed" error:&error].count,205u);
  XCTAssertEqual([other jobsWithState:@"leased" error:&error].count,0u);
}
- (void)testTerminalCleanupPreservesLiveAndRetryableLeases {
  ALNPostgresJobAdapter *other = [self adapterWithShortLockTimeout];
  NSError *error = nil;
  NSString *live = [self enqueue:@{@"maxAttempts":@1}];
  ALNJobEnvelope *liveLease = [other dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertEqualObjects(liveLease.jobID,live);
  NSString *retryable = [self enqueue:@{@"maxAttempts":@2}];
  XCTAssertEqualObjects([other dequeueDueJobAt:[NSDate date] error:&error].jobID,retryable);
  [self expire:retryable];
  XCTAssertTrue([other setQueue:@"default" state:@"paused" error:&error]);
  XCTAssertNil([other dequeueDueJobAt:[NSDate date] error:&error]);
  XCTAssertNil(error,@"%@",error);
  XCTAssertEqualObjects([other jobStatusForID:live error:&error][@"state"],@"leased");
  XCTAssertEqualObjects([other jobStatusForID:retryable error:&error][@"state"],@"leased");
  XCTAssertTrue([other setQueue:@"default" state:@"active" error:&error]);
  ALNJobEnvelope *reclaimed = [other dequeueDueJobAt:[NSDate date] error:&error];
  XCTAssertEqualObjects(reclaimed.jobID,retryable);
  XCTAssertEqual(reclaimed.attempt,2u);
  XCTAssertEqualObjects([other jobStatusForID:live error:&error][@"state"],@"leased");
}
- (void)testBusyQueueControlDoesNotBlockOtherQueues {
  NSString *busyJob = [self enqueue:@{@"queue":@"busy"}];
  NSString *availableJob = [self enqueue:@{@"queue":@"available"}];
  NSError *error = nil;
  ALNPgConnection *blocker = [self.db acquireConnection:&error];
  XCTAssertTrue([blocker beginTransaction:&error]);
  XCTAssertNotNil(([blocker executeQuery:@"SELECT queue FROM arlen_job_queues WHERE namespace=$1 AND queue='busy' FOR UPDATE"
      parameters:@[self.namespaceName] error:&error]));
  ALNPostgresJobAdapter *other = [self adapterWithShortLockTimeout];
  @try {
    ALNJobLease *claimed = (ALNJobLease *)[other dequeueDueJobAt:[NSDate date] error:&error];
    XCTAssertNil(error,@"busy control row must not block other queues: %@",error);
    XCTAssertEqualObjects(claimed.jobID,availableJob);
    error = nil;
    XCTAssertEqualObjects([other jobStatusForID:busyJob error:&error][@"state"],@"pending");
  } @finally {
    NSError *cleanup = nil;
    XCTAssertTrue([blocker rollbackTransaction:&cleanup],@"%@",cleanup);
    [self.db releaseConnection:blocker];
  }
  error = nil;
  XCTAssertEqualObjects([other dequeueDueJobAt:[NSDate date] error:&error].jobID,busyJob);
  XCTAssertNil(error,@"%@",error);
}
@end
