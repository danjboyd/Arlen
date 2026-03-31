#ifndef ALN_EXPORTS_H
#define ALN_EXPORTS_H

#import <Foundation/Foundation.h>

#if defined(_WIN32)
#define ALN_EXPORT extern
#else
#define ALN_EXPORT FOUNDATION_EXPORT
#endif

#endif
