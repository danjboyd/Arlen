#import "ALNClientAddressInternal.h"

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#endif
#include <string.h>

static NSString *ALNClientAddressTrimmed(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// Strips IPv6 brackets, an IPv4 ":port", and an IPv6 "%zone". The result may
// still not be an address.
static NSString *ALNClientAddressCandidate(NSString *value) {
  NSString *trimmed = ALNClientAddressTrimmed(value);
  if ([trimmed length] == 0) {
    return @"";
  }
  if ([trimmed hasPrefix:@"["]) {
    NSRange closing = [trimmed rangeOfString:@"]"];
    if (closing.location == NSNotFound || closing.location <= 1) {
      return @"";
    }
    NSString *rest = [trimmed substringFromIndex:closing.location + 1];
    if ([rest length] > 0 && ![rest hasPrefix:@":"]) {
      return @"";
    }
    trimmed = [trimmed substringWithRange:NSMakeRange(1, closing.location - 1)];
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

// An IPv4-mapped IPv6 address (::ffff:a.b.c.d) is the IPv4 address; a
// dual-stack listener reports IPv4 peers that way.
static BOOL ALNClientAddressIsIPv4Mapped(const uint8_t bytes[16]) {
  static const uint8_t prefix[12] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff};
  return memcmp(bytes, prefix, sizeof(prefix)) == 0;
}

static BOOL ALNClientAddressParseBytesMapped(NSString *value,
                                             int *familyOut,
                                             uint8_t bytesOut[16],
                                             BOOL *mappedOut) {
  *familyOut = 0;
  memset(bytesOut, 0, 16);
  if (mappedOut != NULL) {
    *mappedOut = NO;
  }
  NSString *candidate = ALNClientAddressCandidate(value);
  const char *raw = [candidate UTF8String];
  if ([candidate length] == 0 || raw == NULL) {
    return NO;
  }
  struct in_addr ipv4;
  memset(&ipv4, 0, sizeof(ipv4));
  if (inet_pton(AF_INET, raw, &ipv4) == 1) {
    memcpy(bytesOut, &ipv4, 4);
    *familyOut = AF_INET;
    return YES;
  }
  struct in6_addr ipv6;
  memset(&ipv6, 0, sizeof(ipv6));
  if (inet_pton(AF_INET6, raw, &ipv6) == 1) {
    memcpy(bytesOut, &ipv6, 16);
    *familyOut = AF_INET6;
    if (ALNClientAddressIsIPv4Mapped(bytesOut)) {
      memmove(bytesOut, bytesOut + 12, 4);
      memset(bytesOut + 4, 0, 12);
      *familyOut = AF_INET;
      if (mappedOut != NULL) {
        *mappedOut = YES;
      }
    }
    return YES;
  }
  return NO;
}

static BOOL ALNClientAddressParseBytes(NSString *value, int *familyOut, uint8_t bytesOut[16]) {
  return ALNClientAddressParseBytesMapped(value, familyOut, bytesOut, NULL);
}

static BOOL ALNClientAddressParsePrefix(NSString *value, NSUInteger maxPrefix, NSUInteger *prefixOut) {
  NSString *trimmed = ALNClientAddressTrimmed(value);
  if ([trimmed length] == 0 ||
      [trimmed rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location !=
          NSNotFound ||
      [trimmed length] > 3) {
    return NO;
  }
  NSUInteger prefix = (NSUInteger)[trimmed integerValue];
  if (prefix > maxPrefix) {
    return NO;
  }
  *prefixOut = prefix;
  return YES;
}

// Parses "address[/prefix]"; a bare address is a full-length prefix. An
// IPv4-mapped range (::ffff:a.b.c.d/96..128) is the IPv4 range it maps.
static BOOL ALNClientAddressParseCIDR(NSString *cidr, int *familyOut, uint8_t bytesOut[16], NSUInteger *prefixOut) {
  NSArray *parts = [ALNClientAddressTrimmed(cidr) componentsSeparatedByString:@"/"];
  if ([parts count] == 0 || [parts count] > 2) {
    return NO;
  }
  BOOL mapped = NO;
  if (!ALNClientAddressParseBytesMapped(parts[0], familyOut, bytesOut, &mapped)) {
    return NO;
  }
  if (mapped) {
    NSUInteger prefix = 128;
    if ([parts count] == 2 && (!ALNClientAddressParsePrefix(parts[1], 128, &prefix) || prefix < 96)) {
      return NO;
    }
    *prefixOut = prefix - 96;
    return YES;
  }
  NSUInteger maxPrefix = (*familyOut == AF_INET) ? 32 : 128;
  *prefixOut = maxPrefix;
  if ([parts count] == 2) {
    return ALNClientAddressParsePrefix(parts[1], maxPrefix, prefixOut);
  }
  return YES;
}

NSString *ALNClientAddressCanonicalIP(NSString *value) {
  int family = 0;
  uint8_t bytes[16];
  if (!ALNClientAddressParseBytes(value, &family, bytes)) {
    return nil;
  }
  char text[INET6_ADDRSTRLEN + 1];
  memset(text, 0, sizeof(text));
  if (inet_ntop(family, bytes, text, sizeof(text)) == NULL) {
    return nil;
  }
  return [NSString stringWithUTF8String:text];
}

BOOL ALNClientAddressCIDRIsValid(NSString *cidr) {
  int family = 0;
  uint8_t bytes[16];
  NSUInteger prefix = 0;
  return ALNClientAddressParseCIDR(cidr, &family, bytes, &prefix);
}

static BOOL ALNClientAddressMatchesCIDR(int ipFamily, const uint8_t ipBytes[16], NSString *cidr) {
  int cidrFamily = 0;
  uint8_t cidrBytes[16];
  NSUInteger prefix = 0;
  if (!ALNClientAddressParseCIDR(cidr, &cidrFamily, cidrBytes, &prefix) || cidrFamily != ipFamily) {
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

BOOL ALNClientAddressMatchesAnyCIDR(NSString *ip, NSArray *cidrs) {
  int family = 0;
  uint8_t bytes[16];
  if (![cidrs isKindOfClass:[NSArray class]] || !ALNClientAddressParseBytes(ip, &family, bytes)) {
    return NO;
  }
  for (id cidr in cidrs) {
    if ([cidr isKindOfClass:[NSString class]] && ALNClientAddressMatchesCIDR(family, bytes, cidr)) {
      return YES;
    }
  }
  return NO;
}

NSArray *ALNClientAddressXForwardedForHops(NSString *header) {
  NSString *trimmed = ALNClientAddressTrimmed(header);
  if ([trimmed length] == 0) {
    return @[];
  }
  NSMutableArray *hops = [NSMutableArray array];
  for (NSString *part in [trimmed componentsSeparatedByString:@","]) {
    [hops addObject:ALNClientAddressTrimmed(part)];
  }
  return hops;
}

NSArray *ALNClientAddressForwardedHops(NSString *header) {
  NSString *trimmed = ALNClientAddressTrimmed(header);
  if ([trimmed length] == 0) {
    return @[];
  }
  NSMutableArray *hops = [NSMutableArray array];
  for (NSString *element in [trimmed componentsSeparatedByString:@","]) {
    for (NSString *pair in [element componentsSeparatedByString:@";"]) {
      NSString *candidate = ALNClientAddressTrimmed(pair);
      NSRange equals = [candidate rangeOfString:@"="];
      if (equals.location == NSNotFound ||
          ![[ALNClientAddressTrimmed([candidate substringToIndex:equals.location]) lowercaseString]
              isEqualToString:@"for"]) {
        continue;
      }
      NSString *value = ALNClientAddressTrimmed([candidate substringFromIndex:equals.location + 1]);
      if ([value length] >= 2 && [value hasPrefix:@"\""] && [value hasSuffix:@"\""]) {
        value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
      }
      [hops addObject:value];
      break;
    }
  }
  return hops;
}

NSString *ALNClientAddressForwardedHeaderName(NSDictionary *config) {
  NSDictionary *security = [config isKindOfClass:[NSDictionary class]] &&
                                   [config[@"security"] isKindOfClass:[NSDictionary class]]
                               ? config[@"security"]
                               : @{};
  NSString *header = [ALNClientAddressTrimmed(security[@"forwardedClientIPHeader"]) lowercaseString];
  return [header isEqualToString:@"forwarded"] ? @"forwarded" : @"x-forwarded-for";
}

BOOL ALNClientAddressForwardedHeaderSettingIsValid(id value) {
  if (value == nil) {
    return YES;
  }
  NSString *header = [ALNClientAddressTrimmed(value) lowercaseString];
  return [header isEqualToString:@"x-forwarded-for"] || [header isEqualToString:@"forwarded"];
}

NSArray *ALNClientAddressHopsFromHeader(NSString *headerName, NSString *value) {
  return [[headerName lowercaseString] isEqualToString:@"forwarded"] ? ALNClientAddressForwardedHops(value)
                                                                     : ALNClientAddressXForwardedForHops(value);
}

NSString *ALNClientAddressRateLimitKey(NSString *address, NSUInteger ipv6PrefixLength) {
  int family = 0;
  uint8_t bytes[16];
  if (!ALNClientAddressParseBytes(address, &family, bytes)) {
    return address;
  }
  NSUInteger prefix = (ipv6PrefixLength == 0 || ipv6PrefixLength > 128) ? 128 : ipv6PrefixLength;
  if (family == AF_INET6 && prefix < 128) {
    NSUInteger fullBytes = prefix / 8;
    NSUInteger remainingBits = prefix % 8;
    if (remainingBits > 0) {
      bytes[fullBytes] &= (uint8_t)(0xFF << (8 - remainingBits));
      fullBytes += 1;
    }
    memset(bytes + fullBytes, 0, 16 - fullBytes);
  }
  char text[INET6_ADDRSTRLEN + 1];
  memset(text, 0, sizeof(text));
  if (inet_ntop(family, bytes, text, sizeof(text)) == NULL) {
    return address;
  }
  NSString *canonical = [NSString stringWithUTF8String:text];
  return (family == AF_INET6 && prefix < 128) ? [NSString stringWithFormat:@"%@/%lu", canonical, (unsigned long)prefix]
                                              : canonical;
}

NSString *ALNClientAddressFromForwardedHops(NSString *directPeer,
                                            NSArray *hops,
                                            NSArray *trustedCIDRs,
                                            BOOL *unresolvedOut) {
  if (unresolvedOut != NULL) {
    *unresolvedOut = NO;
  }
  if ([trustedCIDRs count] == 0 || !ALNClientAddressMatchesAnyCIDR(directPeer, trustedCIDRs)) {
    return nil;
  }
  NSString *client = nil;
  for (NSString *hop in [hops reverseObjectEnumerator]) {
    NSString *address = ALNClientAddressCanonicalIP(hop);
    if (address == nil) {
      // An unreadable hop where the client should be: anything left of it
      // came from the client, so there is no address we can believe.
      client = nil;
      break;
    }
    client = address;
    if (!ALNClientAddressMatchesAnyCIDR(address, trustedCIDRs)) {
      break;
    }
  }
  if (client == nil && unresolvedOut != NULL) {
    *unresolvedOut = YES;
  }
  return client;
}
