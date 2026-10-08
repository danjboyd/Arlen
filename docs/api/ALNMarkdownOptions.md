# ALNMarkdownOptions

- Kind: `interface`
- Header: `src/Arlen/Support/ALNMarkdown.h`

Parsing and rendering settings for ALNMarkdown: GFM extensions, inline spans, nesting limit, URL scheme allowlists, HTML class map.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `inlineSpans` | `ALNMarkdownExtensions extensions; // All @property(nonatomic, assign) BOOL smartPunctuation; // NO @property(nonatomic, copy) NSArray<ALNMarkdownInlineSpanSyntax *> *` | `nonatomic, assign` | Public `inlineSpans` property available on `ALNMarkdownOptions`. |
| `maximumNestingDepth` | `NSUInteger` | `nonatomic, assign` | Public `maximumNestingDepth` property available on `ALNMarkdownOptions`. |
| `HTMLClassMap` | `BOOL hardBreaks; // soft line breaks render as <br />; NO // Schemes (lowercase) a link or image URL may use. URLs without a scheme // (relative paths, fragments) are always allowed. A link with any other // scheme renders as its text; an image as its alt text. @property(nonatomic, copy) NSArray<NSString *> *allowedLinkSchemes; // http, https, mailto @property(nonatomic, copy) NSArray<NSString *> *allowedImageSchemes; // http, https // HTML element name -> class attribute value, e.g. @{ @"table" : @"md-table" }. // Element names: p h1-h6 blockquote ul ol li pre code hr table thead tbody tr // th td em strong del a img input span. An inline span uses the first of // "span.<identifier>.<name>", "span.<identifier>" and "span" present. @property(nonatomic, copy) NSDictionary<NSString *, NSString *> *` | `nonatomic, assign` | Public `HTMLClassMap` property available on `ALNMarkdownOptions`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `defaultOptions` | `+ (instancetype)defaultOptions;` | Return options with all GFM extensions on and safe URL allowlists. | Copy and adjust; options are copied when passed to ALNMarkdown. |
