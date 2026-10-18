#ifndef ALN_CLIENT_ADDRESS_INTERNAL_H
#define ALN_CLIENT_ADDRESS_INTERNAL_H

#import <Foundation/Foundation.h>

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

#endif
