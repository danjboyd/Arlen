#ifndef MO_COMPATIBILITY_H
#define MO_COMPATIBILITY_H

// Legacy MojoObjc class/type aliases.
#define MOApplication ALNApplication
#define MOConfig ALNConfig
#define MOHTTPServer ALNHTTPServer
#define MORequest ALNRequest
#define MOResponse ALNResponse
#define MOContext ALNContext
#define MOController ALNController
#define MORoute ALNRoute
#define MORouteMatch ALNRouteMatch
#define MORouter ALNRouter
#define MOView ALNView
#define MOLogger ALNLogger
#define MOMetricsRegistry ALNMetricsRegistry
#define MOAuth ALNAuth
#define MOPerf ALNPerf
#define MOPerfTrace ALNPerfTrace
#define MOPg ALNPg
#define MOPgConnection ALNPgConnection
#define MOGDL2Adapter ALNGDL2Adapter
#define MODisplayGroup ALNDisplayGroup
#define MOSQLBuilder ALNSQLBuilder
#define MOPageState ALNPageState
#define MOMigrationRunner ALNMigrationRunner
#define MOSessionMiddleware ALNSessionMiddleware
#define MOCSRFMiddleware ALNCSRFMiddleware
#define MORateLimitMiddleware ALNRateLimitMiddleware
#define MOSecurityHeadersMiddleware ALNSecurityHeadersMiddleware

// Legacy protocol and enum aliases.
#define MOMiddleware ALNMiddleware
#define MOLifecycleHook ALNLifecycleHook
#define MOPlugin ALNPlugin
#define MOTraceExporter ALNTraceExporter
#define MODatabaseAdapter ALNDatabaseAdapter
#define MODatabaseConnection ALNDatabaseConnection
#define MOLogLevel ALNLogLevel
#define MOLogLevelDebug ALNLogLevelDebug
#define MOLogLevelInfo ALNLogLevelInfo
#define MOLogLevelWarn ALNLogLevelWarn
#define MOLogLevelError ALNLogLevelError
#define MORouteKind ALNRouteKind
#define MORouteKindStatic ALNRouteKindStatic
#define MORouteKindParameterized ALNRouteKindParameterized
#define MORouteKindWildcard ALNRouteKindWildcard

// Legacy error domain aliases.
#define MORequestErrorDomain ALNRequestErrorDomain
#define MOResponseErrorDomain ALNResponseErrorDomain

// Legacy EOC aliases.
#define MOJOEOCRuntime ALNEOCRuntime
#define MOJOEOCTranspiler ALNEOCTranspiler
#define MOJOEOCErrorDomain ALNEOCErrorDomain
#define MOJOEOCErrorLineKey ALNEOCErrorLineKey
#define MOJOEOCErrorColumnKey ALNEOCErrorColumnKey
#define MOJOEOCErrorPathKey ALNEOCErrorPathKey

typedef ALNEOCRenderFunction MOJOEOCRenderFunction;
typedef ALNEOCErrorCode MOJOEOCErrorCode;

#define MOJOEOCErrorTemplateNotFound ALNEOCErrorTemplateNotFound
#define MOJOEOCErrorTemplateExecutionFailed ALNEOCErrorTemplateExecutionFailed
#define MOJOEOCErrorTranspilerSyntax ALNEOCErrorTranspilerSyntax
#define MOJOEOCErrorFileIO ALNEOCErrorFileIO
#define MOJOEOCErrorInvalidArgument ALNEOCErrorInvalidArgument

#define MOJOEOCCanonicalTemplatePath ALNEOCCanonicalTemplatePath
#define MOJOEOCEscapeHTMLString ALNEOCEscapeHTMLString
#define MOJOEOCAppendEscaped ALNEOCAppendEscaped
#define MOJOEOCAppendRaw ALNEOCAppendRaw
#define MOJOEOCClearTemplateRegistry ALNEOCClearTemplateRegistry
#define MOJOEOCRegisterTemplate ALNEOCRegisterTemplate
#define MOJOEOCResolveTemplate ALNEOCResolveTemplate
#define MOJOEOCRenderTemplate ALNEOCRenderTemplate
#define MOJOEOCInclude ALNEOCInclude

#endif
