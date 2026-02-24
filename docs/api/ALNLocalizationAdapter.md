# ALNLocalizationAdapter

- Kind: `protocol`
- Header: `src/Arlen/Support/ALNServices.h`

Localization adapter protocol for translation registration, lookup, and locale discovery.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `adapterName` | `- (NSString *)adapterName;` | Return the stable identifier for this plugin/adapter implementation. | Read this value when you need current runtime/request state. |
| `registerTranslations:locale:error:` | `- (BOOL)registerTranslations:(NSDictionary *)translations locale:(NSString *)locale error:(NSError *_Nullable *_Nullable)error;` | Register localized string table for one locale. | Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter. Call during bootstrap/setup before this behavior is exercised. |
| `localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:` | `- (NSString *)localizedStringForKey:(NSString *)key locale:(NSString *)locale fallbackLocale:(NSString *)fallbackLocale defaultValue:(NSString *)defaultValue arguments:(nullable NSDictionary *)arguments;` | Resolve localized string with fallback/default and interpolation args. | Capture the returned value and propagate errors/validation as needed. |
| `availableLocales` | `- (NSArray *)availableLocales;` | Return locales currently available in this localization adapter. | Read this value when you need current runtime/request state. |
