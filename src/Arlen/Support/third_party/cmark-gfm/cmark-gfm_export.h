/* Arlen: hand-written in place of CMake's generate_export_header(). cmark-gfm
   is compiled into the Arlen framework library, so nothing is exported or
   imported across a DLL boundary. See PROVENANCE.md. */
#ifndef CMARK_GFM_EXPORT_H
#define CMARK_GFM_EXPORT_H

#define CMARK_GFM_STATIC_DEFINE
#define CMARK_GFM_EXPORT
#define CMARK_GFM_NO_EXPORT
#define CMARK_GFM_DEPRECATED __attribute__((__deprecated__))
#define CMARK_GFM_DEPRECATED_EXPORT CMARK_GFM_EXPORT CMARK_GFM_DEPRECATED
#define CMARK_GFM_DEPRECATED_NO_EXPORT CMARK_GFM_NO_EXPORT CMARK_GFM_DEPRECATED

#endif
