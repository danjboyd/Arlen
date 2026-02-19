#ifndef ALN_EOC_TRANSPILER_H
#define ALN_EOC_TRANSPILER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNEOCTranspiler : NSObject

- (NSString *)symbolNameForLogicalPath:(NSString *)logicalPath;
- (NSString *)logicalPathForTemplatePath:(NSString *)templatePath
                             templateRoot:(nullable NSString *)templateRoot;
- (nullable NSString *)transpiledSourceForTemplateString:(NSString *)templateText
                                              logicalPath:(NSString *)logicalPath
                                                    error:
                                                        (NSError *_Nullable *_Nullable)error;
- (BOOL)transpileTemplateAtPath:(NSString *)templatePath
                   templateRoot:(nullable NSString *)templateRoot
                     outputPath:(NSString *)outputPath
                          error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
