#import "ALNMCPModule.h"
#import "ALNMCPSchema.h"
#import "ALNAuth.h"
#import "ALNJSONSerialization.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRouter.h"
#import "ALNRateLimitMiddleware.h"
#import "ALNResponseEnvelopeMiddleware.h"

static NSString *const Version = @"2025-11-25";
static NSString *const ModuleKey = @"Arlen.MCP.module";
static BOOL Dict(id v) { return [v isKindOfClass:[NSDictionary class]]; }
static BOOL String(id v) { return [v isKindOfClass:[NSString class]]; }
static BOOL Bool(id v) { return [v isKindOfClass:[NSNumber class]] && (strcmp([v objCType], @encode(BOOL)) == 0); }
static NSData *JSON(id v) { return [ALNJSONSerialization isValidJSONObject:v] ? [ALNJSONSerialization dataWithJSONObject:v options:0 error:NULL] : nil; }
static NSDictionary *ToolError(NSString *message) {
  return @{ @"isError": @YES, @"content": @[@{@"type": @"text", @"text": message}] };
}
static NSString *Encode(NSString *value) {
  return [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
}
@interface ALNMCPEntry : NSObject
@property(nonatomic, copy) NSDictionary *definition;
@property(nonatomic, copy) ALNMCPToolHandler handler;
@property(nonatomic, copy) ALNMCPResponseTransform transform;
@property(nonatomic, strong) ALNRoute *route;
@property(nonatomic, copy) NSDictionary *mapping;
@property(nonatomic, copy) NSDictionary *listing;
@end
@implementation ALNMCPEntry
@end

// Only the module constructs this request. No HTTP header or JSON field grants this capability.
@interface ALNMCPInvocation : ALNRequest
@property(nonatomic, strong) ALNMCPModule *owner;
@property(nonatomic, strong) ALNMCPEntry *entry;
@property(nonatomic, copy) NSDictionary *arguments;
@end
@implementation ALNMCPInvocation
@end

@interface ALNMCPModule ()
@property(nonatomic, weak) ALNApplication *application;
@property(nonatomic, strong) NSMutableArray *entries;
@property(nonatomic, copy) NSDictionary *config;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, assign) BOOL frozen;
@property(nonatomic, assign) BOOL installed;
@property(nonatomic, assign) NSUInteger maxBytes;
@property(nonatomic, strong) NSError *registrationError;
@property(nonatomic, strong) ALNRateLimitMiddleware *limiter;
- (void)handle:(ALNContext *)context;
@end
@interface ALNMCPController : ALNController
- (void)endpoint:(ALNContext *)context;
- (void)invoke:(ALNContext *)context;
@end
@implementation ALNMCPController
- (void)endpoint:(ALNContext *)context {
  ALNMCPModule *module = context.stash[ModuleKey];
  if (!module) { context.response.statusCode = 503; context.response.committed = YES; return; }
  [module handle:context];
}
- (void)invoke:(ALNContext *)context {
  ALNMCPInvocation *request = [context.request isKindOfClass:[ALNMCPInvocation class]] ? (id)context.request : nil;
  if (!request || request.owner != context.stash[ModuleKey] || ![request.entry.route.name isEqual:context.routeName]) {
    context.response.statusCode = 404; context.response.committed = YES; return;
  }
  NSError *error = nil;
  NSDictionary *result = request.entry.handler(request.arguments, context, &error);
  [context.response setJSONBody:(!error && result) ? result : ToolError(@"Tool execution failed") options:0 error:NULL];
  context.response.committed = YES;
}
@end

@implementation ALNMCPModule
- (instancetype)init {
  if ((self = [super init])) _entries = [NSMutableArray array];
  return self;
}
- (NSString *)moduleIdentifier { return @"mcp"; }
- (NSString *)pluginName { return @"mcp"; }
- (BOOL)add:(NSDictionary *)definition handler:(ALNMCPToolHandler)handler transform:(ALNMCPResponseTransform)transform error:(NSError **)error {
  if (self.frozen || self.installed) return ALNMCPFail(error, @"MCP registration is closed; register tools before installing the module");
  if (!Dict(definition) || (!handler && !String(definition[@"routeName"]))) {
    ALNMCPFail(error, @"Tool requires a handler or routeName"); self.registrationError = error ? *error : [NSError errorWithDomain:@"Arlen.MCP" code:1 userInfo:nil]; return NO;
  }
  NSData *data = JSON(definition);
  if (!data) return ALNMCPFail(error, @"Tool definition must be JSON serializable");
  ALNMCPEntry *entry = [ALNMCPEntry new];
  entry.definition = [ALNJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  entry.handler = handler; entry.transform = transform;
  [self.entries addObject:entry];
  return YES;
}
- (BOOL)registerRouteTool:(NSDictionary *)definition transform:(ALNMCPResponseTransform)transform error:(NSError **)error {
  return [self add:definition handler:nil transform:transform error:error];
}
- (BOOL)registerTool:(NSDictionary *)definition handler:(ALNMCPToolHandler)handler error:(NSError **)error {
  if (!handler || definition[@"routeName"]) return ALNMCPFail(error, @"Custom tools require a handler and cannot specify routeName");
  return [self add:definition handler:handler transform:nil error:error];
}
- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  if (self.application) return ALNMCPFail(error, @"MCP module instance is already installed");
  id config = application.config[@"mcp"] ?: @{};
  if (!Dict(config)) return ALNMCPFail(error, @"mcp config must be an object");
  if (![config[@"enabled"] boolValue]) return YES;
  self.config = config;
  self.path = config[@"path"] ?: @"/mcp";
  if (!String(self.path) || ![self.path hasPrefix:@"/"] || [self.path isEqual:@"/"] ||
      [self.path hasSuffix:@"/"] || [self.path containsString:@"//"] ||
      [[self.path componentsSeparatedByString:@"/"] containsObject:@"."] ||
      [[self.path componentsSeparatedByString:@"/"] containsObject:@".."] ||
      [self.path rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._-"] invertedSet]].location != NSNotFound ||
      [@[@"/healthz", @"/readyz", @"/livez", @"/metrics", @"/clusterz"] containsObject:[self.path stringByDeletingPathExtension]])
    return ALNMCPFail(error, @"MCP path must be a literal non-root HTTP path");
  for (NSString *key in @[@"allowedOrigins", @"requiredScopes", @"requiredRoles", @"policies"]) {
    id values = config[key] ?: @[];
    if (![values isKindOfClass:[NSArray class]]) return ALNMCPFail(error, @"MCP access settings must be string arrays");
    for (id value in values) if (!String(value) || ![value length]) return ALNMCPFail(error, @"MCP access settings require nonempty strings");
  }
  self.maxBytes = config[@"maxOutputBytes"] ? [config[@"maxOutputBytes"] unsignedIntegerValue] : 262144;
  if (self.maxBytes < 1024 || self.maxBytes > 16777216) return ALNMCPFail(error, @"maxOutputBytes must be 1024..16777216");
  NSUInteger requests = config[@"requestsPerMinute"] ? [config[@"requestsPerMinute"] unsignedIntegerValue] : 120;
  if (!requests || requests > 100000) return ALNMCPFail(error, @"requestsPerMinute must be 1..100000");
  self.limiter = [[ALNRateLimitMiddleware alloc] initWithMaxRequests:requests windowSeconds:60];
  if (config[@"providerClass"]) {
    Class cls = String(config[@"providerClass"]) ? NSClassFromString(config[@"providerClass"]) : Nil;
    id provider = cls ? [cls new] : nil;
    if (![provider respondsToSelector:@selector(registerToolsWithMCP:application:error:)]) return ALNMCPFail(error, @"Invalid MCP providerClass");
    if (![provider registerToolsWithMCP:self application:application error:error]) return NO;
  }
  // Reserve the whole prefix: private dispatch paths must never shadow application routes.
  for (ALNRoute *route in [application.router allRoutes]) {
    if ([route.pathPattern isEqual:self.path] || [route.pathPattern hasPrefix:[self.path stringByAppendingString:@"/"]]) return ALNMCPFail(error, @"MCP endpoint prefix collides with an existing route");
  }
  self.application = application;
  for (NSString *method in @[@"POST", @"GET", @"DELETE", @"PUT", @"PATCH", @"OPTIONS", @"HEAD"]) {
    ALNRoute *route = [application registerRouteMethod:method path:self.path name:[@"mcp.transport." stringByAppendingString:method]
                                      controllerClass:[ALNMCPController class] action:@"endpoint"];
    route.includeInOpenAPI = NO;
    route.requiredScopes = config[@"requiredScopes"] ?: @[];
    route.requiredRoles = config[@"requiredRoles"] ?: @[];
    route.policyNames = config[@"policies"] ?: @[];
  }
  NSUInteger index = 0;
  for (ALNMCPEntry *entry in self.entries) {
    if (!entry.handler) continue;
    NSString *name = [NSString stringWithFormat:@"mcp.private.%lu", (unsigned long)index++];
    ALNRoute *route = [application registerRouteMethod:@"POST" path:[self.path stringByAppendingFormat:@"/_tools/%@", name]
                                                name:name controllerClass:[ALNMCPController class] action:@"invoke"];
    route.includeInOpenAPI = NO;
    for (NSString *key in @[@"requiredScopes", @"requiredRoles", @"policies"]) {
      id values = entry.definition[key] ?: @[];
      if (![values isKindOfClass:[NSArray class]]) return ALNMCPFail(error, @"Custom tool permissions must be string arrays");
      for (id value in values) if (!String(value)) return ALNMCPFail(error, @"Custom tool permission must be a string");
    }
    route.requiredScopes = entry.definition[@"requiredScopes"] ?: @[];
    route.requiredRoles = entry.definition[@"requiredRoles"] ?: @[];
    route.policyNames = entry.definition[@"policies"] ?: @[];
    route.minimumAuthAssuranceLevel = [entry.definition[@"minimumAuthAssuranceLevel"] unsignedIntegerValue];
    route.maximumAuthenticationAgeSeconds = [entry.definition[@"maximumAuthenticationAgeSeconds"] unsignedIntegerValue];
    entry.route = route;
  }
  self.installed = YES;
  [application addMiddleware:self];
  [application registerLifecycleHook:self];
  return YES;
}
- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  if ([context.request.path isEqual:self.path] || [context.request.path hasPrefix:[self.path stringByAppendingString:@"/"]]) {
    context.stash[ModuleKey] = self;
    context.stash[ALNResponseEnvelopeDisabledStashKey] = @YES;
    if ([context.request.path isEqual:self.path]) return [self.limiter processContext:context error:error];
  }
  if ([context.request isKindOfClass:[ALNMCPInvocation class]] && ((ALNMCPInvocation *)context.request).owner == self) {
    // Even a route without scope/role metadata must receive a freshly resolved
    // MCP caller identity. Never reuse the outer context's cached claims.
    if (![context authSubject].length) [ALNAuth authenticateContext:context authConfig:self.application.config[@"auth"] ?: @{} error:NULL];
    if (![context authSubject].length) {
      context.response.statusCode = 401;
      context.response.committed = YES;
      return NO;
    }
  }
  return YES;
}
- (BOOL)applicationWillStart:(ALNApplication *)application error:(NSError **)error {
  if (self.registrationError) { if (error) *error = self.registrationError; return NO; }
  NSMutableSet *routeNames = [NSMutableSet set];
  for (ALNRoute *route in [application.router allRoutes]) {
    BOOL reserved = [route.pathPattern isEqual:self.path] || [route.pathPattern hasPrefix:[self.path stringByAppendingString:@"/"]];
    if (reserved && route.controllerClass != [ALNMCPController class]) return ALNMCPFail(error, @"Application route collides with reserved MCP prefix");
    if ([routeNames containsObject:route.name]) return ALNMCPFail(error, @"Duplicate route names are incompatible with MCP registration");
    [routeNames addObject:route.name];
  }
  NSMutableSet *names = [NSMutableSet set];
  NSMutableArray *list = [NSMutableArray array];
  for (ALNMCPEntry *entry in self.entries) {
    NSDictionary *d = entry.definition;
    NSArray *allowed = entry.handler
        ? @[@"name", @"description", @"inputSchema", @"outputSchema", @"annotations", @"requiredScopes", @"requiredRoles", @"policies", @"minimumAuthAssuranceLevel", @"maximumAuthenticationAgeSeconds"]
        : @[@"routeName", @"name", @"description", @"inputSchema", @"outputSchema", @"annotations", @"argumentMapping"];
    for (id key in d) if (![allowed containsObject:key]) return ALNMCPFail(error, [NSString stringWithFormat:@"Unsupported tool registration field: %@", key]);
    if (!entry.handler) entry.route = [application.router routeNamed:d[@"routeName"]];
    ALNRoute *route = entry.route;
    if (!route || (!entry.handler && ([route.pathPattern isEqual:self.path] || [route.pathPattern hasPrefix:[self.path stringByAppendingString:@"/"]]))) return ALNMCPFail(error, @"MCP routeName missing or recursive");
    NSString *name = d[@"name"] ?: (entry.handler ? nil : (route.operationID.length ? route.operationID : route.name));
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-"] invertedSet];
    if (!String(name) || !name.length || name.length > 128 || [name rangeOfCharacterFromSet:invalid].location != NSNotFound || [names containsObject:name]) return ALNMCPFail(error, @"Invalid or duplicate MCP tool name");
    [names addObject:name];
    NSDictionary *annotations = d[@"annotations"];
    if (!Dict(annotations) || annotations.count != 4) return ALNMCPFail(error, @"Explicit readOnlyHint, destructiveHint, idempotentHint and openWorldHint booleans are required");
    for (NSString *key in @[@"readOnlyHint", @"destructiveHint", @"idempotentHint", @"openWorldHint"]) if (!Bool(annotations[key])) return ALNMCPFail(error, @"Side-effect annotations must be booleans");
    NSDictionary *rawInput = d[@"inputSchema"] ?: route.requestSchema;
    if (!rawInput || (Dict(rawInput) && !rawInput.count)) rawInput = @{ @"type": @"object", @"properties": @{} };
    NSDictionary *input = ALNMCPSchema(rawInput, !d[@"inputSchema"], error);
    if (!input) return NO;
    id rawOutput = d[@"outputSchema"] ?: (route.responseSchema.count ? route.responseSchema : nil);
    NSDictionary *output = rawOutput ? ALNMCPSchema(rawOutput, !d[@"outputSchema"], error) : nil;
    if (rawOutput && !output) return NO;
    NSString *description = d[@"description"] ?: route.summary ?: @"";
    if (!String(description)) return ALNMCPFail(error, @"Tool description must be a string");
    NSMutableDictionary *listing = [@{@"name": name, @"description": description, @"inputSchema": input, @"annotations": annotations} mutableCopy];
    if (output) listing[@"outputSchema"] = output;
    entry.listing = listing;
    [list addObject:listing];
    if (entry.handler) continue;
    if (route.formats.count || [route.pathPattern containsString:@"*"] || ![@[@"GET", @"POST", @"PUT", @"PATCH", @"DELETE"] containsObject:route.method]) return ALNMCPFail(error, @"MCP route mappings do not support wildcard paths, format routes or this HTTP method");
    id explicitMapping = d[@"argumentMapping"];
    if (explicitMapping && !Dict(explicitMapping)) return ALNMCPFail(error, @"argumentMapping must be an object");
    NSMutableDictionary *mapping = [NSMutableDictionary dictionary];
    NSMutableSet *destinations = [NSMutableSet set];
    for (NSString *arg in input[@"properties"]) {
      id map = explicitMapping[arg];
      if (!explicitMapping) {
        id prop = route.requestSchema[@"properties"][arg];
        NSString *source = Dict(prop) ? prop[@"source"] : nil;
        if (!source) return ALNMCPFail(error, @"Route arguments need explicit source or argumentMapping");
        map = @{ @"source": source, @"name": arg };
      }
      if (!Dict(map) || [map count] != 2 || ![@[@"path", @"query", @"body"] containsObject:map[@"source"]] || !String(map[@"name"]) || ![map[@"name"] length]) return ALNMCPFail(error, @"Mapping requires only source (path/query/body) and name; header/identity mappings are forbidden");
      NSString *destination = [NSString stringWithFormat:@"%@:%@", map[@"source"], map[@"name"]];
      if ([destinations containsObject:destination]) return ALNMCPFail(error, @"Duplicate argument destination");
      [destinations addObject:destination];
      NSString *type = input[@"properties"][arg][@"type"];
      if (![map[@"source"] isEqual:@"body"] && ![@[@"string", @"integer", @"number", @"boolean"] containsObject:type]) return ALNMCPFail(error, @"Path/query mappings require scalar arguments");
      if ([map[@"source"] isEqual:@"path"] && (![[route.pathPattern componentsSeparatedByString:@"/"] containsObject:[@":" stringByAppendingString:map[@"name"]]] || ![input[@"required"] containsObject:arg])) return ALNMCPFail(error, @"Path arguments must be required and match a route parameter");
      mapping[arg] = map;
    }
    if (explicitMapping && [explicitMapping count] != mapping.count) return ALNMCPFail(error, @"Mapping contains unknown arguments");
    for (NSString *segment in [route.pathPattern componentsSeparatedByString:@"/"]) if ([segment hasPrefix:@":"] && ![destinations containsObject:[@"path:" stringByAppendingString:[segment substringFromIndex:1]]]) return ALNMCPFail(error, @"Unmapped route path parameter");
    if ([input[@"additionalProperties"] boolValue]) return ALNMCPFail(error, @"Route tool inputs must have additionalProperties=false");
    entry.mapping = mapping;
  }
  if (JSON(@{@"tools":list}).length > self.maxBytes) return ALNMCPFail(error, @"Tool catalog exceeds maxOutputBytes");
  self.frozen = YES;
  return YES;
}
- (NSDictionary *)call:(ALNMCPEntry *)entry arguments:(NSDictionary *)arguments context:(ALNContext *)context {
  if (!ALNMCPValidate(arguments, entry.listing[@"inputSchema"])) return ToolError(@"Arguments do not satisfy inputSchema");
  NSMutableDictionary *headers = [context.request.headers mutableCopy];
  for (NSString *key in @[@"content-length", @"transfer-encoding", @"connection", @"mcp-protocol-version", @"mcp-session-id", @"last-event-id", @"accept", @"content-type"]) [headers removeObjectForKey:key];
  headers[@"accept"] = @"application/json";
  headers[@"content-type"] = @"application/json";
  NSMutableArray *segments = [[entry.route.pathPattern componentsSeparatedByString:@"/"] mutableCopy];
  NSMutableArray *query = [NSMutableArray array];
  NSMutableDictionary *body = [NSMutableDictionary dictionary];
  for (NSString *arg in [[arguments allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary *map = entry.mapping[arg];
    if (entry.handler) { body[arg] = arguments[arg]; continue; }
    NSString *source = map[@"source"], *name = map[@"name"];
    id value = arguments[arg];
    NSString *text = String(value) ? value : (Bool(value) ? ([value boolValue] ? @"true" : @"false") : [value description]);
    if ([source isEqual:@"body"]) body[name] = value;
    else if ([source isEqual:@"query"]) [query addObject:[NSString stringWithFormat:@"%@=%@", Encode(name), Encode(text)]];
    else {
      // Keep each value inside one literal path segment, even after HTTP decoding.
      if (!text.length || [text isEqual:@"."] || [text isEqual:@".."] || [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/%\\?#"]].location != NSNotFound) return ToolError(@"Invalid path argument");
      NSUInteger index = [segments indexOfObject:[@":" stringByAppendingString:name]];
      if (index == NSNotFound) return ToolError(@"Route mapping changed");
      segments[index] = Encode(text);
    }
  }
  NSData *data = JSON(body);
  headers[@"content-length"] = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
  ALNMCPInvocation *request = [[ALNMCPInvocation alloc] initWithMethod:entry.route.method
      path:[segments componentsJoinedByString:@"/"] queryString:[query componentsJoinedByString:@"&"] headers:headers body:data];
  request.owner = self; request.entry = entry; request.arguments = arguments;
  request.remoteAddress = context.request.remoteAddress;
  request.effectiveRemoteAddress = context.request.effectiveRemoteAddress;
  request.scheme = context.request.scheme;
  // Fresh context, original credentials, complete dispatcher: no copied claims or session stash.
  ALNResponse *response = [self.application dispatchRequest:request requiringRoute:entry.route];
  if (response.statusCode < 200 || response.statusCode >= 300) return ToolError([NSString stringWithFormat:@"Tool request rejected (HTTP %ld)", (long)response.statusCode]);
  if (response.fileBodyPath || response.bodyLength > self.maxBytes) return ToolError(@"Tool response exceeds supported output bounds");
  NSError *error = nil;
  NSDictionary *result = nil;
  if (entry.transform) result = entry.transform(response, &error);
  else {
    id value = response.bodyData.length ? [ALNJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error] : nil;
    if (Dict(value)) result = entry.handler ? value : @{ @"structuredContent": value };
  }
  if (error || !Dict(result)) return ToolError(@"Tool result transformation failed");
  for (id key in result) if (![@[@"structuredContent", @"content", @"isError"] containsObject:key]) return ToolError(@"Unsupported tool result field");
  if (result[@"isError"] && !Bool(result[@"isError"])) return ToolError(@"Invalid tool result isError");
  id structured = result[@"structuredContent"];
  if (structured && !Dict(structured)) return ToolError(@"structuredContent must be an object");
  if (![result[@"isError"] boolValue] && entry.listing[@"outputSchema"] && !ALNMCPValidate(structured, entry.listing[@"outputSchema"])) return ToolError(@"Tool result violates outputSchema");
  id rawContent = result[@"content"] ?: @[];
  if (![rawContent isKindOfClass:[NSArray class]]) return ToolError(@"Tool content must be an array");
  NSMutableArray *content = [rawContent mutableCopy];
  for (id block in content) {
    if (!Dict(block)) return ToolError(@"Invalid content block");
    if ([block[@"type"] isEqual:@"text"]) {
      if (!String(block[@"text"]) || [block count] != 2) return ToolError(@"Invalid text content");
    } else if ([block[@"type"] isEqual:@"resource_link"]) {
      NSURL *url = String(block[@"uri"]) ? [NSURL URLWithString:block[@"uri"]] : nil;
      if (!url.scheme.length || !String(block[@"name"]) || ![block[@"name"] length]) return ToolError(@"Resource links require an absolute URI and name");
      for (NSString *key in block) if (![@[@"type", @"uri", @"name", @"description", @"mimeType", @"title"] containsObject:key] || !String(block[key])) return ToolError(@"Unsupported resource link field");
    } else return ToolError(@"Unsupported content type");
  }
  if (structured) {
    NSData *serialized = JSON(structured);
    if (!serialized || serialized.length > self.maxBytes) return ToolError(@"Structured result exceeds supported output bounds");
    [content addObject:@{ @"type": @"text", @"text": [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding] }];
  }
  NSMutableDictionary *normalized = [result mutableCopy];
  normalized[@"content"] = content;
  normalized[@"isError"] = result[@"isError"] ?: @NO;
  NSData *serialized = JSON(normalized);
  if (!serialized || serialized.length > self.maxBytes) return ToolError(@"Tool result exceeds maxOutputBytes");
  return normalized;
}
- (void)http:(NSInteger)status context:(ALNContext *)context {
  context.response.statusCode = status;
  context.response.committed = YES;
}
- (void)reply:(id)result code:(NSInteger)code message:(NSString *)message identifier:(id)identifier context:(ALNContext *)context {
  NSDictionary *payload = code ? @{ @"jsonrpc": @"2.0", @"id": identifier ?: [NSNull null], @"error": @{@"code": @(code), @"message": message ?: @"Error"} }
      : @{ @"jsonrpc": @"2.0", @"id": identifier, @"result": result };
  [context.response setJSONBody:payload options:0 error:NULL];
  context.response.committed = YES;
}
- (void)handle:(ALNContext *)context {
  ALNRequest *request = context.request;
  [context.response setHeader:@"Cache-Control" value:@"no-store"];
  [context.response setHeader:@"MCP-Protocol-Version" value:Version];
  NSString *origin = [request headerValueForName:@"origin"];
  if (origin.length && ![self.config[@"allowedOrigins"] containsObject:origin]) { [self http:403 context:context]; return; }
  // Middleware-established identities (including auth-module sessions) are accepted.
  // Otherwise use Arlen's bearer verifier, with the application's issuer/audience settings.
  if (![context authSubject].length) [ALNAuth authenticateContext:context authConfig:self.application.config[@"auth"] ?: @{} error:NULL];
  if (![context authSubject].length) {
    [context.response setHeader:@"WWW-Authenticate" value:@"Bearer"];
    [self http:401 context:context]; return;
  }
  NSString *version = [request headerValueForName:@"mcp-protocol-version"];
  if (version.length && ![version isEqual:Version]) { [self http:400 context:context]; return; }
  if (![request.method isEqual:@"POST"]) {
    [context.response setHeader:@"Allow" value:@"POST"];
    [self http:405 context:context]; return;
  }
  if (!self.frozen) { [self http:503 context:context]; return; }
  NSString *media = [[[[request headerValueForName:@"content-type"] componentsSeparatedByString:@";"] firstObject] lowercaseString];
  if (![media isEqual:@"application/json"]) { [self http:415 context:context]; return; }
  NSMutableSet *accepted = [NSMutableSet set];
  for (NSString *range in [[[request headerValueForName:@"accept"] lowercaseString] componentsSeparatedByString:@","]) {
    NSArray *parts = [range componentsSeparatedByString:@";"];
    BOOL enabled = YES;
    for (NSString *part in parts) {
      NSString *parameter = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if ([parameter hasPrefix:@"q="] && [[parameter substringFromIndex:2] doubleValue] <= 0) enabled = NO;
    }
    if (enabled) [accepted addObject:[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
  }
  if (![accepted containsObject:@"application/json"] || ![accepted containsObject:@"text/event-stream"]) { [self http:406 context:context]; return; }
  if (request.body.length > 1048576) { [self http:413 context:context]; return; }
  NSError *parseError = nil;
  if (![[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding]) {
    [self reply:nil code:-32700 message:@"JSON must be UTF-8" identifier:nil context:context]; return;
  }
  id message = [ALNJSONSerialization JSONObjectWithData:request.body options:NSJSONReadingAllowFragments error:&parseError];
  if (parseError) { [self reply:nil code:-32700 message:@"Parse error" identifier:nil context:context]; return; }
  if (!Dict(message)) { [self reply:nil code:-32600 message:@"Invalid Request; batching is unsupported" identifier:nil context:context]; return; }
  id identifier = message[@"id"];
  BOOL validID = String(identifier) || ([identifier isKindOfClass:[NSNumber class]] && !Bool(identifier));
  BOOL notification = identifier == nil;
  NSString *method = message[@"method"];
  if (![message[@"jsonrpc"] isEqual:@"2.0"] || (!notification && !validID) || !String(method)) {
    // A valid client response has no method. We issue no server requests and ignore it.
    if ([message[@"jsonrpc"] isEqual:@"2.0"] && validID && !method && (message[@"result"] || Dict(message[@"error"]))) { [self http:202 context:context]; return; }
    [self reply:nil code:-32600 message:@"Invalid Request" identifier:validID ? identifier : nil context:context]; return;
  }
  id params = message[@"params"] ?: @{};
  // Notifications never execute tools, never receive a JSON-RPC response.
  if (notification) {
    if (!version.length || !Dict(params)) { [self http:400 context:context]; return; }
    [self http:202 context:context]; return;
  }
  if (!Dict(params)) { [self reply:nil code:-32602 message:@"Invalid params" identifier:identifier context:context]; return; }
  if ([method isEqual:@"initialize"]) {
    if (!String(params[@"protocolVersion"]) || !Dict(params[@"capabilities"]) || !Dict(params[@"clientInfo"]) || !String(params[@"clientInfo"][@"name"]) || !String(params[@"clientInfo"][@"version"])) {
      [self reply:nil code:-32602 message:@"Invalid initialization parameters" identifier:identifier context:context]; return;
    }
    [self reply:@{@"protocolVersion": Version, @"capabilities": @{@"tools": @{}}, @"serverInfo": @{@"name": @"Arlen MCP", @"version": @"1.0.0"}}
          code:0 message:nil identifier:identifier context:context]; return;
  }
  // Stateless transport: the client owns lifecycle ordering. No session ID is issued.
  if (!version.length) { [self http:400 context:context]; return; }
  if ([method isEqual:@"ping"]) { [self reply:@{} code:0 message:nil identifier:identifier context:context]; return; }
  if ([method isEqual:@"tools/list"]) {
    if (params[@"cursor"]) { [self reply:nil code:-32602 message:@"Unknown cursor; catalog fits one page" identifier:identifier context:context]; return; }
    NSArray *sorted = [self.entries sortedArrayUsingComparator:^NSComparisonResult(ALNMCPEntry *a, ALNMCPEntry *b) { return [a.listing[@"name"] compare:b.listing[@"name"]]; }];
    NSMutableArray *list = [NSMutableArray array];
    for (ALNMCPEntry *entry in sorted) [list addObject:entry.listing];
    [self reply:@{@"tools":list} code:0 message:nil identifier:identifier context:context]; return;
  }
  if ([method isEqual:@"tools/call"]) {
    if (!String(params[@"name"]) || (params[@"arguments"] && !Dict(params[@"arguments"])) || params[@"task"]) {
      [self reply:nil code:-32602 message:@"Invalid tools/call parameters; tasks unsupported" identifier:identifier context:context]; return;
    }
    for (ALNMCPEntry *entry in self.entries) if ([entry.listing[@"name"] isEqual:params[@"name"]]) {
      NSDictionary *result;
      @try { result = [self call:entry arguments:params[@"arguments"] ?: @{} context:context]; }
      @catch (NSException *exception) { result = ToolError(@"Tool execution failed"); }
      [self reply:result code:0 message:nil identifier:identifier context:context]; return;
    }
    [self reply:nil code:-32602 message:@"Unknown tool" identifier:identifier context:context]; return;
  }
  [self reply:nil code:-32601 message:@"Method not found" identifier:identifier context:context];
}
@end
