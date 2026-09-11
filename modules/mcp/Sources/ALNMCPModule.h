#import <Foundation/Foundation.h>
#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN
@class ALNContext, ALNResponse, ALNMCPModule, ALNOAuthResourceServer;

/// Return an MCP result: structuredContent (object), optional content (text/resource_link).
typedef NSDictionary *_Nullable (^ALNMCPToolHandler)(NSDictionary *arguments,
    ALNContext *context, NSError *_Nullable *_Nullable error);
/// Runs only after a successful, fully dispatched HTTP response.
typedef NSDictionary *_Nullable (^ALNMCPResponseTransform)(ALNResponse *response,
    NSError *_Nullable *_Nullable error);

@protocol ALNMCPToolProvider <NSObject>
- (BOOL)registerToolsWithMCP:(ALNMCPModule *)module application:(ALNApplication *)application
                     error:(NSError *_Nullable *_Nullable)error;
@end

/// Optional module. Register definitions before installing; contracts freeze at startup.
/// See docs/MCP_MODULE.md for the intentionally restricted JSON Schema/mapping contract.
@interface ALNMCPModule : NSObject <ALNModule, ALNPlugin, ALNLifecycleHook, ALNMiddleware>
/// Set before installation for custom transport/policy hooks. mcp.oauth may instead
/// supply configuration. OAuth protects the endpoint and every mapped REST route.
@property(nonatomic, strong, nullable) ALNOAuthResourceServer *resourceServer;
- (BOOL)registerRouteTool:(NSDictionary *)definition
               transform:(nullable ALNMCPResponseTransform)transform
                   error:(NSError *_Nullable *_Nullable)error;
- (BOOL)registerTool:(NSDictionary *)definition handler:(ALNMCPToolHandler)handler
              error:(NSError *_Nullable *_Nullable)error;
@end
NS_ASSUME_NONNULL_END
