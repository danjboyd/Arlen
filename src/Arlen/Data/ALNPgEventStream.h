#ifndef ALN_PG_EVENT_STREAM_H
#define ALN_PG_EVENT_STREAM_H

#import <Foundation/Foundation.h>

#import "ALNEventStream.h"

NS_ASSUME_NONNULL_BEGIN

// PostgreSQL adapters for durable event streams (GitHub issue 48, part 2), so
// append, replay and resync_required behave the same for every propane worker
// and host.

// Events live in one table (default arlen_event_stream_events, created on first
// use). Appends take a per-stream transaction-scoped advisory lock, so
// concurrent workers never assign the same sequence, and honour idempotency keys
// exactly like ALNInMemoryEventStreamStore.
@interface ALNPgEventStreamStore : NSObject <ALNEventStreamStore>

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                        tableName:(nullable NSString *)tableName
                                   maxConnections:(NSUInteger)maxConnections
                                            error:(NSError *_Nullable *_Nullable)error;

@end

// Delivers committed events to live subscribers in every process through
// PostgreSQL LISTEN/NOTIFY (an internal ALNRealtimeHub with an
// ALNPgRealtimeFanout on its own channel, default arlen_event_streams). The
// listener starts with the first subscription. Delivery is at most once;
// subscribers that miss events recover through replay (the store is durable).
@interface ALNPgEventStreamBroker : NSObject <ALNEventStreamBroker>

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    notifyChannel:(nullable NSString *)notifyChannel
                                            error:(NSError *_Nullable *_Nullable)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END

#endif
