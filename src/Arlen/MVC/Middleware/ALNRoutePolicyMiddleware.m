#import "ALNRoutePolicyMiddleware.h"

#import "ALNContext.h"
#import "ALNLogger.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRoute.h"

#include <arpa/inet.h>
#include <string.h>

NSString *const ALNContextRoutePolicyNamesStashKey = @"aln.route_policies.names";
NSString *const ALNContextRoutePolicyDecisionStashKey = @"aln.route_policies.decision";

static NSString *ALNRoutePolicyErrorDomain = @"Arlen.RoutePolicy.Error";

static NSString *ALNTrimmedPolicyString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNRoutePolicyNameIsValid(NSString *name) {
  if (![name isKindOfClass:[NSString class]] || [name length] == 0 || [name length] > 64) {
    return NO;
  }
  const char *raw = [name UTF8String];
  if (raw == NULL || raw[0] == '\0') {
    return NO;
  }
  for (NSUInteger idx = 0; raw[idx] != '\0'; idx++) {
    char c = raw[idx];
    BOOL alpha = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
    BOOL digit = (c >= '0' && c <= '9');
    if (idx == 0) {
      if (!alpha) {
        return NO;
      }
    } else if (!alpha && !digit) {
      return NO;
    }
  }
  return YES;
}

static NSArray *ALNPolicyStringArray(id value) {
  NSMutableArray *strings = [NSMutableArray array];
  if (![value isKindOfClass:[NSArray class]]) {
    return strings;
  }
  for (id raw in (NSArray *)value) {
    NSString *trimmed = ALNTrimmedPolicyString(raw);
    if ([trimmed length] > 0 && ![strings containsObject:trimmed]) {
      [strings addObject:trimmed];
    }
  }
  return [NSArray arrayWithArray:strings];
}

static NSString *ALNNormalizePolicyPathPrefix(NSString *prefix) {
  NSString *trimmed = ALNTrimmedPolicyString(prefix);
  if ([trimmed length] == 0) {
    return @"";
  }
  while ([trimmed containsString:@"//"]) {
    trimmed = [trimmed stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
  }
  if (![trimmed hasPrefix:@"/"]) {
    trimmed = [@"/" stringByAppendingString:trimmed];
  }
  while ([trimmed length] > 1 && [trimmed hasSuffix:@"/"]) {
    trimmed = [trimmed substringToIndex:[trimmed length] - 1];
  }
  return ([trimmed length] > 0) ? trimmed : @"";
}

static BOOL ALNPathMatchesPolicyPrefix(NSString *path, NSString *prefix) {
  NSString *normalizedPath = ALNNormalizePolicyPathPrefix(path);
  NSString *normalizedPrefix = ALNNormalizePolicyPathPrefix(prefix);
  if ([normalizedPrefix length] == 0) {
    return NO;
  }
  if ([normalizedPrefix isEqualToString:@"/"]) {
    return YES;
  }
  if ([normalizedPath isEqualToString:normalizedPrefix]) {
    return YES;
  }
  NSString *prefixWithSlash = [normalizedPrefix stringByAppendingString:@"/"];
  return [normalizedPath hasPrefix:prefixWithSlash];
}

static NSString *ALNNormalizeIPAddressCandidate(NSString *value) {
  NSString *trimmed = ALNTrimmedPolicyString(value);
  if ([trimmed length] == 0) {
    return @"";
  }
  if ([trimmed hasPrefix:@"["]) {
    NSRange closing = [trimmed rangeOfString:@"]"];
    if (closing.location != NSNotFound && closing.location > 1) {
      return [trimmed substringWithRange:NSMakeRange(1, closing.location - 1)];
    }
  }
  NSRange percent = [trimmed rangeOfString:@"%"];
  if (percent.location != NSNotFound) {
    trimmed = [trimmed substringToIndex:percent.location];
  }
  NSUInteger colonCount = 0;
  for (NSUInteger idx = 0; idx < [trimmed length]; idx++) {
    if ([trimmed characterAtIndex:idx] == ':') {
      colonCount += 1;
    }
  }
  if (colonCount == 1 && [trimmed rangeOfString:@"."].location != NSNotFound) {
    NSArray *parts = [trimmed componentsSeparatedByString:@":"];
    if ([parts count] == 2 && [parts[0] length] > 0 && [parts[1] length] > 0) {
      return parts[0];
    }
  }
  return trimmed;
}

static BOOL ALNParseIPAddressBytes(NSString *value, int *familyOut, uint8_t bytesOut[16]) {
  if (familyOut != NULL) {
    *familyOut = 0;
  }
  if (bytesOut != NULL) {
    memset(bytesOut, 0, 16);
  }
  NSString *candidate = ALNNormalizeIPAddressCandidate(value);
  if ([candidate length] == 0 || bytesOut == NULL) {
    return NO;
  }
  const char *raw = [candidate UTF8String];
  if (raw == NULL) {
    return NO;
  }
  struct in_addr ipv4;
  memset(&ipv4, 0, sizeof(ipv4));
  if (inet_pton(AF_INET, raw, &ipv4) == 1) {
    memcpy(bytesOut, &ipv4, 4);
    if (familyOut != NULL) {
      *familyOut = AF_INET;
    }
    return YES;
  }
  struct in6_addr ipv6;
  memset(&ipv6, 0, sizeof(ipv6));
  if (inet_pton(AF_INET6, raw, &ipv6) == 1) {
    memcpy(bytesOut, &ipv6, 16);
    if (familyOut != NULL) {
      *familyOut = AF_INET6;
    }
    return YES;
  }
  return NO;
}

static BOOL ALNStringIsUnsignedInteger(NSString *value, NSUInteger *parsedOut) {
  NSString *trimmed = ALNTrimmedPolicyString(value);
  if ([trimmed length] == 0) {
    return NO;
  }
  NSScanner *scanner = [NSScanner scannerWithString:trimmed];
  long long parsed = 0;
  if (![scanner scanLongLong:&parsed] || ![scanner isAtEnd] || parsed < 0) {
    return NO;
  }
  if (parsedOut != NULL) {
    *parsedOut = (NSUInteger)parsed;
  }
  return YES;
}

static BOOL ALNCIDRIsValid(NSString *cidr) {
  NSString *trimmed = ALNTrimmedPolicyString(cidr);
  if ([trimmed length] == 0) {
    return NO;
  }
  NSArray *parts = [trimmed componentsSeparatedByString:@"/"];
  if ([parts count] > 2) {
    return NO;
  }
  int family = 0;
  uint8_t bytes[16];
  if (!ALNParseIPAddressBytes(parts[0], &family, bytes)) {
    return NO;
  }
  if ([parts count] == 1) {
    return YES;
  }
  NSUInteger prefix = 0;
  if (!ALNStringIsUnsignedInteger(parts[1], &prefix)) {
    return NO;
  }
  return (family == AF_INET) ? (prefix <= 32) : (prefix <= 128);
}

static BOOL ALNIPAddressMatchesCIDR(NSString *ip, NSString *cidr) {
  NSString *trimmed = ALNTrimmedPolicyString(cidr);
  NSArray *parts = [trimmed componentsSeparatedByString:@"/"];
  if ([parts count] > 2) {
    return NO;
  }
  int ipFamily = 0;
  int cidrFamily = 0;
  uint8_t ipBytes[16];
  uint8_t cidrBytes[16];
  if (!ALNParseIPAddressBytes(ip, &ipFamily, ipBytes) ||
      !ALNParseIPAddressBytes(parts[0], &cidrFamily, cidrBytes) ||
      ipFamily != cidrFamily) {
    return NO;
  }
  NSUInteger prefix = (ipFamily == AF_INET) ? 32 : 128;
  if ([parts count] == 2 && !ALNStringIsUnsignedInteger(parts[1], &prefix)) {
    return NO;
  }
  NSUInteger maxPrefix = (ipFamily == AF_INET) ? 32 : 128;
  if (prefix > maxPrefix) {
    return NO;
  }
  NSUInteger fullBytes = prefix / 8;
  NSUInteger remainingBits = prefix % 8;
  if (fullBytes > 0 && memcmp(ipBytes, cidrBytes, fullBytes) != 0) {
    return NO;
  }
  if (remainingBits == 0) {
    return YES;
  }
  uint8_t mask = (uint8_t)(0xFF << (8 - remainingBits));
  return (ipBytes[fullBytes] & mask) == (cidrBytes[fullBytes] & mask);
}

static BOOL ALNIPMatchesAnyCIDR(NSString *ip, NSArray *cidrs) {
  if ([ip length] == 0) {
    return NO;
  }
  for (NSString *cidr in cidrs ?: @[]) {
    if (ALNIPAddressMatchesCIDR(ip, cidr)) {
      return YES;
    }
  }
  return NO;
}

static NSString *ALNFirstForwardedForValue(NSString *header) {
  NSString *trimmed = ALNTrimmedPolicyString(header);
  if ([trimmed length] == 0) {
    return @"";
  }
  NSArray *entries = [trimmed componentsSeparatedByString:@","];
  for (NSString *entry in entries) {
    NSArray *pairs = [entry componentsSeparatedByString:@";"];
    for (NSString *pair in pairs) {
      NSString *candidate = ALNTrimmedPolicyString(pair);
      NSRange equals = [candidate rangeOfString:@"="];
      if (equals.location == NSNotFound) {
        continue;
      }
      NSString *key = [[ALNTrimmedPolicyString([candidate substringToIndex:equals.location]) lowercaseString] copy];
      if (![key isEqualToString:@"for"]) {
        continue;
      }
      NSString *value = ALNTrimmedPolicyString([candidate substringFromIndex:equals.location + 1]);
      if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] >= 2) {
        value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
      }
      return ALNNormalizeIPAddressCandidate(value);
    }
  }
  return @"";
}

static NSString *ALNFirstXForwardedForValue(NSString *header) {
  NSString *trimmed = ALNTrimmedPolicyString(header);
  if ([trimmed length] == 0) {
    return @"";
  }
  NSArray *parts = [trimmed componentsSeparatedByString:@","];
  for (NSString *part in parts) {
    NSString *candidate = ALNNormalizeIPAddressCandidate(part);
    if ([candidate length] > 0) {
      return candidate;
    }
  }
  return @"";
}

static NSDictionary *ALNSecurityDictionary(NSDictionary *config) {
  NSDictionary *security = [config[@"security"] isKindOfClass:[NSDictionary class]] ? config[@"security"] : @{};
  return security;
}

static NSDictionary *ALNRoutePoliciesDictionary(NSDictionary *config) {
  NSDictionary *policies = [ALNSecurityDictionary(config)[@"routePolicies"] isKindOfClass:[NSDictionary class]]
                                ? ALNSecurityDictionary(config)[@"routePolicies"]
                                : @{};
  return policies;
}

static NSArray *ALNTrustedProxyCIDRs(NSDictionary *config) {
  return ALNPolicyStringArray(ALNSecurityDictionary(config)[@"trustedProxies"]);
}

static NSArray *ALNPolicyNamesForRequest(ALNContext *context) {
  NSDictionary *policies = ALNRoutePoliciesDictionary([context application].config ?: @{});
  NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
  NSArray *sortedNames = [[policies allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSString *path = context.request.path ?: @"/";
  for (NSString *name in sortedNames) {
    NSDictionary *policy = [policies[name] isKindOfClass:[NSDictionary class]] ? policies[name] : @{};
    NSArray *prefixes = ALNPolicyStringArray(policy[@"pathPrefixes"]);
    for (NSString *prefix in prefixes) {
      if (ALNPathMatchesPolicyPrefix(path, prefix)) {
        [names addObject:name];
        break;
      }
    }
  }
  NSArray *routePolicyNames = [context.stash[ALNContextRoutePolicyNamesStashKey] isKindOfClass:[NSArray class]]
                                  ? context.stash[ALNContextRoutePolicyNamesStashKey]
                                  : @[];
  for (NSString *name in routePolicyNames) {
    if ([name isKindOfClass:[NSString class]] && [name length] > 0) {
      [names addObject:name];
    }
  }
  return [names array];
}

static NSDictionary *ALNResolvedClientIP(ALNContext *context, BOOL trustForwardedClientIP) {
  NSString *directPeer = ALNNormalizeIPAddressCandidate(context.request.remoteAddress ?: @"");
  int family = 0;
  uint8_t bytes[16];
  if (!ALNParseIPAddressBytes(directPeer, &family, bytes)) {
    return @{ @"status" : @"unresolved", @"reason" : @"direct_peer_unresolved" };
  }

  NSArray *trustedProxyCIDRs = ALNTrustedProxyCIDRs([context application].config ?: @{});
  if (!trustForwardedClientIP || [trustedProxyCIDRs count] == 0) {
    return @{ @"status" : @"ok", @"client_ip" : directPeer, @"source" : @"direct" };
  }

  if (!ALNIPMatchesAnyCIDR(directPeer, trustedProxyCIDRs)) {
    return @{ @"status" : @"ok", @"client_ip" : directPeer, @"source" : @"direct_untrusted_proxy_headers_ignored" };
  }

  NSString *forwarded = ALNFirstForwardedForValue([context.request headerValueForName:@"Forwarded"]);
  if ([forwarded length] == 0) {
    forwarded = ALNFirstXForwardedForValue([context.request headerValueForName:@"X-Forwarded-For"]);
  }
  if (!ALNParseIPAddressBytes(forwarded, &family, bytes)) {
    return @{
      @"status" : @"unresolved",
      @"reason" : @"forwarded_client_unresolved",
      @"direct_peer" : directPeer,
    };
  }
  return @{
    @"status" : @"ok",
    @"client_ip" : forwarded,
    @"source" : @"trusted_forwarded",
    @"direct_peer" : directPeer,
  };
}

static NSDictionary *ALNRoutePolicyDenial(NSString *policyName,
                                          NSString *reason,
                                          NSString *clientIP,
                                          NSString *source) {
  NSMutableDictionary *decision = [NSMutableDictionary dictionary];
  decision[@"status"] = @"deny";
  decision[@"policy"] = policyName ?: @"";
  decision[@"reason"] = reason ?: @"policy_denied";
  if ([clientIP length] > 0) {
    decision[@"client_ip"] = clientIP;
  }
  if ([source length] > 0) {
    decision[@"client_ip_source"] = source;
  }
  return decision;
}

@implementation ALNRoutePolicyMiddleware

+ (NSError *)validationErrorWithCode:(NSInteger)code
                              reason:(NSString *)reason
                                 key:(NSString *)key
                             details:(NSArray *)details {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] =
      [NSString stringWithFormat:@"Invalid security.routePolicies configuration: %@", reason ?: @"invalid"];
  userInfo[@"reason"] = reason ?: @"invalid";
  if ([key length] > 0) {
    userInfo[@"config_key"] = key;
  }
  if ([details count] > 0) {
    userInfo[@"details"] = details;
  }
  return [NSError errorWithDomain:ALNRoutePolicyErrorDomain code:code userInfo:userInfo];
}

+ (NSError *)validateSecurityConfiguration:(NSDictionary *)config {
  NSMutableArray *details = [NSMutableArray array];
  NSArray *trustedProxies = ALNPolicyStringArray(ALNSecurityDictionary(config)[@"trustedProxies"]);
  for (NSString *cidr in trustedProxies) {
    if (!ALNCIDRIsValid(cidr)) {
      [details addObject:@{
        @"field" : @"security.trustedProxies",
        @"code" : @"invalid_cidr",
        @"value" : cidr ?: @"",
      }];
    }
  }

  NSDictionary *policies = ALNRoutePoliciesDictionary(config);
  NSSet *allowedKeys = [NSSet setWithArray:@[
    @"pathPrefixes",
    @"requireAuth",
    @"trustForwardedClientIP",
    @"sourceIPAllowlist",
  ]];
  for (NSString *name in [[policies allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if (!ALNRoutePolicyNameIsValid(name)) {
      [details addObject:@{
        @"field" : @"security.routePolicies",
        @"code" : @"invalid_policy_name",
        @"policy" : name ?: @"",
      }];
      continue;
    }
    NSDictionary *policy = [policies[name] isKindOfClass:[NSDictionary class]] ? policies[name] : nil;
    if (policy == nil) {
      [details addObject:@{
        @"field" : [NSString stringWithFormat:@"security.routePolicies.%@", name],
        @"code" : @"policy_not_dictionary",
      }];
      continue;
    }
    for (NSString *key in [[policy allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      if (![allowedKeys containsObject:key]) {
        [details addObject:@{
          @"field" : [NSString stringWithFormat:@"security.routePolicies.%@.%@", name, key],
          @"code" : @"unsupported_policy_field",
        }];
      }
    }
    for (NSString *prefix in ALNPolicyStringArray(policy[@"pathPrefixes"])) {
      if ([ALNNormalizePolicyPathPrefix(prefix) length] == 0) {
        [details addObject:@{
          @"field" : [NSString stringWithFormat:@"security.routePolicies.%@.pathPrefixes", name],
          @"code" : @"invalid_path_prefix",
          @"value" : prefix ?: @"",
        }];
      }
    }
    for (NSString *cidr in ALNPolicyStringArray(policy[@"sourceIPAllowlist"])) {
      if (!ALNCIDRIsValid(cidr)) {
        [details addObject:@{
          @"field" : [NSString stringWithFormat:@"security.routePolicies.%@.sourceIPAllowlist", name],
          @"code" : @"invalid_cidr",
          @"value" : cidr ?: @"",
        }];
      }
    }
  }

  if ([details count] > 0) {
    return [self validationErrorWithCode:350
                                  reason:@"invalid_route_policy_config"
                                     key:@"security.routePolicies"
                                 details:details];
  }
  return nil;
}

- (void)applyDenial:(NSDictionary *)decision context:(ALNContext *)context {
  context.stash[ALNContextRoutePolicyDecisionStashKey] = decision ?: @{};
  NSString *reason = decision[@"reason"] ?: @"policy_denied";
  [context.logger warn:@"route policy denied"
                fields:@{
                  @"event" : @"route_policy.denied",
                  @"policy" : decision[@"policy"] ?: @"",
                  @"reason" : reason,
                  @"route" : context.routeName ?: @"",
                  @"path" : context.request.path ?: @"",
                  @"client_ip" : decision[@"client_ip"] ?: @"",
                  @"client_ip_source" : decision[@"client_ip_source"] ?: @"",
                }];
  context.response.statusCode = 403;
  [context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [context.response setHeader:@"X-Arlen-Policy-Denial-Reason" value:reason];
  [context.response setTextBody:@"route policy denied\n"];
  context.response.committed = YES;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSArray *policyNames = ALNPolicyNamesForRequest(context);
  if ([policyNames count] == 0) {
    return YES;
  }

  NSDictionary *policies = ALNRoutePoliciesDictionary([context application].config ?: @{});
  for (NSString *name in policyNames) {
    NSDictionary *policy = [policies[name] isKindOfClass:[NSDictionary class]] ? policies[name] : nil;
    if (policy == nil) {
      [self applyDenial:ALNRoutePolicyDenial(name, @"unknown_policy", @"", @"") context:context];
      return NO;
    }

    NSArray *allowlist = ALNPolicyStringArray(policy[@"sourceIPAllowlist"]);
    if ([allowlist count] > 0) {
      BOOL trustForwarded = [policy[@"trustForwardedClientIP"] respondsToSelector:@selector(boolValue)]
                                ? [policy[@"trustForwardedClientIP"] boolValue]
                                : NO;
      NSDictionary *resolved = ALNResolvedClientIP(context, trustForwarded);
      NSString *clientIP = [resolved[@"client_ip"] isKindOfClass:[NSString class]] ? resolved[@"client_ip"] : @"";
      NSString *source = [resolved[@"source"] isKindOfClass:[NSString class]] ? resolved[@"source"] : @"";
      if (![[resolved[@"status"] description] isEqualToString:@"ok"] || [clientIP length] == 0) {
        NSString *reason = [resolved[@"reason"] isKindOfClass:[NSString class]]
                               ? resolved[@"reason"]
                               : @"client_ip_unresolved";
        [self applyDenial:ALNRoutePolicyDenial(name, reason, @"", source) context:context];
        return NO;
      }
      context.request.effectiveRemoteAddress = clientIP;
      if (!ALNIPMatchesAnyCIDR(clientIP, allowlist)) {
        [self applyDenial:ALNRoutePolicyDenial(name, @"source_ip_denied", clientIP, source)
                  context:context];
        return NO;
      }
    }

    BOOL requireAuth = [policy[@"requireAuth"] respondsToSelector:@selector(boolValue)]
                           ? [policy[@"requireAuth"] boolValue]
                           : NO;
    if (requireAuth && [[context authSubject] length] == 0) {
      [self applyDenial:ALNRoutePolicyDenial(name,
                                             @"authentication_required",
                                             context.request.effectiveRemoteAddress ?: @"",
                                             @"")
                context:context];
      return NO;
    }
  }

  context.stash[ALNContextRoutePolicyDecisionStashKey] = @{
    @"status" : @"allow",
    @"policies" : policyNames ?: @[],
  };
  return YES;
}

@end
