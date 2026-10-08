#ifndef ALN_MARKDOWN_H
#define ALN_MARKDOWN_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Markdown (CommonMark plus GitHub's extensions) parsed by the vendored
// cmark-gfm into an Objective-C node tree, with a safe HTML renderer and a
// plain-text renderer. Apps that need other output formats walk the tree.

typedef NS_ENUM(NSInteger, ALNMarkdownNodeType) {
  ALNMarkdownNodeTypeDocument = 0,
  ALNMarkdownNodeTypeBlockQuote,
  ALNMarkdownNodeTypeList,
  ALNMarkdownNodeTypeItem,
  ALNMarkdownNodeTypeCodeBlock,
  ALNMarkdownNodeTypeHTMLBlock,
  ALNMarkdownNodeTypeParagraph,
  ALNMarkdownNodeTypeHeading,
  ALNMarkdownNodeTypeThematicBreak,
  ALNMarkdownNodeTypeTable,
  ALNMarkdownNodeTypeTableRow,
  ALNMarkdownNodeTypeTableCell,
  ALNMarkdownNodeTypeText,
  ALNMarkdownNodeTypeSoftBreak,
  ALNMarkdownNodeTypeLineBreak,
  ALNMarkdownNodeTypeCode,
  ALNMarkdownNodeTypeHTMLInline,
  ALNMarkdownNodeTypeEmphasis,
  ALNMarkdownNodeTypeStrong,
  ALNMarkdownNodeTypeStrikethrough,
  ALNMarkdownNodeTypeLink,
  ALNMarkdownNodeTypeImage,
  // A span registered with ALNMarkdownInlineSpanSyntax.
  ALNMarkdownNodeTypeInlineSpan,
};

typedef NS_ENUM(NSInteger, ALNMarkdownListType) {
  ALNMarkdownListTypeNone = 0,
  ALNMarkdownListTypeBullet,
  ALNMarkdownListTypeOrdered,
};

typedef NS_ENUM(NSInteger, ALNMarkdownTableAlignment) {
  ALNMarkdownTableAlignmentNone = 0,
  ALNMarkdownTableAlignmentLeft,
  ALNMarkdownTableAlignmentCenter,
  ALNMarkdownTableAlignmentRight,
};

typedef NS_OPTIONS(NSUInteger, ALNMarkdownExtensions) {
  ALNMarkdownExtensionNone = 0,
  ALNMarkdownExtensionTables = 1 << 0,
  ALNMarkdownExtensionTaskLists = 1 << 1,
  ALNMarkdownExtensionStrikethrough = 1 << 2,
  ALNMarkdownExtensionAutolinks = 1 << 3,
  ALNMarkdownExtensionAll = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3),
};

@interface ALNMarkdownNode : NSObject

@property(nonatomic, assign, readonly) ALNMarkdownNodeType type;
@property(nonatomic, copy, readonly) NSArray<ALNMarkdownNode *> *children;

// Text, Code, CodeBlock, HTMLBlock and HTMLInline content.
@property(nonatomic, copy, readonly, nullable) NSString *literal;
// Heading: 1-6.
@property(nonatomic, assign, readonly) NSInteger headingLevel;
// List.
@property(nonatomic, assign, readonly) ALNMarkdownListType listType;
@property(nonatomic, assign, readonly) NSInteger listStart;
@property(nonatomic, assign, readonly) BOOL listTight;
// CodeBlock: the fence's info string ("objc", "" for indented code).
@property(nonatomic, copy, readonly, nullable) NSString *fenceInfo;
// Link and Image. The URL is as written; renderers apply the URL policy.
@property(nonatomic, copy, readonly, nullable) NSString *URL;
@property(nonatomic, copy, readonly, nullable) NSString *title;
// Item.
@property(nonatomic, assign, readonly, getter=isTaskListItem) BOOL taskListItem;
@property(nonatomic, assign, readonly, getter=isChecked) BOOL checked;
// TableRow and TableCell.
@property(nonatomic, assign, readonly, getter=isHeaderRow) BOOL headerRow;
@property(nonatomic, assign, readonly) ALNMarkdownTableAlignment alignment;
// InlineSpan: the syntax's identifier and the name in the markers
// (@"color" and @"red" for ⟦red⟧…⟦/red⟧).
@property(nonatomic, copy, readonly, nullable) NSString *spanIdentifier;
@property(nonatomic, copy, readonly, nullable) NSString *spanName;

// The node's text with all markup dropped (breaks become spaces).
- (NSString *)textContent;

@end

// A custom inline span: <opening>name<closing> … <opening>/name<closing>.
// The span can wrap other inline markdown but must open and close within the
// same inline container, and spans do not nest: markers inside an open span
// stay literal text, as do unknown names and unmatched markers. Markers inside
// code spans and code blocks are never interpreted.
@interface ALNMarkdownInlineSpanSyntax : NSObject

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *openingDelimiter;
@property(nonatomic, copy, readonly) NSString *closingDelimiter;
// nil accepts any name of ASCII letters, digits, '-' and '_'.
@property(nonatomic, copy, readonly, nullable) NSSet<NSString *> *names;

// Returns nil if the identifier or a delimiter is empty.
+ (nullable instancetype)syntaxWithIdentifier:(NSString *)identifier
                             openingDelimiter:(NSString *)openingDelimiter
                             closingDelimiter:(NSString *)closingDelimiter
                                        names:(nullable NSSet<NSString *> *)names;

@end

@interface ALNMarkdownOptions : NSObject <NSCopying>

+ (instancetype)defaultOptions;

// Parsing.
@property(nonatomic, assign) ALNMarkdownExtensions extensions;  // All
@property(nonatomic, assign) BOOL smartPunctuation;              // NO
@property(nonatomic, copy) NSArray<ALNMarkdownInlineSpanSyntax *> *inlineSpans;
// Blocks and inlines nested deeper than this become plain text, which keeps
// the renderers' recursion bounded for hostile input. Default 64.
@property(nonatomic, assign) NSUInteger maximumNestingDepth;

// Rendering.
@property(nonatomic, assign) BOOL hardBreaks;  // soft line breaks render as <br />; NO
// Schemes (lowercase) a link or image URL may use. URLs without a scheme
// (relative paths, fragments) are always allowed. A link with any other
// scheme renders as its text; an image as its alt text.
@property(nonatomic, copy) NSArray<NSString *> *allowedLinkSchemes;   // http, https, mailto
@property(nonatomic, copy) NSArray<NSString *> *allowedImageSchemes;  // http, https
// HTML element name -> class attribute value, e.g. @{ @"table" : @"md-table" }.
// Element names: p h1-h6 blockquote ul ol li pre code hr table thead tbody tr
// th td em strong del a img input span. An inline span uses the first of
// "span.<identifier>.<name>", "span.<identifier>" and "span" present.
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *HTMLClassMap;

@end

@interface ALNMarkdown : NSObject

// Parsing never fails; nil options mean +[ALNMarkdownOptions defaultOptions].
+ (ALNMarkdownNode *)parseString:(nullable NSString *)markdown
                         options:(nullable ALNMarkdownOptions *)options;

// HTML that is safe to embed: raw HTML in the source is escaped, link and
// image URLs follow the scheme allowlist, and attribute values are escaped.
+ (NSString *)HTMLFromString:(nullable NSString *)markdown
                     options:(nullable ALNMarkdownOptions *)options;
+ (NSString *)HTMLFromNode:(ALNMarkdownNode *)node
                   options:(nullable ALNMarkdownOptions *)options;

// Text without markup: list markers, task boxes, quote prefixes and table
// cell separators are kept for readability, and a link whose text differs from
// its URL is followed by " (URL)".
+ (NSString *)plainTextFromString:(nullable NSString *)markdown
                          options:(nullable ALNMarkdownOptions *)options;
+ (NSString *)plainTextFromNode:(ALNMarkdownNode *)node;

+ (NSString *)cmarkGFMVersion;

@end

NS_ASSUME_NONNULL_END

#endif
