# ALNConfig

- Kind: `interface`
- Header: `src/Arlen/Core/ALNConfig.h`

Configuration loader that merges base + environment plist files into the runtime config dictionary.

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `loadConfigAtRoot:environment:error:` | `+ (NSDictionary *)loadConfigAtRoot:(NSString *)rootPath environment:(NSString *)environment error:(NSError *_Nullable *_Nullable)error;` | Load and normalize configuration data. | Call on the class type, not on an instance. Pass `NSError **` when you need detailed failure diagnostics. |
