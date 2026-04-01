#import "ALNLive.h"

#import "ALNRequest.h"
#import "ALNResponse.h"

#import <dispatch/dispatch.h>

static NSString *const ALNLiveErrorDomain = @"Arlen.Live.Error";

typedef NS_ENUM(NSInteger, ALNLiveErrorCode) {
  ALNLiveErrorCodeInvalidOperation = 1,
  ALNLiveErrorCodeSerializationFailed = 2,
};

static NSString *ALNLiveTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNLiveHeaderBoolValue(NSString *value, BOOL *parsed) {
  NSString *normalized = [[ALNLiveTrimmedString(value) lowercaseString] copy];
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    if (parsed != NULL) {
      *parsed = YES;
    }
    return YES;
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    if (parsed != NULL) {
      *parsed = NO;
    }
    return YES;
  }
  return NO;
}

static NSError *ALNLiveError(ALNLiveErrorCode code,
                             NSString *message,
                             NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] =
      [message isKindOfClass:[NSString class]] && [message length] > 0
          ? message
          : @"live response error";
  if ([details isKindOfClass:[NSDictionary class]] && [details count] > 0) {
    userInfo[@"details"] = details;
  }
  return [NSError errorWithDomain:ALNLiveErrorDomain code:code userInfo:userInfo];
}

static NSDictionary *ALNLiveOperation(NSString *operation,
                                      NSString *target,
                                      NSString *html,
                                      NSString *location,
                                      NSNumber *replace,
                                      NSString *eventName,
                                      NSDictionary *detail) {
  NSMutableDictionary *entry = [NSMutableDictionary dictionary];
  if ([operation length] > 0) {
    entry[@"op"] = operation;
  }
  if ([target length] > 0) {
    entry[@"target"] = target;
  }
  if (html != nil) {
    entry[@"html"] = html;
  }
  if ([location length] > 0) {
    entry[@"location"] = location;
  }
  if (replace != nil) {
    entry[@"replace"] = replace;
  }
  if ([eventName length] > 0) {
    entry[@"event"] = eventName;
  }
  if ([detail isKindOfClass:[NSDictionary class]] && [detail count] > 0) {
    entry[@"detail"] = detail;
  }
  return [NSDictionary dictionaryWithDictionary:entry];
}

static BOOL ALNLivePayloadValueIsJSONSafe(id value) {
  if (value == nil || value == [NSNull null]) {
    return YES;
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
      [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
    return [NSJSONSerialization isValidJSONObject:@{ @"value" : value }];
  }
  return NO;
}

static NSDictionary *ALNLiveNormalizedOperationFromValue(id value, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                            @"Live operation must be a dictionary",
                            @{ @"operation_class" : NSStringFromClass([value class] ?: [NSObject class]) });
    }
    return nil;
  }

  NSDictionary *operation = (NSDictionary *)value;
  NSString *name = [[ALNLiveTrimmedString(operation[@"op"]) lowercaseString] copy];
  NSString *target = ALNLiveTrimmedString(operation[@"target"]);
  NSString *html = [operation[@"html"] isKindOfClass:[NSString class]] ? operation[@"html"] : nil;
  NSString *location = ALNLiveTrimmedString(operation[@"location"]);
  NSString *eventName = ALNLiveTrimmedString(operation[@"event"]);
  id replaceValue = operation[@"replace"];
  NSDictionary *detail = [operation[@"detail"] isKindOfClass:[NSDictionary class]]
                             ? operation[@"detail"]
                             : nil;

  BOOL replace = NO;
  BOOL replaceSpecified = NO;
  if ([replaceValue respondsToSelector:@selector(boolValue)]) {
    replace = [replaceValue boolValue];
    replaceSpecified = YES;
  }

  if ([name isEqualToString:@"replace"] || [name isEqualToString:@"update"] ||
      [name isEqualToString:@"append"] || [name isEqualToString:@"prepend"]) {
    if ([target length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live HTML operations require a non-empty target selector",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    return ALNLiveOperation(name, target, html ?: @"", nil, nil, nil, nil);
  }

  if ([name isEqualToString:@"remove"]) {
    if ([target length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live remove operations require a non-empty target selector",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    return ALNLiveOperation(name, target, nil, nil, nil, nil, nil);
  }

  if ([name isEqualToString:@"navigate"]) {
    if ([location length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live navigate operations require a non-empty location",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    return ALNLiveOperation(name,
                            nil,
                            nil,
                            location,
                            replaceSpecified ? @(replace) : @(NO),
                            nil,
                            nil);
  }

  if ([name isEqualToString:@"dispatch"]) {
    if ([eventName length] == 0) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live dispatch operations require a non-empty event name",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    if (detail != nil && !ALNLivePayloadValueIsJSONSafe(detail)) {
      if (error != NULL) {
        *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                              @"Live dispatch detail must be JSON serializable",
                              @{ @"op" : name ?: @"" });
      }
      return nil;
    }
    return ALNLiveOperation(name, target, nil, nil, nil, eventName, detail);
  }

  if (error != NULL) {
    *error = ALNLiveError(ALNLiveErrorCodeInvalidOperation,
                          @"Unsupported live operation",
                          @{ @"op" : name ?: @"" });
  }
  return nil;
}

static NSString *ALNLiveRequestHeaderValue(ALNRequest *request, NSString *name) {
  if (request == nil || ![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return @"";
  }
  return ALNLiveTrimmedString([request headerValueForName:name]);
}

@implementation ALNLive

+ (NSString *)contentType {
  return @"application/vnd.arlen.live+json; charset=utf-8";
}

+ (NSString *)acceptContentType {
  return @"application/vnd.arlen.live+json";
}

+ (NSString *)protocolVersion {
  return @"arlen-live-v1";
}

+ (NSDictionary *)replaceOperationForTarget:(NSString *)target
                                       html:(NSString *)html {
  return ALNLiveOperation(@"replace", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)updateOperationForTarget:(NSString *)target
                                      html:(NSString *)html {
  return ALNLiveOperation(@"update", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)appendOperationForTarget:(NSString *)target
                                      html:(NSString *)html {
  return ALNLiveOperation(@"append", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)prependOperationForTarget:(NSString *)target
                                       html:(NSString *)html {
  return ALNLiveOperation(@"prepend", target ?: @"", html ?: @"", nil, nil, nil, nil);
}

+ (NSDictionary *)removeOperationForTarget:(NSString *)target {
  return ALNLiveOperation(@"remove", target ?: @"", nil, nil, nil, nil, nil);
}

+ (NSDictionary *)navigateOperationForLocation:(NSString *)location
                                       replace:(BOOL)replace {
  return ALNLiveOperation(@"navigate", nil, nil, location ?: @"", @(replace), nil, nil);
}

+ (NSDictionary *)dispatchOperationForEvent:(NSString *)eventName
                                      detail:(NSDictionary *)detail
                                      target:(NSString *)target {
  return ALNLiveOperation(@"dispatch", target ?: @"", nil, nil, nil, eventName ?: @"", detail);
}

+ (BOOL)requestIsLive:(ALNRequest *)request {
  if (request == nil) {
    return NO;
  }
  NSString *headerValue = [request headerValueForName:@"x-arlen-live"];
  BOOL parsedHeaderValue = NO;
  if (ALNLiveHeaderBoolValue(headerValue, &parsedHeaderValue)) {
    return parsedHeaderValue;
  }

  NSString *rawAcceptValue = [request headerValueForName:@"accept"];
  NSString *acceptValue =
      [([rawAcceptValue isKindOfClass:[NSString class]] ? rawAcceptValue : @"") lowercaseString];
  return [acceptValue containsString:[[self acceptContentType] lowercaseString]];
}

+ (NSDictionary *)requestMetadataForRequest:(ALNRequest *)request {
  if (request == nil) {
    return @{};
  }

  NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
  NSString *target = ALNLiveRequestHeaderValue(request, @"x-arlen-live-target");
  NSString *swap =
      [[ALNLiveRequestHeaderValue(request, @"x-arlen-live-swap") lowercaseString] copy];
  NSString *component = ALNLiveRequestHeaderValue(request, @"x-arlen-live-component");
  NSString *eventName = ALNLiveRequestHeaderValue(request, @"x-arlen-live-event");
  NSString *source =
      [[ALNLiveRequestHeaderValue(request, @"x-arlen-live-source") lowercaseString] copy];

  if ([target length] > 0) {
    metadata[@"target"] = target;
  }
  if ([swap length] > 0) {
    metadata[@"swap"] = swap;
  }
  if ([component length] > 0) {
    metadata[@"component"] = component;
  }
  if ([eventName length] > 0) {
    metadata[@"event"] = eventName;
  }
  if ([source length] > 0) {
    metadata[@"source"] = source;
  }
  return [NSDictionary dictionaryWithDictionary:metadata];
}

+ (NSDictionary *)validatedPayloadWithOperations:(NSArray *)operations
                                             meta:(NSDictionary *)meta
                                            error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }

  NSMutableArray *normalizedOperations = [NSMutableArray array];
  for (id value in operations ?: @[]) {
    NSError *normalizeError = nil;
    NSDictionary *normalized = ALNLiveNormalizedOperationFromValue(value, &normalizeError);
    if (normalized == nil) {
      if (error != NULL) {
        *error = normalizeError;
      }
      return nil;
    }
    [normalizedOperations addObject:normalized];
  }

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"version"] = [self protocolVersion];
  payload[@"operations"] = [NSArray arrayWithArray:normalizedOperations];
  if ([meta isKindOfClass:[NSDictionary class]] && [meta count] > 0) {
    payload[@"meta"] = [NSDictionary dictionaryWithDictionary:meta];
  }
  return [NSDictionary dictionaryWithDictionary:payload];
}

+ (BOOL)renderResponse:(ALNResponse *)response
            operations:(NSArray *)operations
                  meta:(NSDictionary *)meta
                 error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (response == nil) {
    if (error != NULL) {
      *error = ALNLiveError(ALNLiveErrorCodeSerializationFailed,
                            @"Live response requires a response object",
                            nil);
    }
    return NO;
  }

  NSDictionary *payload = [self validatedPayloadWithOperations:operations meta:meta error:error];
  if (payload == nil) {
    return NO;
  }

  if (response.statusCode == 0) {
    response.statusCode = 200;
  }
  BOOL ok = [response setJSONBody:payload options:0 error:error];
  if (!ok) {
    if (error != NULL && *error == nil) {
      *error = ALNLiveError(ALNLiveErrorCodeSerializationFailed,
                            @"Live response serialization failed",
                            nil);
    }
    return NO;
  }
  [response setHeader:@"Content-Type" value:[self contentType]];
  [response setHeader:@"X-Arlen-Live-Protocol" value:[self protocolVersion]];
  response.committed = YES;
  return YES;
}

+ (NSString *)runtimeJavaScript {
  static NSString *script = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    script = [@[
      @"(function () {",
      @"  'use strict';",
      @"  if (window.ArlenLive && window.ArlenLive.__version === 'arlen-live-v1') {",
      @"    return;",
      @"  }",
      @"",
      @"  var LIVE_CONTENT_TYPE = 'application/vnd.arlen.live+json';",
      @"  var LIVE_ACCEPT = LIVE_CONTENT_TYPE + ', application/json;q=0.9, text/html;q=0.8';",
      @"  var streamSockets = new Map();",
      @"",
      @"  function closestLiveLink(node) {",
      @"    return node && node.closest ? node.closest('a[data-arlen-live]') : null;",
      @"  }",
      @"",
      @"  function closestLiveForm(node) {",
      @"    return node && node.closest ? node.closest('form[data-arlen-live]') : null;",
      @"  }",
      @"",
      @"  function attributeValue(node, name) {",
      @"    if (!node || !node.getAttribute) {",
      @"      return '';",
      @"    }",
      @"    var value = node.getAttribute(name);",
      @"    if (typeof value !== 'string') {",
      @"      return '';",
      @"    }",
      @"    return value.trim();",
      @"  }",
      @"",
      @"  function collectLiveRequestMetadata(primary, fallback, source) {",
      @"    var metadata = {};",
      @"    var target = attributeValue(primary, 'data-arlen-live-target') || attributeValue(fallback, 'data-arlen-live-target');",
      @"    var swap = attributeValue(primary, 'data-arlen-live-swap') || attributeValue(fallback, 'data-arlen-live-swap');",
      @"    var component = attributeValue(primary, 'data-arlen-live-component') || attributeValue(fallback, 'data-arlen-live-component');",
      @"    var eventName = attributeValue(primary, 'data-arlen-live-event') || attributeValue(fallback, 'data-arlen-live-event');",
      @"    if (target) {",
      @"      metadata.target = target;",
      @"    }",
      @"    if (swap) {",
      @"      metadata.swap = swap;",
      @"    }",
      @"    if (component) {",
      @"      metadata.component = component;",
      @"    }",
      @"    if (eventName) {",
      @"      metadata.event = eventName;",
      @"    }",
      @"    if (source) {",
      @"      metadata.source = source;",
      @"    }",
      @"    return metadata;",
      @"  }",
      @"",
      @"  function applyLiveHeaders(headers, metadata) {",
      @"    if (!headers || !metadata) {",
      @"      return;",
      @"    }",
      @"    if (metadata.target) {",
      @"      headers['X-Arlen-Live-Target'] = metadata.target;",
      @"    }",
      @"    if (metadata.swap) {",
      @"      headers['X-Arlen-Live-Swap'] = metadata.swap;",
      @"    }",
      @"    if (metadata.component) {",
      @"      headers['X-Arlen-Live-Component'] = metadata.component;",
      @"    }",
      @"    if (metadata.event) {",
      @"      headers['X-Arlen-Live-Event'] = metadata.event;",
      @"    }",
      @"    if (metadata.source) {",
      @"      headers['X-Arlen-Live-Source'] = metadata.source;",
      @"    }",
      @"  }",
      @"",
      @"  function resolveTarget(selector) {",
      @"    if (!selector || typeof selector !== 'string') {",
      @"      return null;",
      @"    }",
      @"    try {",
      @"      return document.querySelector(selector);",
      @"    } catch (error) {",
      @"      console.warn('ArlenLive invalid selector', selector, error);",
      @"      return null;",
      @"    }",
      @"  }",
      @"",
      @"  function dispatchDocumentEvent(name, detail, targetSelector) {",
      @"    if (!name || typeof name !== 'string') {",
      @"      return;",
      @"    }",
      @"    var target = resolveTarget(targetSelector) || document;",
      @"    target.dispatchEvent(new CustomEvent(name, { detail: detail || {} }));",
      @"  }",
      @"",
      @"  function applyOperation(operation) {",
      @"    if (!operation || typeof operation !== 'object') {",
      @"      return;",
      @"    }",
      @"    var target = resolveTarget(operation.target);",
      @"    switch (operation.op) {",
      @"      case 'replace':",
      @"        if (target) {",
      @"          target.outerHTML = operation.html || '';",
      @"        }",
      @"        break;",
      @"      case 'update':",
      @"        if (target) {",
      @"          target.innerHTML = operation.html || '';",
      @"        }",
      @"        break;",
      @"      case 'append':",
      @"        if (target) {",
      @"          target.insertAdjacentHTML('beforeend', operation.html || '');",
      @"        }",
      @"        break;",
      @"      case 'prepend':",
      @"        if (target) {",
      @"          target.insertAdjacentHTML('afterbegin', operation.html || '');",
      @"        }",
      @"        break;",
      @"      case 'remove':",
      @"        if (target) {",
      @"          target.remove();",
      @"        }",
      @"        break;",
      @"      case 'navigate':",
      @"        if (operation.location) {",
      @"          if (operation.replace) {",
      @"            window.location.replace(operation.location);",
      @"          } else {",
      @"            window.location.assign(operation.location);",
      @"          }",
      @"        }",
      @"        break;",
      @"      case 'dispatch':",
      @"        dispatchDocumentEvent(operation.event, operation.detail || {}, operation.target || '');",
      @"        break;",
      @"      default:",
      @"        console.warn('ArlenLive unknown operation', operation);",
      @"    }",
      @"  }",
      @"",
      @"  function applyPayload(payload) {",
      @"    if (!payload || typeof payload !== 'object') {",
      @"      return;",
      @"    }",
      @"    var operations = Array.isArray(payload.operations) ? payload.operations : [];",
      @"    operations.forEach(applyOperation);",
      @"    scanStreams();",
      @"    dispatchDocumentEvent('arlen:live:applied', payload, '');",
      @"  }",
      @"",
      @"  function parsePayloadText(text) {",
      @"    if (typeof text !== 'string' || text.length === 0) {",
      @"      return null;",
      @"    }",
      @"    try {",
      @"      var parsed = JSON.parse(text);",
      @"      if (Array.isArray(parsed)) {",
      @"        return { version: 'arlen-live-v1', operations: parsed };",
      @"      }",
      @"      if (parsed && parsed.op) {",
      @"        return { version: 'arlen-live-v1', operations: [parsed] };",
      @"      }",
      @"      return parsed;",
      @"    } catch (error) {",
      @"      console.warn('ArlenLive failed to parse payload', error);",
      @"      return null;",
      @"    }",
      @"  }",
      @"",
      @"  function setFormBusy(form, busy) {",
      @"    if (!form) {",
      @"      return;",
      @"    }",
      @"    form.setAttribute('data-arlen-live-busy', busy ? 'true' : 'false');",
      @"    Array.prototype.forEach.call(",
      @"      form.querySelectorAll('button, input[type=\"submit\"], input[type=\"button\"]'),",
      @"      function (control) {",
      @"        if (busy) {",
      @"          if (control.disabled) {",
      @"            control.setAttribute('data-arlen-live-disabled-before', 'true');",
      @"          } else {",
      @"            control.setAttribute('data-arlen-live-disabled-before', 'false');",
      @"            control.disabled = true;",
      @"          }",
      @"        } else if (control.getAttribute('data-arlen-live-disabled-before') === 'false') {",
      @"          control.disabled = false;",
      @"          control.removeAttribute('data-arlen-live-disabled-before');",
      @"        }",
      @"      }",
      @"    );",
      @"  }",
      @"",
      @"  async function handleLiveResponse(response, fallbackURL) {",
      @"    if (!response) {",
      @"      return null;",
      @"    }",
      @"    var contentType = (response.headers.get('Content-Type') || '').toLowerCase();",
      @"    if (contentType.indexOf(LIVE_CONTENT_TYPE) !== -1) {",
      @"      var payload = await response.json();",
      @"      applyPayload(payload);",
      @"      return payload;",
      @"    }",
      @"    if (response.redirected && response.url) {",
      @"      window.location.assign(response.url);",
      @"      return null;",
      @"    }",
      @"    if (contentType.indexOf('text/html') !== -1) {",
      @"      window.location.assign(response.url || fallbackURL || window.location.href);",
      @"      return null;",
      @"    }",
      @"    return response;",
      @"  }",
      @"",
      @"  async function submitLiveForm(form, submitter) {",
      @"    var method = (form.getAttribute('method') || 'GET').toUpperCase();",
      @"    var action = form.getAttribute('action') || window.location.href;",
      @"    var metadata = collectLiveRequestMetadata(submitter, form, 'form');",
      @"    var headers = {",
      @"      'Accept': LIVE_ACCEPT,",
      @"      'X-Arlen-Live': 'true'",
      @"    };",
      @"    applyLiveHeaders(headers, metadata);",
      @"    var fetchURL = action;",
      @"    var options = {",
      @"      method: method,",
      @"      credentials: 'same-origin',",
      @"      headers: headers",
      @"    };",
      @"    var formData = new FormData(form);",
      @"    if (submitter && submitter.name && !formData.has(submitter.name)) {",
      @"      formData.append(submitter.name, submitter.value || '');",
      @"    }",
      @"",
      @"    if (method === 'GET') {",
      @"      var url = new URL(action, window.location.href);",
      @"      var params = new URLSearchParams(formData);",
      @"      params.forEach(function (value, key) {",
      @"        url.searchParams.set(key, value);",
      @"      });",
      @"      fetchURL = url.toString();",
      @"    } else {",
      @"      options.body = formData;",
      @"    }",
      @"",
      @"    setFormBusy(form, true);",
      @"    dispatchDocumentEvent('arlen:live:request-start', { url: fetchURL, method: method, metadata: metadata }, '');",
      @"    try {",
      @"      var response = await fetch(fetchURL, options);",
      @"      return await handleLiveResponse(response, fetchURL);",
      @"    } finally {",
      @"      setFormBusy(form, false);",
      @"      dispatchDocumentEvent('arlen:live:request-end', { url: fetchURL, method: method, metadata: metadata }, '');",
      @"    }",
      @"  }",
      @"",
      @"  async function followLiveLink(link) {",
      @"    var href = link.getAttribute('href');",
      @"    if (!href || href.charAt(0) === '#') {",
      @"      return null;",
      @"    }",
      @"    var url = new URL(href, window.location.href);",
      @"    var metadata = collectLiveRequestMetadata(link, null, 'link');",
      @"    var headers = {",
      @"      'Accept': LIVE_ACCEPT,",
      @"      'X-Arlen-Live': 'true'",
      @"    };",
      @"    applyLiveHeaders(headers, metadata);",
      @"    var response = await fetch(url.toString(), {",
      @"      method: 'GET',",
      @"      credentials: 'same-origin',",
      @"      headers: headers",
      @"    });",
      @"    return handleLiveResponse(response, url.toString());",
      @"  }",
      @"",
      @"  function normalizeStreamURL(rawURL) {",
      @"    var url = new URL(rawURL, window.location.href);",
      @"    if (url.protocol === 'http:') {",
      @"      url.protocol = 'ws:';",
      @"    } else if (url.protocol === 'https:') {",
      @"      url.protocol = 'wss:';",
      @"    }",
      @"    return url.toString();",
      @"  }",
      @"",
      @"  function ensureStream(rawURL) {",
      @"    if (!rawURL || typeof rawURL !== 'string') {",
      @"      return null;",
      @"    }",
      @"    var url = normalizeStreamURL(rawURL);",
      @"    if (streamSockets.has(url)) {",
      @"      return streamSockets.get(url);",
      @"    }",
      @"    var socket = new WebSocket(url);",
      @"    socket.addEventListener('message', function (event) {",
      @"      var payload = parsePayloadText(event.data);",
      @"      if (payload) {",
      @"        applyPayload(payload);",
      @"      }",
      @"    });",
      @"    socket.addEventListener('close', function () {",
      @"      streamSockets.delete(url);",
      @"      window.setTimeout(function () {",
      @"        ensureStream(rawURL);",
      @"      }, 1000);",
      @"    });",
      @"    streamSockets.set(url, socket);",
      @"    return socket;",
      @"  }",
      @"",
      @"  function scanStreams() {",
      @"    document.querySelectorAll('[data-arlen-live-stream]').forEach(function (element) {",
      @"      var streamURL = element.getAttribute('data-arlen-live-stream');",
      @"      if (streamURL) {",
      @"        ensureStream(streamURL);",
      @"      }",
      @"    });",
      @"  }",
      @"",
      @"  function start() {",
      @"    scanStreams();",
      @"  }",
      @"",
      @"  document.addEventListener('submit', function (event) {",
      @"    var form = closestLiveForm(event.target);",
      @"    if (!form) {",
      @"      return;",
      @"    }",
      @"    event.preventDefault();",
      @"    submitLiveForm(form, event.submitter || null).catch(function (error) {",
      @"      console.error('ArlenLive form request failed', error);",
      @"      window.location.assign(form.getAttribute('action') || window.location.href);",
      @"    });",
      @"  });",
      @"",
      @"  document.addEventListener('click', function (event) {",
      @"    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {",
      @"      return;",
      @"    }",
      @"    var link = closestLiveLink(event.target);",
      @"    if (!link || link.target === '_blank' || link.hasAttribute('download')) {",
      @"      return;",
      @"    }",
      @"    event.preventDefault();",
      @"    followLiveLink(link).catch(function (error) {",
      @"      console.error('ArlenLive link request failed', error);",
      @"      window.location.assign(link.href);",
      @"    });",
      @"  });",
      @"",
      @"  if (document.readyState === 'loading') {",
      @"    document.addEventListener('DOMContentLoaded', start, { once: true });",
      @"  } else {",
      @"    start();",
      @"  }",
      @"",
      @"  window.ArlenLive = {",
      @"    __version: 'arlen-live-v1',",
      @"    applyPayload: applyPayload,",
      @"    ensureStream: ensureStream,",
      @"    requestIsLive: function () { return true; },",
      @"    start: start",
      @"  };",
      @"})();"
    ] componentsJoinedByString:@"\n"];
  });
  return script;
}

@end
