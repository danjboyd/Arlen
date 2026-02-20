# Ecosystem Services

Phase 3E introduces optional ecosystem service abstractions with plugin-first wiring.

## 1. Service Contracts

Arlen now includes these adapter protocols:

- `ALNJobAdapter`
- `ALNCacheAdapter`
- `ALNLocalizationAdapter`
- `ALNMailAdapter`
- `ALNAttachmentAdapter`

Default in-memory adapters are provided:

- `ALNInMemoryJobAdapter`
- `ALNInMemoryCacheAdapter`
- `ALNInMemoryLocalizationAdapter`
- `ALNInMemoryMailAdapter`
- `ALNInMemoryAttachmentAdapter`

## 2. Plugin-First Wiring

Plugins can replace adapters during app registration:

```objc
@interface MyServicesPlugin : NSObject <ALNPlugin>
@end

@implementation MyServicesPlugin

- (NSString *)pluginName {
  return @"my_services_plugin";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)error;
  [application setJobsAdapter:[[ALNInMemoryJobAdapter alloc] initWithAdapterName:@"my_jobs"]];
  [application setCacheAdapter:[[ALNInMemoryCacheAdapter alloc] initWithAdapterName:@"my_cache"]];
  return YES;
}

@end
```

## 3. Controller Access

Controllers can access adapters through `ALNController` helpers:

- `jobsAdapter`
- `cacheAdapter`
- `localizationAdapter`
- `mailAdapter`
- `attachmentAdapter`
- `localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:`

Example:

```objc
- (id)show:(ALNContext *)ctx {
  (void)ctx;
  NSString *message = [self localizedStringForKey:@"home.greeting"
                                           locale:nil
                                   fallbackLocale:nil
                                     defaultValue:@"Hello %{name}"
                                        arguments:@{ @"name" : @"Arlen" }];
  return @{ @"message" : message ?: @"" };
}
```

## 4. Jobs Baseline

`ALNJobAdapter` baseline behavior:

1. enqueue (`enqueueJobNamed:payload:options:error:`)
2. dequeue due jobs (`dequeueDueJobAt:error:`)
3. acknowledge or retry (`acknowledgeJobID:error:`, `retryJob:delaySeconds:error:`)
4. inspect queue/dead-letter snapshots

`options.maxAttempts` controls retry budget.

## 5. Cache Baseline

`ALNCacheAdapter` supports:

- set with optional TTL (`setObject:forKey:ttlSeconds:error:`)
- point lookup at a specific timestamp (`objectForKey:atTime:error:`)
- remove/clear

## 6. I18n Baseline

`ALNLocalizationAdapter` supports:

- locale catalog registration (`registerTranslations:locale:error:`)
- lookup with fallback and interpolation (`localizedStringForKey:...arguments:`)
- locale introspection (`availableLocales`)

`services.i18n.defaultLocale` and `services.i18n.fallbackLocale` control request defaults.

Environment overrides:

- `ARLEN_I18N_DEFAULT_LOCALE`
- `ARLEN_I18N_FALLBACK_LOCALE`

Legacy compatibility fallback:

- `MOJOOBJC_I18N_DEFAULT_LOCALE`
- `MOJOOBJC_I18N_FALLBACK_LOCALE`

## 7. Mail Baseline

`ALNMailAdapter` uses `ALNMailMessage` and supports:

- delivery (`deliverMessage:error:`)
- delivery snapshots (`deliveriesSnapshot`)
- reset for test isolation

## 8. Attachment Baseline

`ALNAttachmentAdapter` supports:

- save named attachment (`saveAttachmentNamed:contentType:data:metadata:error:`)
- fetch data + metadata (`attachmentDataForID:metadata:error:`)
- metadata/list/delete helpers

## 9. Compatibility Suites

Phase 3E includes adapter compatibility suites:

- `ALNRunJobAdapterConformanceSuite`
- `ALNRunCacheAdapterConformanceSuite`
- `ALNRunLocalizationAdapterConformanceSuite`
- `ALNRunMailAdapterConformanceSuite`
- `ALNRunAttachmentAdapterConformanceSuite`
- `ALNRunServiceCompatibilitySuite`

These are intended for plugin adapter verification.

## 10. Boomhauer Service Routes

Built-in sample routes in `boomhauer`:

- `/services/cache`
- `/services/jobs`
- `/services/i18n`
- `/services/mail`
- `/services/attachments`
