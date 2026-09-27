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
| `spoolThresholdBytes` | 1,048,576 | File parts larger than this are spooled to a temporary file |
| `spoolDirectory` | system temp directory | Absolute, existing directory for spooled uploads |

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

For requests up to 110 MiB, set `maxBodyBytes` to `115343360` and explicitly
raise `maxMultipartFileBytes` to the desired file cap (for example `104857600`
for a 100 MiB file with room for fields and framing). Raising the request cap
does not automatically raise per-file or per-field caps.

The server buffers the full request body before multipart parsing. Text fields
and file parts up to `spoolThresholdBytes` are copied into immutable `NSData`.
Larger file parts are written straight from the body into a private temporary
file instead (a `0700` `arlen-upload-*` directory under `spoolDirectory`, one
`0600` file per part), so each large upload no longer occupies memory twice.
Budget memory for the connection buffer, request body, small part copies,
decoding, and simultaneous requests. Part limits apply during parsing after body
receipt; the transport enforces the total request cap while receiving.

A spooled upload reports its file through `temporaryFilePath`, and its `data`
maps that file on each access rather than holding the bytes. The spool directory
belongs to the request: it is removed when the request is deallocated (after the
response, on an exception, or when the client disconnects), or earlier through
`-[ALNRequest removeTemporaryFiles]`. Move or copy an upload before the request
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
