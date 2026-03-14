#ifndef ALN_MSSQL_DIALECT_H
#define ALN_MSSQL_DIALECT_H

#import <Foundation/Foundation.h>

#import "ALNSQLDialect.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNMSSQLDialect : NSObject <ALNSQLDialect>

+ (instancetype)sharedDialect;

@end

NS_ASSUME_NONNULL_END

#endif
