# App Authoring Guide

This guide covers the core workflows most app authors need after scaffolding an
Arlen app: registering routes, writing controllers, using middleware, and
adding route metadata.

If you have not scaffolded an app yet, start with `docs/FIRST_APP_GUIDE.md`.
For durable replayable realtime, pair this guide with `docs/EVENT_STREAMS.md`.

## 1. Generated App Shape

A full-mode app created with `arlen new MyApp` starts with:

- `src/main.m`: app bootstrap and route registration
- `src/Controllers/HomeController.{h,m}`: controller for `/`
- `templates/layouts/main.html.eoc`: default app shell
- `templates/index.html.eoc`: default page template
- `config/app.plist`: app configuration

Arlen apps are ordinary Objective-C programs. There is no hidden routing DSL.
The generated bootstrap uses `ALNRunAppMain` and a normal route-registration
function.

## 2. Registering Routes

The most direct route API is:

```objc
[app registerRouteMethod:@"GET"
                    path:@"/posts/:id"
                    name:@"post_show"
         controllerClass:[PostsController class]
                  action:@"show"];
```

Common patterns:

- `method`: usually `GET`, `POST`, `PUT`, `PATCH`, or `DELETE`
- `path`: static paths and placeholder segments such as `:id`
- `name`: stable route name used later for route metadata
- `controllerClass`: Objective-C controller class
- `action`: selector name without the `:` suffix

Route registration normally lives in `src/main.m`:

```objc
static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"home"
           controllerClass:[HomeController class]
                    action:@"index"];

  [app registerRouteMethod:@"GET"
                      path:@"/posts/:id"
                      name:@"post_show"
           controllerClass:[PostsController class]
                    action:@"show"];
}
```

When you want Arlen to scaffold both the controller and the route registration,
prefer the generator:

```bash
/path/to/Arlen/bin/arlen generate endpoint Posts \
  --route /posts/:id \
  --method GET
```

## 3. Route Groups, Guards, and Mounted Apps

Use route groups when several routes share a path prefix, a guard action, or a
format constraint.

```objc
[app beginRouteGroupWithPrefix:@"/admin"
                   guardAction:@"requireAdmin"
                       formats:nil];

[app registerRouteMethod:@"GET"
                    path:@"/users"
                    name:@"admin_users"
         controllerClass:[AdminController class]
                  action:@"users"];

[app endRouteGroup];
```

Notes:

- grouped paths are joined onto the prefix
- `guardAction` is the controller method name Arlen should call before the main
  action
- `formats` lets you constrain a route group to specific negotiated formats

For composition, mount a child app under a prefix:

```objc
ALNApplication *adminApp = [[ALNApplication alloc] initWithConfig:app.config];
[app mountApplication:adminApp atPrefix:@"/admin"];
```

## 4. Writing Controller Actions

Arlen controller actions typically look like this:

```objc
- (id)show:(ALNContext *)ctx {
  NSString *postID = [self stringParamForName:@"id"];
  [self stashValues:@{
    @"title" : @"Post",
    @"postID" : postID ?: @""
  }];

  NSError *error = nil;
  if (![self renderTemplate:@"posts/show" error:&error]) {
    [self setStatus:500];
    [self renderText:error.localizedDescription ?: @"render failed"];
  }
  return nil;
}
```

Useful controller helpers:

- `renderTemplate:error:` and `renderTemplate:layout:error:` for HTML pages
- `stashValue:forKey:` and `stashValues:` for template locals
- `renderJSON:error:` for explicit JSON serialization
- `renderJSONEnvelopeWithData:meta:error:` for the normalized `{data, meta}`
  envelope
- `renderText:` and `renderData:contentType:` for plain text or custom payloads
- `redirectTo:status:` for redirects
- `setStatus:` when you need to override the default status code

If an action returns an `NSDictionary` or `NSArray` and you have not already
committed a response body, Arlen treats that return value as JSON and serializes
it automatically.

## 5. Params, Validation, Session, and Auth Helpers

Arlen merges route, query, and request-body params for common controller reads.
The helpers you will use most often are:

- `stringParamForName:`
- `queryValueForName:`
- `queryIntegerForName:`
- `queryBooleanForName:`
- `headerValueForName:`
- `requireStringParam:value:`
- `requireIntegerParam:value:`

For validation errors:

```objc
[self addValidationErrorForField:@"email"
                            code:@"required"
                         message:@"Email is required."];
return [self renderValidationErrors];
```

For stateful browser flows:

- `session`
- `markSessionDirty`
- `csrfToken`

For auth-aware flows:

- `authClaims`
- `authScopes`
- `authRoles`
- `authSubject`
- `authProvider`
- `authMethods`
- `authAssuranceLevel`
- `isMFAAuthenticated`

Use those helpers instead of digging through raw session data directly.

## 5.1 Request-Spanning State In Production

Sessions are signed cookie-backed by default, but app-owned domain lookups still
need durable storage when they can change. In production with multiple
`propane` workers, do not store users, roles, scenarios, workflows, or other
business records only in process-local objects such as `NSMutableDictionary`,
singleton stores, or in-memory adapters.

Use a durable lookup behind the request flow:

- signed cookie session stores a stable user identifier
- controller/middleware loads the user, roles, and mutable business state from
  a database or another durable adapter
- caches may be in-memory only when a cache miss can be rebuilt from durable
  state

Declare the intent in config so doctor/deploy guardrails can reason about it:

```plist
state = {
  durable = YES;
  mode = "database";
  target = "default";
};
```

## 6. Middleware

Arlen middleware implements the `ALNMiddleware` protocol:

```objc
@interface RequestIDMiddleware : NSObject <ALNMiddleware>
@end

@implementation RequestIDMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  [context.response setHeader:@"X-Request-Source" value:@"middleware"];
  return YES;
}

- (void)didProcessContext:(ALNContext *)context {
  (void)context;
}

@end
```

Register middleware during bootstrap:

```objc
[app addMiddleware:[[RequestIDMiddleware alloc] init]];
```

Rules of thumb:

- middleware runs in registration order
- return `NO` from `processContext:error:` to stop dispatch
- populate `error` for deterministic failure responses
- use `didProcessContext:` for post-dispatch cleanup or header decoration

Built-in middleware such as session, CSRF, rate-limit, security headers, and
response envelopes is documented in the API reference and related feature docs.

## 7. Route Metadata, Schemas, and OpenAPI

Register the route first, then attach metadata by route name:

```objc
NSError *error = nil;
[app configureRouteNamed:@"post_show"
           requestSchema:nil
          responseSchema:@{
            @"type" : @"object",
            @"fields" : @{
              @"id" : @{ @"type" : @"string" }
            }
          }
                 summary:@"Show one post"
             operationID:@"postShow"
                    tags:@[ @"posts" ]
           requiredScopes:nil
            requiredRoles:nil
          includeInOpenAPI:YES
                    error:&error];
```

Use route metadata for:

- request/response validation
- OpenAPI generation
- required scopes and roles
- stable operation summaries and tags

For step-up/MFA-sensitive routes, use
`configureAuthAssuranceForRouteNamed:...`.

## 8. Useful Runtime Inspection Commands

From app root:

```bash
/path/to/Arlen/bin/arlen routes
/path/to/Arlen/bin/arlen config --env development --json
/path/to/Arlen/bin/arlen check
```

Use `arlen routes` when you want to verify that generated or grouped routes are
registered the way you expect.

## 9. Next Guides

- `docs/CONFIGURATION_REFERENCE.md`
- `docs/MODULES.md`
- `docs/GETTING_STARTED_API_FIRST.md`
- `docs/GETTING_STARTED_HTML_FIRST.md`
