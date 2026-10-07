#ifndef ALN_TEST_WAIT_H
#define ALN_TEST_WAIT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Waits for a condition instead of sleeping for a guessed interval. A wait
// returns as soon as its condition holds, so it can take a generous timeout
// without slowing the passing case. Each wait records no failure itself:
// callers assert on the result, with whatever context explains the failure.
//
// The checks run on the calling thread's run loop through XCTestExpectation
// and XCTWaiter, which Apple XCTest and Arlen's tools-xctest fork both provide.
// Toolchains whose XCTest lacks XCTWaiter (the Windows preview lane) fall back
// to a sleep-and-check loop.

typedef BOOL (^ALNTestWaitCondition)(void);

// How often a wait checks its condition unless told otherwise.
FOUNDATION_EXPORT const NSTimeInterval ALNTestWaitDefaultInterval;

// Returns YES once `condition` returns YES, checking it immediately and then
// every `interval` seconds; returns NO if it still fails when `timeout` passes.
FOUNDATION_EXPORT BOOL ALNTestWaitUntil(NSTimeInterval timeout,
                                        NSTimeInterval interval,
                                        ALNTestWaitCondition condition);

// Returns YES once `task` has exited (and been reaped), NO on timeout.
FOUNDATION_EXPORT BOOL ALNTestWaitForTaskExit(NSTask *task, NSTimeInterval timeout);

#if !defined(_WIN32)
// Whether something on 127.0.0.1:`port` accepts a TCP connection. The probe
// connects and closes without sending a request, so don't use it on a server
// started with `--once`: the probe would be the one connection it serves.
FOUNDATION_EXPORT BOOL ALNTestTCPPortAcceptsConnections(int port);

// Returns YES once 127.0.0.1:`port` accepts connections, NO on timeout.
FOUNDATION_EXPORT BOOL ALNTestWaitForTCPPort(int port, NSTimeInterval timeout);
#endif

NS_ASSUME_NONNULL_END

#endif
