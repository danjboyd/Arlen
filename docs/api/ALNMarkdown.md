# ALNMarkdown

- Kind: `interface`
- Header: `src/Arlen/Support/ALNMarkdown.h`

CommonMark/GFM Markdown parsing (vendored cmark-gfm) with a safe HTML renderer and a plain-text renderer.

## Typical Usage

```objc
NSString *html = [ALNMarkdown HTMLFromString:message.body options:nil];
NSString *text = [ALNMarkdown plainTextFromString:message.body options:nil];
```

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `parseString:options:` | `+ (ALNMarkdownNode *)parseString:(nullable NSString *)markdown options:(nullable ALNMarkdownOptions *)options;` | Parse Markdown into an ALNMarkdownNode document tree. | Never fails; nil input gives an empty document. Apply inline spans and the nesting limit through options. |
| `HTMLFromString:options:` | `+ (NSString *)HTMLFromString:(nullable NSString *)markdown options:(nullable ALNMarkdownOptions *)options;` | Render Markdown to HTML that is safe for untrusted input. | Raw HTML is escaped and link/image URLs are limited to the options' scheme allowlists, so the result can go through `<%== %>`. |
| `HTMLFromNode:options:` | `+ (NSString *)HTMLFromNode:(ALNMarkdownNode *)node options:(nullable ALNMarkdownOptions *)options;` | Render an already parsed node (or subtree) to safe HTML. | Pass the same options used for parsing so rendering settings such as the class map apply. |
| `plainTextFromString:options:` | `+ (NSString *)plainTextFromString:(nullable NSString *)markdown options:(nullable ALNMarkdownOptions *)options;` | Render Markdown as readable plain text without markup. | Use for search indexing, classifiers and text-only channels; link URLs follow their text in parentheses. |
| `plainTextFromNode:` | `+ (NSString *)plainTextFromNode:(ALNMarkdownNode *)node;` | Render an already parsed node as plain text. | Useful after inspecting or filtering the tree. |
| `cmarkGFMVersion` | `+ (NSString *)cmarkGFMVersion;` | Return the vendored cmark-gfm version string. | Diagnostics only. |
