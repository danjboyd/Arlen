#import <Foundation/Foundation.h>
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNHTTPServer.h"
#import "ALNMCPModule.h"
#import "ALNResponse.h"
#import "ALNRoute.h"
#import "ALNJSONSerialization.h"

// Application services stay in the application, not the framework module.
@interface CatalogService : NSObject
+ (NSArray *)items;
@end
@implementation CatalogService
+ (NSArray *)items { return @[@{@"id":@"1", @"title":@"GNUstep Handbook"}, @{@"id":@"2", @"title":@"Objective-C Notes"}]; }
@end
@interface CatalogController : ALNController
@end
@implementation CatalogController
- (id)item:(ALNContext *)context {
  for (NSDictionary *item in [CatalogService items]) if ([item[@"id"] isEqual:context.params[@"id"]]) return item;
  context.response.statusCode = 404;
  return @{@"error":@"Item not found"};
}
@end
int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *oauthPath = [NSProcessInfo processInfo].environment[@"MCP_EXAMPLE_OAUTH_CONFIG"];
    NSDictionary *oauthConfig = nil;
    if (oauthPath) {
      NSData *data = [NSData dataWithContentsOfFile:oauthPath];
      oauthConfig = data ? [ALNJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
      if (![oauthConfig isKindOfClass:[NSDictionary class]] || ![oauthConfig[@"mcp"] isKindOfClass:[NSDictionary class]] ||
          ![oauthConfig[@"mcp"][@"oauth"] isKindOfClass:[NSDictionary class]] || ![oauthConfig[@"mcp"][@"enabled"] boolValue]) {
        fprintf(stderr, "MCP_EXAMPLE_OAUTH_CONFIG must contain valid mcp.oauth configuration.\n"); return 2;
      }
    }
    NSString *secret = [NSProcessInfo processInfo].environment[@"MCP_EXAMPLE_SECRET"];
    if (!oauthPath && secret.length < 32) { fprintf(stderr, "Set MCP_EXAMPLE_SECRET to at least 32 characters.\n"); return 2; }
    ALNApplication *app = [[ALNApplication alloc] initWithConfig:oauthConfig ?: @{
      @"environment":@"development", @"host":@"127.0.0.1", @"port":@3210, @"apiOnly":@YES,
      @"auth":@{@"enabled":@YES, @"bearerSecret":secret ?: @"", @"issuer":@"mcp-example", @"audience":@"arlen-catalog"},
      @"session":@{@"enabled":@NO}, @"csrf":@{@"enabled":@NO},
      @"mcp":@{@"enabled":@YES, @"requiredScopes":@[@"catalog:read"]}
    }];
    ALNRoute *route = [app registerRouteMethod:@"GET" path:@"/catalog/:id" name:@"catalog_item" controllerClass:[CatalogController class] action:@"item"];
    route.summary = @"Read one catalog item";
    route.operationID = @"catalog.item";
    route.requiredScopes = oauthConfig ? oauthConfig[@"mcp"][@"requiredScopes"] : @[@"catalog:read"];
    route.requestSchema = @{@"type":@"object", @"properties":@{@"id":@{@"type":@"string", @"source":@"path", @"required":@YES}}};
    route.responseSchema = @{@"type":@"object", @"properties":@{@"id":@{@"type":@"string"}, @"title":@{@"type":@"string"}}, @"required":@[@"id", @"title"]};
    NSDictionary *annotations = @{@"readOnlyHint":@YES, @"destructiveHint":@NO, @"idempotentHint":@YES, @"openWorldHint":@NO};
    ALNMCPModule *mcp = [ALNMCPModule new];
    NSError *error = nil;
    BOOL ok = [mcp registerRouteTool:@{@"routeName":@"catalog_item", @"name":@"catalog.item.v1", @"annotations":annotations} transform:nil error:&error];
    ok = ok && [mcp registerTool:@{@"name":@"catalog.summary.v1", @"description":@"Summarize the local catalog", @"annotations":annotations,
        @"inputSchema":@{@"type":@"object"},
        @"outputSchema":@{@"type":@"object", @"properties":@{@"count":@{@"type":@"integer"}}, @"required":@[@"count"]}}
        handler:^NSDictionary *(NSDictionary *arguments, ALNContext *context, NSError **handlerError) {
          if (![context authSubject].length) return nil;
          return @{@"structuredContent":@{@"count":@([[CatalogService items] count])},
                   @"content":@[@{@"type":@"resource_link", @"uri":@"https://www.gnustep.org/", @"name":@"GNUstep"}]};
        } error:&error];
    ok = ok && [app registerPlugin:mcp error:&error] && [app startWithError:&error];
    if (!ok) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app publicRoot:@"/nonexistent"];
    return [server runWithHost:@"127.0.0.1" portOverride:argc > 1 ? atoi(argv[1]) : 3210 once:NO];
  }
}
