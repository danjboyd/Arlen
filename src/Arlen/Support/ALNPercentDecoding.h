#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns nil for malformed percent escapes, invalid UTF-8, or a NUL byte.
// Set plusAsSpace only for application/x-www-form-urlencoded data. A literal
// plus in a URL path or query remains a plus.
FOUNDATION_EXPORT NSString *_Nullable ALNPercentDecodedString(NSString *value, BOOL plusAsSpace);

NS_ASSUME_NONNULL_END
