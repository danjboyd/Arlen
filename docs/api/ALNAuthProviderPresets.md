# ALNAuthProviderPresets

- Kind: `interface`
- Header: `src/Arlen/Support/ALNAuthProviderPresets.h`

Support services for auth, metrics, logging, performance, realtime, and adapters.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `availablePresets` | `+ (NSDictionary *)availablePresets;` | Perform `available presets` for `ALNAuthProviderPresets`. | Call on the class type, not on an instance. |
| `presetNamed:error:` | `+ (nullable NSDictionary *)presetNamed:(NSString *)presetName error:(NSError *_Nullable *_Nullable)error;` | Perform `preset named` for `ALNAuthProviderPresets`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `providerConfigurationFromPresetNamed:overrides:error:` | `+ (nullable NSDictionary *)providerConfigurationFromPresetNamed:(NSString *)presetName overrides:(nullable NSDictionary *)overrides error:(NSError *_Nullable *_Nullable)error;` | Perform `provider configuration from preset named` for `ALNAuthProviderPresets`. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
| `normalizedProvidersFromConfiguration:error:` | `+ (nullable NSDictionary *)normalizedProvidersFromConfiguration:(NSDictionary *)providersConfiguration error:(NSError *_Nullable *_Nullable)error;` | Normalize values into stable internal structure. | Call on the class type, not on an instance. Pass `NSError **` and treat a `nil` result as failure. |
