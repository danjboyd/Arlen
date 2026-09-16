#import "ALNPostgresJobAdapter.h"
#import <math.h>
#import "ALNJSONSerialization.h"

static BOOL PJFail(NSError **error, NSInteger code, NSString *message) {
  if (error) *error = [NSError errorWithDomain:ALNServiceErrorDomain code:code
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
  return NO;
}
static NSString *PJString(id value) {
  return [value isKindOfClass:[NSString class]] ? value : @"";
}
static NSString *PJJSON(id value, NSError **error) {
  if (![ALNJSONSerialization isValidJSONObject:value]) {
    PJFail(error, 610, @"job payload/result must be JSON serializable");
    return nil;
  }
  NSData *data = [ALNJSONSerialization dataWithJSONObject:value options:0 error:error];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}
static NSString *PJColumns(void) {
  return @"job_id, name, payload, queue, state, attempt, max_attempts, sequence, "
          "EXTRACT(EPOCH FROM not_before)::double precision AS due, "
          "EXTRACT(EPOCH FROM created_at)::double precision AS created, "
          "EXTRACT(EPOCH FROM lease_expires_at)::double precision AS expires, "
          "lease_token, result, failure_message, replay_of";
}
static ALNJobEnvelope *PJEnvelope(NSDictionary *row, NSTimeInterval duration) {
  ALNJobEnvelope *envelope = [[ALNJobEnvelope alloc]
      initWithJobID:row[@"job_id"] name:row[@"name"] payload:row[@"payload"]
      attempt:[row[@"attempt"] unsignedIntegerValue] maxAttempts:[row[@"max_attempts"] unsignedIntegerValue]
      notBefore:[NSDate dateWithTimeIntervalSince1970:[row[@"due"] doubleValue]]
      createdAt:[NSDate dateWithTimeIntervalSince1970:[row[@"created"] doubleValue]]
      sequence:[row[@"sequence"] unsignedIntegerValue]];
  if ([row[@"state"] isEqual:@"leased"]) {
    return [[ALNJobLease alloc] initWithEnvelope:envelope leaseToken:row[@"lease_token"]
        leaseExpiresAt:[NSDate dateWithTimeIntervalSince1970:[row[@"expires"] doubleValue]]
        leaseDurationSeconds:duration];
  }
  return envelope;
}

@implementation ALNPostgresJobAdapter

- (instancetype)initWithDatabase:(ALNPg *)database namespace:(NSString *)namespaceName
           leaseDurationSeconds:(NSTimeInterval)leaseDurationSeconds error:(NSError **)error {
  if (!database || [PJString(namespaceName) length] == 0 || [namespaceName length] > 200 ||
      !isfinite(leaseDurationSeconds) || leaseDurationSeconds < 0.3 || leaseDurationSeconds > 86400) {
    PJFail(error, 600, @"PostgreSQL jobs require a database, namespace (1–200 characters), and lease duration (0.3–86400 seconds)");
    return nil;
  }
  self = [super init];
  if (self) {
    _database = database;
    _namespaceName = [namespaceName copy];
    _leaseDurationSeconds = leaseDurationSeconds;
  }
  return self;
}
- (NSString *)adapterName { return @"postgres_jobs"; }

+ (NSArray<NSString *> *)schemaStatements {
  return @[
    (@"CREATE TABLE IF NOT EXISTS arlen_job_schema (version integer PRIMARY KEY CHECK (version = 1))"),
    (@"INSERT INTO arlen_job_schema(version) VALUES(1) ON CONFLICT DO NOTHING"),
    (@"CREATE TABLE IF NOT EXISTS arlen_job_queues (namespace text NOT NULL, queue text NOT NULL, "
     "state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','paused','draining')), PRIMARY KEY(namespace,queue))"),
    (@"CREATE TABLE IF NOT EXISTS arlen_jobs (namespace text NOT NULL, job_id text NOT NULL, "
     "sequence bigserial NOT NULL, name text NOT NULL, payload jsonb NOT NULL, queue text NOT NULL, "
     "state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','leased','completed','failed')), "
     "attempt integer NOT NULL DEFAULT 0 CHECK(attempt >= 0), max_attempts integer NOT NULL CHECK(max_attempts > 0), "
     "not_before timestamptz NOT NULL DEFAULT clock_timestamp(), created_at timestamptz NOT NULL DEFAULT clock_timestamp(), "
     "updated_at timestamptz NOT NULL DEFAULT clock_timestamp(), lease_token text, lease_expires_at timestamptz, "
     "idempotency_key text, retain_deduplication boolean NOT NULL DEFAULT false, result jsonb, failure_message text, replay_of text, "
     "PRIMARY KEY(namespace,job_id), FOREIGN KEY(namespace,queue) REFERENCES arlen_job_queues(namespace,queue), "
     "CHECK ((state = 'leased') = (lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)))"),
    (@"CREATE UNIQUE INDEX IF NOT EXISTS arlen_jobs_deduplication ON arlen_jobs(namespace,idempotency_key) "
     "WHERE idempotency_key IS NOT NULL AND (state IN ('pending','leased') OR retain_deduplication)"),
    (@"CREATE INDEX IF NOT EXISTS arlen_jobs_due ON arlen_jobs(namespace,queue,not_before,sequence) WHERE state = 'pending'"),
    (@"CREATE INDEX IF NOT EXISTS arlen_jobs_expiry ON arlen_jobs(namespace,lease_expires_at) WHERE state = 'leased'")
  ];
}
- (BOOL)installSchemaWithError:(NSError **)error {
  return [self.database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection, NSError **txError) {
    if ([connection executeQuery:@"SELECT pg_advisory_xact_lock(714182639041)" parameters:@[] error:txError] == nil) return NO;
    for (NSString *sql in [[self class] schemaStatements]) {
      if ([connection executeCommand:sql parameters:@[] error:txError] < 0) return NO;
    }
    return YES;
  } error:error];
}
- (NSString *)enqueueJobNamed:(NSString *)name payload:(NSDictionary *)payload
                     options:(NSDictionary *)options error:(NSError **)error {
  __block NSString *jobID = nil;
  BOOL ok = [self.database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection, NSError **txError) {
    jobID = [self enqueueJobNamed:name payload:payload options:options onConnection:connection error:txError];
    return jobID != nil;
  } error:error];
  return ok ? jobID : nil;
}
- (NSString *)enqueueJobNamed:(NSString *)name payload:(NSDictionary *)payload options:(NSDictionary *)options
                onConnection:(id<ALNDatabaseConnection>)connection error:(NSError **)error {
  if ((options && ![options isKindOfClass:[NSDictionary class]]) ||
      (payload && ![payload isKindOfClass:[NSDictionary class]])) {
    PJFail(error, 601, @"payload and options must be dictionaries"); return nil;
  }
  for (NSString *option in @[@"queue", @"idempotencyKey", @"replayOf"]) {
    if (options[option] && ![options[option] isKindOfClass:[NSString class]]) {
      PJFail(error, 601, @"queue, idempotencyKey, and replayOf must be strings"); return nil;
    }
  }
  if ((options[@"maxAttempts"] && ![options[@"maxAttempts"] isKindOfClass:[NSNumber class]]) ||
      (options[@"retainDeduplication"] && ![options[@"retainDeduplication"] isKindOfClass:[NSNumber class]]) ||
      (options[@"notBefore"] && ![options[@"notBefore"] isKindOfClass:[NSDate class]] &&
       ![options[@"notBefore"] isKindOfClass:[NSNumber class]])) {
    PJFail(error, 601, @"maxAttempts/retainDeduplication must be numbers; notBefore must be a date or numeric delay"); return nil;
  }
  NSString *queue = PJString(options[@"queue"]);
  if (queue.length == 0) queue = @"default";
  double attemptValue = options[@"maxAttempts"] ? [options[@"maxAttempts"] doubleValue] : 3;
  if (PJString(name).length == 0 || !isfinite(attemptValue) || attemptValue < 1 || attemptValue > INT_MAX ||
      floor(attemptValue) != attemptValue || queue.length > 200) {
    PJFail(error, 601, @"job name, queue, or maxAttempts is invalid"); return nil;
  }
  NSInteger attempts = (NSInteger)attemptValue;
  NSString *json = PJJSON(payload ?: @{}, error);
  if (!json) return nil;
  NSString *key = PJString(options[@"idempotencyKey"]);
  // Serialize identical enqueue requests, including across independent processes.
  if (key.length && ![connection executeQuery:@"SELECT pg_advisory_xact_lock(hashtextextended($1, 0))"
      parameters:@[[NSString stringWithFormat:@"%@:%lu:%@", self.namespaceName, (unsigned long)key.length, key]] error:error]) return nil;
  if (key.length) {
    NSArray *existing = [connection executeQuery:@"SELECT job_id FROM arlen_jobs WHERE namespace=$1 AND idempotency_key=$2 "
        "AND (state IN ('pending','leased') OR retain_deduplication)" parameters:@[self.namespaceName,key] error:error];
    if (!existing) return nil;
    if (existing.count) return existing[0][@"job_id"];
  }
  if ([connection executeCommand:@"INSERT INTO arlen_job_queues(namespace,queue) VALUES($1,$2) ON CONFLICT DO NOTHING"
      parameters:@[self.namespaceName,queue] error:error] < 0) return nil;
  NSDictionary *queueRow = [connection executeQueryOne:@"SELECT state FROM arlen_job_queues WHERE namespace=$1 AND queue=$2 FOR SHARE"
      parameters:@[self.namespaceName,queue] error:error];
  if (!queueRow) return nil;
  if ([queueRow[@"state"] isEqual:@"draining"]) {
    PJFail(error, 602, @"queue is draining; new jobs are rejected"); return nil;
  }
  id due = options[@"notBefore"];
  BOOL absolute = [due isKindOfClass:[NSDate class]];
  double seconds = absolute ? [due timeIntervalSince1970] : (due ? [due doubleValue] : 0);
  if (!isfinite(seconds)) { PJFail(error, 601, @"notBefore must be finite"); return nil; }
  NSString *jobID = [[NSUUID UUID] UUIDString];
  NSArray *rows = [connection executeQuery:@"INSERT INTO arlen_jobs(namespace,job_id,name,payload,queue,max_attempts,not_before,"
      "idempotency_key,retain_deduplication,replay_of) VALUES($1,$2,$3,$4::jsonb,$5,$6,"
      "CASE WHEN $7::boolean THEN to_timestamp($8::double precision) ELSE clock_timestamp()+($8::double precision * interval '1 second') END,"
      "$9,$10::boolean,$11) RETURNING job_id"
      parameters:@[self.namespaceName,jobID,name,json,queue,@(attempts),@(absolute),@(seconds),
                   key.length ? key : [NSNull null], @([options[@"retainDeduplication"] boolValue]),
                   options[@"replayOf"] ?: [NSNull null]] error:error];
  return rows.count ? rows[0][@"job_id"] : nil;
}

- (ALNJobEnvelope *)dequeueDueJobAt:(NSDate *)timestamp error:(NSError **)error {
  __block ALNJobEnvelope *job = nil;
  BOOL ok = [self.database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c, NSError **txError) {
    // Expiration uses database time, never a caller's scheduling timestamp.
    if ([c executeCommand:@"UPDATE arlen_jobs SET state='failed', lease_token=NULL, lease_expires_at=NULL, "
        "failure_message='worker lease expired at attempt limit', updated_at=clock_timestamp() "
        "WHERE namespace=$1 AND state='leased' AND lease_expires_at<=clock_timestamp() AND attempt>=max_attempts"
        parameters:@[self.namespaceName] error:txError] < 0) return NO;
    // Queue locks make pause/drain linearizable with claims and enqueues.
    NSArray *queues = [c executeQuery:@"SELECT queue FROM arlen_job_queues WHERE namespace=$1 AND state IN ('active','draining') ORDER BY queue FOR SHARE"
        parameters:@[self.namespaceName] error:txError];
    if (!queues) return NO;
    if (!queues.count) return YES;
    NSArray *rows = [c executeQuery:[NSString stringWithFormat:
        @"SELECT %@ FROM arlen_jobs WHERE namespace=$1 AND queue IN "
         "(SELECT jsonb_array_elements_text($3::jsonb)) AND "
         "((state='pending' AND not_before<=to_timestamp($2::double precision)) OR "
         "(state='leased' AND lease_expires_at<=clock_timestamp() AND attempt<max_attempts)) "
         "ORDER BY not_before,sequence FOR UPDATE SKIP LOCKED LIMIT 1", PJColumns()]
        parameters:@[self.namespaceName,@([(timestamp ?: [NSDate date]) timeIntervalSince1970]),
                     PJJSON([queues valueForKey:@"queue"], txError)] error:txError];
    if (!rows) return NO;
    if (!rows.count) return YES;
    NSArray *claimed = [c executeQuery:[NSString stringWithFormat:
        @"UPDATE arlen_jobs SET state='leased',attempt=attempt+1,lease_token=$3,"
         "lease_expires_at=clock_timestamp()+($4::double precision * interval '1 second'),updated_at=clock_timestamp() "
         "WHERE namespace=$1 AND job_id=$2 RETURNING %@", PJColumns()]
        parameters:@[self.namespaceName,rows[0][@"job_id"],[[NSUUID UUID] UUIDString],@(self.leaseDurationSeconds)] error:txError];
    if (!claimed) return NO;
    job = PJEnvelope(claimed[0], self.leaseDurationSeconds);
    return YES;
  } error:error];
  return ok ? job : nil;
}
- (BOOL)mutateLease:(ALNJobEnvelope *)job set:(NSString *)assignment extra:(NSArray *)extra error:(NSError **)error {
  if (![job isKindOfClass:[ALNJobLease class]]) return PJFail(error,603,@"a fenced job lease is required");
  NSMutableArray *params = [NSMutableArray arrayWithArray:@[self.namespaceName,job.jobID,((ALNJobLease *)job).leaseToken]];
  [params addObjectsFromArray:extra];
  return [self.database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c, NSError **txError) {
    // Evaluate expiration after obtaining the lock: a wait on an unchanged row
    // must not authorize a completion using a pre-wait clock reading.
    NSArray *locked = [c executeQuery:@"SELECT job_id FROM arlen_jobs WHERE namespace=$1 AND job_id=$2 FOR UPDATE"
        parameters:@[self.namespaceName,job.jobID] error:txError];
    if (!locked) return NO;
    NSInteger count = [c executeCommand:[NSString stringWithFormat:
        @"UPDATE arlen_jobs SET %@,updated_at=clock_timestamp() WHERE namespace=$1 AND job_id=$2 AND lease_token=$3 "
         "AND state='leased' AND lease_expires_at>clock_timestamp()", assignment] parameters:params error:txError];
    if (count < 0) return NO;
    return count == 1 ? YES : PJFail(txError,604,@"job lease expired or belongs to another worker");
  } error:error];
}
- (BOOL)renewJob:(ALNJobLease *)job error:(NSError **)error {
  return [self mutateLease:job set:@"lease_expires_at=clock_timestamp()+($4::double precision * interval '1 second')"
      extra:@[@(self.leaseDurationSeconds)] error:error];
}
- (BOOL)completeJob:(ALNJobLease *)job result:(id)result error:(NSError **)error {
  NSString *json = PJJSON(@{@"value":result ?: [NSNull null]},error);
  if (!json) return NO;
  return [self mutateLease:job set:@"state='completed',result=$4::jsonb,lease_token=NULL,lease_expires_at=NULL"
      extra:@[json] error:error];
}
- (BOOL)acknowledgeJobID:(NSString *)jobID error:(NSError **)error {
  return PJFail(error,603,@"PostgreSQL jobs require completeJob:result:error: with a lease; ID-only acknowledgement is unsafe");
}
- (BOOL)retryJob:(ALNJobEnvelope *)job delaySeconds:(NSTimeInterval)delaySeconds error:(NSError **)error {
  return [self retryJob:job delaySeconds:delaySeconds failureMessage:nil error:error];
}
- (BOOL)retryJob:(ALNJobEnvelope *)job delaySeconds:(NSTimeInterval)delaySeconds
 failureMessage:(NSString *)failureMessage error:(NSError **)error {
  if (!isfinite(delaySeconds) || delaySeconds < 0) return PJFail(error,601,@"retry delay must be finite and nonnegative");
  return [self mutateLease:job set:@"state=CASE WHEN attempt>=max_attempts THEN 'failed' ELSE 'pending' END,"
      "not_before=clock_timestamp()+($4::double precision * interval '1 second'),failure_message=$5,lease_token=NULL,lease_expires_at=NULL"
      extra:@[@(delaySeconds),failureMessage ?: [NSNull null]] error:error];
}
- (NSArray<ALNJobEnvelope *> *)jobsWithState:(NSString *)state error:(NSError **)error {
  NSArray *rows = [self.database executeQuery:[NSString stringWithFormat:@"SELECT %@ FROM arlen_jobs WHERE namespace=$1 AND state=$2 ORDER BY sequence",PJColumns()]
      parameters:@[self.namespaceName,state] error:error];
  if (!rows) return nil;
  NSMutableArray *jobs = [NSMutableArray array];
  for (NSDictionary *row in rows) [jobs addObject:PJEnvelope(row,self.leaseDurationSeconds)];
  return jobs;
}
- (NSArray *)pendingJobsSnapshot { return [self jobsWithState:@"pending" error:NULL] ?: @[]; }
- (NSArray *)leasedJobsSnapshot { return [self jobsWithState:@"leased" error:NULL] ?: @[]; }
- (NSArray *)deadLetterJobsSnapshot { return [self jobsWithState:@"failed" error:NULL] ?: @[]; }
- (NSDictionary *)jobStatusForID:(NSString *)jobID error:(NSError **)error {
  NSArray *rows = [self.database executeQuery:[NSString stringWithFormat:@"SELECT %@ FROM arlen_jobs WHERE namespace=$1 AND job_id=$2",PJColumns()]
      parameters:@[self.namespaceName,jobID] error:error];
  if (!rows || !rows.count) return nil;
  NSDictionary *row = rows[0];
  NSMutableDictionary *status = [[PJEnvelope(row,self.leaseDurationSeconds) dictionaryRepresentation] mutableCopy];
  status[@"state"] = row[@"state"];
  status[@"queue"] = row[@"queue"];
  status[@"result"] = [row[@"result"] isKindOfClass:[NSDictionary class]] ? row[@"result"][@"value"] : [NSNull null];
  status[@"failureMessage"] = row[@"failure_message"];
  status[@"replayOf"] = row[@"replay_of"];
  status[@"leaseExpiresAt"] = row[@"expires"];
  return status;
}
- (BOOL)setQueue:(NSString *)queue state:(NSString *)state error:(NSError **)error {
  if (!PJString(queue).length || queue.length > 200 || ![@[@"active",@"paused",@"draining"] containsObject:state])
    return PJFail(error,601,@"queue state must be active, paused, or draining");
  return [self.database executeCommand:@"INSERT INTO arlen_job_queues(namespace,queue,state) VALUES($1,$2,$3) "
      "ON CONFLICT(namespace,queue) DO UPDATE SET state=EXCLUDED.state"
      parameters:@[self.namespaceName,queue,state] error:error] >= 0;
}
- (NSArray<NSDictionary *> *)queueStatesWithError:(NSError **)error {
  return [self.database executeQuery:@"SELECT q.queue,q.state,COUNT(*) FILTER(WHERE j.state='pending') AS pending,"
      "COUNT(*) FILTER(WHERE j.state='leased') AS leased,COUNT(*) FILTER(WHERE j.state='failed') AS failed "
      "FROM arlen_job_queues q LEFT JOIN arlen_jobs j ON j.namespace=q.namespace AND j.queue=q.queue "
      "WHERE q.namespace=$1 GROUP BY q.queue,q.state ORDER BY q.queue" parameters:@[self.namespaceName] error:error];
}
- (NSString *)replayJobID:(NSString *)jobID idempotencyKey:(NSString *)idempotencyKey
           delaySeconds:(NSTimeInterval)delaySeconds error:(NSError **)error {
  if (!PJString(idempotencyKey).length || !isfinite(delaySeconds) || delaySeconds < 0) {
    PJFail(error,601,@"replay requires an explicit idempotency key and finite nonnegative delay"); return nil;
  }
  __block NSString *replayed = nil;
  BOOL ok = [self.database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c,NSError **txError) {
    NSDictionary *row = [c executeQueryOne:@"SELECT name,payload,queue,max_attempts,state FROM arlen_jobs WHERE namespace=$1 AND job_id=$2"
        parameters:@[self.namespaceName,jobID] error:txError];
    if (!row) {
      if (txError && *txError) return NO;
      return PJFail(txError,605,@"replay source job was not found");
    }
    if (![@[@"failed",@"completed"] containsObject:row[@"state"]]) return PJFail(txError,605,@"only terminal jobs can be replayed");
    replayed = [self enqueueJobNamed:row[@"name"] payload:row[@"payload"] options:@{
      @"queue":row[@"queue"],@"maxAttempts":row[@"max_attempts"],@"notBefore":@(delaySeconds),
      @"idempotencyKey":idempotencyKey,@"retainDeduplication":@YES,@"replayOf":jobID} onConnection:c error:txError];
    if (!replayed) return NO;
    NSDictionary *replayRow = [c executeQueryOne:@"SELECT replay_of FROM arlen_jobs WHERE namespace=$1 AND job_id=$2"
        parameters:@[self.namespaceName,replayed] error:txError];
    if (!replayRow) return NO;
    if (![replayRow[@"replay_of"] isEqual:jobID]) return PJFail(txError,606,@"replay idempotency key belongs to another request");
    return YES;
  } error:error];
  return ok ? replayed : nil;
}
- (BOOL)resetWithError:(NSError **)error {
  return [self.database withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> c,NSError **txError) {
    if ([c executeCommand:@"DELETE FROM arlen_jobs WHERE namespace=$1" parameters:@[self.namespaceName] error:txError] < 0) return NO;
    return [c executeCommand:@"DELETE FROM arlen_job_queues WHERE namespace=$1" parameters:@[self.namespaceName] error:txError] >= 0;
  } error:error];
}
- (void)reset { [self resetWithError:NULL]; }
@end
