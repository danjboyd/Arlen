#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNClientAddressInternal.h"

@interface ClientAddressTests : XCTestCase
@end

@implementation ClientAddressTests

- (NSString *)clientFromPeer:(NSString *)peer xForwardedFor:(NSString *)header trusted:(NSArray *)trusted {
  return ALNClientAddressFromForwardedHops(peer, ALNClientAddressXForwardedForHops(header), trusted, NULL);
}

- (void)testCanonicalIPAcceptsAddressesWithPortsBracketsAndZones {
  XCTAssertEqualObjects(@"203.0.113.9", ALNClientAddressCanonicalIP(@" 203.0.113.9 "));
  XCTAssertEqualObjects(@"203.0.113.9", ALNClientAddressCanonicalIP(@"203.0.113.9:4711"));
  XCTAssertEqualObjects(@"2001:db8::1", ALNClientAddressCanonicalIP(@"2001:DB8:0:0::1"));
  XCTAssertEqualObjects(@"2001:db8::1", ALNClientAddressCanonicalIP(@"[2001:db8::1]:4711"));
  XCTAssertEqualObjects(@"fe80::1", ALNClientAddressCanonicalIP(@"fe80::1%eth0"));
}

- (void)testCanonicalIPRejectsNonAddresses {
  for (NSString *value in @[ @"", @"unknown", @"_hidden", @"203.0.113", @"203.0.113.256", @"[2001:db8::1]x",
                             @"999.1.1.1", @"example.com" ]) {
    XCTAssertNil(ALNClientAddressCanonicalIP(value), @"%@", value);
  }
  XCTAssertNil(ALNClientAddressCanonicalIP(nil));
}

- (void)testCIDRValidationAndMatchingCoverIPv4AndIPv6 {
  XCTAssertTrue(ALNClientAddressCIDRIsValid(@"10.0.0.0/8"));
  XCTAssertTrue(ALNClientAddressCIDRIsValid(@"2001:db8::/32"));
  XCTAssertTrue(ALNClientAddressCIDRIsValid(@"127.0.0.1"));
  XCTAssertFalse(ALNClientAddressCIDRIsValid(@"10.0.0.0/33"));
  XCTAssertFalse(ALNClientAddressCIDRIsValid(@"2001:db8::/129"));
  XCTAssertFalse(ALNClientAddressCIDRIsValid(@"10.0.0.0/x"));
  XCTAssertFalse(ALNClientAddressCIDRIsValid(@"10.0.0.0/8/1"));

  XCTAssertTrue(ALNClientAddressMatchesAnyCIDR(@"10.1.2.3", @[ @"192.0.2.0/24", @"10.0.0.0/8" ]));
  XCTAssertFalse(ALNClientAddressMatchesAnyCIDR(@"11.1.2.3", @[ @"10.0.0.0/8" ]));
  XCTAssertTrue(ALNClientAddressMatchesAnyCIDR(@"2001:db8::42", @[ @"2001:db8::/32" ]));
  XCTAssertFalse(ALNClientAddressMatchesAnyCIDR(@"2001:db9::42", @[ @"2001:db8::/32" ]));
  XCTAssertFalse(ALNClientAddressMatchesAnyCIDR(@"10.1.2.3", @[ @"::/0" ]));
  XCTAssertFalse(ALNClientAddressMatchesAnyCIDR(@"not-an-ip", @[ @"0.0.0.0/0" ]));
}

// nginx's $proxy_add_x_forwarded_for (and most load balancers) append the
// peer they saw to whatever the client sent.
- (void)testAppendedXForwardedForResolvesToThePeerTheProxySaw {
  NSArray *trusted = @[ @"127.0.0.1/32" ];
  XCTAssertEqualObjects(@"203.0.113.9", [self clientFromPeer:@"127.0.0.1"
                                                xForwardedFor:@"203.0.113.9"
                                                      trusted:trusted]);
  XCTAssertEqualObjects(@"203.0.113.9", [self clientFromPeer:@"127.0.0.1"
                                                xForwardedFor:@"10.1.1.1, 203.0.113.9"
                                                      trusted:trusted]);
  XCTAssertEqualObjects(@"203.0.113.9", [self clientFromPeer:@"127.0.0.1"
                                                xForwardedFor:@"garbage, 10.1.1.1,203.0.113.9"
                                                      trusted:trusted]);
}

- (void)testChainsOfTrustedProxiesAreSkippedFromTheRight {
  NSArray *trusted = @[ @"127.0.0.1/32", @"10.0.0.0/8" ];
  // client -> edge LB (10.0.0.5) -> nginx (127.0.0.1) -> app
  XCTAssertEqualObjects(@"203.0.113.9", [self clientFromPeer:@"127.0.0.1"
                                                xForwardedFor:@"198.51.100.1, 203.0.113.9, 10.0.0.5"
                                                      trusted:trusted]);
  // Every hop is a trusted proxy: the left-most is the client.
  XCTAssertEqualObjects(@"10.0.0.7", [self clientFromPeer:@"127.0.0.1"
                                             xForwardedFor:@"10.0.0.7, 10.0.0.5"
                                                   trusted:trusted]);
}

- (void)testIPv6HopsAndProxies {
  NSArray *trusted = @[ @"::1/128", @"2001:db8:ffff::/48" ];
  XCTAssertEqualObjects(@"2001:db8::9", [self clientFromPeer:@"::1"
                                                xForwardedFor:@"2001:db8::1, [2001:DB8::9]:5000, 2001:db8:ffff::2"
                                                      trusted:trusted]);
}

- (void)testUnreadableHopsAndUntrustedPeersResolveToNothing {
  NSArray *trusted = @[ @"127.0.0.1/32" ];
  BOOL unresolved = NO;
  XCTAssertNil(ALNClientAddressFromForwardedHops(@"127.0.0.1",
                                                 ALNClientAddressXForwardedForHops(@"203.0.113.9, unknown"),
                                                 trusted,
                                                 &unresolved));
  XCTAssertTrue(unresolved);

  unresolved = NO;
  XCTAssertNil(ALNClientAddressFromForwardedHops(@"127.0.0.1", @[], trusted, &unresolved));
  XCTAssertTrue(unresolved);

  unresolved = YES;
  XCTAssertNil(ALNClientAddressFromForwardedHops(@"198.51.100.20",
                                                 ALNClientAddressXForwardedForHops(@"203.0.113.9"),
                                                 trusted,
                                                 &unresolved));
  XCTAssertFalse(unresolved);

  unresolved = YES;
  XCTAssertNil(ALNClientAddressFromForwardedHops(@"127.0.0.1",
                                                 ALNClientAddressXForwardedForHops(@"203.0.113.9"),
                                                 @[],
                                                 &unresolved));
  XCTAssertFalse(unresolved);
}

// A dual-stack listener reports IPv4 peers as ::ffff:a.b.c.d.
- (void)testIPv4MappedIPv6CanonicalizesToIPv4 {
  for (NSString *spelling in @[ @"::ffff:10.1.1.1", @"::FFFF:10.1.1.1", @"[::ffff:10.1.1.1]",
                                @"[::ffff:10.1.1.1]:4711", @"0:0:0:0:0:ffff:0a01:0101", @"10.1.1.1" ]) {
    XCTAssertEqualObjects(@"10.1.1.1", ALNClientAddressCanonicalIP(spelling), @"%@", spelling);
  }
  // Not mapped: IPv4-compatible and NAT64 forms stay IPv6.
  XCTAssertEqualObjects(@"64:ff9b::a01:101", ALNClientAddressCanonicalIP(@"64:ff9b::10.1.1.1"));
}

- (void)testIPv4MappedPeersAndHopsMatchIPv4Ranges {
  NSArray *trusted = @[ @"127.0.0.1/32" ];
  XCTAssertTrue(ALNClientAddressMatchesAnyCIDR(@"::ffff:127.0.0.1", trusted));
  XCTAssertTrue(ALNClientAddressMatchesAnyCIDR(@"::ffff:10.1.1.1", @[ @"10.0.0.0/8" ]));
  XCTAssertTrue(ALNClientAddressMatchesAnyCIDR(@"10.1.1.1", @[ @"::ffff:10.0.0.0/104" ]));
  XCTAssertFalse(ALNClientAddressMatchesAnyCIDR(@"::ffff:11.1.1.1", @[ @"10.0.0.0/8" ]));
  XCTAssertFalse(ALNClientAddressCIDRIsValid(@"::ffff:10.0.0.0/95"));

  // Mapped direct peer is a trusted proxy; a mapped hop is skipped as trusted
  // and the result has the same spelling as the plain IPv4 form.
  NSArray *chain = @[ @"127.0.0.1/32", @"10.0.0.0/8" ];
  XCTAssertEqualObjects(@"203.0.113.9",
                        [self clientFromPeer:@"::ffff:127.0.0.1"
                               xForwardedFor:@"::ffff:203.0.113.9, [::FFFF:10.1.1.1]:80"
                                     trusted:chain]);
  XCTAssertEqualObjects([self clientFromPeer:@"127.0.0.1" xForwardedFor:@"203.0.113.9" trusted:trusted],
                        [self clientFromPeer:@"::ffff:127.0.0.1" xForwardedFor:@"::ffff:203.0.113.9" trusted:trusted]);
}

- (void)testForwardedHeaderHopsAreReadInOrder {
  NSArray *hops = ALNClientAddressForwardedHops(
      @"for=10.1.1.1;proto=https, proto=http, for=\"[2001:db8::9]:4711\";by=10.0.0.1, For=203.0.113.9");
  XCTAssertEqualObjects((@[ @"10.1.1.1", @"[2001:db8::9]:4711", @"203.0.113.9" ]), hops);
  XCTAssertEqualObjects(@"203.0.113.9",
                        ALNClientAddressFromForwardedHops(@"127.0.0.1", hops, @[ @"127.0.0.1/32" ], NULL));
}

@end
