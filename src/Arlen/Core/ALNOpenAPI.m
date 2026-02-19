#import "ALNOpenAPI.h"

#import "ALNRoute.h"

static NSDictionary *ALNDescriptorFromValue(id raw) {
  if ([raw isKindOfClass:[NSDictionary class]]) {
    return raw;
  }
  if ([raw isKindOfClass:[NSString class]]) {
    return @{ @"type" : [raw lowercaseString] };
  }
  return @{};
}

static NSDictionary *ALNSchemaProperties(NSDictionary *schema) {
  if (![schema isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  if ([schema[@"properties"] isKindOfClass:[NSDictionary class]]) {
    return schema[@"properties"];
  }

  NSMutableDictionary *properties = [NSMutableDictionary dictionary];
  NSSet *reserved = [NSSet setWithArray:@[
    @"type", @"required", @"description", @"title", @"items", @"enum", @"source",
    @"default", @"coerce", @"minimum", @"maximum", @"minLength", @"maxLength"
  ]];
  for (id key in schema) {
    if (![key isKindOfClass:[NSString class]] || [reserved containsObject:key]) {
      continue;
    }
    id value = schema[key];
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSString class]]) {
      properties[key] = value;
    }
  }
  return properties;
}

static NSSet *ALNSchemaRequired(NSDictionary *schema, NSDictionary *properties) {
  NSMutableSet *required = [NSMutableSet set];
  if ([schema[@"required"] isKindOfClass:[NSArray class]]) {
    for (id value in schema[@"required"]) {
      if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        [required addObject:value];
      }
    }
  }
  for (NSString *field in properties) {
    NSDictionary *descriptor = ALNDescriptorFromValue(properties[field]);
    if ([descriptor[@"required"] respondsToSelector:@selector(boolValue)] &&
        [descriptor[@"required"] boolValue]) {
      [required addObject:field];
    }
  }
  return required;
}

static NSString *ALNOpenAPITypeForType(NSString *type) {
  NSString *normalized = [[type ?: @"string" lowercaseString] copy];
  if ([normalized isEqualToString:@"integer"] || [normalized isEqualToString:@"number"] ||
      [normalized isEqualToString:@"boolean"] || [normalized isEqualToString:@"array"] ||
      [normalized isEqualToString:@"object"] || [normalized isEqualToString:@"string"]) {
    return normalized;
  }
  return @"string";
}

static NSDictionary *ALNOpenAPISchemaFromDescriptor(NSDictionary *descriptor) {
  NSString *type = ALNOpenAPITypeForType(descriptor[@"type"]);
  NSMutableDictionary *schema = [NSMutableDictionary dictionaryWithObject:type forKey:@"type"];

  if ([descriptor[@"description"] isKindOfClass:[NSString class]]) {
    schema[@"description"] = descriptor[@"description"];
  }
  if ([descriptor[@"enum"] isKindOfClass:[NSArray class]] &&
      [descriptor[@"enum"] count] > 0) {
    schema[@"enum"] = descriptor[@"enum"];
  }
  if (descriptor[@"minimum"] != nil) {
    schema[@"minimum"] = descriptor[@"minimum"];
  }
  if (descriptor[@"maximum"] != nil) {
    schema[@"maximum"] = descriptor[@"maximum"];
  }
  if (descriptor[@"minLength"] != nil) {
    schema[@"minLength"] = descriptor[@"minLength"];
  }
  if (descriptor[@"maxLength"] != nil) {
    schema[@"maxLength"] = descriptor[@"maxLength"];
  }
  if (descriptor[@"default"] != nil) {
    schema[@"default"] = descriptor[@"default"];
  }

  if ([type isEqualToString:@"array"]) {
    NSDictionary *items = ALNDescriptorFromValue(descriptor[@"items"]);
    schema[@"items"] = ALNOpenAPISchemaFromDescriptor(items);
  } else if ([type isEqualToString:@"object"]) {
    NSDictionary *properties = ALNSchemaProperties(descriptor);
    NSSet *required = ALNSchemaRequired(descriptor, properties);
    NSMutableDictionary *objectProps = [NSMutableDictionary dictionary];
    NSArray *keys = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in keys) {
      objectProps[name] = ALNOpenAPISchemaFromDescriptor(ALNDescriptorFromValue(properties[name]));
    }
    schema[@"properties"] = objectProps;
    if ([required count] > 0) {
      schema[@"required"] = [[required allObjects] sortedArrayUsingSelector:@selector(compare:)];
    }
  }

  return schema;
}

static NSString *ALNOpenAPIPathFromPattern(NSString *pattern) {
  if (![pattern isKindOfClass:[NSString class]] || [pattern length] == 0) {
    return @"/";
  }
  NSArray *segments = [pattern componentsSeparatedByString:@"/"];
  NSMutableArray *mapped = [NSMutableArray array];
  for (NSString *segment in segments) {
    if ([segment length] == 0) {
      [mapped addObject:@""];
      continue;
    }
    if ([segment hasPrefix:@":"] || [segment hasPrefix:@"*"]) {
      NSString *name = [segment substringFromIndex:1];
      if ([name length] == 0) {
        name = @"param";
      }
      [mapped addObject:[NSString stringWithFormat:@"{%@}", name]];
    } else {
      [mapped addObject:segment];
    }
  }
  NSString *joined = [mapped componentsJoinedByString:@"/"];
  return ([joined length] > 0) ? joined : @"/";
}

static NSString *ALNOpenAPIMethod(NSString *method) {
  NSString *normalized = [[method ?: @"GET" uppercaseString] copy];
  if ([normalized isEqualToString:@"ANY"]) {
    return @"get";
  }
  return [normalized lowercaseString];
}

static NSString *ALNOperationIDForRoute(ALNRoute *route) {
  if ([route.operationID length] > 0) {
    return route.operationID;
  }
  if ([route.name length] > 0) {
    return route.name;
  }
  NSString *path = [[route.pathPattern ?: @"/"
      stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
      stringByReplacingOccurrencesOfString:@":" withString:@""];
  return [NSString stringWithFormat:@"%@_%@", [[route.method ?: @"GET" lowercaseString] copy], path];
}

static NSArray *ALNNormalizedStringArray(NSArray *values) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0 || [normalized containsObject:trimmed]) {
      continue;
    }
    [normalized addObject:trimmed];
  }
  return [NSArray arrayWithArray:normalized];
}

static BOOL ALNRouteLikelyAPI(ALNRoute *route) {
  if ([route.pathPattern hasPrefix:@"/api/"] || [route.pathPattern isEqualToString:@"/api"]) {
    return YES;
  }
  for (NSString *format in route.formats ?: @[]) {
    if ([[format lowercaseString] isEqualToString:@"json"] ||
        [format isEqualToString:@"*"]) {
      return YES;
    }
  }
  if ([route.requestSchema count] > 0 || [route.responseSchema count] > 0) {
    return YES;
  }
  if ([route.requiredScopes count] > 0 || [route.requiredRoles count] > 0) {
    return YES;
  }
  return NO;
}

NSDictionary *ALNBuildOpenAPISpecification(NSArray *routes, NSDictionary *config) {
  NSDictionary *openapiConfig = [config[@"openapi"] isKindOfClass:[NSDictionary class]]
                                    ? config[@"openapi"]
                                    : @{};

  NSString *title = [openapiConfig[@"title"] isKindOfClass:[NSString class]]
                        ? openapiConfig[@"title"]
                        : @"Arlen API";
  NSString *version = [openapiConfig[@"version"] isKindOfClass:[NSString class]]
                          ? openapiConfig[@"version"]
                          : @"0.1.0";
  NSString *description = [openapiConfig[@"description"] isKindOfClass:[NSString class]]
                              ? openapiConfig[@"description"]
                              : @"Generated by Arlen";

  NSString *host = [config[@"host"] isKindOfClass:[NSString class]] ? config[@"host"] : @"127.0.0.1";
  NSInteger port = [config[@"port"] respondsToSelector:@selector(integerValue)]
                       ? [config[@"port"] integerValue]
                       : 3000;

  NSMutableDictionary *paths = [NSMutableDictionary dictionary];
  BOOL usesBearerAuth = NO;

  for (ALNRoute *route in routes ?: @[]) {
    if (![route isKindOfClass:[ALNRoute class]]) {
      continue;
    }
    if (!route.includeInOpenAPI) {
      continue;
    }
    if (!ALNRouteLikelyAPI(route)) {
      continue;
    }

    NSString *openAPIPath = ALNOpenAPIPathFromPattern(route.pathPattern ?: @"/");
    NSMutableDictionary *pathItem =
        [paths[openAPIPath] isKindOfClass:[NSMutableDictionary class]]
            ? paths[openAPIPath]
            : [NSMutableDictionary dictionary];

    NSString *method = ALNOpenAPIMethod(route.method);
    NSMutableDictionary *operation = [NSMutableDictionary dictionary];
    operation[@"operationId"] = ALNOperationIDForRoute(route);
    if ([route.summary length] > 0) {
      operation[@"summary"] = route.summary;
    }
    NSArray *tags = ALNNormalizedStringArray(route.tags);
    if ([tags count] > 0) {
      operation[@"tags"] = tags;
    }

    NSDictionary *requestSchema = [route.requestSchema isKindOfClass:[NSDictionary class]]
                                      ? route.requestSchema
                                      : @{};
    NSDictionary *requestProperties = ALNSchemaProperties(requestSchema);
    NSSet *requestRequired = ALNSchemaRequired(requestSchema, requestProperties);
    NSMutableArray *parameters = [NSMutableArray array];
    NSMutableDictionary *bodyProperties = [NSMutableDictionary dictionary];
    NSMutableArray *bodyRequired = [NSMutableArray array];

    NSArray *routeSegments = [[route.pathPattern ?: @"/" componentsSeparatedByString:@"/"] copy];
    NSMutableSet *pathParameters = [NSMutableSet set];
    for (NSString *segment in routeSegments) {
      if ([segment hasPrefix:@":"] || [segment hasPrefix:@"*"]) {
        NSString *name = [segment substringFromIndex:1];
        if ([name length] > 0) {
          [pathParameters addObject:name];
        }
      }
    }

    for (NSString *pathParam in pathParameters) {
      NSDictionary *descriptor = ALNDescriptorFromValue(requestProperties[pathParam] ?: @{ @"type" : @"string" });
      [parameters addObject:@{
        @"name" : pathParam,
        @"in" : @"path",
        @"required" : @(YES),
        @"schema" : ALNOpenAPISchemaFromDescriptor(descriptor),
      }];
    }

    NSArray *requestFields = [[requestProperties allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *field in requestFields) {
      if ([pathParameters containsObject:field]) {
        continue;
      }
      NSDictionary *descriptor = ALNDescriptorFromValue(requestProperties[field]);
      NSString *source = [descriptor[@"source"] isKindOfClass:[NSString class]]
                             ? [descriptor[@"source"] lowercaseString]
                             : @"query";
      BOOL required = [requestRequired containsObject:field];
      if ([source isEqualToString:@"body"]) {
        bodyProperties[field] = ALNOpenAPISchemaFromDescriptor(descriptor);
        if (required) {
          [bodyRequired addObject:field];
        }
        continue;
      }

      NSString *location = ([source isEqualToString:@"header"]) ? @"header" : @"query";
      [parameters addObject:@{
        @"name" : field,
        @"in" : location,
        @"required" : @(required),
        @"schema" : ALNOpenAPISchemaFromDescriptor(descriptor),
      }];
    }

    if ([parameters count] > 0) {
      operation[@"parameters"] = parameters;
    }
    if ([bodyProperties count] > 0) {
      NSMutableDictionary *bodySchema = [NSMutableDictionary dictionaryWithDictionary:@{
        @"type" : @"object",
        @"properties" : bodyProperties,
      }];
      if ([bodyRequired count] > 0) {
        bodySchema[@"required"] = [ALNNormalizedStringArray(bodyRequired)
            sortedArrayUsingSelector:@selector(compare:)];
      }
      operation[@"requestBody"] = @{
        @"required" : @([bodyRequired count] > 0),
        @"content" : @{
          @"application/json" : @{
            @"schema" : bodySchema
          }
        }
      };
    }

    NSDictionary *responseSchema = [route.responseSchema isKindOfClass:[NSDictionary class]]
                                       ? route.responseSchema
                                       : @{};
    NSMutableDictionary *responses = [NSMutableDictionary dictionary];
    if ([responseSchema count] > 0) {
      NSDictionary *schemaDescriptor =
          (responseSchema[@"properties"] == nil && responseSchema[@"type"] == nil)
              ? @{ @"type" : @"object", @"properties" : responseSchema }
              : responseSchema;
      responses[@"200"] = @{
        @"description" : @"Successful response",
        @"content" : @{
          @"application/json" : @{
            @"schema" : ALNOpenAPISchemaFromDescriptor(schemaDescriptor)
          }
        }
      };
    } else {
      responses[@"200"] = @{
        @"description" : @"Successful response",
      };
    }

    NSArray *requiredScopes = ALNNormalizedStringArray(route.requiredScopes);
    NSArray *requiredRoles = ALNNormalizedStringArray(route.requiredRoles);
    if ([requiredScopes count] > 0 || [requiredRoles count] > 0) {
      usesBearerAuth = YES;
      operation[@"security"] = @[ @{ @"BearerAuth" : requiredScopes ?: @[] } ];
      responses[@"401"] = @{ @"description" : @"Unauthorized" };
      responses[@"403"] = @{ @"description" : @"Forbidden" };
    }

    operation[@"responses"] = responses;
    pathItem[method] = operation;
    paths[openAPIPath] = pathItem;
  }

  NSMutableDictionary *spec = [NSMutableDictionary dictionary];
  spec[@"openapi"] = @"3.1.0";
  spec[@"info"] = @{
    @"title" : title,
    @"version" : version,
    @"description" : description,
  };
  spec[@"servers"] = @[ @{ @"url" : [NSString stringWithFormat:@"http://%@:%ld", host, (long)port] } ];
  spec[@"paths"] = paths;

  if (usesBearerAuth) {
    spec[@"components"] = @{
      @"securitySchemes" : @{
        @"BearerAuth" : @{
          @"type" : @"http",
          @"scheme" : @"bearer",
          @"bearerFormat" : @"JWT",
        }
      }
    };
  }
  return spec;
}
