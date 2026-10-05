#ifndef ALN_XCTEST_COMPAT_H
#define ALN_XCTEST_COMPAT_H

// Arlen's GNUstep runner is the vendored danjboyd/tools-xctest fork, and Apple
// XCTest provides the same APIs. Toolchains that still ship an older
// tools-xctest (the Windows preview lane) lack skips, time allowances, and
// attachments; there these helpers degrade to the previous behavior.

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#if __has_include(<XCTest/XCTAttachment.h>)
#define ALN_XCTEST_HAS_ATTACHMENTS 1
#else
#define ALN_XCTEST_HAS_ATTACHMENTS 0
#endif

#ifndef XCTSkipUnless
#define XCTSkipUnless(expression, ...)                                                        \
  do {                                                                                     \
    if (!(expression)) {                                                                   \
      NSLog(@"%@ skipped (runner lacks XCTSkip): " __VA_ARGS__, NSStringFromSelector(_cmd)); \
      return;                                                                              \
    }                                                                                      \
  } while (0)
#endif

// Raises this test's per-test time limit (enforced by `xctest
// -test-timeouts-enabled YES` / `-default-test-execution-time-allowance`) for a
// test that legitimately runs longer than the lane default.
static inline void ALNTestSetExecutionTimeAllowance(XCTestCase *testCase, NSTimeInterval seconds) {
  if ([testCase respondsToSelector:NSSelectorFromString(@"setExecutionTimeAllowance:")]) {
    [testCase setValue:@(seconds) forKey:@"executionTimeAllowance"];
  }
}

// Keeps a shell command and its output with the test's results. As in Apple's
// XCTest, the attachment is only saved (and linked from the JUnit report) when
// the test fails.
static inline void ALNTestAttachCommandOutput(XCTestCase *testCase,
                                              NSString *command,
                                              NSString *output,
                                              int exitCode) {
#if ALN_XCTEST_HAS_ATTACHMENTS
  NSString *text = [NSString stringWithFormat:@"$ %@\n# exit %d\n%@",
                                              command ?: @"", exitCode, output ?: @""];
  XCTAttachment *attachment = [XCTAttachment attachmentWithString:text];
  attachment.name = @"shell-command";
  [testCase addAttachment:attachment];
#else
  (void)testCase;
  (void)command;
  (void)output;
  (void)exitCode;
#endif
}

#endif
