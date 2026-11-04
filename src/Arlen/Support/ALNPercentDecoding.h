#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns nil for malformed percent escapes, invalid UTF-8, or a NUL byte.
// Set plusAsSpace for form-style URL queries and application/x-www-form-urlencoded
// data. URL paths keep a literal plus; percent-encoded %2B stays a plus in either mode.
FOUNDATION_EXPORT NSString *_Nullable ALNPercentDecodedString(NSString *value, BOOL plusAsSpace);

NS_ASSUME_NONNULL_END
