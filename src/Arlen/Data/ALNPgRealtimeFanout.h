#ifndef ALN_PG_REALTIME_FANOUT_H
#define ALN_PG_REALTIME_FANOUT_H

#import <Foundation/Foundation.h>

#import "ALNRealtime.h"

NS_ASSUME_NONNULL_BEGIN

// PostgreSQL LISTEN/NOTIFY fanout for ALNRealtimeHub (GitHub issue 48): every
// process (for example each propane worker) runs one, so a message published in
// any process reaches websocket subscribers in all of them.
//
// Publishes go out on a serial queue (ordered, never blocking the caller) as
// NOTIFY on one PostgreSQL channel; each process LISTENs on a dedicated
// connection, skips its own messages, and reconnects with backoff. Payloads too
// large for NOTIFY (about 8000 bytes) are written to arlen_realtime_payloads and
// sent by id. Delivery is at most once: messages published while a listener is
// reconnecting are not replayed (durable streams use ALNEventStreamBroker).
@interface ALNPgRealtimeFanout : NSObject <ALNRealtimeFanout>

@property(nonatomic, copy, readonly) NSString *originIdentifier;
@property(nonatomic, assign, readonly, getter=isListening) BOOL listening;

- (nullable instancetype)initWithConnectionString:(NSString *)connectionString
                                    notifyChannel:(nullable NSString *)notifyChannel
                                              hub:(ALNRealtimeHub *)hub
                                            error:(NSError *_Nullable *_Nullable)error;
// Starts the listener thread; returns once the first LISTEN succeeded or
// `timeout` passed (the thread keeps retrying either way).
- (BOOL)startWaitingUpTo:(NSTimeInterval)timeout;
// Blocks until queued publishes have been sent (tests and orderly shutdown).
- (void)flushPublishes;
- (void)stop;

@end

NS_ASSUME_NONNULL_END

#endif
