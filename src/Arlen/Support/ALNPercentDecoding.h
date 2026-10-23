#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns nil for malformed percent escapes, invalid UTF-8, or an encoded NUL.
// Callers choose whether an invalid component is ignored or kept as sent.
// Set plusAsSpace only for query strings and application/x-www-form-urlencoded data.
FOUNDATION_EXPORT NSString *_Nullable ALNPercentDecodedString(NSString *value, BOOL plusAsSpace);

NS_ASSUME_NONNULL_END
