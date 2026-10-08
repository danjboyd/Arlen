# Markdown

Arlen renders Markdown through `ALNMarkdown` (`#import "ALNMarkdown.h"`, also
in `Arlen.h`). Parsing is done by [cmark-gfm](https://github.com/github/cmark-gfm),
the CommonMark reference implementation with GitHub's extensions. It is vendored
at `src/Arlen/Support/third_party/cmark-gfm` and compiled into the framework,
so apps need no host package.

What you get:

- a node tree you can walk to write your own renderers (email HTML, chat
  formats, anything else)
- an HTML renderer that is safe for untrusted input by default
- a plain-text renderer for search, classifiers and text-only channels
- GFM tables, task lists, strikethrough and autolinks, each switchable per call
- custom inline spans such as `⟦red⟧text⟦/red⟧`, delivered as typed nodes
- an EOC helper, `ALNEOCMarkdownHTML()`

## Basic Usage

```objc
NSString *html = [ALNMarkdown HTMLFromString:@"**Hello** from _Arlen_" options:nil];
// <p><strong>Hello</strong> from <em>Arlen</em></p>\n

NSString *text = [ALNMarkdown plainTextFromString:@"See [the docs](https://example.com)." options:nil];
// See the docs (https://example.com).
```

Parsing never fails. `nil` input renders as an empty string, and NUL characters
become U+FFFD.

In a template, render a Markdown string with raw output:

```html
<article><%== ALNEOCMarkdownHTML($message.body) %></article>
```

`ALNEOCMarkdownHTML` uses the default options and is safe for user-written
input, which is why raw output (`<%== %>`) is correct here. `nil` and `NSNull`
render as nothing. For other options, render in the controller with
`+HTMLFromString:options:` and pass the result in.

## Safe HTML

The built-in HTML renderer follows CommonMark's HTML output exactly (the GFM
spec examples are part of the unit tests), with these deliberate differences:

- **Raw HTML is escaped, not passed through.** `<script>alert(1)</script>` in
  the source renders as the visible text `&lt;script&gt;…`. An HTML block becomes
  a paragraph of that text; inline HTML becomes text in place.
- **Link URLs are limited to `http`, `https` and `mailto`; image URLs to `http`
  and `https`.** A link with any other scheme (`javascript:`, `data:`,
  `vbscript:`, `file:`, …) renders as its text with no `<a>`; an image as its
  alt text. URLs without a scheme (`/docs`, `#top`, `page.html`) are allowed.
  The scheme check matches what a browser does: case is ignored, and tabs,
  newlines and leading control characters are removed first, so
  `java&#x09;script:` is still caught.
- **Every attribute value is escaped**, including link titles, image alt text
  and code-fence language names.

Change the allowlists with `allowedLinkSchemes` and `allowedImageSchemes`.

## Options

`ALNMarkdownOptions` holds both parsing and rendering settings. Start from
`+defaultOptions`; options are copied when you pass them in.

| Property | Default | Effect |
|---|---|---|
| `extensions` | `ALNMarkdownExtensionAll` | Tables, task lists, strikethrough and autolinks; clear bits to turn any off |
| `smartPunctuation` | `NO` | Curly quotes, en/em dashes, ellipses |
| `inlineSpans` | `@[]` | Custom inline span syntaxes (below) |
| `maximumNestingDepth` | `64` | Blocks and inlines nested deeper become plain text |
| `hardBreaks` | `NO` | Render soft line breaks as `<br />` (useful for chat-style messages) |
| `allowedLinkSchemes` | `http`, `https`, `mailto` | Schemes a link may use |
| `allowedImageSchemes` | `http`, `https` | Schemes an image may use |
| `HTMLClassMap` | `@{}` | `class` attributes to add, by element name |

`maximumNestingDepth` exists because the renderers are recursive. Without it, a
hostile 20 KB document of nested `>` or list markers could exhaust a worker
thread's stack. Content beyond the limit is kept, as text.

### Styling with a class map

`HTMLClassMap` maps an element name to a class attribute, so output can be
styled without post-processing:

```objc
ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
options.HTMLClassMap = @{ @"table" : @"table table-sm", @"blockquote" : @"quote", @"a" : @"link" };
```

Element names are `p`, `h1`–`h6`, `blockquote`, `ul`, `ol`, `li`, `pre`,
`code`, `hr`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `em`, `strong`,
`del`, `a`, `img`, `input` (task-list checkboxes) and `span` (inline spans).
A fenced code block keeps its `language-…` class and gets the `code` class
after it.

## Custom Inline Spans

An inline span syntax is an opening marker, a name and a closing marker around
inline content, such as `⟦red⟧text⟦/red⟧`:

```objc
ALNMarkdownInlineSpanSyntax *color =
    [ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"color"
                                     openingDelimiter:@"⟦"
                                     closingDelimiter:@"⟧"
                                                names:[NSSet setWithArray:@[ @"red", @"green", @"blue" ]]];
ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
options.inlineSpans = @[ color ];

ALNMarkdownNode *document = [ALNMarkdown parseString:@"Status: ⟦red⟧**down**⟦/red⟧" options:options];
```

The span becomes an `ALNMarkdownNodeTypeInlineSpan` node with `spanIdentifier`
`@"color"` and `spanName` `@"red"`; its children are the parsed inline content
(here a strong node). The rules:

- A span may wrap other inline Markdown (emphasis, links, code).
- It must open and close inside the same inline container: `⟦red⟧**x⟦/red⟧**`
  stays literal.
- Spans do not nest. Markers inside an open span stay literal text.
- Unknown names, unmatched markers and markers inside code stay literal.
- `names:nil` accepts any name made of ASCII letters, digits, `-` and `_`.

The HTML renderer writes
`<span data-markdown-span="color" data-value="red">…</span>`, with a class from
`HTMLClassMap` under `span.color.red`, `span.color` or `span` (first found).
Renderers that need inline styles, such as for email, walk the tree instead.

## The Node Tree

`+parseString:options:` returns the document node. Each `ALNMarkdownNode` has a
`type` and `children`, plus the fields that apply to its type:

| Type | Fields |
|---|---|
| `Heading` | `headingLevel` (1–6) |
| `List` | `listType` (bullet or ordered), `listStart`, `listTight` |
| `Item` | `isTaskListItem`, `isChecked` |
| `CodeBlock` | `literal`, `fenceInfo` |
| `HTMLBlock`, `HTMLInline` | `literal` (the raw HTML, as text) |
| `Text`, `Code` | `literal` |
| `Link`, `Image` | `URL` (as written), `title` |
| `TableRow` | `isHeaderRow` |
| `TableCell` | `alignment` |
| `InlineSpan` | `spanIdentifier`, `spanName` |

Other types are `Document`, `BlockQuote`, `Paragraph`, `ThematicBreak`,
`Table`, `SoftBreak`, `LineBreak`, `Emphasis`, `Strong` and `Strikethrough`.
`-textContent` returns a node's text with markup removed.

A custom renderer is a recursive walk:

```objc
static void AppendTeamsHTML(ALNMarkdownNode *node, NSMutableString *out) {
  switch (node.type) {
  case ALNMarkdownNodeTypeText:
    [out appendString:EscapeForTeams(node.literal)];
    return;
  case ALNMarkdownNodeTypeStrong:
    [out appendString:@"<b>"];
    for (ALNMarkdownNode *child in node.children) AppendTeamsHTML(child, out);
    [out appendString:@"</b>"];
    return;
  // …
  default:
    for (ALNMarkdownNode *child in node.children) AppendTeamsHTML(child, out);
  }
}
```

`URL` is the URL exactly as written. A custom renderer must apply its own
scheme allowlist before emitting a link, and must escape every literal.

## Plain Text

`+plainTextFromString:options:` and `+plainTextFromNode:` remove markup but keep
the text readable:

- Emphasis, code and heading markers are dropped.
- A link whose text differs from its URL becomes `text (URL)`; an autolink is
  just the URL; an image is `alt (URL)`.
- Lists keep `- ` and `1. ` markers, nested two spaces deeper; task items keep
  `[ ]` and `[x]`.
- Block quotes keep a `> ` prefix.
- Table cells are separated by ` | `, one row per line.
- Code blocks and raw HTML are kept as their text; thematic breaks are dropped.
- Blocks are separated by blank lines, and there is no trailing newline.

## Updating cmark-gfm

`src/Arlen/Support/third_party/cmark-gfm/PROVENANCE.md` records the imported
version, the files taken and the local changes, with the steps for an update.
`+[ALNMarkdown cmarkGFMVersion]` reports the version compiled in.
