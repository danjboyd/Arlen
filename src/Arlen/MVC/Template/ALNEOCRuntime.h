#ifndef ALN_EOC_RUNTIME_H
#define ALN_EOC_RUNTIME_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNEOCErrorDomain;
extern NSString *const ALNEOCErrorLineKey;
extern NSString *const ALNEOCErrorColumnKey;
extern NSString *const ALNEOCErrorPathKey;

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

void ALNEOCAppendEscaped(NSMutableString *out, id _Nullable value);
void ALNEOCAppendRaw(NSMutableString *out, id _Nullable value);

void ALNEOCClearTemplateRegistry(void);
void ALNEOCRegisterTemplate(NSString *logicalPath, ALNEOCRenderFunction function);
ALNEOCRenderFunction _Nullable ALNEOCResolveTemplate(NSString *logicalPath);

NSString *_Nullable ALNEOCRenderTemplate(NSString *logicalPath,
                                          id _Nullable ctx,
                                          NSError **_Nullable error);
BOOL ALNEOCInclude(NSMutableString *out,
                    id _Nullable ctx,
                    NSString *logicalPath,
                    NSError **_Nullable error);

NS_ASSUME_NONNULL_END

#endif
