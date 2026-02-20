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

Concrete backend adapter now available:

- `ALNRedisCacheAdapter` (`redis://` URL initializer, namespace isolation, and cache-conformance compatible TTL behavior)

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

Concrete backend adapter now available:

- `ALNFileSystemAttachmentAdapter` (persist attachment binaries + metadata to a configured root directory)

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

## 11. External Adapter Plugin Templates

`arlen generate plugin` now supports service-oriented presets:

- `--preset redis-cache`
- `--preset queue-jobs`
- `--preset smtp-mail`

Example:

```sh
arlen generate plugin RedisCache --preset redis-cache
arlen generate plugin QueueJobs --preset queue-jobs
arlen generate plugin SmtpMail --preset smtp-mail
```

All presets are compile-safe templates that default to in-memory adapters until you replace the template hooks with concrete backend clients.

The `redis-cache` preset now instantiates `ALNRedisCacheAdapter` directly when `ARLEN_REDIS_URL` is set.

## 12. Optional Job Worker Runtime Contract

Phase 3E follow-on adds an optional worker contract for scheduled/asynchronous execution:

- `ALNJobWorkerRuntime` (`handleJob:error:`)
- `ALNJobWorker` (`runDueJobsAt:runtime:error:`)
- `ALNJobWorkerRunSummary` (deterministic run metrics)

`ALNJobWorker` drives dequeue/ack/retry against any `ALNJobAdapter` implementation and is intentionally optional so app/server topology can remain plugin-defined.

## 13. Production Persistence and Retention Guidance

Recommended production direction by service area:

- Cache: use Redis or Memcached; reserve in-memory cache for development and tests.
- Jobs: use a durable queue backend (Redis streams, PostgreSQL queue table, or dedicated broker) for multi-process reliability.
- Mail: use SMTP/API provider adapters with provider-side retries and bounce tracking.
- Attachments: store payload bytes in object storage and keep metadata in relational records.
- I18n: keep locale catalogs versioned and deploy them with app releases.

Retention policy baseline:

1. Jobs:
   Requeue with bounded retries and move exhausted jobs to dead-letter storage.
2. Dead letters:
   Keep at least 7-30 days, with explicit replay/deletion workflows.
3. Mail:
   Retain delivery metadata and provider message IDs for audit/debug windows.
4. Attachments:
   Define lifecycle policies by bucket/path and remove orphaned metadata.
5. Cache:
   Set explicit TTLs for all keys and avoid unbounded key growth.

Operational checklist:

- Run `ALNRun*ConformanceSuite` for each custom adapter in CI.
- Alert on queue depth, retry rates, dead-letter growth, and mail delivery failures.
- Document adapter failover behavior and data-loss assumptions per environment.

Optional conformance validation with a live Redis instance:

```sh
ARLEN_REDIS_TEST_URL="redis://127.0.0.1:6379/0" make test-unit
```
