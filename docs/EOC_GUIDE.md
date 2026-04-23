# EOC Guide

This is the primary guide and reference for Arlen's EOC template language.

EOC stands for Encapsulated Objective-C. It is Arlen's embedded template syntax
for `.html.eoc` files.

If you have used embedded template systems in other web frameworks, the shape
will feel familiar:

- plain HTML stays plain HTML
- delimiter tags switch briefly into host-language code
- escaped and raw output are distinct
- layouts, partials, and collection rendering are explicit

EOC follows those cues, but it is not a compatibility layer for another
framework's template syntax. EOC is compiled for Arlen and uses Objective-C
inside the template tags.

## 1. What EOC Is

EOC templates:

- live in `.html.eoc` files
- compile to Objective-C source during the template build step
- render with Objective-C/Foundation values from the current render context
- HTML-escape normal expression output by default
- treat template code as trusted application code

Important trust model:

- EOC is not a sandbox
- template code executes with normal process privileges
- raw output and arbitrary Objective-C code should be treated with the same care
  as the rest of your app code

## 2. Mental Model

An EOC template is mostly HTML with occasional tags:

- use plain text for markup
- use `<%= ... %>` when you want to print a value safely
- use `<% ... %>` when you want control flow or local Objective-C statements
- use `<%@ ... %>` for EOC composition directives such as layouts, slots,
  partials, and required locals

Typical page:

```html
<%@ layout "layouts/main" %>
<%@ requires title, items %>

<h1><%= $title %></h1>

<ul>
<% for (NSString *item in $items) { %>
  <li><%= item %></li>
<% } %>
</ul>
```

## 3. Tag Reference

EOC supports five tag forms.

### 3.1 `<% code %>`

Executes raw Objective-C statements.

Use this for:

- `if` / `else`
- `for` / `for ... in`
- local variables
- imperative helper calls

Example:

```html
<% if ([$items count] == 0) { %>
  <p>No items yet.</p>
<% } else { %>
  <p>Showing <%= @([$items count]) %> items.</p>
<% } %>
```

### 3.2 `<%= expr %>`

Evaluates an expression and appends HTML-escaped output.

Escapes:

- `&`
- `<`
- `>`
- `"`
- `'`

Use this for normal user-facing output.

Example:

```html
<h1><%= $title %></h1>
<p><%= $user.profile.email %></p>
```

### 3.3 `<%== expr %>`

Evaluates an expression and appends raw output with no escaping.

Use this only for trusted HTML that is already safe to emit.

Example:

```html
<section class="body"><%== $trustedHTML %></section>
```

### 3.4 `<%# comment %>`

Template comment. The comment is ignored by the transpiler and produces no
output.

Example:

```html
<%# This note is for template authors only. %>
```

### 3.5 `<%@ directive %>`

Directive tag used for composition and template contracts.

Supported directives are covered in [Section 7](#7-directive-reference).

## 4. Sigil Locals

EOC uses sigil locals so controller-provided values read naturally in
templates.

The `$` prefix is deliberate. In Objective-C, `user.profile.email` already looks
like normal in-scope code. EOC uses the sigil to mark render-context lookup
explicitly so templates can distinguish controller-provided locals from ordinary
Objective-C variables, ivars, methods, and temporaries.

### 4.1 Syntax

- `$identifier`
- `$identifier.segment`
- `$identifier.segment.moreSegments`

Rules:

- each segment must match `[A-Za-z_][A-Za-z0-9_]*`
- root lookup starts from the current render context
- dotted lookups traverse each segment on the current object
- locals are `id` values and may be strings, numbers, arrays, dictionaries, or
  custom objects

Examples:

```html
<%= $title %>
<%= $user.profile.email %>
<%= [$formatter displayNameForUser:$user] %>
<% for (id row in $rows) { %>
  <%= row %>
<% } %>
```

### 4.2 Lookup Behavior

At render time, EOC resolves sigil locals deterministically:

- dictionary-like objects use key lookup
- other objects use key-value coding style lookup
- missing values resolve to `nil` unless strict locals mode is enabled

This means the same sigil form works against common Foundation containers and
Objective-C objects.

### 4.3 Why EOC Uses A Sigil

The sigil is a disambiguation marker, not a new control-flow language.

- `$user` means "look up `user` from the current render context"
- `user` means "use the normal Objective-C variable named `user` if one exists"

Without the sigil, EOC would have to guess whether `user.profile.email` was:

- a render-context lookup
- an Objective-C local variable or ivar
- a method result
- invalid code that should fail at compile time

The sigil keeps that boundary explicit and gives the transpiler a deterministic
rewrite target such as `ALNEOCLocal(...)` or `ALNEOCLocalPath(...)`. It also
improves diagnostics because missing locals can be reported as template-context
errors instead of generic Objective-C failures.

Example:

```html
<%
id user = @{ @"name" : @"Debug Override" };
%>

<p>Context user: <%= $user.name %></p>
<p>Local variable user: <%= [user objectForKey:@"name"] %></p>
```

In that template:

- `$user` comes from the controller or caller render context
- `user` comes from the Objective-C local declared in the `<% ... %>` block

### 4.4 Where Sigil Locals Work

Sigil locals can be used anywhere an Objective-C expression is valid inside EOC
code or output tags.

Examples:

```html
<%= $title %>
<%= [$dateFormatter stringFromDate:$post.publishedAt] %>
<% if ([$items count] > 0) { %>
  <p>Found items.</p>
<% } %>
```

### 4.5 What Sigil Locals Are Not

Sigil locals are not a second language inside EOC. They are shorthand for
render-context lookup inside otherwise normal Objective-C expressions.

This is valid:

```html
<%= [$user displayName] %>
```

This is also valid:

```html
<%= [$formatter formattedTotal:$invoice.total] %>
```

## 5. Escaping and Output Rules

EOC is HTML-safe by default for normal output.

### 5.1 Default Escaping

- `<%= ... %>` escapes HTML-sensitive characters
- `<%== ... %>` does not escape
- `nil` output becomes an empty string

### 5.2 String Conversion

By default, non-string values render as follows:

- use `-stringValue` when available and it returns an `NSString`
- otherwise fall back to `-[NSObject description]`

This makes common Foundation values render without boilerplate:

```html
<p>Count: <%= @([$items count]) %></p>
<p>Status: <%= $statusNumber %></p>
```

### 5.3 Raw Output Guidance

Prefer `<%= ... %>` unless you are deliberately inserting trusted markup.

Good use case:

```html
<%== $sanitizedSnippet %>
```

Bad use case:

```html
<%== $userSuppliedComment %>
```

## 6. Control Flow and Objective-C in Templates

EOC does not invent a separate control-flow language. Inside `<% ... %>` tags
you write Objective-C.

### 6.1 Conditionals

```html
<% if ($flashMessage != nil) { %>
  <p class="flash"><%= $flashMessage %></p>
<% } %>
```

### 6.2 Loops

```html
<ul>
<% for (id row in $rows) { %>
  <li><%= [row description] %></li>
<% } %>
</ul>
```

### 6.3 Local Variables

```html
<%
NSString *pageTitle = $title ?: @"Untitled";
BOOL showSidebar = ([$items count] > 0);
%>

<title><%= pageTitle %></title>
<% if (showSidebar) { %>
  <aside>...</aside>
<% } %>
```

### 6.4 Multiline Tags

Code and expressions may span multiple lines when that makes the template
clearer.

```html
<% if ([self shouldShowBannerForUser:$user
                              today:$today]) { %>
  <%= $bannerText %>
<% } %>
```

## 7. Directive Reference

Directives use the `<%@ ... %>` form.

They are how EOC handles template composition and template-level contracts.

### 7.1 `layout`

Declares the layout template for the current page.

```html
<%@ layout "layouts/main" %>
```

Notes:

- layout paths normalize to `.html.eoc`
- layouts are explicit; EOC does not use deep inheritance trees
- when a layout is rendered, the page body becomes the `content` slot

### 7.2 `yield`

Used in a layout to render a slot.

```html
<main><%@ yield %></main>
<aside><%@ yield "sidebar" %></aside>
```

Notes:

- plain `yield` targets the `content` slot
- named `yield` targets that named slot
- layouts own the surrounding fallback markup

### 7.3 `slot` and `endslot`

Used in a page template to fill a named layout slot.

```html
<%@ layout "layouts/main" %>

<%@ slot "sidebar" %>
  <nav>...</nav>
<%@ endslot %>

<h1><%= $title %></h1>
```

Notes:

- `slot` captures rendered output until `endslot`
- slots are meaningful when a layout consumes them with `yield`
- `eocc` can warn when a slot is filled without a layout or never yielded

### 7.4 `requires`

Declares required locals for the template.

```html
<%@ requires title, rows %>
```

Use `requires` when the template contract should fail clearly instead of
quietly rendering with missing data.

Notes:

- required locals are checked at render time
- missing required locals fail rendering
- `eocc` records the required-local metadata for analysis/tooling

### 7.5 `include`

Renders another template in the current context.

```html
<%@ include "partials/_nav" %>
<%@ include "partials/_summary" with @{ @"title" : $title } %>
```

Notes:

- include paths normalize to `.html.eoc`
- the current context is shared by default
- `with` overlays explicit locals on top of the current context
- include failures bubble up as render errors

Use partials for repeated page fragments, not to simulate hidden inheritance.

### 7.6 `render`

Renders a collection through a partial.

```html
<%@ render "partials/_row" collection:$rows as:"row" %>
<%@ render "partials/_row" collection:$rows as:"row" empty:"partials/_empty" %>
<%@ render "partials/_row" collection:$rows as:"row" empty:"partials/_empty" with @{ @"title" : $title } %>
```

Notes:

- `collection:` provides the enumerable source
- `as:` names the local bound to each item
- `empty:` renders a fallback partial when the collection is empty
- `with` overlays additional locals for each iteration

Use `render` when you want collection rendering to stay declarative and
consistent rather than hand-writing a loop plus include calls in every page.

## 8. Composition Patterns

### 8.1 Page With Layout

`templates/layouts/main.html.eoc`:

```html
<!doctype html>
<html>
  <head>
    <title><%= $title %></title>
  </head>
  <body>
    <main><%@ yield %></main>
  </body>
</html>
```

`templates/posts/show.html.eoc`:

```html
<%@ layout "layouts/main" %>
<%@ requires title, post %>

<article>
  <h1><%= $post.title %></h1>
  <div><%= $post.body %></div>
</article>
```

### 8.2 Page With Named Slot

Layout:

```html
<main><%@ yield %></main>
<aside><%@ yield "sidebar" %></aside>
```

Page:

```html
<%@ layout "layouts/main" %>

<%@ slot "sidebar" %>
  <p>Related links</p>
<%@ endslot %>

<h1><%= $title %></h1>
```

### 8.3 Partial With Explicit Locals

Page:

```html
<%@ include "partials/_summary" with @{
  @"title" : $title,
  @"count" : @([$rows count])
} %>
```

Partial:

```html
<%@ requires title, count %>
<p><%= $title %>: <%= $count %></p>
```

### 8.4 Collection Rendering

Page:

```html
<%@ render "partials/_row" collection:$rows as:"row" empty:"partials/_empty" %>
```

Row partial:

```html
<li><%= $row.name %></li>
```

Empty partial:

```html
<p>No rows found.</p>
```

## 9. Controller and View Integration

EOC gets most of its input from controller stash/context values.

Typical controller flow:

```objc
- (id)index:(ALNContext *)ctx {
  [self stashValues:@{
    @"title" : @"Dashboard",
    @"rows" : rows ?: @[]
  }];

  NSError *error = nil;
  if (![self renderTemplate:@"dashboard/index" error:&error]) {
    [self setStatus:500];
    [self renderText:error.localizedDescription ?: @"render failed"];
  }
  return nil;
}
```

Useful related controller APIs:

- `stashValue:forKey:`
- `stashValues:`
- `renderTemplate:error:`
- `renderTemplate:layout:error:`
- `renderTemplate:context:layout:strictLocals:strictStringify:error:`

This means the most common authoring model is:

1. controller prepares a dictionary-like view model
2. template reads it with sigil locals
3. layout/partial composition stays in the template layer

## 10. Strict Modes

EOC supports opt-in strict render modes for catching mistakes earlier.

### 10.1 Strict Locals

With strict locals enabled:

- unresolved `$local` lookups fail rendering
- missing dotted keypath segments fail rendering
- diagnostics include template location metadata

Use this when you want templates to fail loudly on missing inputs rather than
quietly rendering blanks.

### 10.2 Strict Stringify

With strict stringify enabled:

- expression output must be clearly string-convertible
- accepted values are `NSString` or objects whose `-stringValue` returns an
  `NSString`
- ambiguous objects fail instead of silently falling back to generic
  `description`

Use this when template output contracts matter more than convenience.

## 11. Diagnostics and Tooling

EOC is designed around deterministic diagnostics.

The `eocc` transpiler reports:

- syntax/transpile failures with path, line, and column metadata
- static composition failures before code generation
- lint warnings for common template mistakes

Current documented lint categories include:

- `unguarded_include`
- `slot_without_layout`
- `unused_slot_fill`

Useful commands:

```bash
make eocc
make transpile
./build/eocc --template-root templates --output-dir build/gen/templates templates/index.html.eoc
```

For direct `eocc` flags and diagnostics behavior, see
`docs/CLI_REFERENCE.md`.

## 12. Common Mistakes

### 12.1 Using Raw Output for Normal Content

Prefer:

```html
<%= $commentBody %>
```

Not:

```html
<%== $commentBody %>
```

### 12.2 Forgetting That EOC Uses Objective-C

Inside code tags, write Objective-C statements, not Ruby-, Perl-, or
JavaScript-style control flow.

Correct:

```html
<% if ([$rows count] > 0) { %>
  ...
<% } %>
```

### 12.3 Overusing Imperative Includes

Direct runtime helper calls are available for trusted code paths, but the
directive forms are the preferred authoring surface:

- use `<%@ include ... %>` instead of manual include helper calls
- use `<%@ render ... %>` instead of repeating loop-plus-include plumbing

### 12.4 Treating Layouts Like Inheritance Chains

EOC composition is explicit and additive:

- page chooses a layout
- page may fill slots
- layout yields slots

Do not expect deep, implicit, multi-level template inheritance semantics.

## 13. Authoring Guidelines

Prefer these habits:

- keep most markup as plain HTML
- use `<%= ... %>` by default
- use `requires` for templates with real input contracts
- push business logic into controllers or helpers, not sprawling template code
- use partials for repeated fragments
- use `render` for repeated collection-partial patterns
- keep slot names deterministic and descriptive

## 14. Quick Reference

```html
<% code %>
<%= expr %>
<%== expr %>
<%# comment %>
<%@ layout "layouts/main" %>
<%@ requires title, rows %>
<%@ yield %>
<%@ yield "sidebar" %>
<%@ slot "sidebar" %> ... <%@ endslot %>
<%@ include "partials/_nav" %>
<%@ include "partials/_row" with @{ @"row" : $row } %>
<%@ render "partials/_row" collection:$rows as:"row" %>
<%@ render "partials/_row" collection:$rows as:"row" empty:"partials/_empty" with @{ @"title" : $title } %>
```

## 15. Related Docs

- `docs/GETTING_STARTED_HTML_FIRST.md`
- `docs/APP_AUTHORING_GUIDE.md`
- `docs/TEMPLATE_TROUBLESHOOTING.md`
- `docs/CLI_REFERENCE.md`
- `V1_SPEC.md`
