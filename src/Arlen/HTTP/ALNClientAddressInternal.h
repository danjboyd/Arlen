#ifndef ALN_CLIENT_ADDRESS_INTERNAL_H
#define ALN_CLIENT_ADDRESS_INTERNAL_H

#import <Foundation/Foundation.h>

@class ALNRequest;

// Client-address helpers shared by the HTTP server (effectiveRemoteAddress,
// which the rate limiter keys on) and route policies (sourceIPAllowlist).
// Framework-internal; not exported from Arlen.h.

// `value` (an IPv4 or IPv6 address, optionally with a port, IPv6 brackets or
// a zone) in canonical form, or nil when it is not an IP address.
FOUNDATION_EXPORT NSString *ALNClientAddressCanonicalIP(NSString *value);

// YES for "address" or "address/prefix", IPv4 or IPv6.
FOUNDATION_EXPORT BOOL ALNClientAddressCIDRIsValid(NSString *cidr);

FOUNDATION_EXPORT BOOL ALNClientAddressMatchesAnyCIDR(NSString *ip, NSArray *cidrs);

// The hops of an X-Forwarded-For header, left to right, whitespace-trimmed
// and not validated.
FOUNDATION_EXPORT NSArray *ALNClientAddressXForwardedForHops(NSString *header);

// The `for=` values of an RFC 7239 Forwarded header, left to right, quotes
// removed. Elements without `for=` are skipped.
FOUNDATION_EXPORT NSArray *ALNClientAddressForwardedHops(NSString *header);

// The one header trusted proxies report the client in, from
// `security.forwardedClientIPHeader` in the app config: "x-forwarded-for"
// (the default) or "forwarded" (RFC 7239). Every reader (the server's
// effectiveRemoteAddress and route policies) uses this; the header that is not
// selected is ignored, since a proxy passes through whichever one it does not
// set.
FOUNDATION_EXPORT NSString *ALNClientAddressForwardedHeaderName(NSDictionary *config);

// NO for a `security.forwardedClientIPHeader` value other than nil,
// "X-Forwarded-For" or "Forwarded" (any case). Startup rejects those.
FOUNDATION_EXPORT BOOL ALNClientAddressForwardedHeaderSettingIsValid(id value);

// The hops of `value`, read as the header `headerName` (one of the names
// ALNClientAddressForwardedHeaderName returns).
FOUNDATION_EXPORT NSArray *ALNClientAddressHopsFromHeader(NSString *headerName, NSString *value);

// The key a rate limiter counts `address` under: the canonical IPv4 address,
// or for IPv6 its /`ipv6PrefixLength` network ("2001:db8:1:2::/64"), since a
// single IPv6 client usually controls a whole /64. A prefix of 0 or above 128
// means 128. Non-IP values are returned unchanged.
FOUNDATION_EXPORT NSString *ALNClientAddressRateLimitKey(NSString *address, NSUInteger ipv6PrefixLength);

// The client a request came from, when `directPeer` is a proxy in
// `trustedCIDRs` that appended the peer it saw to `hops`.
//
// A client can put anything at the left of the chain; only what trusted
// proxies appended at the right can be believed. So walk the hops from the
// right, skip hops that are themselves trusted proxies, and return the first
// one that is not. When every hop is a trusted proxy, the left-most is the
// client.
//
// Returns nil when `directPeer` is not a trusted proxy (`*unresolvedOut` NO:
// ignore the headers), and when there are no hops or a hop reached before the
// client is not an IP address (`*unresolvedOut` YES: forwarding that can't be
// read). The result is canonical (see ALNClientAddressCanonicalIP).
FOUNDATION_EXPORT NSString *ALNClientAddressFromForwardedHops(NSString *directPeer,
                                                              NSArray *hops,
                                                              NSArray *trustedCIDRs,
                                                              BOOL *unresolvedOut);

// What ALNHTTPServer does to every parsed request: sets
// effectiveRemoteAddress (and scheme) from the forwarded headers when the peer
// is in the top-level `trustedProxyCIDRs` (or `trustedProxy` is on), else to
// remoteAddress. Implemented in ALNHTTPServer.m.
FOUNDATION_EXPORT void ALNApplyProxyMetadata(ALNRequest *request, NSDictionary *config);

#endif
