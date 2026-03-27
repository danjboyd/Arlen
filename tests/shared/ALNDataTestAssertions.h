#ifndef ALN_DATA_TEST_ASSERTIONS_H
#define ALN_DATA_TEST_ASSERTIONS_H

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *ALNNormalizedSQLForAssertion(NSString *_Nullable sql);

#define ALNAssertBuiltSQLAndParameters(built, expectedSQL, expectedParameters)               \
  do {                                                                                       \
    NSDictionary *__aln_built_assert_built = (built);                                        \
    XCTAssertNotNil(__aln_built_assert_built);                                               \
    if (__aln_built_assert_built != nil) {                                                   \
      XCTAssertEqualObjects(ALNNormalizedSQLForAssertion(__aln_built_assert_built[@"sql"]),  \
                            ALNNormalizedSQLForAssertion((expectedSQL)));                    \
      NSArray *__aln_built_assert_parameters =                                               \
          [__aln_built_assert_built[@"parameters"] isKindOfClass:[NSArray class]]            \
              ? __aln_built_assert_built[@"parameters"]                                      \
              : nil;                                                                         \
      XCTAssertEqualObjects((expectedParameters) ?: @[], __aln_built_assert_parameters ?: @[]); \
    }                                                                                        \
  } while (0)

#define ALNAssertErrorDetails(error, expectedDomain, expectedCode, expectedSubstring)        \
  do {                                                                                       \
    NSError *__aln_error_assert_error = (error);                                             \
    XCTAssertNotNil(__aln_error_assert_error);                                               \
    if (__aln_error_assert_error != nil) {                                                   \
      if ([(expectedDomain) length] > 0) {                                                   \
        XCTAssertEqualObjects((expectedDomain), __aln_error_assert_error.domain);            \
      }                                                                                      \
      if ((expectedCode) != NSNotFound) {                                                    \
        XCTAssertEqual((expectedCode), __aln_error_assert_error.code);                       \
      }                                                                                      \
      if ([(expectedSubstring) length] > 0) {                                                \
        XCTAssertTrue([[__aln_error_assert_error localizedDescription]                       \
                          containsString:(expectedSubstring)],                                \
                      @"%@",                                                                  \
                      __aln_error_assert_error);                                              \
      }                                                                                      \
    }                                                                                        \
  } while (0)

#define ALNAssertResultColumns(result, expectedColumns)                                      \
  do {                                                                                       \
    ALNDatabaseResult *__aln_result_columns_result = (result);                               \
    NSArray *__aln_result_columns_expected = (expectedColumns) ?: @[];                       \
    XCTAssertNotNil(__aln_result_columns_result);                                            \
    if (__aln_result_columns_result != nil) {                                                \
      XCTAssertEqualObjects(__aln_result_columns_expected,                                   \
                            __aln_result_columns_result.columns ?: @[]);                     \
      ALNDatabaseRow *__aln_result_columns_first = [__aln_result_columns_result first];      \
      if (__aln_result_columns_first != nil) {                                               \
        XCTAssertEqualObjects(__aln_result_columns_expected,                                 \
                              __aln_result_columns_first.columns ?: @[]);                    \
      }                                                                                      \
    }                                                                                        \
  } while (0)

#define ALNAssertRowOrderedValues(row, expectedValues)                                       \
  do {                                                                                       \
    ALNDatabaseRow *__aln_row_values_row = (row);                                            \
    NSArray *__aln_row_values_expected = (expectedValues) ?: @[];                            \
    XCTAssertNotNil(__aln_row_values_row);                                                   \
    if (__aln_row_values_row != nil) {                                                       \
      for (NSUInteger __aln_row_values_idx = 0;                                              \
           __aln_row_values_idx < [__aln_row_values_expected count];                         \
           __aln_row_values_idx++) {                                                         \
        XCTAssertEqualObjects(__aln_row_values_expected[__aln_row_values_idx],               \
                              [__aln_row_values_row objectAtColumnIndex:__aln_row_values_idx]); \
      }                                                                                      \
    }                                                                                        \
  } while (0)

#define ALNAssertTypedDictionaryValue(row, columnName, expectedClass, expectedValue)         \
  do {                                                                                       \
    NSDictionary *__aln_typed_row = (row);                                                   \
    NSString *__aln_typed_column_name = (columnName);                                        \
    XCTAssertNotNil(__aln_typed_row);                                                        \
    if (__aln_typed_row != nil) {                                                            \
      id __aln_typed_value = __aln_typed_row[__aln_typed_column_name];                       \
      XCTAssertTrue([__aln_typed_value isKindOfClass:(expectedClass)],                       \
                    @"column %@ expected %@ but got %@",                                     \
                    __aln_typed_column_name,                                                 \
                    NSStringFromClass((expectedClass)),                                      \
                    [__aln_typed_value class]);                                              \
      if ((expectedValue) != nil) {                                                          \
        XCTAssertEqualObjects((expectedValue), __aln_typed_value);                           \
      }                                                                                      \
    }                                                                                        \
  } while (0)

#define ALNAssertResultContract(result, expectedColumns, expectedClasses, expectedValues)    \
  do {                                                                                       \
    ALNDatabaseResult *__aln_contract_result = (result);                                     \
    NSArray *__aln_contract_expected_columns = (expectedColumns) ?: @[];                     \
    NSDictionary *__aln_contract_expected_classes = (expectedClasses) ?: @{};                \
    NSDictionary *__aln_contract_expected_values = (expectedValues) ?: @{};                  \
    XCTAssertNotNil(__aln_contract_result);                                                  \
    if (__aln_contract_result != nil) {                                                      \
      XCTAssertEqualObjects(__aln_contract_expected_columns,                                 \
                            __aln_contract_result.columns ?: @[]);                           \
      ALNDatabaseRow *__aln_contract_first = [__aln_contract_result first];                  \
      XCTAssertNotNil(__aln_contract_first);                                                 \
      if (__aln_contract_first != nil) {                                                     \
        XCTAssertEqualObjects(__aln_contract_expected_columns,                               \
                              __aln_contract_first.columns ?: @[]);                          \
        NSDictionary *__aln_contract_row = __aln_contract_first.dictionaryRepresentation;    \
        for (NSString *__aln_contract_column_name in __aln_contract_expected_classes) {      \
          id __aln_contract_value = __aln_contract_row[__aln_contract_column_name];          \
          Class __aln_contract_class =                                                       \
              __aln_contract_expected_classes[__aln_contract_column_name];                   \
          XCTAssertTrue([__aln_contract_value isKindOfClass:__aln_contract_class],           \
                        @"column %@ expected %@ but got %@",                                 \
                        __aln_contract_column_name,                                          \
                        NSStringFromClass(__aln_contract_class),                             \
                        [__aln_contract_value class]);                                       \
          id __aln_contract_expected_value =                                                 \
              __aln_contract_expected_values[__aln_contract_column_name];                    \
          if (__aln_contract_expected_value != nil) {                                        \
            XCTAssertEqualObjects(__aln_contract_expected_value, __aln_contract_value);      \
          }                                                                                  \
        }                                                                                    \
      }                                                                                      \
    }                                                                                        \
  } while (0)

NS_ASSUME_NONNULL_END

#endif
