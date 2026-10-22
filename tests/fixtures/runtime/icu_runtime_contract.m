#import <Foundation/Foundation.h>

#include <stdio.h>
#include <unicode/icudataver.h>
#include <unicode/ucal.h>
#include <unicode/uversion.h>

// Fixed UTC instants exercise system zoneinfo through NSTimeZone and distro
// ICU data through NSDateFormatter, independently of the machine's local zone.
int main(void) {
  @autoreleasepool {
    UVersionInfo version, dataVersion;
    char versionText[U_MAX_VERSION_STRING_LENGTH], dataText[U_MAX_VERSION_STRING_LENGTH];
    UErrorCode status = U_ZERO_ERROR;
    u_getVersion(version);
    u_versionToString(version, versionText);
    u_getDataVersion(dataVersion, &status);
    if (U_FAILURE(status)) return 10;
    u_versionToString(dataVersion, dataText);
    const char *tzVersion = ucal_getTZDataVersion(&status);
    if (U_FAILURE(status) || !tzVersion) return 11;

    NSTimeZone *zone = [NSTimeZone timeZoneWithName:@"America/Chicago"];
    NSDate *winter = [NSDate dateWithTimeIntervalSince1970:1768478400.0];
    NSDate *summer = [NSDate dateWithTimeIntervalSince1970:1784116800.0];
    if (!zone || [zone secondsFromGMTForDate:winter] != -21600 ||
        [zone secondsFromGMTForDate:summer] != -18000) return 12;

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = zone;
    formatter.dateFormat = @"yyyy-MM-dd HH:mm Z";
    NSString *cold = [formatter stringFromDate:winter];
    NSString *warm = [formatter stringFromDate:summer];
    if (![cold isEqualToString:@"2026-01-15 06:00 -0600"] ||
        ![warm isEqualToString:@"2026-07-15 07:00 -0500"]) {
      NSLog(@"unexpected fixed-date formatting %@ / %@", cold, warm);
      return 13;
    }
    printf("ICU=%s data=%s tz=%s winter=%s summer=%s\n", versionText, dataText,
           tzVersion, cold.UTF8String, warm.UTF8String);
    puts("pass:ICU-and-Foundation-timezone-formatting");
  }
  return 0;
}
