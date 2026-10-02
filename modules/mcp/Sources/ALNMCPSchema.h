#import <Foundation/Foundation.h>
NSDictionary *ALNMCPSchema(id schema, BOOL route, NSError **error);
BOOL ALNMCPValidate(id value, NSDictionary *schema);
BOOL ALNMCPFail(NSError **error, NSString *message);
