# ALNMigrationRunner

- Kind: `interface`
- Header: `src/Arlen/Data/ALNMigrationRunner.h`

Migration discovery and migration execution runner for SQL migration directories.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `migrationFilesAtPath:error:` | `+ (nullable NSArray<NSString *> *)migrationFilesAtPath:(NSString *)migrationsPath error:(NSError *_Nullable *_Nullable)error;` | List migration files from migration directory in deterministic order. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `pendingMigrationFilesAtPath:database:databaseTarget:error:` | `+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath database:(ALNPg *)database databaseTarget:(nullable NSString *)databaseTarget error:(NSError *_Nullable *_Nullable)error;` | Return migrations not yet applied for the selected database target. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `pendingMigrationFilesAtPath:database:error:` | `+ (nullable NSArray<NSString *> *)pendingMigrationFilesAtPath:(NSString *)migrationsPath database:(ALNPg *)database error:(NSError *_Nullable *_Nullable)error;` | Return pending migrations for the default database target. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `applyMigrationsAtPath:database:databaseTarget:dryRun:appliedFiles:error:` | `+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath database:(ALNPg *)database databaseTarget:(nullable NSString *)databaseTarget dryRun:(BOOL)dryRun appliedFiles:(NSArray<NSString *> *_Nullable *_Nullable)appliedFiles error:(NSError *_Nullable *_Nullable)error;` | Apply pending migrations for one database target with optional dry-run. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `applyMigrationsAtPath:database:dryRun:appliedFiles:error:` | `+ (BOOL)applyMigrationsAtPath:(NSString *)migrationsPath database:(ALNPg *)database dryRun:(BOOL)dryRun appliedFiles:(NSArray<NSString *> *_Nullable *_Nullable)appliedFiles error:(NSError *_Nullable *_Nullable)error;` | Apply pending migrations for default target with optional dry-run. | Call on the class type, not on an instance. Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. |
| `versionForMigrationFile:` | `+ (NSString *)versionForMigrationFile:(NSString *)filePath;` | Extract migration version prefix from migration filename. | Call on the class type, not on an instance. |
