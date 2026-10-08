# ALNMarkdownNode

- Kind: `interface`
- Header: `src/Arlen/Support/ALNMarkdown.h`

Immutable node of a parsed Markdown document; walk `children` by `type` to write custom renderers.

## Properties

| Property | Type | Attributes | Purpose |
| --- | --- | --- | --- |
| `type` | `ALNMarkdownNodeType` | `nonatomic, assign, readonly` | Public `type` property available on `ALNMarkdownNode`. |
| `children` | `NSArray<ALNMarkdownNode *> *` | `nonatomic, copy, readonly` | Public `children` property available on `ALNMarkdownNode`. |
| `literal` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `literal` property available on `ALNMarkdownNode`. |
| `headingLevel` | `NSInteger` | `nonatomic, assign, readonly` | Public `headingLevel` property available on `ALNMarkdownNode`. |
| `listType` | `ALNMarkdownListType` | `nonatomic, assign, readonly` | Public `listType` property available on `ALNMarkdownNode`. |
| `listStart` | `NSInteger` | `nonatomic, assign, readonly` | Public `listStart` property available on `ALNMarkdownNode`. |
| `listTight` | `BOOL` | `nonatomic, assign, readonly` | Public `listTight` property available on `ALNMarkdownNode`. |
| `fenceInfo` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `fenceInfo` property available on `ALNMarkdownNode`. |
| `URL` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `URL` property available on `ALNMarkdownNode`. |
| `title` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `title` property available on `ALNMarkdownNode`. |
| `taskListItem` | `BOOL` | `nonatomic, assign, readonly, getter=isTaskListItem` | Public `taskListItem` property available on `ALNMarkdownNode`. |
| `checked` | `BOOL` | `nonatomic, assign, readonly, getter=isChecked` | Public `checked` property available on `ALNMarkdownNode`. |
| `headerRow` | `BOOL` | `nonatomic, assign, readonly, getter=isHeaderRow` | Public `headerRow` property available on `ALNMarkdownNode`. |
| `alignment` | `ALNMarkdownTableAlignment` | `nonatomic, assign, readonly` | Public `alignment` property available on `ALNMarkdownNode`. |
| `spanIdentifier` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `spanIdentifier` property available on `ALNMarkdownNode`. |
| `spanName` | `NSString *` | `nonatomic, copy, readonly, nullable` | Public `spanName` property available on `ALNMarkdownNode`. |

## Methods

| Selector | Signature | Purpose | How to use |
| --- | --- | --- | --- |
| `textContent` | `- (NSString *)textContent;` | Return the node's text with markup removed. | Breaks become spaces; code and raw HTML contribute their literal text. |
