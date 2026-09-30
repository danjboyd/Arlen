# Multipart forms and uploads

`ALNRequest` parses `multipart/form-data` text fields and binary uploads.
URL-encoded forms and JSON request bodies retain their existing behavior.

```objc
NSString *description = ctx.request.formParams[@"description"];
NSArray<NSString *> *tags = ctx.request.formValues[@"tag"];
for (ALNUpload *upload in [ctx.request uploadsForName:@"document"]) {
  NSData *bytes = upload.data;
  NSString *originalName = upload.originalFilename;
  NSString *declaredType = upload.contentType;
  NSUInteger byteCount = upload.size;
  // Choose an application-owned destination if persistence is needed:
  // [upload writeToFile:destination error:&error];
}
```

`formParams` returns the last text value for each field name, consistent with
URL-encoded forms. `formValues` returns all text values per name in arrival order
for both form encodings. `uploads` and `uploadsForName:` preserve upload order.
`multipartParts` preserves the combined order of text and file parts. Each
`ALNMultipartPart` exposes `fieldName`, `originalFilename`, `contentType`, `data`,
`size`, and UTF-8 `text`; file parts are `ALNUpload` instances. `text` can be nil
for binary files. An absent declared content type is the empty string.
A filename parameter, even an empty one, identifies a file part.

## Limits and memory

Set these keys in the application's `requestLimits` configuration dictionary:

| Key | Default | Meaning |
| --- | ---: | --- |
| `maxBodyBytes` | 1,048,576 | Total request body bytes, including multipart framing |
| `maxMultipartParts` | 128 | Combined text and file part count |
| `maxMultipartFieldBytes` | 65,536 | Bytes in each text field before UTF-8 decoding |
| `maxMultipartFileBytes` | 1,048,576 | Bytes in each uploaded file |
| `maxMultipartHeaderBytes` | 16,384 | Per-part header bytes, excluding the terminating CRLF CRLF |
| `spoolThresholdBytes` | 1,048,576 | Request bodies and file parts larger than this are spooled to temporary files |
| `spoolDirectory` | system temp directory | Absolute, existing directory for spooled bodies and uploads |

For example, in `config/app.plist`:

```plist
requestLimits = {
  maxBodyBytes = 6291456;
  maxMultipartFileBytes = 5242880;
  maxMultipartParts = 16;
};
```

Bare decimal values, quoted decimal strings, and integer `NSNumber` values
have the same meaning. All documented request limits are normalized to numbers
when configuration loads. Limits must be positive whole numbers no greater than
the smaller of `LLONG_MAX` and `NSUIntegerMax`; fractions, trailing text,
overflow, and nonnumeric values are rejected with the offending
`requestLimits.<key>` in the configuration error. Direct parser calls also
validate their supplied limits and return an error without raising an exception.
Values exactly at a limit are accepted. The HTTP
server also applies `maxHeaderBytes` and `maxRequestLineBytes` to HTTP framing.
`ARLEN_MAX_BODY_BYTES` overrides the total body limit; multipart-specific keys
are configured in `requestLimits`.

To allow large uploads on specific routes only, set `maxBodyBytes` on those
routes and keep the global limit small:

```objc
ALNRoute *upload = [app registerRouteMethod:@"POST" path:@"/documents" name:@"documents_upload"
                            controllerClass:[DocumentsController class] action:@"upload"];
upload.maxBodyBytes = 115343360;  // 110 MiB; the rest of the app keeps requestLimits.maxBodyBytes
```

Other routes still get `413` for larger bodies, at the head, without reading
them. On the upload route, multipart parsing uses the route limit as the body cap
and lets a single file use all of it. See
[Configuration Reference](CONFIGURATION_REFERENCE.md#3-request-limits).

For requests up to 110 MiB on every route, set `maxBodyBytes` to `115343360` and explicitly
raise `maxMultipartFileBytes` to the desired file cap (for example `104857600`
for a 100 MiB file with room for fields and framing). Raising the request cap
does not automatically raise per-file or per-field caps.

A request whose `Content-Length` is at most `spoolThresholdBytes` is buffered in
memory as before. A larger body is streamed from the socket into a private
`0600` `arlen-body-*` file under `spoolDirectory` as it arrives, and
`request.body` maps that file instead of holding the bytes on the heap. This
applies to any request body, not only multipart, on both HTTP parser backends.
The total body cap (`maxBodyBytes`) is checked against `Content-Length` before
anything is read or written.

During multipart parsing, text fields and file parts up to `spoolThresholdBytes`
are copied into immutable `NSData`. Larger file parts are written into a private
temporary file instead (a `0700` `arlen-upload-*` directory under
`spoolDirectory`, one `0600` file per part). With the default limits
(`maxBodyBytes` and `spoolThresholdBytes` both 1 MiB) nothing is spooled; raise
`maxBodyBytes` and `maxMultipartFileBytes` for large uploads and both kinds of
spooling take effect. Budget memory for the connection buffer, bodies up to the
threshold, small part copies, decoding, and simultaneous requests. Part limits
apply during parsing after body receipt. Keep `spoolDirectory` on a filesystem
with room for `maxBodyBytes` times the number of concurrent uploads, twice over
for multipart (body file plus part files).

A spooled upload reports its file through `temporaryFilePath`, and its `data`
maps that file on each access rather than holding the bytes. Spool files belong
to the request: the server removes them as soon as the handler returns or raises,
and a request that is deallocated removes any that remain; code can also call
`-[ALNRequest removeTemporaryFiles]` earlier. A body file for a client that disconnects
mid-upload is removed before any request exists. Move or copy an upload before the request
ends; do not hand `temporaryFilePath` to work that outlives it. Failed parses
expose no partial parts and leave no spool files. If spooling itself fails (for
example a missing `spoolDirectory` or a full disk), the request gets a `500`.

`writeToFile:error:` writes only to a caller-supplied path, atomically. For a
spooled upload the first write moves the file (a rename on the same filesystem,
a copy from the mapped file otherwise); afterwards `data` reads from that path
and further writes copy it. The caller owns and removes the persisted file.

## Parsing and errors

Parsing supports CRLF framing, quoted boundaries, quoted-pair escapes (including
escaped quotes in filenames), repeated names, empty fields/files, and exact
binary bytes including NUL and invalid UTF-8. Only a delimiter at a legal line
boundary with a valid suffix separates parts. Text fields and part headers must
be UTF-8. Original filenames are metadata; paths in filenames are never used as
destinations. Declared content types are metadata, not validated file formats.

This parser accepts a strict form-data subset: a body begins with its initial
boundary and ends with the closing boundary plus an optional CRLF. Preambles,
epilogues, folded/duplicate part headers, content-transfer-encoding, and nested
multipart decoding are unsupported. Each part requires a form-data disposition
and a nonempty name. Filename extended parameters (`filename*`) are not decoded;
clients should send `filename`. Boundary length is 1–70 ASCII characters with
no trailing space. Invalid UTF-8 text is rejected rather than silently replaced.

Application dispatch and the HTTP server validate multipart bodies before
handlers or static responses. Malformed/truncated bodies return HTTP 400;
limit violations return HTTP 413. `ALNMultipartErrorDomain` distinguishes
`ALNMultipartErrorMalformed`, `ALNMultipartErrorTruncated`, and
`ALNMultipartErrorLimitExceeded`. A connection aborted before receiving its
advertised body length never reaches application dispatch.

For constructor-created requests, accessors parse lazily with default limits.
Inspect `multipartError` to distinguish an invalid form from an empty one, or
call `parseMultipartFormWithLimits:error:` explicitly. A later call with different
limits reparses the body and replaces the cached result. Accessors retain the
last explicitly supplied policy. Raw `body` remains available on errors.
