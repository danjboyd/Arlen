#import <Foundation/Foundation.h>
#import <stdio.h>

#import "ALNApplication.h"
#import "ALNDataverseClient.h"
#import "ALNDataverseQuery.h"
#import "ALNJSONSerialization.h"

static NSString *TrimmedString(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  return @"";
}

static NSString *EnvironmentString(NSString *name) {
  if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return nil;
  }
  const char *value = getenv([name UTF8String]);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  NSString *string = [NSString stringWithUTF8String:value];
  return [string length] > 0 ? string : nil;
}

static BOOL EnvironmentBool(NSString *name, BOOL fallback) {
  NSString *value = [[TrimmedString(EnvironmentString(name)) lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"] ||
      [value isEqualToString:@"y"]) {
    return YES;
  }
  if ([value isEqualToString:@"0"] || [value isEqualToString:@"false"] || [value isEqualToString:@"no"] ||
      [value isEqualToString:@"n"]) {
    return NO;
  }
  return fallback;
}

static NSString *ISO8601Now(void) {
  static NSDateFormatter *formatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  });
  return [formatter stringFromDate:[NSDate date]] ?: @"";
}

static NSString *UniqueValue(NSString *prefix) {
  NSString *sanitized = [TrimmedString(prefix) length] > 0 ? TrimmedString(prefix) : @"phase23";
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  if ([uuid length] > 12) {
    uuid = [uuid substringToIndex:12];
  }
  return [NSString stringWithFormat:@"%@_%@", sanitized, uuid];
}

static NSDictionary *ErrorPayload(NSError *error) {
  if (![error isKindOfClass:[NSError class]]) {
    return @{};
  }
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"domain"] = error.domain ?: @"";
  payload[@"code"] = @(error.code);
  payload[@"message"] = error.localizedDescription ?: @"";
  NSError *underlying = [error.userInfo[NSUnderlyingErrorKey] isKindOfClass:[NSError class]]
                            ? error.userInfo[NSUnderlyingErrorKey]
                            : nil;
  if (underlying != nil) {
    payload[@"underlying"] = @{
      @"domain" : underlying.domain ?: @"",
      @"code" : @(underlying.code),
      @"message" : underlying.localizedDescription ?: @"",
    };
  }
  return [payload copy];
}

static BOOL WriteManifest(NSString *path, NSDictionary *payload, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *resolvedPath = [path stringByStandardizingPath];
  NSString *directory = [resolvedPath stringByDeletingLastPathComponent];
  NSError *directoryError = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&directoryError]) {
    if (error != NULL) {
      *error = directoryError;
    }
    return NO;
  }
  NSData *json = [ALNJSONSerialization dataWithJSONObject:payload ?: @{}
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
  if (json == nil) {
    return NO;
  }
  return [json writeToFile:resolvedPath options:NSDataWritingAtomic error:error];
}

static NSString *StringValue(id value) {
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return [value stringValue];
  }
  return nil;
}

static NSArray<NSString *> *UniqueFields(NSArray<NSString *> *fields) {
  NSMutableOrderedSet<NSString *> *ordered = [NSMutableOrderedSet orderedSet];
  for (NSString *field in fields) {
    NSString *normalized = TrimmedString(field);
    if ([normalized length] > 0) {
      [ordered addObject:normalized];
    }
  }
  return [ordered array];
}

static ALNDataverseRecord *FetchRecordByAlternateKey(ALNDataverseClient *client,
                                                     NSString *entitySet,
                                                     NSString *alternateKeyField,
                                                     NSString *alternateKeyValue,
                                                     NSArray<NSString *> *selectFields,
                                                     NSUInteger maxAttempts,
                                                     BOOL allowMissing,
                                                     NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  for (NSUInteger attempt = 0; attempt < MAX((NSUInteger)1, maxAttempts); attempt++) {
    NSError *queryError = nil;
    ALNDataverseQuery *query = [ALNDataverseQuery queryWithEntitySetName:entitySet error:&queryError];
    if (query == nil) {
      if (error != NULL) {
        *error = queryError;
      }
      return nil;
    }
    query = [query queryBySettingSelectFields:selectFields];
    query = [query queryBySettingPredicate:@{
      alternateKeyField : alternateKeyValue ?: @"",
    }];
    query = [query queryBySettingTop:@1];

    NSError *pageError = nil;
    ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&pageError];
    if (page != nil && [page.records count] > 0) {
      return page.records[0];
    }
    if (pageError != nil) {
      if (error != NULL) {
        *error = pageError;
      }
      return nil;
    }
    if (attempt + 1 < maxAttempts) {
      [NSThread sleepForTimeInterval:1.0];
    }
  }

  if (allowMissing) {
    return nil;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                 code:1
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"Dataverse live smoke query did not return the expected record",
                               @"entity_set" : entitySet ?: @"",
                               @"alternate_key_field" : alternateKeyField ?: @"",
                               @"alternate_key_value" : alternateKeyValue ?: @"",
                             }];
  }
  return nil;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *outputPath =
        EnvironmentString(@"ARLEN_PHASE23_LIVE_SMOKE_OUTPUT") ?:
        [[[NSFileManager defaultManager] currentDirectoryPath]
            stringByAppendingPathComponent:@"build/release_confidence/phase23/live_smoke/manifest.json"];
    NSString *targetName = EnvironmentString(@"ARLEN_PHASE23_DATAVERSE_TARGET") ?: @"default";
    NSString *entitySet = EnvironmentString(@"ARLEN_PHASE23_DATAVERSE_ENTITY_SET");
    NSString *idField = EnvironmentString(@"ARLEN_PHASE23_DATAVERSE_ID_FIELD");
    NSString *nameField = EnvironmentString(@"ARLEN_PHASE23_DATAVERSE_NAME_FIELD");
    NSString *alternateKeyField = EnvironmentString(@"ARLEN_PHASE23_DATAVERSE_ALTKEY_FIELD");
    NSString *formattedField = EnvironmentString(@"ARLEN_PHASE23_DATAVERSE_FORMATTED_FIELD");
    BOOL expectPaging = EnvironmentBool(@"ARLEN_PHASE23_DATAVERSE_EXPECT_PAGING", NO);
    BOOL writeEnabled = EnvironmentBool(@"ARLEN_PHASE23_DATAVERSE_WRITE_ENABLED", NO);

    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *requiredName in @[ @"ARLEN_PHASE23_DATAVERSE_ENTITY_SET", @"ARLEN_PHASE23_DATAVERSE_ID_FIELD",
                                      @"ARLEN_PHASE23_DATAVERSE_NAME_FIELD" ]) {
      if ([EnvironmentString(requiredName) length] == 0) {
        [missing addObject:requiredName];
      }
    }
    if (writeEnabled && [alternateKeyField length] == 0) {
      [missing addObject:@"ARLEN_PHASE23_DATAVERSE_ALTKEY_FIELD"];
    }

    NSMutableDictionary *checks = [NSMutableDictionary dictionary];
    NSMutableDictionary *details = [NSMutableDictionary dictionary];
    details[@"target"] = targetName;
    details[@"entity_set"] = entitySet ?: @"";
    details[@"expect_paging"] = @(expectPaging);
    details[@"write_enabled"] = @(writeEnabled);
    if ([formattedField length] > 0) {
      details[@"formatted_field"] = formattedField;
    }

    NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
    manifest[@"version"] = @"phase23-live-smoke-v1";
    manifest[@"generated_at"] = ISO8601Now();
    manifest[@"checks"] = checks;
    manifest[@"details"] = details;

    if ([missing count] > 0) {
      manifest[@"status"] = @"fail";
      manifest[@"reason"] = @"missing_env";
      manifest[@"missing_env"] = missing;
      NSError *writeError = nil;
      WriteManifest(outputPath, manifest, &writeError);
      fprintf(stderr, "phase23-live-smoke: missing required env: %s\n", [[missing componentsJoinedByString:@", "] UTF8String]);
      return 1;
    }

    NSError *error = nil;
    ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{}];
    ALNDataverseClient *client = [application dataverseClientNamed:targetName error:&error];
    NSString *cleanupRecordID = nil;
    NSString *alternateKeyValue = nil;

    @try {
      if (client == nil) {
        @throw error ?: [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                            code:2
                                        userInfo:@{
                                          NSLocalizedDescriptionKey : @"failed to resolve Dataverse client from environment",
                                        }];
      }

      NSDictionary *ping = [client ping:&error];
      if (ping == nil) {
        @throw error ?: [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                            code:3
                                        userInfo:@{
                                          NSLocalizedDescriptionKey : @"Dataverse ping failed",
                                        }];
      }
      checks[@"auth"] = @"pass";
      details[@"ping_keys"] = [[ping allKeys] sortedArrayUsingSelector:@selector(compare:)];

      NSArray<NSString *> *selectFields =
          UniqueFields(@[ idField ?: @"", nameField ?: @"", alternateKeyField ?: @"", formattedField ?: @"" ]);
      ALNDataverseQuery *query = [ALNDataverseQuery queryWithEntitySetName:entitySet error:&error];
      if (query == nil) {
        @throw error;
      }
      query = [query queryBySettingSelectFields:selectFields];
      query = [query queryBySettingTop:@1];
      query = [query queryBySettingIncludeCount:YES];
      query = [query queryBySettingIncludeFormattedValues:YES];

      ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&error];
      if (page == nil) {
        @throw error;
      }
      if ([page.records count] == 0) {
        @throw [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                   code:4
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Dataverse live smoke read returned zero records",
                                 @"entity_set" : entitySet ?: @"",
                               }];
      }
      checks[@"read"] = @"pass";
      checks[@"count"] = (page.totalCount != nil) ? @"pass" : @"fail";
      if (page.totalCount != nil) {
        details[@"total_count"] = page.totalCount;
      }
      ALNDataverseRecord *record = page.records[0];
      NSString *firstRecordID = StringValue(record.values[idField]);
      if ([firstRecordID length] > 0) {
        details[@"first_record_id"] = firstRecordID;
      }
      if ([formattedField length] > 0) {
        checks[@"formatted_values"] =
            ([TrimmedString(record.formattedValues[formattedField]) length] > 0) ? @"pass" : @"fail";
      } else {
        checks[@"formatted_values"] = @"skipped";
      }
      if (expectPaging) {
        if ([page.nextLinkURLString length] == 0) {
          checks[@"paging"] = @"fail";
        } else {
          ALNDataverseEntityPage *nextPage = [client fetchNextPageWithURLString:page.nextLinkURLString error:&error];
          if (nextPage == nil || [nextPage.records count] == 0) {
            @throw error ?: [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                                code:5
                                            userInfo:@{
                                              NSLocalizedDescriptionKey : @"Dataverse live smoke paging request failed",
                                            }];
          }
          checks[@"paging"] = @"pass";
        }
      } else {
        checks[@"paging"] = ([page.nextLinkURLString length] > 0) ? @"pass" : @"skipped";
      }

      if (writeEnabled) {
        alternateKeyValue = UniqueValue(@"phase23dv");
        NSString *createdName = [NSString stringWithFormat:@"Arlen Phase23 %@", alternateKeyValue];
        NSDictionary *createResult = [client upsertRecordInEntitySet:entitySet
                                                   alternateKeyValues:@{ alternateKeyField : alternateKeyValue }
                                                               values:@{ nameField : createdName }
                                                            createOnly:YES
                                                            updateOnly:NO
                                                   returnRepresentation:NO
                                                                error:&error];
        if (createResult == nil) {
          @throw error;
        }
        checks[@"upsert_create"] = @"pass";

        ALNDataverseRecord *createdRecord = FetchRecordByAlternateKey(client,
                                                                      entitySet,
                                                                      alternateKeyField,
                                                                      alternateKeyValue,
                                                                      selectFields,
                                                                      5,
                                                                      NO,
                                                                      &error);
        if (createdRecord == nil) {
          @throw error;
        }
        cleanupRecordID = StringValue(createdRecord.values[idField]);
        if ([cleanupRecordID length] == 0) {
          @throw [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                     code:6
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"created Dataverse record did not include the configured id field",
                                   @"id_field" : idField ?: @"",
                                 }];
        }

        NSString *updatedName = [NSString stringWithFormat:@"%@ Updated", createdName];
        NSDictionary *updateResult = [client upsertRecordInEntitySet:entitySet
                                                   alternateKeyValues:@{ alternateKeyField : alternateKeyValue }
                                                               values:@{ nameField : updatedName }
                                                            createOnly:NO
                                                            updateOnly:YES
                                                   returnRepresentation:NO
                                                                error:&error];
        if (updateResult == nil) {
          @throw error;
        }
        checks[@"upsert_update"] = @"pass";

        ALNDataverseRecord *updatedRecord = FetchRecordByAlternateKey(client,
                                                                      entitySet,
                                                                      alternateKeyField,
                                                                      alternateKeyValue,
                                                                      selectFields,
                                                                      5,
                                                                      NO,
                                                                      &error);
        if (updatedRecord == nil) {
          @throw error;
        }
        if (![[TrimmedString(updatedRecord.values[nameField]) lowercaseString]
                isEqualToString:[[TrimmedString(updatedName) lowercaseString]
                                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]) {
          @throw [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                     code:7
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Dataverse live smoke update did not persist the expected field value",
                                   @"field" : nameField ?: @"",
                                 }];
        }

        if (![client deleteRecordInEntitySet:entitySet recordID:cleanupRecordID ifMatch:nil error:&error]) {
          @throw error;
        }
        ALNDataverseRecord *deletedRecord = FetchRecordByAlternateKey(client,
                                                                      entitySet,
                                                                      alternateKeyField,
                                                                      alternateKeyValue,
                                                                      selectFields,
                                                                      3,
                                                                      YES,
                                                                      &error);
        if (deletedRecord != nil) {
          @throw [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                     code:8
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Dataverse live smoke delete did not remove the created record",
                                 }];
        }
        cleanupRecordID = nil;
        checks[@"delete"] = @"pass";
      } else {
        checks[@"upsert_create"] = @"skipped";
        checks[@"upsert_update"] = @"skipped";
        checks[@"delete"] = @"skipped";
      }
    } @catch (NSError *caughtError) {
      error = caughtError;
    } @catch (NSException *exception) {
      error = [NSError errorWithDomain:@"Arlen.Phase23.LiveSmoke"
                                  code:9
                              userInfo:@{
                                NSLocalizedDescriptionKey : exception.reason ?: @"unexpected live smoke exception",
                              }];
    }

    if ([cleanupRecordID length] > 0 && client != nil) {
      [client deleteRecordInEntitySet:entitySet recordID:cleanupRecordID ifMatch:nil error:NULL];
    }

    BOOL hasFailure = NO;
    for (NSString *status in [checks allValues]) {
      if ([status isEqualToString:@"fail"]) {
        hasFailure = YES;
        break;
      }
    }
    if (error != nil) {
      hasFailure = YES;
      manifest[@"error"] = ErrorPayload(error);
    }
    manifest[@"status"] = hasFailure ? @"fail" : @"pass";
    manifest[@"reason"] = hasFailure ? @"live_smoke_failed" : @"";

    NSError *writeError = nil;
    if (!WriteManifest(outputPath, manifest, &writeError)) {
      fprintf(stderr, "phase23-live-smoke: failed to write manifest: %s\n",
              [[writeError localizedDescription] UTF8String]);
      return 1;
    }

    fprintf(stdout, "phase23-live-smoke: wrote %s (%s)\n",
            [outputPath UTF8String],
            [manifest[@"status"] UTF8String]);
    return hasFailure ? 1 : 0;
  }
}
