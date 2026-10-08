# ALNMarkdownInlineSpanSyntax

- Kind: `interface`
- Header: `src/Arlen/Support/ALNMarkdown.h`

Custom inline span syntax such as `⟦red⟧text⟦/red⟧`, delivered as ALNMarkdownNodeTypeInlineSpan nodes.

## Typical Usage

```objc
ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
options.inlineSpans = @[ [ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"color"
                                                         openingDelimiter:@"⟦"
                                                         closingDelimiter:@"⟧"
                                                                    names:[NSSet setWithArray:@[ @"red" ]]] ];
```

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `identifier` | `NSString *` | `nonatomic, copy, readonly` | Public `identifier` property available on `ALNMarkdownInlineSpanSyntax`. |
| `openingDelimiter` | `NSString *` | `nonatomic, copy, readonly` | Public `openingDelimiter` property available on `ALNMarkdownInlineSpanSyntax`. |
| `closingDelimiter` | `NSString *` | `nonatomic, copy, readonly` | Public `closingDelimiter` property available on `ALNMarkdownInlineSpanSyntax`. |
| `names` | `NSSet<NSString *> *` | `nonatomic, copy, readonly, nullable` | Public `names` property available on `ALNMarkdownInlineSpanSyntax`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `syntaxWithIdentifier:openingDelimiter:closingDelimiter:names:` | `+ (nullable instancetype)syntaxWithIdentifier:(NSString *)identifier openingDelimiter:(NSString *)openingDelimiter closingDelimiter:(NSString *)closingDelimiter names:(nullable NSSet<NSString *> *)names;` | Define a custom inline span syntax. | Returns nil for an empty identifier or delimiter; pass names:nil to accept any ASCII name. |
