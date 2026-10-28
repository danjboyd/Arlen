#ifndef ALN_SSE_READER_H
#define ALN_SSE_READER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const ALNSSEReaderErrorDomain;

typedef NS_ENUM(NSInteger, ALNSSEReaderErrorCode) {
  ALNSSEReaderErrorInvalidArgument = 1,
  ALNSSEReaderErrorLineTooLarge = 2,
  ALNSSEReaderErrorEventTooLarge = 3,
  ALNSSEReaderErrorInvalidUTF8 = 4,
  ALNSSEReaderErrorStopped = 5,
  ALNSSEReaderErrorInvalidState = 6,
};

/// Immutable generic SSE event. No vendor payload or terminal-event semantics.
@interface ALNSSEEvent : NSObject
@property(nonatomic, copy, readonly) NSString *eventType;
@property(nonatomic, copy, readonly) NSString *data;
@property(nonatomic, copy, readonly) NSString *lastEventID;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Return NO to stop parsing permanently; previously delivered events remain delivered.
typedef BOOL (^ALNSSEEventHandler)(ALNSSEEvent *event);

/// Incremental, bounded SSE framing for ALNHTTPClient's arbitrary byte chunks.
/// Single caller/thread only; callbacks run inline and must not reenter the reader.
/// This strict UTF-8 reader rejects malformed completed lines rather than replacing
/// invalid bytes as a browser EventSource would. No networking or reconnect logic.
@interface ALNSSEReader : NSObject
@property(nonatomic, assign, readonly) NSUInteger maxLineBytes;
@property(nonatomic, assign, readonly) NSUInteger maxEventBytes;

/// Defaults: 65536 bytes per line and 1048576 accumulated data bytes per event.
- (instancetype)init;
/// Both limits must be positive. Line bytes exclude CR/LF and include a leading
/// BOM. Event bytes count UTF-8 data values plus one appended LF per data field
/// (including the LF removed at dispatch). Type/ID are separately line-bounded.
- (nullable instancetype)initWithMaxLineBytes:(NSUInteger)maxLineBytes
                               maxEventBytes:(NSUInteger)maxEventBytes
                                       error:(NSError *_Nullable *_Nullable)error;
/// Delivers complete events in order, without retaining input or queuing output.
/// Errors are permanent and contain no stream content. Returning NO from the
/// handler produces Stopped; handler exceptions propagate and permanently stop
/// the reader.
- (BOOL)consumeData:(NSData *)data
           onEvent:(ALNSSEEventHandler)onEvent
             error:(NSError *_Nullable *_Nullable)error;
/// Marks EOF and discards an unfinished event/line; never dispatches at EOF.
/// Repeated finish succeeds. Consuming after finish fails with InvalidState.
/// Success says nothing about application protocol completion: apps must require
/// their own terminal event. Create a new reader for each response.
- (BOOL)finishWithError:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END

#endif
