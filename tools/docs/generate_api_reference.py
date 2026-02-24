#!/usr/bin/env python3
"""Generate API reference markdown from Arlen public headers.

The generator reads the public umbrella headers (`Arlen.h` and `ArlenData.h`),
parses interfaces/protocols/properties/methods, and emits:

- docs/API_REFERENCE.md (index)
- docs/api/<Symbol>.md (per-symbol reference pages)
"""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple


INCLUDE_RE = re.compile(r'^\s*#import\s+"([^"]+)"\s*$')
SYMBOL_RE = re.compile(r'^\s*@(interface|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)\b')
PROPERTY_START_RE = re.compile(r'^\s*@property\b')
PROPERTY_RE = re.compile(r'^\s*@property\s*\(([^)]*)\)\s*(.+?)\s*;\s*$')
METHOD_START_RE = re.compile(r'^\s*[-+]\s*\(')
METHOD_RE = re.compile(r'^\s*([-+])\s*\(([^)]+)\)\s*(.+);\s*$')


@dataclass
class PropertyDoc:
    name: str
    type_name: str
    attributes: str
    raw_signature: str


@dataclass
class MethodDoc:
    scope: str  # '+' or '-'
    return_type: str
    signature: str
    selector: str


@dataclass
class SymbolDoc:
    name: str
    kind: str  # interface/protocol
    header: str
    properties: List[PropertyDoc] = field(default_factory=list)
    methods: List[MethodDoc] = field(default_factory=list)


VERB_PURPOSES = {
    "init": "Initialize a new instance configured for this API surface.",
    "shared": "Return the shared singleton instance.",
    "load": "Load and normalize configuration data.",
    "register": "Register this component so it participates in runtime behavior.",
    "add": "Add this item to the current runtime collection.",
    "set": "Set or override the current value for this concern.",
    "begin": "Begin a scoped operation that must be closed by a matching end call.",
    "end": "Close a previously started scoped operation.",
    "mount": "Mount or attach this component into the active application tree.",
    "configure": "Configure behavior for an already-registered runtime element.",
    "dispatch": "Dispatch the current request through routing and controller handling.",
    "write": "Write a serialized representation to disk.",
    "start": "Start runtime lifecycle processing and readiness checks.",
    "shutdown": "Shut down runtime processing and release resources.",
    "render": "Render a response payload for the current request context.",
    "redirect": "Send a redirect response.",
    "accept": "Accept and handle an upgraded realtime connection.",
    "execute": "Execute the operation against the active backend.",
    "with": "Run a scoped callback with managed lifecycle semantics.",
    "match": "Match input against the configured pattern set.",
    "verify": "Verify and validate the input against configured rules.",
    "authenticate": "Authenticate request credentials and populate auth context.",
    "apply": "Apply this helper to context and update response state.",
    "localized": "Resolve a localized string with fallback behavior.",
    "enqueue": "Enqueue a background job for async processing.",
    "dequeue": "Lease the next due job from the adapter.",
    "acknowledge": "Acknowledge successful handling of a leased job.",
    "retry": "Reschedule a failed job with backoff semantics.",
    "subscribe": "Register a subscriber for channel messages.",
    "unsubscribe": "Remove an existing subscription.",
    "publish": "Publish a message to channel subscribers.",
    "snapshot": "Return a point-in-time snapshot of current runtime state.",
    "reset": "Reset state to a clean baseline for testing or maintenance.",
    "build": "Build a deterministic compiled representation.",
    "normalize": "Normalize values into stable internal structure.",
}

EXACT_PURPOSES = {
    "processContext:error:": "Run middleware pre-processing for the current request context.",
    "didProcessContext:": "Run middleware post-processing after controller dispatch completes.",
    "applicationWillStart:error:": "Lifecycle hook called before application startup completes.",
    "applicationDidStart:": "Lifecycle hook called after startup succeeds.",
    "applicationWillStop:": "Lifecycle hook called before shutdown begins.",
    "applicationDidStop:": "Lifecycle hook called after shutdown finishes.",
    "pluginName": "Return the plugin's stable registration name.",
    "registerWithApplication:error:": "Register plugin behavior and routes on an application instance.",
    "middlewaresForApplication:": "Return middleware instances provided by this plugin.",
    "exportTrace:request:response:routeName:controllerName:actionName:": "Export a completed request trace event.",
    "jsonWritingOptions": "Return JSON serializer options used by controller helpers.",
    "session": "Return the mutable session map for the current request.",
    "markSessionDirty": "Mark session state as modified so middleware persists it.",
    "csrfToken": "Return the CSRF token associated with the current request/session.",
    "allParams": "Return merged request parameters (route, query, and body).",
    "params": "Return merged request parameters (route, query, and body).",
    "paramValueForName:": "Return a raw parameter value by key.",
    "stringParamForName:": "Return a parameter coerced to string when possible.",
    "queryValueForName:": "Return a query-string parameter by key.",
    "headerValueForName:": "Return a request header value by key.",
    "queryIntegerForName:": "Return a query parameter parsed as an integer.",
    "queryBooleanForName:": "Return a query parameter parsed as a boolean.",
    "headerIntegerForName:": "Return a header parsed as an integer.",
    "headerBooleanForName:": "Return a header parsed as a boolean.",
    "requireStringParam:value:": "Require a string parameter and copy it to the out-parameter.",
    "requireIntegerParam:value:": "Require an integer parameter and copy it to the out-parameter.",
    "requestFormat": "Resolve request format from explicit route format or Accept negotiation.",
    "wantsJSON": "Return whether request negotiation prefers JSON.",
    "addValidationErrorForField:code:message:": "Append a structured validation error to context state.",
    "validationErrors": "Return collected validation errors for this request.",
    "validatedParams": "Return schema-validated and transformed parameter values.",
    "validatedValueForName:": "Return one validated parameter value by field key.",
    "authClaims": "Return authenticated JWT/API claims for the current request.",
    "authScopes": "Return authenticated scopes for authorization checks.",
    "authRoles": "Return authenticated roles for authorization checks.",
    "authSubject": "Return the authenticated subject identifier (`sub`).",
    "jobsAdapter": "Return the configured jobs adapter for the current application/context.",
    "cacheAdapter": "Return the configured cache adapter for the current application/context.",
    "localizationAdapter": "Return the configured localization adapter for the current application/context.",
    "mailAdapter": "Return the configured mail adapter for the current application/context.",
    "attachmentAdapter": "Return the configured attachment adapter for the current application/context.",
    "pageStateForKey:": "Return a page-state helper bound to one logical page namespace.",
    "renderTemplate:context:error:": "Render a template with explicit local context.",
    "renderTemplate:context:layout:error:": "Render a template with explicit context and layout.",
    "renderTemplate:error:": "Render a template using current stash/context defaults.",
    "renderTemplate:layout:error:": "Render a template with an explicit layout and default context.",
    "stashValue:forKey:": "Set one value in controller stash for template rendering.",
    "stashValues:": "Merge multiple values into controller stash.",
    "stashValueForKey:": "Read one value from controller stash.",
    "renderNegotiatedTemplate:context:jsonObject:error:": "Render template or JSON based on negotiated request format.",
    "renderJSON:error:": "Serialize an object to JSON and set response body/content type.",
    "renderText:": "Set plain-text response body.",
    "renderSSEEvents:": "Render server-sent event frames.",
    "acceptWebSocketEcho": "Upgrade and run a websocket echo session.",
    "acceptWebSocketChannel:": "Upgrade and subscribe websocket connection to a realtime channel.",
    "redirectTo:status:": "Set redirect status and `Location` header.",
    "setStatus:": "Set HTTP response status code.",
    "hasRendered": "Return whether the controller already produced a response.",
    "renderValidationErrors": "Render current validation errors using normalized error envelope.",
    "normalizedEnvelopeWithData:meta:": "Build normalized response envelope `{data, meta}` structure.",
    "renderJSONEnvelopeWithData:meta:error:": "Serialize and render normalized `{data, meta}` JSON envelope.",
    "openAPISpecification": "Build OpenAPI document from registered routes and schema metadata.",
    "writeOpenAPISpecToPath:pretty:error:": "Write OpenAPI document to disk for tooling/publishing.",
    "routeTable": "Return route metadata table for diagnostics and route inspection.",
    "routeNamed:": "Return one route by registered name.",
    "allRoutes": "Return all registered route objects in registration order.",
    "matchMethod:path:": "Match request method/path against registered routes.",
    "matchMethod:path:format:": "Match request method/path/format against registered routes.",
    "matchPath:": "Match one path against this route pattern and return extracted params.",
    "matchesFormat:": "Return whether route allows this negotiated/requested format.",
    "dictionaryRepresentation": "Return this object as a stable dictionary payload.",
    "executeQuery:parameters:error:": "Execute SQL query and return zero or more result rows.",
    "executeQueryOne:parameters:error:": "Execute SQL query and return at most one row.",
    "executeCommand:parameters:error:": "Execute SQL command and return affected-row count.",
    "withTransactionUsingBlock:error:": "Run a callback inside a managed transaction.",
    "resolveTargetForOperationClass:routingContext:error:": "Resolve database target for read/write operation class.",
    "executeQuery:parameters:routingContext:error:": "Execute routed read query using router target policy.",
    "executeCommand:parameters:routingContext:error:": "Execute routed write command using router target policy.",
    "withTransactionUsingBlock:routingContext:error:": "Run a routed transaction callback on selected write target.",
    "setFilterValue:forField:": "Set or replace one display-group filter criterion.",
    "removeFilterForField:": "Remove one display-group filter criterion.",
    "clearFilters": "Clear all active display-group filters.",
    "addSortField:descending:": "Append one sort descriptor to display-group query order.",
    "clearSortOrder": "Clear all configured display-group sort descriptors.",
    "fetch:": "Execute display-group query using current filters/sort descriptors.",
    "migrationFilesAtPath:error:": "List migration files from migration directory in deterministic order.",
    "pendingMigrationFilesAtPath:database:databaseTarget:error:": "Return migrations not yet applied for the selected database target.",
    "pendingMigrationFilesAtPath:database:error:": "Return pending migrations for the default database target.",
    "applyMigrationsAtPath:database:databaseTarget:dryRun:appliedFiles:error:": "Apply pending migrations for one database target with optional dry-run.",
    "applyMigrationsAtPath:database:dryRun:appliedFiles:error:": "Apply pending migrations for default target with optional dry-run.",
    "versionForMigrationFile:": "Extract migration version prefix from migration filename.",
    "prepareStatementNamed:sql:parameterCount:error:": "Prepare a named SQL statement on the active connection.",
    "executePreparedQueryNamed:parameters:error:": "Execute a prepared query statement by name.",
    "executePreparedCommandNamed:parameters:error:": "Execute a prepared command statement by name.",
    "beginTransaction:": "Begin SQL transaction on current connection.",
    "commitTransaction:": "Commit SQL transaction on current connection.",
    "rollbackTransaction:": "Roll back SQL transaction on current connection.",
    "executeBuilderQuery:error:": "Compile and execute an `ALNSQLBuilder` query.",
    "executeBuilderCommand:error:": "Compile and execute an `ALNSQLBuilder` command.",
    "resetExecutionCaches": "Reset prepared-statement and builder compilation caches.",
    "selectFrom:columns:": "Create a `SELECT` SQL builder for table and optional column list.",
    "selectFrom:alias:columns:": "Create a `SELECT` SQL builder with explicit table alias.",
    "insertInto:values:": "Create an `INSERT` SQL builder with field/value map.",
    "updateTable:values:": "Create an `UPDATE` SQL builder with field/value map.",
    "deleteFrom:": "Create a `DELETE` SQL builder for the target table.",
    "fromAlias:": "Set or override the primary table alias for the query.",
    "build:": "Build SQL and parameter payload as a dictionary structure.",
    "buildSQL:": "Compile and return SQL text for this builder.",
    "buildParameters:": "Compile and return ordered SQL parameters for this builder.",
    "onConflictDoNothing": "Configure PostgreSQL `ON CONFLICT DO NOTHING` behavior.",
    "onConflictColumns:doUpdateSetFields:": "Configure PostgreSQL upsert conflict update using field names.",
    "onConflictColumns:doUpdateAssignments:": "Configure PostgreSQL upsert conflict update using explicit assignments.",
    "onConflictDoUpdateWhereExpression:parameters:": "Configure conditional `DO UPDATE ... WHERE ...` clause for upsert.",
    "setHeader:value:": "Set/replace one response header.",
    "headerForName:": "Return response header value by name.",
    "appendData:": "Append raw bytes to response body buffer.",
    "appendText:": "Append UTF-8 text to response body buffer.",
    "setTextBody:": "Replace response body with UTF-8 text and text content type.",
    "setJSONBody:options:error:": "Serialize object as JSON response body using requested options.",
    "serializedData": "Return full HTTP response bytes ready for socket write.",
    "printRoutesToFile:": "Print route table to a stream for diagnostics.",
    "runWithHost:portOverride:once:": "Run HTTP server loop with optional host/port overrides.",
    "requestStop": "Request graceful server shutdown.",
    "requestFromRawData:error:": "Parse an HTTP request object from raw wire bytes.",
    "normalizeTemplateLogicalPath:": "Normalize template path to deterministic logical path key.",
    "symbolNameForLogicalPath:": "Convert template logical path to deterministic ObjC symbol name.",
    "logicalPathForTemplatePath:templateRoot:": "Resolve logical template path from file path and template root.",
    "lintDiagnosticsForTemplateString:logicalPath:error:": "Run template lint pass and return diagnostics payloads.",
    "transpiledSourceForTemplateString:logicalPath:error:": "Transpile template source text into Objective-C runtime source.",
    "transpileTemplateAtPath:templateRoot:outputPath:error:": "Transpile one template file to generated Objective-C file.",
    "bearerTokenFromAuthorizationHeader:error:": "Extract bearer token from an Authorization header value.",
    "verifyJWTToken:secret:issuer:audience:error:": "Verify JWT signature and optional issuer/audience constraints.",
    "authenticateContext:authConfig:error:": "Authenticate request and populate auth claims/scopes/roles on context.",
    "applyClaims:toContext:": "Copy verified auth claims onto request context.",
    "scopesFromClaims:": "Extract scope list from claims payload.",
    "rolesFromClaims:": "Extract role list from claims payload.",
    "context:hasRequiredScopes:": "Return whether context claims satisfy required scope set.",
    "context:hasRequiredRoles:": "Return whether context claims satisfy required role set.",
    "logLevel:message:fields:": "Emit one structured log entry at the requested level.",
    "debug:fields:": "Emit debug-level structured log entry.",
    "info:fields:": "Emit info-level structured log entry.",
    "warn:fields:": "Emit warn-level structured log entry.",
    "error:fields:": "Emit error-level structured log entry.",
    "incrementCounter:": "Increment counter metric by `1`.",
    "incrementCounter:by:": "Increment counter metric by explicit amount.",
    "setGauge:value:": "Set gauge metric to an absolute value.",
    "addGauge:delta:": "Add delta to existing gauge metric value.",
    "recordTiming:milliseconds:": "Record timing metric sample in milliseconds.",
    "snapshot": "Return in-memory metrics snapshot for programmatic inspection.",
    "prometheusText": "Render metrics snapshot in Prometheus exposition text format.",
    "startStage:": "Start timing for one named perf stage.",
    "endStage:": "End timing for one named perf stage.",
    "setStage:durationMilliseconds:": "Set an explicit duration for one perf stage.",
    "durationMillisecondsForStage:": "Return recorded duration for one perf stage.",
    "receiveRealtimeMessage:onChannel:": "Realtime subscriber callback for one published channel message.",
    "sharedHub": "Return process-wide `ALNRealtimeHub` singleton.",
    "subscribeChannel:subscriber:": "Subscribe one subscriber to a realtime channel.",
    "unsubscribe:": "Unsubscribe a prior realtime subscription.",
    "publishMessage:onChannel:": "Publish message to all subscribers for a channel.",
    "subscriberCountForChannel:": "Return current subscriber count for a channel.",
    "enqueueJobNamed:payload:options:error:": "Enqueue a background job with optional scheduling/retry metadata.",
    "dequeueDueJobAt:error:": "Lease the next due background job at a timestamp.",
    "acknowledgeJobID:error:": "Acknowledge completion for a previously leased job.",
    "retryJob:delaySeconds:error:": "Requeue a leased job with retry delay.",
    "pendingJobsSnapshot": "Return snapshot of currently pending jobs.",
    "deadLetterJobsSnapshot": "Return snapshot of dead-lettered jobs.",
    "runDueJobsAt:runtime:error:": "Lease and execute due jobs through a worker runtime callback.",
    "handleJob:error:": "Handle one leased job and return worker disposition (`ack`, `retry`, or `discard`).",
    "setObject:forKey:ttlSeconds:error:": "Set cache value with optional TTL for one key.",
    "objectForKey:atTime:error:": "Read cache value for one key using a point-in-time clock.",
    "removeObjectForKey:error:": "Remove one cache entry by key.",
    "clearWithError:": "Clear all entries for this adapter/store.",
    "registerTranslations:locale:error:": "Register localized string table for one locale.",
    "localizedStringForKey:locale:fallbackLocale:defaultValue:arguments:": "Resolve localized string with fallback/default and interpolation args.",
    "availableLocales": "Return locales currently available in this localization adapter.",
    "deliverMessage:error:": "Deliver one outbound mail message.",
    "deliveriesSnapshot": "Return snapshot of delivered outbound messages.",
    "saveAttachmentNamed:contentType:data:metadata:error:": "Save attachment payload and return generated attachment identifier.",
    "attachmentDataForID:metadata:error:": "Load attachment bytes and optional metadata for an attachment ID.",
    "attachmentMetadataForID:error:": "Return metadata only for an attachment ID.",
    "deleteAttachmentID:error:": "Delete one attachment by ID.",
    "listAttachmentMetadata": "Return metadata list for all stored attachments.",
    "allValues": "Return all values currently stored in this state container.",
    "valueForKey:": "Return one value by key from the current state container.",
    "setValue:forKey:": "Set one value by key in the current state container.",
    "clear": "Clear all values in this state container.",
    "close": "Close the active resource/connection and release underlying handles.",
    "capabilityMetadata": "Return machine-readable capability metadata for this adapter/runtime.",
    "isNativeGDL2RuntimeAvailable": "Return whether native GDL2 runtime support is available.",
    "acquireConnection:": "Acquire a pooled database connection instance.",
    "releaseConnection:": "Release a pooled database connection back to the adapter.",
    "acquireAdapterConnection:": "Acquire a protocol-typed adapter connection instance.",
    "releaseAdapterConnection:": "Release a protocol-typed adapter connection instance.",
}

EXACT_USAGE = {
    "processContext:error:": "Return `NO` to short-circuit request handling. Populate `error` for deterministic middleware failures.",
    "applicationWillStart:error:": "Register hooks before `startWithError:`; returning `NO` aborts startup.",
    "registerWithApplication:error:": "Call during app bootstrap before server start. Return `NO` and fill `error` on invalid plugin configuration.",
    "renderValidationErrors": "Use after accumulating validation errors; this standardizes envelope shape and status behavior.",
    "renderSSEEvents:": "Set SSE-appropriate headers before calling when streaming manually; events should already be normalized dictionaries.",
    "acceptWebSocketEcho": "Use from websocket-only routes. This method writes the websocket response directly.",
    "acceptWebSocketChannel:": "Pair with `ALNRealtimeHub` publish paths; channel value should be stable and tenant-safe.",
    "startWithError:": "Call once before accepting traffic. On failure, inspect startup compile/security diagnostics in `error`.",
    "shutdown": "Call during graceful stop to execute lifecycle hooks and flush runtime state.",
    "beginRouteGroupWithPrefix:guardAction:formats:": "Call once for a grouped route section, then register routes, then call `endRouteGroup`.",
    "endRouteGroup": "Always pair with `beginRouteGroupWithPrefix:guardAction:formats:` to avoid leaking group settings.",
    "mountApplication:atPrefix:": "Mount child app at a fixed URL prefix before startup.",
    "mountStaticDirectory:atPrefix:allowExtensions:": "Prefer explicit extension allowlists in production to reduce accidental file exposure.",
    "configureRouteNamed:requestSchema:responseSchema:summary:operationID:tags:requiredScopes:requiredRoles:includeInOpenAPI:error:": "Call after route registration and before startup so compile-on-start checks can validate schemas/scopes/roles.",
    "dispatchRequest:": "Used by HTTP server internals; app code typically calls higher-level server APIs.",
    "setJSONBody:options:error:": "Use options from `ALNController +jsonWritingOptions` unless you need custom formatting.",
    "runWithHost:portOverride:once:": "Use `once:YES` for single-request smoke tests; use `once:NO` for normal long-running server mode.",
    "requestFromRawData:error:": "Useful for parser tests and custom socket harnesses; validate that method/path/headers were parsed as expected.",
    "withTransactionUsingBlock:error:": "Return `YES` from block to commit; return `NO` or set `error` to trigger rollback.",
    "withTransaction:error:": "Return `YES` from block to commit; return `NO` or set `error` to trigger rollback.",
    "withTransactionUsingBlock:routingContext:error:": "Provide routing context when read/write routing policy depends on tenant/request hints.",
    "build:": "Use when you need both SQL string and ordered parameter array in one call.",
    "buildSQL:": "Pair with `buildParameters:` when executing against custom adapters.",
    "buildParameters:": "Call after full query composition; parameter order matches placeholders in `buildSQL:`.",
    "renderNegotiatedTemplate:context:jsonObject:error:": "Provide both template and JSON object so the controller can switch by `Accept` header automatically.",
    "queryIntegerForName:": "Prefer this over manual parsing to avoid repeated validation boilerplate.",
    "queryBooleanForName:": "Accepts common boolean forms; check for `nil` when parameter is absent or invalid.",
    "headerIntegerForName:": "Use for numeric custom headers; returns `nil` when parsing fails.",
    "headerBooleanForName:": "Use for feature-flag style headers; returns `nil` when parsing fails.",
    "requireStringParam:value:": "If this returns `NO`, add/return validation errors immediately rather than continuing handler logic.",
    "requireIntegerParam:value:": "If this returns `NO`, add/return validation errors immediately rather than continuing handler logic.",
    "applyETagAndReturnNotModifiedIfMatch:": "Call before expensive render/DB work; if it returns `YES`, exit action early.",
    "authenticateContext:authConfig:error:": "Call from auth middleware/guards before role/scope checks.",
    "enqueueJobNamed:payload:options:error:": "Pass idempotency/retry metadata in `options` when you need deterministic re-enqueue behavior.",
    "dequeueDueJobAt:error:": "Workers should poll with clock source used for scheduling and retry calculations.",
    "retryJob:delaySeconds:error:": "Use bounded retry delays; combine with dead-letter handling after max attempts.",
    "runDueJobsAt:runtime:error:": "Use small run limits per worker tick to keep throughput predictable.",
    "deliverMessage:error:": "Prefer immutable message objects and include metadata for downstream auditing.",
    "saveAttachmentNamed:contentType:data:metadata:error:": "Store business identifiers in `metadata` rather than encoding them into the attachment name.",
}


def normalize_whitespace(text: str) -> str:
    return " ".join(text.strip().split())


def parse_selector(method_tail: str) -> str:
    labels = re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*:', method_tail)
    if labels:
        return "".join(f"{label}:" for label in labels)
    # no-argument selector
    token = method_tail.split()[0]
    return token.rstrip(";")


def first_selector_token(selector: str) -> str:
    token = selector.rstrip(":")
    if ":" in token:
        token = token.split(":", 1)[0]
    return token


def camel_words(token: str) -> List[str]:
    token = token.replace("_", " ")
    parts = re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?![a-z])|\d+", token)
    return [p.lower() for p in parts if p]


def humanize_selector(selector: str) -> str:
    token = first_selector_token(selector)
    words = camel_words(token)
    if not words:
        return selector
    return " ".join(words)


def fallback_symbol_summary(symbol: SymbolDoc) -> str:
    header = symbol.header
    name = symbol.name

    if symbol.kind == "protocol":
        if name.endswith("Adapter"):
            return f"Protocol contract for `{name}` adapter implementations."
        if name.endswith("Hook"):
            return f"Lifecycle hook protocol for `{name}` implementations."
        if name.endswith("Runtime"):
            return f"Protocol contract for `{name}` runtime integrations."
        return f"Protocol contract exported as part of the `{name}` API surface."

    if name.startswith("ALNInMemory"):
        return "In-memory adapter implementation useful for development and tests."
    if name.startswith("ALNFile"):
        return "Filesystem-backed adapter implementation for durable local environments."
    if name.startswith("ALNRetrying"):
        return "Retry-wrapper adapter implementation with deterministic retry semantics."
    if name.endswith("Adapter"):
        return f"Concrete adapter implementation for `{name}`."
    if name.endswith("Middleware"):
        return "Built-in middleware implementation ready to register on an application."
    if name.endswith("Worker") or name.endswith("WorkerRunSummary"):
        return "Background job worker runtime helper API."

    if "/Core/" in header:
        return "Core runtime API surface for application lifecycle, config, and contracts."
    if "/HTTP/" in header:
        return "HTTP request/response and server runtime primitives."
    if "/MVC/Controller/" in header:
        return "Controller and request-context APIs used during request handling."
    if "/MVC/Routing/" in header:
        return "Routing primitives for route registration and path matching."
    if "/MVC/Template/" in header:
        return "EOC template transpilation APIs for compile-time and diagnostics workflows."
    if "/MVC/View/" in header:
        return "View rendering APIs for template execution."
    if "/MVC/Middleware/" in header:
        return "Built-in middleware construction APIs."
    if "/Data/" in header:
        return "Data-layer APIs for SQL composition, adapters, and migration/runtime operations."
    if "/Support/" in header:
        return "Support services for auth, metrics, logging, performance, realtime, and adapters."
    return "Public API surface exported by Arlen."


def fallback_property_purpose(symbol: SymbolDoc, prop: PropertyDoc) -> str:
    name = prop.name
    if name.endswith("Adapter"):
        return "Adapter used by this runtime for the corresponding service concern."
    if name in {"router", "logger", "metrics", "config", "environment", "middlewares", "plugins", "lifecycleHooks", "staticMounts"}:
        return f"Runtime `{name}` component configured for this application instance."
    if name.startswith("cluster"):
        return "Cluster/runtime metadata exposed for diagnostics and routing behavior."
    if name in {"clusterName", "clusterNodeID"}:
        return "Cluster identity metadata attached to readiness/response diagnostics."
    if name in {"started", "isStarted"}:
        return "Lifecycle flag that indicates whether startup has completed."
    if name == "traceExporter":
        return "Optional request-trace exporter invoked after route dispatch."
    return f"Public `{name}` property available on `{symbol.name}`."


def fallback_purpose(symbol: SymbolDoc, method: MethodDoc) -> str:
    selector = method.selector
    token = first_selector_token(selector)
    lowered = token.lower()

    if selector in EXACT_PURPOSES:
        return EXACT_PURPOSES[selector]

    if symbol.name in {"ALNSQLBuilder", "ALNPostgresSQLBuilder"}:
        if token.startswith("where"):
            return "Add a `WHERE` predicate to the SQL builder."
        if token.startswith("having"):
            return "Add a `HAVING` predicate to the SQL builder."
        if token.startswith(("join", "leftJoin", "rightJoin", "fullJoin", "crossJoin")):
            return "Add a SQL join clause to the builder."
        if token.startswith("groupBy"):
            return "Add `GROUP BY` fields to the SQL builder."
        if token.startswith("orderBy"):
            return "Add `ORDER BY` expression(s) to the SQL builder."
        if token.startswith(("withCTE", "withRecursiveCTE")):
            return "Add a common table expression (`WITH`) to the SQL builder."
        if token.startswith(("union", "intersect", "except")):
            return "Combine this query with another set-operation query."
        if token in {"limit", "offset"}:
            return "Set pagination clause values for the SQL builder."
        if token in {"forUpdate", "forUpdateOfTables", "skipLocked"}:
            return "Configure row-locking clause behavior for the SQL builder."
        if token.startswith("returning"):
            return "Configure `RETURNING` columns for insert/update/delete statements."
        if token.startswith("selectExpression"):
            return "Append a raw or parameterized select expression."
        if token.startswith("windowNamed"):
            return "Register a named SQL window definition."

    if lowered in {"pluginname", "adaptername"}:
        return "Return the stable identifier for this plugin/adapter implementation."
    if lowered in {"routeTable".lower(), "allRoutes".lower(), "openAPISpecification".lower()}:
        return "Return a deterministic runtime snapshot suitable for diagnostics or tooling."
    if lowered.startswith("init"):
        return f"Initialize and return a new `{symbol.name}` instance."
    if lowered.startswith("is") or lowered.startswith("has"):
        return f"Return whether `{symbol.name}` currently satisfies this condition."
    if lowered.startswith("can"):
        return f"Return whether `{symbol.name}` can perform this operation right now."
    if lowered.startswith("executequery"):
        return "Execute a read/query operation and return row dictionaries."
    if lowered.startswith("executecommand"):
        return "Execute a write/command operation and return affected row count."

    for prefix, purpose in VERB_PURPOSES.items():
        if lowered.startswith(prefix):
            return purpose

    return f"Perform `{humanize_selector(selector)}` for `{symbol.name}`."


def fallback_usage(symbol: SymbolDoc, method: MethodDoc) -> str:
    selector = method.selector
    token = first_selector_token(selector).lower()
    return_type = method.return_type.strip()
    tips: List[str] = []

    if selector in EXACT_USAGE:
        return EXACT_USAGE[selector]

    if method.scope == "+":
        tips.append("Call on the class type, not on an instance.")

    if token.startswith("init"):
        tips.append("Use as `[[Class alloc] init...]`; treat `nil` as initialization failure.")

    if "error:" in selector:
        if "BOOL" in method.return_type:
            tips.append("Check the returned `BOOL`; on `NO`, inspect the `error` out-parameter.")
        elif "nullable" in method.return_type or "instancetype" in method.return_type:
            tips.append("Pass `NSError **` and treat a `nil` result as failure.")
        else:
            tips.append("Pass `NSError **` when you need detailed failure diagnostics.")

    if token.startswith("render"):
        tips.append("Call from controller action paths after selecting response status/headers.")
    if "UsingBlock:" in selector or "WithBlock:" in selector:
        tips.append("Keep the block side-effect scoped; Arlen manages setup/teardown around it.")
    if token.startswith("begin"):
        tips.append("Always pair with the corresponding `end...` call to avoid leaked state.")
    if token.startswith("set") and return_type == "void":
        tips.append("Call before downstream behavior that depends on this updated value.")
    if token.startswith(("add", "register")):
        tips.append("Call during bootstrap/setup before this behavior is exercised.")
    if "instancetype" in return_type:
        tips.append("This method is chainable; continue composing and call `build`/`buildSQL` to finalize.")

    if not tips:
        if "BOOL" in return_type:
            tips.append("Check the return value to confirm the operation succeeded.")
        elif return_type == "void":
            tips.append("Call for side effects; this method does not return a value.")
        elif ":" not in selector:
            tips.append("Read this value when you need current runtime/request state.")
        elif "NSArray" in return_type or "NSDictionary" in return_type:
            tips.append("Treat returned collection values as snapshots unless the API documents mutability.")
        else:
            tips.append("Capture the returned value and propagate errors/validation as needed.")

    return " ".join(tips)


def parse_public_header_list(repo_root: Path) -> List[Path]:
    umbrellas = [
        repo_root / "src" / "Arlen" / "Arlen.h",
        repo_root / "src" / "ArlenData" / "ArlenData.h",
    ]

    resolved: List[Path] = []
    seen: set[Path] = set()

    for umbrella in umbrellas:
        if not umbrella.exists():
            continue
        for line in umbrella.read_text(encoding="utf-8").splitlines():
            match = INCLUDE_RE.match(line)
            if not match:
                continue
            inc = match.group(1)
            if inc.startswith("Arlen/"):
                candidate = repo_root / "src" / inc
            else:
                candidate = repo_root / "src" / "Arlen" / inc
            candidate = candidate.resolve()
            if candidate.exists() and candidate not in seen:
                seen.add(candidate)
                resolved.append(candidate)

    return sorted(resolved)


def read_statement(lines: List[str], start_index: int) -> Tuple[str, int]:
    statement = normalize_whitespace(lines[start_index])
    i = start_index
    while not statement.endswith(";") and i + 1 < len(lines):
        i += 1
        statement = normalize_whitespace(statement + " " + lines[i])
    return statement, i


def parse_header(path: Path, repo_root: Path) -> List[SymbolDoc]:
    lines = path.read_text(encoding="utf-8").splitlines()
    symbols: List[SymbolDoc] = []
    current: Optional[SymbolDoc] = None

    i = 0
    while i < len(lines):
        line = lines[i]

        symbol_match = SYMBOL_RE.match(line)
        if symbol_match:
            kind = symbol_match.group(1)
            name = symbol_match.group(2)
            current = SymbolDoc(
                name=name,
                kind=kind,
                header=str(path.relative_to(repo_root)).replace(os.sep, "/"),
            )
            symbols.append(current)
            i += 1
            continue

        if current is None:
            i += 1
            continue

        if line.strip().startswith("@end"):
            current = None
            i += 1
            continue

        if PROPERTY_START_RE.match(line):
            statement, end_index = read_statement(lines, i)
            prop_match = PROPERTY_RE.match(statement)
            if prop_match:
                attrs = normalize_whitespace(prop_match.group(1))
                rest = normalize_whitespace(prop_match.group(2))
                name_match = re.match(r"(.+?)\s*(\*?)\s*([A-Za-z_][A-Za-z0-9_]*)$", rest)
                if name_match:
                    type_name = name_match.group(1).strip()
                    if name_match.group(2):
                        type_name = f"{type_name} *"
                    name = name_match.group(3).strip()
                    current.properties.append(
                        PropertyDoc(
                            name=name,
                            type_name=type_name,
                            attributes=attrs,
                            raw_signature=statement,
                        )
                    )
            i = end_index + 1
            continue

        if METHOD_START_RE.match(line):
            statement, end_index = read_statement(lines, i)
            m = METHOD_RE.match(statement)
            if m:
                scope = m.group(1)
                return_type = normalize_whitespace(m.group(2))
                tail = normalize_whitespace(m.group(3))
                selector = parse_selector(tail)
                current.methods.append(
                    MethodDoc(
                        scope=scope,
                        return_type=return_type,
                        signature=statement,
                        selector=selector,
                    )
                )
            i = end_index + 1
            continue

        i += 1

    return symbols


def load_metadata(path: Path) -> Dict[str, Dict[str, Dict[str, str]]]:
    if not path.exists():
        return {"symbols": {}, "methods": {}, "properties": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        "symbols": data.get("symbols", {}),
        "methods": data.get("methods", {}),
        "properties": data.get("properties", {}),
    }


def symbol_section_for_header(header: str) -> str:
    if "/Core/" in header:
        return "Core"
    if "/HTTP/" in header:
        return "HTTP"
    if "/MVC/Controller/" in header:
        return "MVC Controllers"
    if "/MVC/Routing/" in header:
        return "MVC Routing"
    if "/MVC/Template/" in header:
        return "Template"
    if "/MVC/View/" in header:
        return "View"
    if "/MVC/Middleware/" in header:
        return "Middleware"
    if "/Data/" in header:
        return "Data"
    if "/Support/" in header:
        return "Support"
    return "Other"


def write_symbol_page(symbol: SymbolDoc, output_dir: Path, metadata: Dict[str, Dict[str, Dict[str, str]]]) -> None:
    symbol_meta = metadata["symbols"].get(symbol.name, {})
    summary = symbol_meta.get("summary", fallback_symbol_summary(symbol))
    usage_example = symbol_meta.get("usage_example")

    lines: List[str] = []
    lines.append(f"# {symbol.name}")
    lines.append("")
    lines.append(f"- Kind: `{symbol.kind}`")
    lines.append(f"- Header: `{symbol.header}`")
    lines.append("")
    lines.append(summary)

    if usage_example:
        lines.append("")
        lines.append("## Typical Usage")
        lines.append("")
        lines.append("```objc")
        lines.append(usage_example.rstrip())
        lines.append("```")

    if symbol.properties:
        lines.append("")
        lines.append("## Properties")
        lines.append("")
        lines.append("| Property | Type | Attributes | Purpose |")
        lines.append("| --- | --- | --- | --- |")
        for prop in symbol.properties:
            key = f"{symbol.name}|{prop.name}"
            prop_meta = metadata["properties"].get(key, {})
            purpose = prop_meta.get("purpose", fallback_property_purpose(symbol, prop))
            lines.append(
                f"| `{prop.name}` | `{prop.type_name}` | `{prop.attributes}` | {purpose} |"
            )

    if symbol.methods:
        lines.append("")
        lines.append("## Methods")
        lines.append("")
        lines.append("| Selector | Signature | Purpose | How to use |")
        lines.append("| --- | --- | --- | --- |")
        for method in symbol.methods:
            key = f"{symbol.name}|{method.selector}"
            method_meta = metadata["methods"].get(key, {})
            purpose = method_meta.get("purpose", fallback_purpose(symbol, method))
            usage = method_meta.get("usage", fallback_usage(symbol, method))
            signature = method.signature.replace("|", "\\|")
            lines.append(
                f"| `{method.selector}` | `{signature}` | {purpose} | {usage} |"
            )

    destination = output_dir / f"{symbol.name}.md"
    destination.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_index(
    symbols: List[SymbolDoc],
    index_path: Path,
    metadata: Dict[str, Dict[str, Dict[str, str]]],
    public_headers: List[Path],
    repo_root: Path,
) -> None:
    sections: Dict[str, List[SymbolDoc]] = {}
    for symbol in symbols:
        section = symbol_section_for_header(symbol.header)
        sections.setdefault(section, []).append(symbol)

    method_count = sum(len(symbol.methods) for symbol in symbols)
    property_count = sum(len(symbol.properties) for symbol in symbols)

    lines: List[str] = []
    lines.append("# API Reference")
    lines.append("")
    lines.append(
        "This reference is generated from public headers exported by "
        "`src/Arlen/Arlen.h` and `src/ArlenData/ArlenData.h`."
    )
    lines.append("")
    lines.append("Regenerate after public header changes:")
    lines.append("")
    lines.append("```bash")
    lines.append("python3 tools/docs/generate_api_reference.py")
    lines.append("```")
    lines.append("")
    lines.append("- Generated from source headers and metadata (deterministic output)")
    lines.append(f"- Public headers: `{len(public_headers)}`")
    lines.append(f"- Symbols: `{len(symbols)}`")
    lines.append(f"- Public methods: `{method_count}`")
    lines.append(f"- Public properties: `{property_count}`")
    lines.append("")
    lines.append("## API Surface Boundary")
    lines.append("")
    lines.append("- `src/Arlen/Arlen.h` is the primary framework umbrella header.")
    lines.append("- `src/ArlenData/ArlenData.h` is the standalone data-layer umbrella header.")
    lines.append("")
    lines.append("## Symbol Index")
    lines.append("")

    section_order = [
        "Core",
        "HTTP",
        "MVC Controllers",
        "MVC Routing",
        "Middleware",
        "Template",
        "View",
        "Data",
        "Support",
        "Other",
    ]

    for section in section_order:
        group = sorted(sections.get(section, []), key=lambda s: s.name)
        if not group:
            continue
        lines.append(f"### {section}")
        lines.append("")
        for symbol in group:
            summary = metadata["symbols"].get(symbol.name, {}).get(
                "summary", fallback_symbol_summary(symbol)
            )
            lines.append(f"- [{symbol.name}](api/{symbol.name}.md): {summary}")
        lines.append("")

    lines.append("## Public Header List")
    lines.append("")
    for header in public_headers:
        rel = header.relative_to(repo_root).as_posix()
        lines.append(f"- `{rel}`")

    index_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Arlen API reference markdown.")
    parser.add_argument(
        "--repo-root",
        default=None,
        help="Repository root (defaults to script-relative detection).",
    )
    parser.add_argument(
        "--metadata",
        default=None,
        help="Path to metadata JSON file.",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="API symbol page output directory (default: docs/api).",
    )
    parser.add_argument(
        "--index-path",
        default=None,
        help="Path to API index markdown (default: docs/API_REFERENCE.md).",
    )
    args = parser.parse_args()

    script_path = Path(__file__).resolve()
    inferred_repo_root = script_path.parents[2]
    repo_root = Path(args.repo_root).resolve() if args.repo_root else inferred_repo_root

    metadata_path = (
        Path(args.metadata).resolve()
        if args.metadata
        else repo_root / "tools" / "docs" / "api_metadata.json"
    )
    output_dir = (
        Path(args.output_dir).resolve()
        if args.output_dir
        else repo_root / "docs" / "api"
    )
    index_path = (
        Path(args.index_path).resolve()
        if args.index_path
        else repo_root / "docs" / "API_REFERENCE.md"
    )

    output_dir.mkdir(parents=True, exist_ok=True)

    metadata = load_metadata(metadata_path)
    public_headers = parse_public_header_list(repo_root)

    all_symbols: List[SymbolDoc] = []
    for header in public_headers:
        all_symbols.extend(parse_header(header, repo_root))

    # Deterministic order for stable docs diffs.
    all_symbols.sort(key=lambda s: (symbol_section_for_header(s.header), s.name))

    for symbol in all_symbols:
        write_symbol_page(symbol, output_dir, metadata)

    write_index(all_symbols, index_path, metadata, public_headers, repo_root)

    print(
        f"Generated API reference: {len(all_symbols)} symbols, "
        f"{sum(len(s.methods) for s in all_symbols)} methods, "
        f"{sum(len(s.properties) for s in all_symbols)} properties"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
