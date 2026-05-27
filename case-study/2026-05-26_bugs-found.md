# Bugs found in NanoHTTPD 2.0.0 by the Checker Framework

**Date:** 2026-05-26
**Subject:** the bugs the four checkers (Nullness, Index, Regex, Resource Leak / MustCall) surfaced in the vendored `NanoHTTPD.java`. Line numbers refer to the **pristine** file as committed in `644d3fc` (i.e. before any of our edits).

> **Read this first — scope and non-claims.**
>
> - This is **NanoHTTPD 2.0.0-Release, from 2013** (commit `9be4e37`). We chose
>   an old, un-hardened version on purpose; see the repo README.
> - This is **not a commentary on current NanoHTTPD**, which has had ~10 years
>   of releases since. Several of these bugs may already be fixed upstream. We
>   deliberately did not diff against the current version.
> - This is **not a security advisory.** No CVE, no disclosure process. It's an
>   educational inventory of what a type-checker finds in ordinary older Java.
> - Severity language below ("crash", "leak", "DoS-flavored") describes the
>   *local* behavior of the 2.0.0 code on the described input. NanoHTTPD spawns
>   a thread per request by default, so a per-request crash fails that request
>   rather than the whole server — but resource leaks accumulate across requests.

Most of these are reachable from **untrusted HTTP request input** — malformed
headers, truncated percent-escapes, odd multipart bodies — which is what makes
them more than academic.

## Summary

| # | Bug | Pristine loc | Triggered by | Surfaced by | Status |
|---|-----|--------------|--------------|-------------|--------|
| 1 | Client `Socket` leaked if stream accessors throw | 108–109 | a client that connects then errors during `getInputStream()`/`getOutputStream()` | Resource Leak | fixed |
| 2 | Per-request `RandomAccessFile` leaked on exception | 654 | any `IOException` mid-request after the temp bucket is opened | Resource Leak | fixed |
| 3 | `FileOutputStream` in `saveTmpFile` never closed | 960 | every multipart file upload (PUT / multipart POST) | Resource Leak | fixed |
| 4 | `DefaultTempFile`'s `FileOutputStream` never closed | 397 | every temp file the default manager creates | Resource Leak | **open (residual)** |
| 5 | `getTmpBucket()` returns `null` on failure; callers deref | 978 / 654 | temp-file creation failing (disk full, perms) | Nullness | fixed |
| 6 | Multipart `StringTokenizer st` deref when Content-Type absent | 705 | `multipart/form-data` request with no `Content-Type` header value | Nullness | fixed |
| 7 | `contentTypeHeader` deref when null | 711–712 | same as #6 | Nullness | fixed |
| 8 | Missing `name` in content-disposition → NPE | 868–869 | multipart part with a `Content-Disposition` lacking `name=` | Nullness | fixed |
| 9 | Missing `filename` in content-disposition → NPE | 892–893 | file part with a `Content-Disposition` lacking `filename=` | Nullness | fixed |
| 10 | Null `uri` flows into `serve()` | 650 / 735 | a request line with no URI token | Nullness | fixed |
| 11 | `decodePercent` substring out of bounds | 174 | a URI/param value ending in a truncated `%` escape (e.g. `...%` or `...%A`) | Index | fixed |
| 12 | `bpositions[boundarycount-2]` negative index | 889 | a multipart body whose first part has a `Content-Type` (so `boundarycount` is still 1) | Index | fixed |
| 13 | `mpline.substring(0, d-2)` negative endIndex | 880 | a multipart value line where the boundary appears within the first 2 chars | Index | fixed |
| 14 | Quote-stripping substring OOB on short values | 869 / 893 | a `name`/`filename` value shorter than 2 characters | Index | fixed |
| 15 | `start()` not idempotent — leaks first `ServerSocket` | 100 | calling `start()` twice without `stop()` in between | Resource Leak | fixed |
| 16 | Quoted-boundary stripping never runs (logic typo) | 713 | a multipart boundary wrapped in quotes | **not caught** | preserved |

## Detail by category

### Resource leaks (#1–#4, #15)

These are the most consequential because they **accumulate**. A thread-per-
request server that leaks a file descriptor or socket on certain inputs can be
walked toward FD exhaustion by a client that repeatedly sends those inputs.

- **#1 — client socket leak (line 108).** In the accept loop, `finalAccept`
  (the accepted `Socket`) is only closed inside the async task that runs the
  session. If `getInputStream()` / `getOutputStream()` / the temp-file-manager
  factory throws *before* the task is enqueued, the socket is dropped on the
  floor — caught by an empty `catch (IOException)`. Surfaced once `myServerSocket`
  was annotated `@Owning`.
- **#2 — RandomAccessFile leak (line 654).** The per-request temp "bucket" file
  is never closed if any of the body-reading or parsing steps throws.
- **#3 — saveTmpFile FOS leak (line 960).** `new FileOutputStream(name).getChannel()`
  — the stream is created purely for its channel and is never closeable
  afterward. Leaks on every upload.
- **#4 — DefaultTempFile FOS leak (line 397) — STILL OPEN.** The constructor
  opens a `FileOutputStream` into a field that no code ever uses or closes.
  This one is a documented residual: fixing it correctly requires propagating
  ownership/must-call obligations through the `TempFile` interface and a
  `List<TempFile>`, which is a real refactor (see the residuals section of the
  change-analysis doc).
- **#15 — non-idempotent start() (line 100).** `start()` assigns a fresh
  `ServerSocket` to the field unconditionally. A second `start()` (without an
  intervening `stop()`) silently leaks the first socket and its bound port. The
  Resource Leak Checker's `@CreatesMustCallFor`/`@Owning` machinery flagged the
  unconditional re-assignment; the fix throws `IllegalStateException`.

### NullPointerExceptions from request input (#5–#10)

Each crashes the request-handling thread on a specific malformed request. All
trace back to a value that can be `null` — usually a `Map.get()` on a header or
disposition field — being dereferenced without a check. The Nullness Checker
flags them once the relevant `@Nullable` is made explicit; the fixes add the
missing validation (returning `BAD_REQUEST`, or for #5 throwing `IOException`
which the existing handler already catches).

The common shape: NanoHTTPD reads a header into a `Map<String,String>`, then
later assumes the key is present. Well-formed clients always send the key, so
the bug only bites on adversarial or buggy clients — exactly the inputs a
server should survive.

### Index / bounds crashes (#11–#14)

`String.substring` and array indexing with computed offsets that aren't
validated against the actual length. The Index Checker proves these unsafe.
The standout is **#11**: `decodePercent` does `str.substring(i+1, i+3)` on
seeing `%`, with no check that two more chars exist — so any value ending in a
bare `%` throws `StringIndexOutOfBoundsException`. That's trivially reachable in
a query string or form field.

### The bug the type-checkers could NOT catch (#16)

Line 713:

```java
if (boundary.startsWith("\"") && boundary.startsWith("\"")) {
    boundary = boundary.substring(1, boundary.length() - 1);
}
```

The second `startsWith` should be `endsWith`. The intent is "if the boundary is
wrapped in quotes, strip them"; as written, the quote-stripping branch is taken
for any boundary that merely *starts* with a quote, and a boundary that is
quoted normally still works only by accident of the first check.

This is a **logic bug, not a type error** — both operands are valid `boolean`
expressions on valid `String`s, so every checker is happy. We left it in place
(out of scope for an annotation/finding-elimination exercise) and call it out
here because it's the clearest illustration of the boundary of what pluggable
type-checking buys you: it eliminates whole *categories* of bug (null deref,
out-of-bounds, unclosed resources), but it does not understand intent.

## Cross-reference

The phase-by-phase account of how each of these was annotated and fixed — and
the four findings that remain (three CF analysis limitations plus bug #4) — is
in [`2026-05-25_change-analysis.md`](2026-05-25_change-analysis.md).
