// Foundation plus <pthread.h> for the first-use race probes, which start raw
// pthreads on purpose.
//
// Workaround for the gnustep-cli v0.1.0 Windows toolchain (Arlen #200 §4):
// libdispatch's os/generic_win_base.h, pulled in by Foundation, declares
// `typedef void pthread_attr_t;`, which clashes with winpthreads. Include the
// real <pthread.h> first, then park libdispatch's typedef under another name
// while Foundation loads. Delete this header once the toolchain fixes the typedef.
#ifndef ALN_PROBE_THREADING_H
#define ALN_PROBE_THREADING_H

#if defined(_WIN32)
#include <pthread.h>
#define pthread_attr_t ALNLibdispatchWindowsPthreadAttrPlaceholder
#import <Foundation/Foundation.h>
#undef pthread_attr_t
#else
#import <Foundation/Foundation.h>
#include <pthread.h>
#endif

#endif
