#import "ALNMarkdown.h"

#import <dispatch/dispatch.h>

#include "third_party/cmark-gfm/cmark-gfm.h"
#include "third_party/cmark-gfm/cmark-gfm-core-extensions.h"
#include "third_party/cmark-gfm/cmark-gfm-extension_api.h"
#include "third_party/cmark-gfm/strikethrough.h"
#include "third_party/cmark-gfm/table.h"

#pragma mark - Nodes

@interface ALNMarkdownNode ()

@property(nonatomic, assign, readwrite) ALNMarkdownNodeType type;
@property(nonatomic, strong) NSMutableArray<ALNMarkdownNode *> *mutableChildren;
@property(nonatomic, copy, readwrite, nullable) NSString *literal;
@property(nonatomic, assign, readwrite) NSInteger headingLevel;
@property(nonatomic, assign, readwrite) ALNMarkdownListType listType;
@property(nonatomic, assign, readwrite) NSInteger listStart;
@property(nonatomic, assign, readwrite) BOOL listTight;
@property(nonatomic, copy, readwrite, nullable) NSString *fenceInfo;
@property(nonatomic, copy, readwrite, nullable) NSString *URL;
@property(nonatomic, copy, readwrite, nullable) NSString *title;
@property(nonatomic, assign, readwrite, getter=isTaskListItem) BOOL taskListItem;
@property(nonatomic, assign, readwrite, getter=isChecked) BOOL checked;
@property(nonatomic, assign, readwrite, getter=isHeaderRow) BOOL headerRow;
@property(nonatomic, assign, readwrite) ALNMarkdownTableAlignment alignment;
@property(nonatomic, copy, readwrite, nullable) NSString *spanIdentifier;
@property(nonatomic, copy, readwrite, nullable) NSString *spanName;

@end

@implementation ALNMarkdownNode

- (instancetype)initWithType:(ALNMarkdownNodeType)type {
  self = [super init];
  if (self != nil) {
    _type = type;
    _mutableChildren = [NSMutableArray array];
  }
  return self;
}

+ (instancetype)textNode:(NSString *)text {
  ALNMarkdownNode *node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeText];
  node.literal = text;
  return node;
}

- (NSArray<ALNMarkdownNode *> *)children {
  return [self.mutableChildren copy];
}

static void ALNMarkdownAppendTextContent(ALNMarkdownNode *node, NSMutableString *out) {
  switch (node.type) {
  case ALNMarkdownNodeTypeText:
  case ALNMarkdownNodeTypeCode:
  case ALNMarkdownNodeTypeHTMLInline:
    [out appendString:node.literal ?: @""];
    return;
  case ALNMarkdownNodeTypeCodeBlock:
  case ALNMarkdownNodeTypeHTMLBlock:
    [out appendString:node.literal ?: @""];
    return;
  case ALNMarkdownNodeTypeSoftBreak:
  case ALNMarkdownNodeTypeLineBreak:
    [out appendString:@" "];
    return;
  default:
    break;
  }
  for (ALNMarkdownNode *child in node.mutableChildren) {
    ALNMarkdownAppendTextContent(child, out);
  }
}

- (NSString *)textContent {
  NSMutableString *out = [NSMutableString string];
  ALNMarkdownAppendTextContent(self, out);
  return out;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<ALNMarkdownNode type=%ld children=%lu>", (long)self.type,
                                    (unsigned long)[self.mutableChildren count]];
}

@end

#pragma mark - Inline span syntax

@implementation ALNMarkdownInlineSpanSyntax

+ (instancetype)syntaxWithIdentifier:(NSString *)identifier
                    openingDelimiter:(NSString *)openingDelimiter
                    closingDelimiter:(NSString *)closingDelimiter
                               names:(NSSet<NSString *> *)names {
  if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 ||
      ![openingDelimiter isKindOfClass:[NSString class]] || [openingDelimiter length] == 0 ||
      ![closingDelimiter isKindOfClass:[NSString class]] || [closingDelimiter length] == 0) {
    return nil;
  }
  ALNMarkdownInlineSpanSyntax *syntax = [[self alloc] init];
  syntax->_identifier = [identifier copy];
  syntax->_openingDelimiter = [openingDelimiter copy];
  syntax->_closingDelimiter = [closingDelimiter copy];
  syntax->_names = [names copy];
  return syntax;
}

@end

#pragma mark - Options

@implementation ALNMarkdownOptions

+ (instancetype)defaultOptions {
  return [[self alloc] init];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _extensions = ALNMarkdownExtensionAll;
    _smartPunctuation = NO;
    _inlineSpans = @[];
    _maximumNestingDepth = 64;
    _hardBreaks = NO;
    _allowedLinkSchemes = @[ @"http", @"https", @"mailto" ];
    _allowedImageSchemes = @[ @"http", @"https" ];
    _HTMLClassMap = @{};
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  ALNMarkdownOptions *copy = [[[self class] allocWithZone:zone] init];
  copy.extensions = self.extensions;
  copy.smartPunctuation = self.smartPunctuation;
  copy.inlineSpans = self.inlineSpans;
  copy.maximumNestingDepth = self.maximumNestingDepth;
  copy.hardBreaks = self.hardBreaks;
  copy.allowedLinkSchemes = self.allowedLinkSchemes;
  copy.allowedImageSchemes = self.allowedImageSchemes;
  copy.HTMLClassMap = self.HTMLClassMap;
  return copy;
}

@end

#pragma mark - Parsing

static void ALNMarkdownEnsureExtensionsRegistered(void) {
  // cmark-gfm's registration flag is a plain static, so the first parse on
  // two threads at once would register the core extensions twice.
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cmark_gfm_core_extensions_ensure_registered();
  });
}

static NSString *ALNMarkdownString(const char *bytes) {
  if (bytes == NULL) {
    return @"";
  }
  return [NSString stringWithUTF8String:bytes] ?: @"";
}

static BOOL ALNMarkdownIsBlock(cmark_node *node) {
  return (cmark_node_get_type(node) & CMARK_NODE_TYPE_MASK) == CMARK_NODE_TYPE_BLOCK;
}

static ALNMarkdownTableAlignment ALNMarkdownAlignmentFromByte(uint8_t value) {
  switch (value) {
  case 'l':
    return ALNMarkdownTableAlignmentLeft;
  case 'c':
    return ALNMarkdownTableAlignmentCenter;
  case 'r':
    return ALNMarkdownTableAlignmentRight;
  default:
    return ALNMarkdownTableAlignmentNone;
  }
}

static ALNMarkdownNode *ALNMarkdownNodeFromCmark(cmark_node *source, cmark_syntax_extension *tasklist) {
  cmark_node_type sourceType = cmark_node_get_type(source);
  ALNMarkdownNode *node = nil;

  if (sourceType == CMARK_NODE_DOCUMENT) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeDocument];
  } else if (sourceType == CMARK_NODE_BLOCK_QUOTE) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeBlockQuote];
  } else if (sourceType == CMARK_NODE_LIST) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeList];
    node.listType = cmark_node_get_list_type(source) == CMARK_ORDERED_LIST ? ALNMarkdownListTypeOrdered
                                                                           : ALNMarkdownListTypeBullet;
    node.listStart = cmark_node_get_list_start(source);
    node.listTight = cmark_node_get_list_tight(source) != 0;
  } else if (sourceType == CMARK_NODE_ITEM) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeItem];
    if (tasklist != NULL && cmark_node_get_syntax_extension(source) == tasklist) {
      node.taskListItem = YES;
      node.checked = cmark_gfm_extensions_get_tasklist_item_checked(source);
    }
  } else if (sourceType == CMARK_NODE_CODE_BLOCK) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeCodeBlock];
    node.literal = ALNMarkdownString(cmark_node_get_literal(source));
    node.fenceInfo = ALNMarkdownString(cmark_node_get_fence_info(source));
  } else if (sourceType == CMARK_NODE_HTML_BLOCK) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeHTMLBlock];
    node.literal = ALNMarkdownString(cmark_node_get_literal(source));
  } else if (sourceType == CMARK_NODE_PARAGRAPH) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeParagraph];
  } else if (sourceType == CMARK_NODE_HEADING) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeHeading];
    node.headingLevel = cmark_node_get_heading_level(source);
  } else if (sourceType == CMARK_NODE_THEMATIC_BREAK) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeThematicBreak];
  } else if (sourceType == CMARK_NODE_TABLE) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeTable];
  } else if (sourceType == CMARK_NODE_TABLE_ROW) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeTableRow];
    node.headerRow = cmark_gfm_extensions_get_table_row_is_header(source) != 0;
  } else if (sourceType == CMARK_NODE_TABLE_CELL) {
    // Alignment is set by ALNMarkdownConvertDocument, which knows the column.
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeTableCell];
  } else if (sourceType == CMARK_NODE_TEXT) {
    node = [ALNMarkdownNode textNode:ALNMarkdownString(cmark_node_get_literal(source))];
  } else if (sourceType == CMARK_NODE_SOFTBREAK) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeSoftBreak];
  } else if (sourceType == CMARK_NODE_LINEBREAK) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeLineBreak];
  } else if (sourceType == CMARK_NODE_CODE) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeCode];
    node.literal = ALNMarkdownString(cmark_node_get_literal(source));
  } else if (sourceType == CMARK_NODE_HTML_INLINE) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeHTMLInline];
    node.literal = ALNMarkdownString(cmark_node_get_literal(source));
  } else if (sourceType == CMARK_NODE_EMPH) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeEmphasis];
  } else if (sourceType == CMARK_NODE_STRONG) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeStrong];
  } else if (sourceType == CMARK_NODE_STRIKETHROUGH) {
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeStrikethrough];
  } else if (sourceType == CMARK_NODE_LINK || sourceType == CMARK_NODE_IMAGE) {
    node = [[ALNMarkdownNode alloc]
        initWithType:(sourceType == CMARK_NODE_LINK ? ALNMarkdownNodeTypeLink : ALNMarkdownNodeTypeImage)];
    node.URL = ALNMarkdownString(cmark_node_get_url(source));
    node.title = ALNMarkdownString(cmark_node_get_title(source));
  } else if (ALNMarkdownIsBlock(source)) {
    // Node types this parser configuration never produces (footnotes, custom
    // blocks): keep their content.
    node = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeParagraph];
  } else {
    // Inline types this configuration never produces: an empty text node.
    node = [ALNMarkdownNode textNode:@""];
  }
  return node;
}

// cmark's iterator gives these an enter event only (iterator.c S_is_leaf).
static BOOL ALNMarkdownIsLeaf(cmark_node *node) {
  switch (cmark_node_get_type(node)) {
  case CMARK_NODE_HTML_BLOCK:
  case CMARK_NODE_THEMATIC_BREAK:
  case CMARK_NODE_CODE_BLOCK:
  case CMARK_NODE_TEXT:
  case CMARK_NODE_SOFTBREAK:
  case CMARK_NODE_LINEBREAK:
  case CMARK_NODE_CODE:
  case CMARK_NODE_HTML_INLINE:
    return YES;
  default:
    return NO;
  }
}

// Converts iteratively (cmark's iterator), so a hostile document cannot
// exhaust the stack here; subtrees deeper than maximumNestingDepth collapse
// to their text so the recursive renderers stay bounded too.
static ALNMarkdownNode *ALNMarkdownConvertDocument(cmark_node *document, NSUInteger maximumDepth) {
  cmark_syntax_extension *tasklist = cmark_find_syntax_extension("tasklist");
  NSMutableArray<ALNMarkdownNode *> *stack = [NSMutableArray array];
  ALNMarkdownNode *root = nil;
  cmark_node *collapsedRoot = NULL;
  NSMutableString *collapsedText = nil;

  cmark_iter *iter = cmark_iter_new(document);
  cmark_event_type event;
  while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *current = cmark_iter_get_node(iter);
    BOOL entering = (event == CMARK_EVENT_ENTER);

    if (collapsedRoot != NULL) {
      if (current == collapsedRoot && !entering) {
        ALNMarkdownNode *text = [ALNMarkdownNode textNode:collapsedText];
        ALNMarkdownNode *parent = [stack lastObject];
        if (ALNMarkdownIsBlock(collapsedRoot)) {
          ALNMarkdownNode *paragraph = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeParagraph];
          [paragraph.mutableChildren addObject:text];
          [parent.mutableChildren addObject:paragraph];
        } else {
          [parent.mutableChildren addObject:text];
        }
        collapsedRoot = NULL;
        collapsedText = nil;
      } else if (entering) {
        cmark_node_type type = cmark_node_get_type(current);
        if (type == CMARK_NODE_TEXT || type == CMARK_NODE_CODE || type == CMARK_NODE_HTML_INLINE) {
          [collapsedText appendString:ALNMarkdownString(cmark_node_get_literal(current))];
        } else if (type == CMARK_NODE_SOFTBREAK || type == CMARK_NODE_LINEBREAK) {
          [collapsedText appendString:@" "];
        } else if (ALNMarkdownIsBlock(current) && [collapsedText length] > 0 &&
                   ![collapsedText hasSuffix:@" "]) {
          [collapsedText appendString:@" "];
        }
      }
      continue;
    }

    if (!entering) {
      if (current != document) {
        [stack removeLastObject];
      }
      continue;
    }

    BOOL leaf = ALNMarkdownIsLeaf(current);
    if (current != document && !leaf && [stack count] > maximumDepth) {
      collapsedRoot = current;
      collapsedText = [NSMutableString string];
      continue;
    }

    ALNMarkdownNode *node = ALNMarkdownNodeFromCmark(current, tasklist);
    if (current == document) {
      root = node;
      [stack addObject:node];
      continue;
    }
    ALNMarkdownNode *parent = [stack lastObject];
    if (node.type == ALNMarkdownNodeTypeTableCell) {
      cmark_node *row = cmark_node_parent(current);
      cmark_node *table = row != NULL ? cmark_node_parent(row) : NULL;
      NSUInteger column = [parent.mutableChildren count];
      if (table != NULL && column < cmark_gfm_extensions_get_table_columns(table)) {
        uint8_t *alignments = cmark_gfm_extensions_get_table_alignments(table);
        if (alignments != NULL) {
          node.alignment = ALNMarkdownAlignmentFromByte(alignments[column]);
        }
      }
    }
    [parent.mutableChildren addObject:node];
    if (!leaf) {
      [stack addObject:node];
    }
  }
  cmark_iter_free(iter);
  return root ?: [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeDocument];
}

#pragma mark - Inline spans

// Every step below is linear in the inline content, so unmatched or
// malformed markers in hostile input cannot make parsing quadratic.

static const NSUInteger ALNMarkdownMaximumSpanNameLength = 64;

typedef NS_ENUM(NSInteger, ALNMarkdownSpanTokenKind) {
  ALNMarkdownSpanTokenNode = 0,
  ALNMarkdownSpanTokenText,
  ALNMarkdownSpanTokenOpener,
  ALNMarkdownSpanTokenCloser,
};

@interface ALNMarkdownSpanToken : NSObject
@property(nonatomic, assign) ALNMarkdownSpanTokenKind kind;
@property(nonatomic, strong) ALNMarkdownNode *node;  // Node tokens
@property(nonatomic, copy) NSString *text;           // Text tokens, and a marker's literal text
@property(nonatomic, assign) NSUInteger syntaxIndex;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) NSRange range;
@end

@implementation ALNMarkdownSpanToken
@end

static BOOL ALNMarkdownSpanNameIsValid(NSString *name, ALNMarkdownInlineSpanSyntax *syntax) {
  if ([name length] == 0 || [name length] > ALNMarkdownMaximumSpanNameLength) {
    return NO;
  }
  if (syntax.names != nil) {
    return [syntax.names containsObject:name];
  }
  for (NSUInteger i = 0; i < [name length]; i++) {
    unichar c = [name characterAtIndex:i];
    BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' ||
              c == '_';
    if (!ok) {
      return NO;
    }
  }
  return YES;
}

// The markers of one syntax in text, left to right. A closing delimiter is
// only looked for within a name's length of its opening delimiter.
static void ALNMarkdownCollectSpanMarkers(NSString *text,
                                          ALNMarkdownInlineSpanSyntax *syntax,
                                          NSUInteger syntaxIndex,
                                          NSMutableArray<ALNMarkdownSpanToken *> *markers) {
  NSUInteger length = [text length];
  NSUInteger position = 0;
  while (position < length) {
    NSRange open = [text rangeOfString:syntax.openingDelimiter
                               options:NSLiteralSearch
                                 range:NSMakeRange(position, length - position)];
    if (open.location == NSNotFound) {
      return;
    }
    NSUInteger nameStart = NSMaxRange(open);
    BOOL closing = NO;
    if (nameStart < length && [text characterAtIndex:nameStart] == '/') {
      closing = YES;
      nameStart++;
    }
    NSUInteger window = MIN(length - nameStart, ALNMarkdownMaximumSpanNameLength + [syntax.closingDelimiter length]);
    NSRange close = [text rangeOfString:syntax.closingDelimiter
                                options:NSLiteralSearch
                                  range:NSMakeRange(nameStart, window)];
    if (close.location != NSNotFound) {
      NSString *name = [text substringWithRange:NSMakeRange(nameStart, close.location - nameStart)];
      if (ALNMarkdownSpanNameIsValid(name, syntax)) {
        ALNMarkdownSpanToken *marker = [[ALNMarkdownSpanToken alloc] init];
        marker.kind = closing ? ALNMarkdownSpanTokenCloser : ALNMarkdownSpanTokenOpener;
        marker.syntaxIndex = syntaxIndex;
        marker.name = name;
        marker.range = NSMakeRange(open.location, NSMaxRange(close) - open.location);
        marker.text = [text substringWithRange:marker.range];
        [markers addObject:marker];
        position = NSMaxRange(close);
        continue;
      }
    }
    position = open.location + 1;
  }
}

static void ALNMarkdownAppendTextToken(NSMutableArray<ALNMarkdownSpanToken *> *tokens, NSString *text) {
  if ([text length] == 0) {
    return;
  }
  ALNMarkdownSpanToken *token = [[ALNMarkdownSpanToken alloc] init];
  token.kind = ALNMarkdownSpanTokenText;
  token.text = text;
  [tokens addObject:token];
}

// Splits a text node into text and marker tokens. Where markers of different
// syntaxes overlap, the earlier one wins (the first-registered syntax on a tie).
static void ALNMarkdownTokenizeText(NSString *text,
                                    NSArray<ALNMarkdownInlineSpanSyntax *> *syntaxes,
                                    NSMutableArray<ALNMarkdownSpanToken *> *tokens) {
  NSMutableArray<ALNMarkdownSpanToken *> *markers = [NSMutableArray array];
  [syntaxes enumerateObjectsUsingBlock:^(ALNMarkdownInlineSpanSyntax *syntax, NSUInteger index, BOOL *stop) {
    (void)stop;
    ALNMarkdownCollectSpanMarkers(text, syntax, index, markers);
  }];
  if ([syntaxes count] > 1) {
    [markers sortWithOptions:NSSortStable
             usingComparator:^NSComparisonResult(ALNMarkdownSpanToken *a, ALNMarkdownSpanToken *b) {
               if (a.range.location != b.range.location) {
                 return a.range.location < b.range.location ? NSOrderedAscending : NSOrderedDescending;
               }
               return a.syntaxIndex < b.syntaxIndex ? NSOrderedAscending
                                                    : (a.syntaxIndex > b.syntaxIndex ? NSOrderedDescending
                                                                                     : NSOrderedSame);
             }];
  }
  NSUInteger location = 0;
  for (ALNMarkdownSpanToken *marker in markers) {
    if (marker.range.location < location) {
      continue;
    }
    ALNMarkdownAppendTextToken(tokens, [text substringWithRange:NSMakeRange(location, marker.range.location - location)]);
    [tokens addObject:marker];
    location = NSMaxRange(marker.range);
  }
  ALNMarkdownAppendTextToken(tokens, [text substringFromIndex:location]);
}

// Builds a child list, joining adjacent text without repeated copying.
@interface ALNMarkdownInlineBuilder : NSObject
@property(nonatomic, strong) NSMutableArray<ALNMarkdownNode *> *nodes;
@property(nonatomic, strong) NSMutableString *pendingText;
@end

@implementation ALNMarkdownInlineBuilder

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _nodes = [NSMutableArray array];
  }
  return self;
}

- (void)appendText:(NSString *)text {
  if (self.pendingText == nil) {
    self.pendingText = [NSMutableString string];
  }
  [self.pendingText appendString:text ?: @""];
}

- (void)appendNode:(ALNMarkdownNode *)node {
  [self flush];
  [self.nodes addObject:node];
}

- (void)flush {
  if ([self.pendingText length] > 0) {
    [self.nodes addObject:[ALNMarkdownNode textNode:[self.pendingText copy]]];
  }
  self.pendingText = nil;
}

- (NSMutableArray<ALNMarkdownNode *> *)finish {
  [self flush];
  return self.nodes;
}

@end

static void ALNMarkdownApplySpans(ALNMarkdownNode *container, NSArray<ALNMarkdownInlineSpanSyntax *> *syntaxes);

static NSString *ALNMarkdownSpanKey(ALNMarkdownSpanToken *marker) {
  return [NSString stringWithFormat:@"%lu|%@", (unsigned long)marker.syntaxIndex, marker.name];
}

// Replaces a container's inline children with the same children plus span
// nodes. An opener pairs with the next closer of the same syntax and name;
// anything between them, markers included, becomes the span's content as is.
static void ALNMarkdownApplySpansToInlines(ALNMarkdownNode *container,
                                           NSArray<ALNMarkdownInlineSpanSyntax *> *syntaxes) {
  NSMutableArray<ALNMarkdownSpanToken *> *tokens = [NSMutableArray array];
  for (ALNMarkdownNode *child in container.mutableChildren) {
    if (child.type == ALNMarkdownNodeTypeText) {
      ALNMarkdownTokenizeText(child.literal ?: @"", syntaxes, tokens);
      continue;
    }
    ALNMarkdownSpanToken *token = [[ALNMarkdownSpanToken alloc] init];
    token.kind = ALNMarkdownSpanTokenNode;
    token.node = child;
    [tokens addObject:token];
  }

  // Closer positions by syntax and name, consumed left to right.
  NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *closers = [NSMutableDictionary dictionary];
  [tokens enumerateObjectsUsingBlock:^(ALNMarkdownSpanToken *token, NSUInteger index, BOOL *stop) {
    (void)stop;
    if (token.kind == ALNMarkdownSpanTokenCloser) {
      NSString *key = ALNMarkdownSpanKey(token);
      if (closers[key] == nil) {
        closers[key] = [NSMutableArray array];
      }
      [closers[key] addObject:@(index)];
    }
  }];
  NSMutableDictionary<NSString *, NSNumber *> *cursors = [NSMutableDictionary dictionary];

  ALNMarkdownInlineBuilder *result = [[ALNMarkdownInlineBuilder alloc] init];
  NSUInteger index = 0;
  while (index < [tokens count]) {
    ALNMarkdownSpanToken *token = tokens[index];
    if (token.kind == ALNMarkdownSpanTokenOpener) {
      NSString *key = ALNMarkdownSpanKey(token);
      NSArray<NSNumber *> *positions = closers[key];
      NSUInteger cursor = [cursors[key] unsignedIntegerValue];
      while (cursor < [positions count] && [positions[cursor] unsignedIntegerValue] <= index) {
        cursor++;
      }
      cursors[key] = @(cursor);
      if (cursor < [positions count]) {
        NSUInteger closerIndex = [positions[cursor] unsignedIntegerValue];
        ALNMarkdownNode *span = [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeInlineSpan];
        span.spanIdentifier = syntaxes[token.syntaxIndex].identifier;
        span.spanName = token.name;
        ALNMarkdownInlineBuilder *content = [[ALNMarkdownInlineBuilder alloc] init];
        for (NSUInteger j = index + 1; j < closerIndex; j++) {
          ALNMarkdownSpanToken *inner = tokens[j];
          if (inner.kind == ALNMarkdownSpanTokenNode) {
            [content appendNode:inner.node];
          } else {
            [content appendText:inner.text];
          }
        }
        span.mutableChildren = [content finish];
        [result appendNode:span];
        index = closerIndex + 1;
        continue;
      }
    }
    if (token.kind == ALNMarkdownSpanTokenNode) {
      ALNMarkdownApplySpans(token.node, syntaxes);
      [result appendNode:token.node];
    } else {
      [result appendText:token.text];
    }
    index++;
  }
  container.mutableChildren = [result finish];
}

static void ALNMarkdownApplySpans(ALNMarkdownNode *node, NSArray<ALNMarkdownInlineSpanSyntax *> *syntaxes) {
  switch (node.type) {
  case ALNMarkdownNodeTypeParagraph:
  case ALNMarkdownNodeTypeHeading:
  case ALNMarkdownNodeTypeTableCell:
  case ALNMarkdownNodeTypeEmphasis:
  case ALNMarkdownNodeTypeStrong:
  case ALNMarkdownNodeTypeStrikethrough:
  case ALNMarkdownNodeTypeLink:
  case ALNMarkdownNodeTypeImage:
    ALNMarkdownApplySpansToInlines(node, syntaxes);
    return;
  case ALNMarkdownNodeTypeInlineSpan:
    return;
  default:
    for (ALNMarkdownNode *child in node.mutableChildren) {
      ALNMarkdownApplySpans(child, syntaxes);
    }
    return;
  }
}

#pragma mark - HTML rendering

static void ALNMarkdownEscapeHTML(NSMutableString *out, NSString *text) {
  // Matches cmark's escape_html: & < > " only.
  NSUInteger length = [text length];
  NSUInteger start = 0;
  for (NSUInteger i = 0; i < length; i++) {
    unichar c = [text characterAtIndex:i];
    NSString *replacement = nil;
    switch (c) {
    case '&':
      replacement = @"&amp;";
      break;
    case '<':
      replacement = @"&lt;";
      break;
    case '>':
      replacement = @"&gt;";
      break;
    case '"':
      replacement = @"&quot;";
      break;
    default:
      break;
    }
    if (replacement != nil) {
      if (i > start) {
        [out appendString:[text substringWithRange:NSMakeRange(start, i - start)]];
      }
      [out appendString:replacement];
      start = i + 1;
    }
  }
  if (start < length) {
    [out appendString:(start == 0 ? text : [text substringFromIndex:start])];
  }
}

static BOOL ALNMarkdownHrefByteIsSafe(uint8_t c) {
  // cmark's HREF_SAFE table.
  if (c >= 'a' && c <= 'z') return YES;
  if (c >= 'A' && c <= 'Z') return YES;
  if (c >= '0' && c <= '9') return YES;
  switch (c) {
  case '!': case '#': case '$': case '%': case '(': case ')': case '*': case '+': case ',':
  case '-': case '.': case '/': case ':': case ';': case '=': case '?': case '@': case '_':
  case '~':
    return YES;
  default:
    return NO;
  }
}

static void ALNMarkdownEscapeHref(NSMutableString *out, NSString *url) {
  NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
  const uint8_t *bytes = [data bytes];
  for (NSUInteger i = 0; i < [data length]; i++) {
    uint8_t c = bytes[i];
    if (ALNMarkdownHrefByteIsSafe(c)) {
      [out appendFormat:@"%c", c];
    } else if (c == '&') {
      [out appendString:@"&amp;"];
    } else if (c == '\'') {
      [out appendString:@"&#x27;"];
    } else {
      [out appendFormat:@"%%%02X", c];
    }
  }
}

// The scheme a browser would see: leading/trailing C0 controls and spaces are
// stripped and tabs/newlines removed (WHATWG URL parsing), so "java\tscript:"
// is a javascript: URL. Returns nil for a URL without a scheme.
static NSString *ALNMarkdownURLScheme(NSString *url) {
  NSMutableString *cleaned = [NSMutableString string];
  for (NSUInteger i = 0; i < [url length]; i++) {
    unichar c = [url characterAtIndex:i];
    if (c == '\t' || c == '\n' || c == '\r') {
      continue;
    }
    [cleaned appendFormat:@"%C", c];
  }
  NSUInteger start = 0;
  while (start < [cleaned length] && [cleaned characterAtIndex:start] <= 0x20) {
    start++;
  }
  NSUInteger i = start;
  for (; i < [cleaned length]; i++) {
    unichar c = [cleaned characterAtIndex:i];
    BOOL letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    if (c == ':') {
      break;
    }
    if (i == start ? !letter : !(letter || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.')) {
      return nil;
    }
  }
  if (i >= [cleaned length] || i == start) {
    return nil;
  }
  return [[cleaned substringWithRange:NSMakeRange(start, i - start)] lowercaseString];
}

static BOOL ALNMarkdownURLIsAllowed(NSString *url, NSArray<NSString *> *schemes) {
  NSString *scheme = ALNMarkdownURLScheme(url ?: @"");
  if (scheme == nil) {
    return YES;
  }
  for (NSString *allowed in schemes) {
    if ([[allowed lowercaseString] isEqualToString:scheme]) {
      return YES;
    }
  }
  return NO;
}

typedef struct {
  BOOL inTableHeader;
  BOOL needClosingTableBody;
} ALNMarkdownTableState;

@interface ALNMarkdownHTMLRenderer : NSObject
@property(nonatomic, strong) ALNMarkdownOptions *options;
@property(nonatomic, strong) NSMutableString *out;
@end

@implementation ALNMarkdownHTMLRenderer {
  ALNMarkdownTableState _table;
}

- (void)cr {
  if ([self.out length] > 0 && ![self.out hasSuffix:@"\n"]) {
    [self.out appendString:@"\n"];
  }
}

- (NSString *)classForKeys:(NSArray<NSString *> *)keys {
  for (NSString *key in keys) {
    NSString *value = self.options.HTMLClassMap[key];
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
      return value;
    }
  }
  return nil;
}

// Appends "<tag" plus a class attribute when the class map names one.
- (void)openTag:(NSString *)tag {
  [self.out appendFormat:@"<%@", tag];
  NSString *className = [self classForKeys:@[ tag ]];
  if (className != nil) {
    [self.out appendString:@" class=\""];
    ALNMarkdownEscapeHTML(self.out, className);
    [self.out appendString:@"\""];
  }
}

- (void)renderChildren:(ALNMarkdownNode *)node tight:(BOOL)tight {
  for (ALNMarkdownNode *child in node.mutableChildren) {
    [self render:child tight:tight];
  }
}

// Like cmark, a strong directly inside a strong adds no second tag pair.
- (void)renderStrongChildren:(ALNMarkdownNode *)node {
  for (ALNMarkdownNode *child in node.mutableChildren) {
    if (child.type == ALNMarkdownNodeTypeStrong) {
      [self renderStrongChildren:child];
    } else {
      [self render:child tight:NO];
    }
  }
}

- (void)renderPlain:(ALNMarkdownNode *)node {
  switch (node.type) {
  case ALNMarkdownNodeTypeText:
  case ALNMarkdownNodeTypeCode:
  case ALNMarkdownNodeTypeHTMLInline:
    ALNMarkdownEscapeHTML(self.out, node.literal ?: @"");
    return;
  case ALNMarkdownNodeTypeSoftBreak:
  case ALNMarkdownNodeTypeLineBreak:
    [self.out appendString:@" "];
    return;
  default:
    for (ALNMarkdownNode *child in node.mutableChildren) {
      [self renderPlain:child];
    }
    return;
  }
}

- (void)render:(ALNMarkdownNode *)node tight:(BOOL)tight {
  switch (node.type) {
  case ALNMarkdownNodeTypeDocument:
    [self renderChildren:node tight:NO];
    return;

  case ALNMarkdownNodeTypeBlockQuote:
    [self cr];
    [self openTag:@"blockquote"];
    [self.out appendString:@">\n"];
    [self renderChildren:node tight:NO];
    [self cr];
    [self.out appendString:@"</blockquote>\n"];
    return;

  case ALNMarkdownNodeTypeList: {
    BOOL bullet = node.listType != ALNMarkdownListTypeOrdered;
    [self cr];
    [self openTag:(bullet ? @"ul" : @"ol")];
    if (!bullet && node.listStart != 1) {
      [self.out appendFormat:@" start=\"%ld\"", (long)node.listStart];
    }
    [self.out appendString:@">\n"];
    [self renderChildren:node tight:node.listTight];
    [self.out appendString:(bullet ? @"</ul>\n" : @"</ol>\n")];
    return;
  }

  case ALNMarkdownNodeTypeItem:
    [self cr];
    [self openTag:@"li"];
    [self.out appendString:@">"];
    if (node.isTaskListItem) {
      [self openTag:@"input"];
      [self.out appendString:(node.isChecked ? @" type=\"checkbox\" checked=\"\" disabled=\"\" /> "
                                             : @" type=\"checkbox\" disabled=\"\" /> ")];
    }
    [self renderChildren:node tight:tight];
    [self.out appendString:@"</li>\n"];
    return;

  case ALNMarkdownNodeTypeHeading: {
    NSInteger level = MAX(1, MIN(6, node.headingLevel));
    [self cr];
    [self openTag:[NSString stringWithFormat:@"h%ld", (long)level]];
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    [self.out appendFormat:@"</h%ld>\n", (long)level];
    return;
  }

  case ALNMarkdownNodeTypeCodeBlock: {
    [self cr];
    [self openTag:@"pre"];
    [self.out appendString:@"><code"];
    NSString *info = node.fenceInfo ?: @"";
    NSRange space = [info rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *language = space.location == NSNotFound ? info : [info substringToIndex:space.location];
    NSString *mapped = [self classForKeys:@[ @"code" ]];
    if ([info length] > 0 || mapped != nil) {
      [self.out appendString:@" class=\""];
      if ([info length] > 0) {
        [self.out appendString:@"language-"];
        ALNMarkdownEscapeHTML(self.out, language);
      }
      if (mapped != nil) {
        if ([info length] > 0) {
          [self.out appendString:@" "];
        }
        ALNMarkdownEscapeHTML(self.out, mapped);
      }
      [self.out appendString:@"\""];
    }
    [self.out appendString:@">"];
    ALNMarkdownEscapeHTML(self.out, node.literal ?: @"");
    [self.out appendString:@"</code></pre>\n"];
    return;
  }

  case ALNMarkdownNodeTypeHTMLBlock: {
    // Raw HTML is shown as text, never passed through.
    NSString *literal = node.literal ?: @"";
    while ([literal hasSuffix:@"\n"]) {
      literal = [literal substringToIndex:[literal length] - 1];
    }
    [self cr];
    [self openTag:@"p"];
    [self.out appendString:@">"];
    ALNMarkdownEscapeHTML(self.out, literal);
    [self.out appendString:@"</p>\n"];
    return;
  }

  case ALNMarkdownNodeTypeThematicBreak:
    [self cr];
    [self openTag:@"hr"];
    [self.out appendString:@" />\n"];
    return;

  case ALNMarkdownNodeTypeParagraph:
    if (tight) {
      [self renderChildren:node tight:NO];
      return;
    }
    [self cr];
    [self openTag:@"p"];
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    [self.out appendString:@"</p>\n"];
    return;

  case ALNMarkdownNodeTypeTable: {
    ALNMarkdownTableState saved = _table;
    _table.needClosingTableBody = NO;
    _table.inTableHeader = NO;
    [self cr];
    [self openTag:@"table"];
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    if (_table.needClosingTableBody) {
      [self cr];
      [self.out appendString:@"</tbody>"];
      [self cr];
    }
    [self cr];
    [self.out appendString:@"</table>"];
    [self cr];
    _table = saved;
    return;
  }

  case ALNMarkdownNodeTypeTableRow:
    [self cr];
    if (node.isHeaderRow) {
      _table.inTableHeader = YES;
      [self openTag:@"thead"];
      [self.out appendString:@">"];
      [self cr];
    } else if (!_table.needClosingTableBody) {
      [self openTag:@"tbody"];
      [self.out appendString:@">"];
      [self cr];
      _table.needClosingTableBody = YES;
    }
    [self openTag:@"tr"];
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    [self cr];
    [self.out appendString:@"</tr>"];
    if (node.isHeaderRow) {
      [self cr];
      [self.out appendString:@"</thead>"];
      _table.inTableHeader = NO;
    }
    return;

  case ALNMarkdownNodeTypeTableCell: {
    NSString *tag = _table.inTableHeader ? @"th" : @"td";
    [self cr];
    [self openTag:tag];
    switch (node.alignment) {
    case ALNMarkdownTableAlignmentLeft:
      [self.out appendString:@" align=\"left\""];
      break;
    case ALNMarkdownTableAlignmentCenter:
      [self.out appendString:@" align=\"center\""];
      break;
    case ALNMarkdownTableAlignmentRight:
      [self.out appendString:@" align=\"right\""];
      break;
    default:
      break;
    }
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    [self.out appendFormat:@"</%@>", tag];
    return;
  }

  case ALNMarkdownNodeTypeText:
    ALNMarkdownEscapeHTML(self.out, node.literal ?: @"");
    return;

  case ALNMarkdownNodeTypeSoftBreak:
    [self.out appendString:(self.options.hardBreaks ? @"<br />\n" : @"\n")];
    return;

  case ALNMarkdownNodeTypeLineBreak:
    [self.out appendString:@"<br />\n"];
    return;

  case ALNMarkdownNodeTypeCode:
    [self openTag:@"code"];
    [self.out appendString:@">"];
    ALNMarkdownEscapeHTML(self.out, node.literal ?: @"");
    [self.out appendString:@"</code>"];
    return;

  case ALNMarkdownNodeTypeHTMLInline:
    ALNMarkdownEscapeHTML(self.out, node.literal ?: @"");
    return;

  case ALNMarkdownNodeTypeEmphasis:
    [self openTag:@"em"];
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    [self.out appendString:@"</em>"];
    return;

  case ALNMarkdownNodeTypeStrong:
    [self openTag:@"strong"];
    [self.out appendString:@">"];
    [self renderStrongChildren:node];
    [self.out appendString:@"</strong>"];
    return;

  case ALNMarkdownNodeTypeStrikethrough:
    [self openTag:@"del"];
    [self.out appendString:@">"];
    [self renderChildren:node tight:NO];
    [self.out appendString:@"</del>"];
    return;

  case ALNMarkdownNodeTypeLink:
    if (!ALNMarkdownURLIsAllowed(node.URL, self.options.allowedLinkSchemes)) {
      [self renderChildren:node tight:NO];
      return;
    }
    [self openTag:@"a"];
    [self.out appendString:@" href=\""];
    ALNMarkdownEscapeHref(self.out, node.URL ?: @"");
    if ([node.title length] > 0) {
      [self.out appendString:@"\" title=\""];
      ALNMarkdownEscapeHTML(self.out, node.title);
    }
    [self.out appendString:@"\">"];
    [self renderChildren:node tight:NO];
    [self.out appendString:@"</a>"];
    return;

  case ALNMarkdownNodeTypeImage:
    if (!ALNMarkdownURLIsAllowed(node.URL, self.options.allowedImageSchemes)) {
      [self renderPlain:node];
      return;
    }
    [self openTag:@"img"];
    [self.out appendString:@" src=\""];
    ALNMarkdownEscapeHref(self.out, node.URL ?: @"");
    [self.out appendString:@"\" alt=\""];
    for (ALNMarkdownNode *child in node.mutableChildren) {
      [self renderPlain:child];
    }
    if ([node.title length] > 0) {
      [self.out appendString:@"\" title=\""];
      ALNMarkdownEscapeHTML(self.out, node.title);
    }
    [self.out appendString:@"\" />"];
    return;

  case ALNMarkdownNodeTypeInlineSpan: {
    NSString *identifier = node.spanIdentifier ?: @"";
    NSString *name = node.spanName ?: @"";
    [self.out appendString:@"<span"];
    NSString *className = [self classForKeys:@[
      [NSString stringWithFormat:@"span.%@.%@", identifier, name],
      [NSString stringWithFormat:@"span.%@", identifier], @"span"
    ]];
    if (className != nil) {
      [self.out appendString:@" class=\""];
      ALNMarkdownEscapeHTML(self.out, className);
      [self.out appendString:@"\""];
    }
    [self.out appendString:@" data-markdown-span=\""];
    ALNMarkdownEscapeHTML(self.out, identifier);
    [self.out appendString:@"\" data-value=\""];
    ALNMarkdownEscapeHTML(self.out, name);
    [self.out appendString:@"\">"];
    [self renderChildren:node tight:NO];
    [self.out appendString:@"</span>"];
    return;
  }
  }
}

@end

#pragma mark - Plain-text rendering

static NSString *ALNMarkdownPlainBlocks(NSArray<ALNMarkdownNode *> *blocks, NSString *separator);

static void ALNMarkdownAppendPlainInline(ALNMarkdownNode *node, NSMutableString *out) {
  switch (node.type) {
  case ALNMarkdownNodeTypeText:
  case ALNMarkdownNodeTypeCode:
  case ALNMarkdownNodeTypeHTMLInline:
    [out appendString:node.literal ?: @""];
    return;
  case ALNMarkdownNodeTypeSoftBreak:
  case ALNMarkdownNodeTypeLineBreak:
    [out appendString:@"\n"];
    return;
  case ALNMarkdownNodeTypeLink:
  case ALNMarkdownNodeTypeImage: {
    NSMutableString *text = [NSMutableString string];
    for (ALNMarkdownNode *child in node.mutableChildren) {
      ALNMarkdownAppendPlainInline(child, text);
    }
    [out appendString:text];
    NSString *url = node.URL ?: @"";
    NSString *bareURL = [url hasPrefix:@"mailto:"] ? [url substringFromIndex:7] : url;
    if ([url length] > 0 && ![text isEqualToString:url] && ![text isEqualToString:bareURL]) {
      [out appendString:([text length] > 0 ? [NSString stringWithFormat:@" (%@)", url] : url)];
    }
    return;
  }
  default:
    for (ALNMarkdownNode *child in node.mutableChildren) {
      ALNMarkdownAppendPlainInline(child, out);
    }
    return;
  }
}

static NSString *ALNMarkdownIndentLines(NSString *text, NSString *first, NSString *rest) {
  NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
  NSMutableArray<NSString *> *indented = [NSMutableArray array];
  [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
    (void)stop;
    NSString *prefix = index == 0 ? first : rest;
    if ([line length] == 0) {
      prefix = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    [indented addObject:[prefix stringByAppendingString:line]];
  }];
  return [indented componentsJoinedByString:@"\n"];
}

static NSString *ALNMarkdownPlainBlock(ALNMarkdownNode *node) {
  switch (node.type) {
  case ALNMarkdownNodeTypeDocument:
    return ALNMarkdownPlainBlocks(node.mutableChildren, @"\n\n");
  case ALNMarkdownNodeTypeBlockQuote:
    return ALNMarkdownIndentLines(ALNMarkdownPlainBlocks(node.mutableChildren, @"\n\n"), @"> ", @"> ");
  case ALNMarkdownNodeTypeList: {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    NSInteger number = node.listStart;
    for (ALNMarkdownNode *item in node.mutableChildren) {
      NSString *marker = node.listType == ALNMarkdownListTypeOrdered
                             ? [NSString stringWithFormat:@"%ld. ", (long)number++]
                             : @"- ";
      if (item.isTaskListItem) {
        marker = [marker stringByAppendingString:(item.isChecked ? @"[x] " : @"[ ] ")];
      }
      NSString *body = ALNMarkdownPlainBlocks(item.mutableChildren, node.listTight ? @"\n" : @"\n\n");
      NSString *padding = [@"" stringByPaddingToLength:[marker length] withString:@" " startingAtIndex:0];
      [items addObject:ALNMarkdownIndentLines(body, marker, padding)];
    }
    return [items componentsJoinedByString:@"\n"];
  }
  case ALNMarkdownNodeTypeItem:
    return ALNMarkdownPlainBlocks(node.mutableChildren, @"\n");
  case ALNMarkdownNodeTypeCodeBlock:
  case ALNMarkdownNodeTypeHTMLBlock: {
    NSString *literal = node.literal ?: @"";
    while ([literal hasSuffix:@"\n"]) {
      literal = [literal substringToIndex:[literal length] - 1];
    }
    return literal;
  }
  case ALNMarkdownNodeTypeThematicBreak:
    return @"";
  case ALNMarkdownNodeTypeTable: {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (ALNMarkdownNode *row in node.mutableChildren) {
      NSMutableArray<NSString *> *cells = [NSMutableArray array];
      for (ALNMarkdownNode *cell in row.mutableChildren) {
        NSMutableString *text = [NSMutableString string];
        ALNMarkdownAppendPlainInline(cell, text);
        [cells addObject:text];
      }
      [rows addObject:[cells componentsJoinedByString:@" | "]];
    }
    return [rows componentsJoinedByString:@"\n"];
  }
  default: {
    NSMutableString *text = [NSMutableString string];
    ALNMarkdownAppendPlainInline(node, text);
    return text;
  }
  }
}

static NSString *ALNMarkdownPlainBlocks(NSArray<ALNMarkdownNode *> *blocks, NSString *separator) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (ALNMarkdownNode *block in blocks) {
    NSString *text = ALNMarkdownPlainBlock(block);
    if ([text length] > 0) {
      [parts addObject:text];
    }
  }
  return [parts componentsJoinedByString:separator];
}

#pragma mark - Entry points

@implementation ALNMarkdown

+ (ALNMarkdownOptions *)resolvedOptions:(ALNMarkdownOptions *)options {
  return [options isKindOfClass:[ALNMarkdownOptions class]] ? [options copy] : [ALNMarkdownOptions defaultOptions];
}

+ (ALNMarkdownNode *)parseString:(NSString *)markdown options:(ALNMarkdownOptions *)options {
  ALNMarkdownOptions *resolved = [self resolvedOptions:options];
  ALNMarkdownEnsureExtensionsRegistered();

  int cmarkOptions = CMARK_OPT_DEFAULT;
  if (resolved.smartPunctuation) {
    cmarkOptions |= CMARK_OPT_SMART;
  }
  cmark_parser *parser = cmark_parser_new(cmarkOptions);
  struct {
    ALNMarkdownExtensions flag;
    const char *name;
  } extensions[] = {
    {ALNMarkdownExtensionTables, "table"},
    {ALNMarkdownExtensionTaskLists, "tasklist"},
    {ALNMarkdownExtensionStrikethrough, "strikethrough"},
    {ALNMarkdownExtensionAutolinks, "autolink"},
  };
  for (size_t i = 0; i < sizeof(extensions) / sizeof(extensions[0]); i++) {
    if ((resolved.extensions & extensions[i].flag) == 0) {
      continue;
    }
    cmark_syntax_extension *extension = cmark_find_syntax_extension(extensions[i].name);
    if (extension != NULL) {
      cmark_parser_attach_syntax_extension(parser, extension);
    }
  }

  NSString *source = [markdown isKindOfClass:[NSString class]] ? markdown : @"";
  NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES] ?: [NSData data];
  cmark_parser_feed(parser, [data bytes], [data length]);
  cmark_node *document = cmark_parser_finish(parser);
  ALNMarkdownNode *root = nil;
  if (document != NULL) {
    cmark_consolidate_text_nodes(document);
    root = ALNMarkdownConvertDocument(document, MAX((NSUInteger)1, resolved.maximumNestingDepth));
    cmark_node_free(document);
  }
  cmark_parser_free(parser);
  root = root ?: [[ALNMarkdownNode alloc] initWithType:ALNMarkdownNodeTypeDocument];

  NSMutableArray<ALNMarkdownInlineSpanSyntax *> *syntaxes = [NSMutableArray array];
  for (id syntax in resolved.inlineSpans ?: @[]) {
    if ([syntax isKindOfClass:[ALNMarkdownInlineSpanSyntax class]]) {
      [syntaxes addObject:syntax];
    }
  }
  if ([syntaxes count] > 0) {
    ALNMarkdownApplySpans(root, syntaxes);
  }
  return root;
}

+ (NSString *)HTMLFromNode:(ALNMarkdownNode *)node options:(ALNMarkdownOptions *)options {
  if (![node isKindOfClass:[ALNMarkdownNode class]]) {
    return @"";
  }
  ALNMarkdownHTMLRenderer *renderer = [[ALNMarkdownHTMLRenderer alloc] init];
  renderer.options = [self resolvedOptions:options];
  renderer.out = [NSMutableString string];
  [renderer render:node tight:NO];
  return [renderer.out copy];
}

+ (NSString *)HTMLFromString:(NSString *)markdown options:(ALNMarkdownOptions *)options {
  return [self HTMLFromNode:[self parseString:markdown options:options] options:options];
}

+ (NSString *)plainTextFromNode:(ALNMarkdownNode *)node {
  if (![node isKindOfClass:[ALNMarkdownNode class]]) {
    return @"";
  }
  return ALNMarkdownPlainBlock(node);
}

+ (NSString *)plainTextFromString:(NSString *)markdown options:(ALNMarkdownOptions *)options {
  return [self plainTextFromNode:[self parseString:markdown options:options]];
}

+ (NSString *)cmarkGFMVersion {
  return ALNMarkdownString(cmark_version_string());
}

@end

NSString *ALNEOCMarkdownHTML(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  NSString *markdown = [value isKindOfClass:[NSString class]] ? value : [value description];
  return [ALNMarkdown HTMLFromString:markdown options:nil];
}
