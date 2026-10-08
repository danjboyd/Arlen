#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNMarkdown.h"
#import "../shared/ALNTestSupport.h"

@interface MarkdownTests : XCTestCase
@end

@implementation MarkdownTests

- (NSString *)html:(NSString *)markdown {
  return [ALNMarkdown HTMLFromString:markdown options:nil];
}

- (NSUInteger)depthOfNode:(ALNMarkdownNode *)node {
  NSUInteger deepest = 0;
  for (ALNMarkdownNode *child in node.children) {
    // Not MAX(): GNUstep's macro evaluates the recursive call twice.
    NSUInteger depth = [self depthOfNode:child];
    if (depth > deepest) {
      deepest = depth;
    }
  }
  return deepest + 1;
}

- (void)collectNodes:(ALNMarkdownNode *)node into:(NSMutableArray<ALNMarkdownNode *> *)nodes {
  [nodes addObject:node];
  for (ALNMarkdownNode *child in node.children) {
    [self collectNodes:child into:nodes];
  }
}

- (NSArray<ALNMarkdownNode *> *)nodesIn:(ALNMarkdownNode *)root {
  NSMutableArray<ALNMarkdownNode *> *nodes = [NSMutableArray array];
  [self collectNodes:root into:nodes];
  return nodes;
}

- (ALNMarkdownInlineSpanSyntax *)colorSyntax {
  return [ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"color"
                                          openingDelimiter:@"⟦"
                                          closingDelimiter:@"⟧"
                                                     names:[NSSet setWithArray:@[ @"red", @"blue" ]]];
}

- (ALNMarkdownOptions *)colorOptions {
  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  options.inlineSpans = @[ [self colorSyntax] ];
  return options;
}

#pragma mark - Spec conformance

// Every GFM spec example whose output the safety rules leave alone renders
// exactly as the spec says. Like cmark-gfm's spec runner, each example gets
// only the extension it is tagged with. Examples with raw HTML (escaped here, by design)
// or a URL scheme outside the allowlist are covered by the tests below.
- (void)testGFMSpecExamplesMatchExpectedHTML {
  NSString *path = ALNTestPathFromRepoRoot(@"tests/fixtures/markdown/gfm_spec_examples.json");
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data, @"%@", path);
  NSDictionary *fixture = data != nil ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  NSArray *examples = fixture[@"examples"];
  XCTAssertEqual((NSUInteger)672, [examples count]);

  NSDictionary<NSString *, NSNumber *> *extensionFlags = @{
    @"" : @(ALNMarkdownExtensionNone),
    @"table" : @(ALNMarkdownExtensionTables),
    @"strikethrough" : @(ALNMarkdownExtensionStrikethrough),
    @"autolink" : @(ALNMarkdownExtensionAutolinks),
  };
  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  NSUInteger compared = 0;
  NSUInteger skippedRawHTML = 0;
  NSUInteger skippedURLPolicy = 0;
  for (NSDictionary *example in examples) {
    NSString *extension = example[@"extension"];
    // "disabled" examples are ones cmark-gfm's own spec run skips; tagfilter
    // only filters raw HTML, which is always escaped here.
    if ([extension isEqualToString:@"disabled"] || [extension isEqualToString:@"tagfilter"]) {
      continue;
    }
    XCTAssertNotNil(extensionFlags[extension], @"untagged extension %@", extension);
    options.extensions = [extensionFlags[extension] unsignedIntegerValue];
    ALNMarkdownNode *document = [ALNMarkdown parseString:example[@"markdown"] options:options];
    BOOL rawHTML = NO;
    BOOL blockedURL = NO;
    for (ALNMarkdownNode *node in [self nodesIn:document]) {
      if (node.type == ALNMarkdownNodeTypeHTMLBlock || node.type == ALNMarkdownNodeTypeHTMLInline) {
        rawHTML = YES;
      }
      if (node.type == ALNMarkdownNodeTypeLink || node.type == ALNMarkdownNodeTypeImage) {
        NSString *rendered = [ALNMarkdown HTMLFromNode:node options:options];
        BOOL tagged = [rendered hasPrefix:(node.type == ALNMarkdownNodeTypeLink ? @"<a " : @"<img ")];
        if (!tagged) {
          blockedURL = YES;
        }
      }
    }
    if (rawHTML) {
      skippedRawHTML++;
      continue;
    }
    if (blockedURL) {
      skippedURLPolicy++;
      continue;
    }
    compared++;
    NSString *html = [ALNMarkdown HTMLFromNode:document options:options];
    XCTAssertEqualObjects(example[@"html"], html, @"spec example %@ (%@): %@", example[@"example"],
                          example[@"section"], example[@"markdown"]);
  }
  // Guards against the filters above quietly skipping most of the spec.
  XCTAssertGreaterThan(compared, (NSUInteger)500);
  XCTAssertLessThan(skippedRawHTML, (NSUInteger)120);
  XCTAssertLessThan(skippedURLPolicy, (NSUInteger)20);
}

#pragma mark - Safety

- (void)testRawHTMLIsEscapedNotPassedThrough {
  XCTAssertEqualObjects(@"<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>\n", [self html:@"<script>alert(1)</script>\n"]);
  XCTAssertEqualObjects(@"<p>a &lt;img src=x onerror=alert(1)&gt; b</p>\n",
                        [self html:@"a <img src=x onerror=alert(1)> b"]);
  XCTAssertEqualObjects(@"<p>&lt;div onclick=&quot;alert(1)&quot;&gt;\nhi\n&lt;/div&gt;</p>\n",
                        [self html:@"<div onclick=\"alert(1)\">\nhi\n</div>\n"]);

  NSString *html = [self html:@"<img src=x onerror=alert(1)>\n\n<iframe src=\"https://evil.example\"></iframe>\n\n"
                              @"x <svg onload=alert(1)> <a href=\"javascript:alert(1)\">y</a>"];
  XCTAssertFalse([html containsString:@"<img"], @"%@", html);
  XCTAssertFalse([html containsString:@"<iframe"], @"%@", html);
  XCTAssertFalse([html containsString:@"<svg"], @"%@", html);
  XCTAssertFalse([html containsString:@"<a "], @"%@", html);
}

- (void)testLinkURLsAreLimitedToAllowedSchemes {
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](javascript:alert(1))"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](JaVaScRiPt:alert(1))"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](java&#x09;script:alert(1))"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](<java\tscript:alert(1)>)"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](&#32;javascript:alert(1))"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](vbscript:msgbox)"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](data:text/html;base64,PHNjcmlwdD4=)"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x](file:///etc/passwd)"]);
  XCTAssertEqualObjects(@"<p>javascript:alert(1)</p>\n", [self html:@"<javascript:alert(1)>"]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [self html:@"[x][r]\n\n[r]: javascript:alert(1)"]);
  XCTAssertEqualObjects(@"<p>alt</p>\n", [self html:@"![alt](javascript:alert(1))"]);
  XCTAssertEqualObjects(@"<p>alt</p>\n", [self html:@"![alt](data:image/svg+xml,<svg/onload=alert(1)>)"]);

  XCTAssertEqualObjects(@"<p><a href=\"https://example.com/a?b=1&amp;c=2\">x</a></p>\n",
                        [self html:@"[x](https://example.com/a?b=1&c=2)"]);
  XCTAssertEqualObjects(@"<p><a href=\"HTTP://example.com\">x</a></p>\n", [self html:@"[x](HTTP://example.com)"]);
  XCTAssertEqualObjects(@"<p><a href=\"mailto:a@example.com\">x</a></p>\n", [self html:@"[x](mailto:a@example.com)"]);
  XCTAssertEqualObjects(@"<p><a href=\"/docs#install\">x</a></p>\n", [self html:@"[x](/docs#install)"]);
  XCTAssertEqualObjects(@"<p><a href=\"#top\">x</a></p>\n", [self html:@"[x](#top)"]);
  XCTAssertEqualObjects(@"<p><img src=\"https://example.com/a.png\" alt=\"a\" /></p>\n",
                        [self html:@"![a](https://example.com/a.png)"]);
  XCTAssertEqualObjects(@"<p>a</p>\n", [self html:@"![a](mailto:a@example.com)"]);

  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  options.allowedLinkSchemes = @[ @"https", @"tel" ];
  XCTAssertEqualObjects(@"<p><a href=\"tel:+15555550100\">call</a></p>\n",
                        [ALNMarkdown HTMLFromString:@"[call](tel:+15555550100)" options:options]);
  XCTAssertEqualObjects(@"<p>x</p>\n", [ALNMarkdown HTMLFromString:@"[x](http://example.com)" options:options]);
}

- (void)testAttributesCannotBeBrokenOutOf {
  NSString *html = [self html:@"[x](https://example.com/\"onmouseover=alert(1) \"t\\\" onmouseover=\\\"alert(1)\")"];
  XCTAssertFalse([html containsString:@"\" onmouseover"], @"%@", html);
  XCTAssertTrue([html containsString:@"%22onmouseover=alert(1)"], @"%@", html);
  XCTAssertTrue([html containsString:@"title=\"t&quot; onmouseover=&quot;alert(1)\""], @"%@", html);

  html = [self html:@"![a\" onerror=\"alert(1)](https://example.com/a.png 'b\" onload=\"x')"];
  XCTAssertTrue([html containsString:@"alt=\"a&quot; onerror=&quot;alert(1)\""], @"%@", html);
  XCTAssertTrue([html containsString:@"title=\"b&quot; onload=&quot;x\""], @"%@", html);

  html = [self html:@"```js\" onmouseover=\"alert(1)\nx\n```"];
  XCTAssertEqualObjects(@"<pre><code class=\"language-js&quot;\">x\n</code></pre>\n", html);
}

#pragma mark - Extensions

- (void)testGFMExtensionsAreOnByDefault {
  XCTAssertEqualObjects(@"<p><del>gone</del></p>\n", [self html:@"~~gone~~"]);
  XCTAssertEqualObjects(@"<p>see <a href=\"http://www.example.com\">www.example.com</a></p>\n",
                        [self html:@"see www.example.com"]);
  XCTAssertEqualObjects(@"<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> todo</li>\n"
                        @"<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> done</li>\n</ul>\n",
                        [self html:@"- [ ] todo\n- [x] done\n"]);
  XCTAssertEqualObjects(@"<table>\n<thead>\n<tr>\n<th>a</th>\n<th align=\"right\">b</th>\n</tr>\n</thead>\n"
                        @"<tbody>\n<tr>\n<td>1</td>\n<td align=\"right\">2</td>\n</tr>\n</tbody>\n</table>\n",
                        [self html:@"| a | b |\n|---|--:|\n| 1 | 2 |\n"]);
}

- (void)testEachExtensionCanBeSwitchedOffPerCall {
  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  options.extensions = ALNMarkdownExtensionAll & ~ALNMarkdownExtensionTables;
  XCTAssertEqualObjects(@"<p>| a |\n|---|</p>\n", [ALNMarkdown HTMLFromString:@"| a |\n|---|\n" options:options]);

  options.extensions = ALNMarkdownExtensionAll & ~ALNMarkdownExtensionStrikethrough;
  XCTAssertEqualObjects(@"<p>~~gone~~</p>\n", [ALNMarkdown HTMLFromString:@"~~gone~~" options:options]);

  options.extensions = ALNMarkdownExtensionAll & ~ALNMarkdownExtensionAutolinks;
  XCTAssertEqualObjects(@"<p>see www.example.com</p>\n",
                        [ALNMarkdown HTMLFromString:@"see www.example.com" options:options]);

  options.extensions = ALNMarkdownExtensionAll & ~ALNMarkdownExtensionTaskLists;
  XCTAssertEqualObjects(@"<ul>\n<li>[ ] todo</li>\n</ul>\n", [ALNMarkdown HTMLFromString:@"- [ ] todo" options:options]);

  options.extensions = ALNMarkdownExtensionNone;
  XCTAssertEqualObjects(@"<p>~~a~~ www.example.com</p>\n",
                        [ALNMarkdown HTMLFromString:@"~~a~~ www.example.com" options:options]);
}

#pragma mark - Node tree

- (void)testNodeTreeExposesBlockAndInlineDetails {
  ALNMarkdownNode *document =
      [ALNMarkdown parseString:@"## Title\n\n3. one\n4. [two](https://example.com \"T\")\n\n"
                               @"```objc extra\ncode\n```\n\n| h | i |\n|:-:|:--|\n| *a* | `b` |\n"
                       options:nil];
  XCTAssertEqual(ALNMarkdownNodeTypeDocument, document.type);
  XCTAssertEqual((NSUInteger)4, [document.children count]);

  ALNMarkdownNode *heading = document.children[0];
  XCTAssertEqual(ALNMarkdownNodeTypeHeading, heading.type);
  XCTAssertEqual((NSInteger)2, heading.headingLevel);
  XCTAssertEqualObjects(@"Title", [heading textContent]);

  ALNMarkdownNode *list = document.children[1];
  XCTAssertEqual(ALNMarkdownNodeTypeList, list.type);
  XCTAssertEqual(ALNMarkdownListTypeOrdered, list.listType);
  XCTAssertEqual((NSInteger)3, list.listStart);
  XCTAssertTrue(list.listTight);
  ALNMarkdownNode *link = list.children[1].children[0].children[0];
  XCTAssertEqual(ALNMarkdownNodeTypeLink, link.type);
  XCTAssertEqualObjects(@"https://example.com", link.URL);
  XCTAssertEqualObjects(@"T", link.title);

  ALNMarkdownNode *code = document.children[2];
  XCTAssertEqual(ALNMarkdownNodeTypeCodeBlock, code.type);
  XCTAssertEqualObjects(@"objc extra", code.fenceInfo);
  XCTAssertEqualObjects(@"code\n", code.literal);

  ALNMarkdownNode *table = document.children[3];
  XCTAssertEqual(ALNMarkdownNodeTypeTable, table.type);
  ALNMarkdownNode *headerRow = table.children[0];
  XCTAssertTrue(headerRow.isHeaderRow);
  XCTAssertEqual(ALNMarkdownTableAlignmentCenter, headerRow.children[0].alignment);
  XCTAssertEqual(ALNMarkdownTableAlignmentLeft, headerRow.children[1].alignment);
  ALNMarkdownNode *bodyRow = table.children[1];
  XCTAssertFalse(bodyRow.isHeaderRow);
  XCTAssertEqual(ALNMarkdownNodeTypeEmphasis, bodyRow.children[0].children[0].type);
  XCTAssertEqual(ALNMarkdownNodeTypeCode, bodyRow.children[1].children[0].type);
  XCTAssertEqualObjects(@"b", bodyRow.children[1].children[0].literal);
}

- (void)testTaskListItemsAreMarkedInTheTree {
  ALNMarkdownNode *list = [ALNMarkdown parseString:@"- [x] done\n- plain\n" options:nil].children[0];
  XCTAssertTrue(list.children[0].isTaskListItem);
  XCTAssertTrue(list.children[0].isChecked);
  XCTAssertFalse(list.children[1].isTaskListItem);
}

- (void)testDeepNestingIsCollapsedToBoundedDepth {
  NSString *quotes = [[@"" stringByPaddingToLength:20000 withString:@">" startingAtIndex:0]
      stringByAppendingString:@" deep"];
  ALNMarkdownNode *document = [ALNMarkdown parseString:quotes options:nil];
  XCTAssertLessThanOrEqual([self depthOfNode:document], (NSUInteger)67);
  XCTAssertTrue([[ALNMarkdown HTMLFromNode:document options:nil] containsString:@"deep"]);
  XCTAssertEqualObjects(@"deep", [[ALNMarkdown plainTextFromNode:document]
                                     stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"> \n"]]);

  NSMutableString *lists = [NSMutableString string];
  for (NSUInteger i = 0; i < 2000; i++) {
    [lists appendString:[[@"" stringByPaddingToLength:i * 2 withString:@" " startingAtIndex:0]
                            stringByAppendingString:@"- x\n"]];
  }
  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  options.maximumNestingDepth = 10;
  document = [ALNMarkdown parseString:lists options:options];
  XCTAssertLessThanOrEqual([self depthOfNode:document], (NSUInteger)13);

  NSString *emphasis = [[@"" stringByPaddingToLength:5000 withString:@"*a " startingAtIndex:0]
      stringByAppendingString:[@"" stringByPaddingToLength:5000 withString:@"a* " startingAtIndex:0]];
  XCTAssertNotNil([self html:emphasis]);
  XCTAssertNotNil([self html:[[@"" stringByPaddingToLength:20000 withString:@"[" startingAtIndex:0]
                                 stringByAppendingString:@"x"]]);
}

#pragma mark - Inline spans

- (void)testCustomInlineSpanRoundTripsAsTypedNode {
  ALNMarkdownNode *document = [ALNMarkdown parseString:@"a ⟦red⟧**bold** and `code`⟦/red⟧ b" options:[self colorOptions]];
  ALNMarkdownNode *paragraph = document.children[0];
  XCTAssertEqual((NSUInteger)3, [paragraph.children count]);
  XCTAssertEqualObjects(@"a ", paragraph.children[0].literal);
  ALNMarkdownNode *span = paragraph.children[1];
  XCTAssertEqual(ALNMarkdownNodeTypeInlineSpan, span.type);
  XCTAssertEqualObjects(@"color", span.spanIdentifier);
  XCTAssertEqualObjects(@"red", span.spanName);
  XCTAssertEqual(ALNMarkdownNodeTypeStrong, span.children[0].type);
  XCTAssertEqualObjects(@" and ", span.children[1].literal);
  XCTAssertEqual(ALNMarkdownNodeTypeCode, span.children[2].type);
  XCTAssertEqualObjects(@" b", paragraph.children[2].literal);

  XCTAssertEqualObjects(@"<p>a <span data-markdown-span=\"color\" data-value=\"red\"><strong>bold</strong> and "
                        @"<code>code</code></span> b</p>\n",
                        [ALNMarkdown HTMLFromNode:document options:nil]);
  XCTAssertEqualObjects(@"a bold and code b", [ALNMarkdown plainTextFromNode:document]);
}

- (void)testInlineSpansInsideOtherInlinesAndBlocks {
  ALNMarkdownOptions *options = [self colorOptions];
  XCTAssertEqualObjects(@"<p><em>x <span data-markdown-span=\"color\" data-value=\"blue\">y</span></em></p>\n",
                        [ALNMarkdown HTMLFromString:@"*x ⟦blue⟧y⟦/blue⟧*" options:options]);
  XCTAssertEqualObjects(@"<h1><span data-markdown-span=\"color\" data-value=\"red\">t</span></h1>\n",
                        [ALNMarkdown HTMLFromString:@"# ⟦red⟧t⟦/red⟧" options:options]);
  NSString *table = [ALNMarkdown HTMLFromString:@"| a |\n|---|\n| ⟦red⟧c⟦/red⟧ |\n" options:options];
  XCTAssertTrue([table containsString:@"<td><span data-markdown-span=\"color\" data-value=\"red\">c</span></td>"],
                @"%@", table);
}

- (void)testInvalidInlineSpanMarkersStayLiteral {
  ALNMarkdownOptions *options = [self colorOptions];
  // Unknown name, unmatched opener, unmatched closer, mismatched pair.
  XCTAssertEqualObjects(@"<p>⟦green⟧x⟦/green⟧</p>\n", [ALNMarkdown HTMLFromString:@"⟦green⟧x⟦/green⟧" options:options]);
  XCTAssertEqualObjects(@"<p>⟦red⟧x</p>\n", [ALNMarkdown HTMLFromString:@"⟦red⟧x" options:options]);
  XCTAssertEqualObjects(@"<p>x⟦/red⟧</p>\n", [ALNMarkdown HTMLFromString:@"x⟦/red⟧" options:options]);
  XCTAssertEqualObjects(@"<p>⟦red⟧x⟦/blue⟧</p>\n", [ALNMarkdown HTMLFromString:@"⟦red⟧x⟦/blue⟧" options:options]);
  // Markers in code are never interpreted.
  XCTAssertEqualObjects(@"<p><code>⟦red⟧x⟦/red⟧</code></p>\n",
                        [ALNMarkdown HTMLFromString:@"`⟦red⟧x⟦/red⟧`" options:options]);
  // A span must close in the inline container it opened in.
  XCTAssertEqualObjects(@"<p>⟦red⟧<strong>x⟦/red⟧</strong></p>\n",
                        [ALNMarkdown HTMLFromString:@"⟦red⟧**x⟦/red⟧**" options:options]);
  // Spans do not nest: the inner markers stay text.
  XCTAssertEqualObjects(@"<p><span data-markdown-span=\"color\" data-value=\"red\">a ⟦blue⟧b⟦/blue⟧ c</span></p>\n",
                        [ALNMarkdown HTMLFromString:@"⟦red⟧a ⟦blue⟧b⟦/blue⟧ c⟦/red⟧" options:options]);
  // Without the syntax registered, nothing changes.
  XCTAssertEqualObjects(@"<p>⟦red⟧x⟦/red⟧</p>\n", [self html:@"⟦red⟧x⟦/red⟧"]);
}

// Unmatched and malformed markers must not make the span pass quadratic. A
// search-to-the-end, scan-for-the-closer implementation is O(n^2) on each of
// these inputs.
- (void)testHostileSpanMarkersParseInLinearTime {
  ALNMarkdownOptions *options = [self colorOptions];
  ALNMarkdownInlineSpanSyntax *tag = [ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"tag"
                                                                      openingDelimiter:@"⟦"
                                                                      closingDelimiter:@"⟧"
                                                                                 names:nil];
  options.inlineSpans = @[ [self colorSyntax], tag ];
  NSArray<NSString *> *inputs = @[
    [@"" stringByPaddingToLength:40000 withString:@"⟦" startingAtIndex:0],
    [[@"" stringByPaddingToLength:40000 withString:@"⟦" startingAtIndex:0] stringByAppendingString:@"⟧"],
    [@"" stringByPaddingToLength:60000 withString:@"⟦red⟧" startingAtIndex:0],
    [@"" stringByPaddingToLength:60000 withString:@"⟦/red⟧ x " startingAtIndex:0],
    [[@"" stringByPaddingToLength:60000 withString:@"⟦red⟧*a* " startingAtIndex:0] stringByAppendingString:@"⟦/red⟧"],
  ];
  for (NSString *input in inputs) {
    NSDate *start = [NSDate date];
    NSString *html = [ALNMarkdown HTMLFromString:input options:options];
    NSTimeInterval elapsed = -[start timeIntervalSinceNow];
    XCTAssertGreaterThan([html length], (NSUInteger)0);
    XCTAssertLessThan(elapsed, 10.0, @"input of %lu characters took %.1fs", (unsigned long)[input length], elapsed);
  }
  // The last input pairs its first opener with the only closer.
  ALNMarkdownNode *paragraph = [ALNMarkdown parseString:[inputs lastObject] options:options].children[0];
  XCTAssertEqual((NSUInteger)1, [paragraph.children count]);
  XCTAssertEqual(ALNMarkdownNodeTypeInlineSpan, paragraph.children[0].type);
}

- (void)testInlineSpanSyntaxValidationAndOpenNames {
  XCTAssertNil([ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"" openingDelimiter:@"{" closingDelimiter:@"}" names:nil]);
  XCTAssertNil([ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"x" openingDelimiter:@"" closingDelimiter:@"}" names:nil]);

  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  options.inlineSpans = @[ [ALNMarkdownInlineSpanSyntax syntaxWithIdentifier:@"tag"
                                                             openingDelimiter:@"{{"
                                                             closingDelimiter:@"}}"
                                                                        names:nil] ];
  ALNMarkdownNode *span = [ALNMarkdown parseString:@"{{note-1}}hi{{/note-1}} {{bad name}}x{{/bad name}}"
                                           options:options].children[0].children[0];
  XCTAssertEqual(ALNMarkdownNodeTypeInlineSpan, span.type);
  XCTAssertEqualObjects(@"note-1", span.spanName);
  XCTAssertTrue([[ALNMarkdown HTMLFromString:@"{{bad name}}x{{/bad name}}" options:options]
      isEqualToString:@"<p>{{bad name}}x{{/bad name}}</p>\n"]);
}

#pragma mark - Renderer options

- (void)testHTMLClassMapStylesOutput {
  ALNMarkdownOptions *options = [self colorOptions];
  options.HTMLClassMap = @{
    @"p" : @"md-p",
    @"table" : @"md-table",
    @"code" : @"md-code",
    @"a" : @"md-link",
    @"span.color.red" : @"text-red",
    @"span.color" : @"text-color",
  };
  XCTAssertEqualObjects(@"<p class=\"md-p\"><a class=\"md-link\" href=\"https://e.com\">x</a> "
                        @"<span class=\"text-red\" data-markdown-span=\"color\" data-value=\"red\">r</span> "
                        @"<span class=\"text-color\" data-markdown-span=\"color\" data-value=\"blue\">b</span></p>\n",
                        [ALNMarkdown HTMLFromString:@"[x](https://e.com) ⟦red⟧r⟦/red⟧ ⟦blue⟧b⟦/blue⟧" options:options]);
  XCTAssertEqualObjects(@"<pre><code class=\"language-sh md-code\">ls\n</code></pre>\n",
                        [ALNMarkdown HTMLFromString:@"```sh\nls\n```" options:options]);
  XCTAssertTrue([[ALNMarkdown HTMLFromString:@"| a |\n|---|\n" options:options] hasPrefix:@"<table class=\"md-table\">"]);
}

- (void)testBreakAndPunctuationOptions {
  XCTAssertEqualObjects(@"<p>a\nb</p>\n", [self html:@"a\nb"]);
  ALNMarkdownOptions *options = [ALNMarkdownOptions defaultOptions];
  options.hardBreaks = YES;
  XCTAssertEqualObjects(@"<p>a<br />\nb</p>\n", [ALNMarkdown HTMLFromString:@"a\nb" options:options]);
  options.smartPunctuation = YES;
  XCTAssertEqualObjects(@"<p>“a” — b…</p>\n", [ALNMarkdown HTMLFromString:@"\"a\" --- b..." options:options]);
}

#pragma mark - Plain text

- (void)testPlainTextOfMixedDocument {
  NSString *markdown = @"# Release *notes*\n\n"
                       @"Read [the guide](https://example.com/guide) or visit https://example.com.\n"
                       @"Mail <ops@example.com>.\n\n"
                       @"- one\n- **two**\n  1. nested\n\n"
                       @"* [x] shipped\n* [ ] pending\n\n"
                       @"> quoted\n> text\n\n"
                       @"| Name | Qty |\n|------|----:|\n| `a` | 1 |\n| b | 2 |\n\n"
                       @"```\ncode <b>\n```\n\n"
                       @"---\n\n"
                       @"![chart](https://example.com/c.png) <i>raw</i>\n";
  NSString *expected = @"Release notes\n\n"
                       @"Read the guide (https://example.com/guide) or visit https://example.com.\n"
                       @"Mail ops@example.com.\n\n"
                       @"- one\n- two\n  1. nested\n\n"
                       @"- [x] shipped\n- [ ] pending\n\n"
                       @"> quoted\n> text\n\n"
                       @"Name | Qty\na | 1\nb | 2\n\n"
                       @"code <b>\n\n"
                       @"chart (https://example.com/c.png) <i>raw</i>";
  XCTAssertEqualObjects(expected, [ALNMarkdown plainTextFromString:markdown options:nil]);
}

#pragma mark - Templates

- (void)testEOCHelperRendersSafeHTML {
  XCTAssertEqualObjects(@"<p><strong>hi</strong> &lt;b&gt;</p>\n", ALNEOCMarkdownHTML(@"**hi** <b>"));
  XCTAssertEqualObjects(@"", ALNEOCMarkdownHTML(nil));
  XCTAssertEqualObjects(@"", ALNEOCMarkdownHTML([NSNull null]));
  XCTAssertEqualObjects(@"<p>42</p>\n", ALNEOCMarkdownHTML(@42));
}

// cmark-gfm stays a private dependency: apps and other framework code see only
// ALNMarkdown, so the vendored library can be updated or replaced freely.
- (void)testCmarkGFMIsEncapsulatedToMarkdownModule {
  NSString *repoRoot = ALNTestRepoRoot();
  for (NSString *root in @[ @"src", @"modules", @"tools" ]) {
    NSString *rootPath = [repoRoot stringByAppendingPathComponent:root];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:rootPath];
    NSString *relativePath = nil;
    while ((relativePath = [enumerator nextObject]) != nil) {
      if (![relativePath hasSuffix:@".m"] && ![relativePath hasSuffix:@".h"]) {
        continue;
      }
      if ([relativePath hasPrefix:@"Arlen/Support/third_party/cmark-gfm/"] ||
          [relativePath isEqualToString:@"Arlen/Support/ALNMarkdown.m"]) {
        continue;
      }
      NSString *contents = [NSString stringWithContentsOfFile:[rootPath stringByAppendingPathComponent:relativePath]
                                                     encoding:NSUTF8StringEncoding
                                                        error:NULL];
      XCTAssertFalse([contents containsString:@"third_party/cmark-gfm"], @"file=%@/%@", root, relativePath);
      XCTAssertFalse([contents containsString:@"cmark_"], @"file=%@/%@", root, relativePath);
    }
  }
}

- (void)testInputEdgeCases {
  XCTAssertEqualObjects(@"", [self html:@""]);
  XCTAssertEqualObjects(@"", [self html:nil]);
  unichar withNUL[] = {'a', 0, 'b'};
  XCTAssertEqualObjects(@"<p>a\uFFFDb</p>\n", [self html:[NSString stringWithCharacters:withNUL length:3]]);
  XCTAssertTrue([[ALNMarkdown cmarkGFMVersion] isEqualToString:@"0.29.0.gfm.13"]);
}

@end
