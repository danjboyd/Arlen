#ifndef ALN_EOC_RUNTIME_H
#define ALN_EOC_RUNTIME_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNEOCErrorDomain;
extern NSString *const ALNEOCErrorLineKey;
extern NSString *const ALNEOCErrorColumnKey;
extern NSString *const ALNEOCErrorPathKey;
extern NSString *const ALNEOCErrorLocalNameKey;
extern NSString *const ALNEOCErrorKeyPathKey;
extern NSString *const ALNEOCErrorSegmentKey;

typedef NS_ENUM(NSInteger, ALNEOCErrorCode) {
  ALNEOCErrorTemplateNotFound = 1,
  ALNEOCErrorTemplateExecutionFailed = 2,
  ALNEOCErrorTranspilerSyntax = 3,
  ALNEOCErrorFileIO = 4,
  ALNEOCErrorInvalidArgument = 5,
};

typedef NSString *_Nullable (*ALNEOCRenderFunction)(id _Nullable ctx,
                                                     NSError **_Nullable error);

NSString *ALNEOCCanonicalTemplatePath(NSString *path);
NSString *ALNEOCEscapeHTMLString(NSString *input);
NSString *ALNEOCSafeLinkURL(id _Nullable value);
NSString *ALNEOCNormalizeTemplateReference(NSString *path);

BOOL ALNEOCStrictLocalsEnabled(void);
BOOL ALNEOCStrictStringifyEnabled(void);
void ALNEOCSetStrictLocalsEnabled(BOOL enabled);
void ALNEOCSetStrictStringifyEnabled(BOOL enabled);
NSDictionary *ALNEOCPushRenderOptions(BOOL strictLocals, BOOL strictStringify);
void ALNEOCPopRenderOptions(NSDictionary *_Nullable token);
NSDictionary *ALNEOCPushCompositionState(void);
void ALNEOCPopCompositionState(NSDictionary *_Nullable token);

id _Nullable ALNEOCLocal(id _Nullable ctx,
                         NSString *name,
                         NSString *templatePath,
                         NSUInteger line,
                         NSUInteger column,
                         NSError **_Nullable error);
id _Nullable ALNEOCLocalPath(id _Nullable ctx,
                             NSString *keyPath,
                             NSString *templatePath,
                             NSUInteger line,
                             NSUInteger column,
                             NSError **_Nullable error);

void ALNEOCAppendEscaped(NSMutableString *out, id _Nullable value);
void ALNEOCAppendRaw(NSMutableString *out, id _Nullable value);
BOOL ALNEOCAppendEscapedChecked(NSMutableString *out,
                                id _Nullable value,
                                NSString *templatePath,
                                NSUInteger line,
                                NSUInteger column,
                                NSError **_Nullable error);
BOOL ALNEOCAppendRawChecked(NSMutableString *out,
                            id _Nullable value,
                            NSString *templatePath,
                            NSUInteger line,
                            NSUInteger column,
                            NSError **_Nullable error);
BOOL ALNEOCEnsureRequiredLocals(id _Nullable ctx,
                                NSArray<NSString *> *requiredLocals,
                                NSString *templatePath,
                                NSUInteger line,
                                NSUInteger column,
                                NSError **_Nullable error);
BOOL ALNEOCSetSlot(id _Nullable ctx,
                   NSString *slotName,
                   NSString *content,
                   NSString *templatePath,
                   NSUInteger line,
                   NSUInteger column,
                   NSError **_Nullable error);
void ALNEOCSetSlotContent(NSString *slotName, NSString *content);
BOOL ALNEOCAppendYield(NSMutableString *out,
                       id _Nullable ctx,
                       NSString *slotName,
                       NSString *templatePath,
                       NSUInteger line,
                       NSUInteger column,
                       NSError **_Nullable error);

void ALNEOCClearTemplateRegistry(void);
void ALNEOCRegisterTemplate(NSString *logicalPath, ALNEOCRenderFunction function);
void ALNEOCRegisterTemplateLayout(NSString *logicalPath, NSString *layoutLogicalPath);
NSString *_Nullable ALNEOCResolveTemplateLayout(NSString *logicalPath);
ALNEOCRenderFunction _Nullable ALNEOCResolveTemplate(NSString *logicalPath);

NSString *_Nullable ALNEOCRenderTemplate(NSString *logicalPath,
                                          id _Nullable ctx,
                                          NSError **_Nullable error);
BOOL ALNEOCInclude(NSMutableString *out,
                    id _Nullable ctx,
                    NSString *logicalPath,
                    NSError **_Nullable error);
BOOL ALNEOCIncludeWithLocals(NSMutableString *out,
                             id _Nullable ctx,
                             NSString *logicalPath,
                             id _Nullable locals,
                             NSString *templatePath,
                             NSUInteger line,
                             NSUInteger column,
                             NSError **_Nullable error);
BOOL ALNEOCRenderCollection(NSMutableString *out,
                            id _Nullable ctx,
                            NSString *logicalPath,
                            id _Nullable collection,
                            NSString *itemLocalName,
                            NSString *_Nullable emptyLogicalPath,
                            id _Nullable locals,
                            NSString *templatePath,
                            NSUInteger line,
                            NSUInteger column,
                            NSError **_Nullable error);

// Markdown to safe HTML with the default ALNMarkdownOptions, for raw output:
// <%== ALNEOCMarkdownHTML($body) %>. nil and NSNull render as "". Defined in
// ALNMarkdown.m (framework library), not in the template runtime.
NSString *ALNEOCMarkdownHTML(id _Nullable value);

// JSON that is safe to place inside an inline <script> element, for raw output:
// <script>var data = <%== ALNEOCJSONForScript($payload) %>;</script>.
// Serializes with sorted keys, then writes <, >, &, U+2028 and U+2029 as
// \u003c, \u003e, \u0026, \u2028 and \u2029 so string values cannot close the
// script element or break a JavaScript string literal. Scalars are allowed;
// nil and NSNull render as null, and so does a value that cannot be
// serialized. Defined in ALNJSONSerialization.m (framework library), not in
// the template runtime.
NSString *ALNEOCJSONForScript(id _Nullable value);

NS_ASSUME_NONNULL_END

#endif
