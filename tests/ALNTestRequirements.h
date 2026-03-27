#ifndef ALN_TEST_REQUIREMENTS_H
#define ALN_TEST_REQUIREMENTS_H

#import <Foundation/Foundation.h>

static inline BOOL ALNTestRequireCondition(BOOL condition,
                                           NSString *suiteName,
                                           NSString *testName,
                                           NSString *requirement,
                                           NSString *reason) {
  if (condition) {
    return YES;
  }

  NSString *suite = [suiteName length] > 0 ? suiteName : @"UnknownSuite";
  NSString *test = [testName length] > 0 ? testName : @"unknownTest";
  NSString *requirementName = [requirement length] > 0 ? requirement : @"unspecified_requirement";
  NSString *message = [NSString
      stringWithFormat:@"ARLEN TEST REQUIREMENT UNSATISFIED [%@ %@] requirement=%@ reason=%@",
                       suite,
                       test,
                       requirementName,
                       [reason length] > 0 ? reason : @"not_provided"];
  fprintf(stderr, "%s\n", [message UTF8String]);
  return NO;
}

#define ALN_REQUIRE_TEST_CONDITION_OR_RETURN(condition, requirement, reason)               \
  do {                                                                                     \
    if (!ALNTestRequireCondition((condition),                                              \
                                 NSStringFromClass([self class]),                          \
                                 NSStringFromSelector(_cmd),                               \
                                 (requirement),                                            \
                                 (reason))) {                                              \
      return;                                                                              \
    }                                                                                      \
  } while (0)

#endif
