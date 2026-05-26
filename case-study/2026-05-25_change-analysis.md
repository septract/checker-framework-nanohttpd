# Annotating NanoHTTPD with the Checker Framework

**Date:** 2026-05-25
**Target:** `case-study/src/main/java/fi/iki/elonen/NanoHTTPD.java` (NanoHTTPD 2.0.0-Release, 1018 lines)
**Goal:** Drive Checker Framework findings to zero **without cheating** — no `@SuppressWarnings`, no stub files lying about library signatures, no flag manipulation that silences findings.

## Headline

| | Commit | Findings | Net change |
|--|--------|----------|------------|
| Pristine upstream | `644d3fc` | 41 | — |
| Phase 1 — annotations only | `ae11aff` | 35 | −6 |
| Phase 2 — trivial bug fixes + refactors | `f8c1cdb` | 4 | −31 |

Diff vs. pristine (`644d3fc → f8c1cdb`): **+124 insertions / −44 deletions**, ~12% delta. (Phase 1 alone was +33/−17; phase 2 added the rest.)

The 4 remaining findings are not hidden. They produce `[WARNING]` lines on every build, and the Makefile target fails on them.

---

## A taxonomy of the changes

The work decomposes into five distinct *kinds* of change. The category an edit falls into is more interesting than the line count: it tells you what each kind of work actually costs, and where the value of CF lies.

### A. Honest type-qualifier annotations
Adding `@Nullable`, `@MonotonicNonNull`, `@NonNegative`, etc. to existing declarations.

Each annotation states something that **was already true** about the code. CF then checks the rest of the file for consistency with the annotation. The annotation cannot break runtime behavior — annotations are erased — and CF will reject an annotation that contradicts the code.

These edits are zero-risk: no new logic, no new control flow, the bytecode is unchanged.

**Examples:** `@Nullable hostname` (line 82 ctor calls `this(null, port)`), `@Nullable Method.lookup return` (body has `return null` on no match), `@MonotonicNonNull myServerSocket` (assigned exactly once in start()).

### B. Lifecycle / contract annotations
Adding annotations that describe an API contract spanning multiple methods or classes: `@InheritableMustCall("stop")` on the NanoHTTPD class, `@Owning` on `myServerSocket`, `@CreatesMustCallFor("this")` on `start()`, `@EnsuresCalledMethods(close)` on `stop()`, `@EnsuresNonNull` on the setters, `@RequiresNonNull` on `stop()`, `@UnknownInitialization NanoHTTPD this` on setter receivers.

These are also zero-risk on the local edit, but they *propagate*: declaring a class `@InheritableMustCall` obligates every implementer; declaring a method `@RequiresNonNull` obligates every caller; etc. The propagation can cascade into other findings that have to be addressed.

In practice the propagation is where the *educational* content of CF lives — these contracts force you to make explicit decisions about ownership, lifecycle, and preconditions that informal Java code leaves implicit.

### C. Behavior-preserving CF-friendly restructure
Changes to the source that preserve observable behavior on every valid execution but give CF a structural form it can reason about.

Examples in this work:
- `final InputStream localData = this.data;` captured at top of `Response.send()` — CF preserves narrowing through method calls on a final local where it doesn't on a field.
- `rlen = Math.min(rlen, buf.length)` clamp in `findHeaderEnd` — the invariant `rlen ≤ buf.length` already held in all callers, but CF couldn't see it.
- Inline guard `if (matchcount >= 0 && matchcount < boundary.length && ...)` in `getBoundaryPositions` — `matchcount`'s value is always in `[0, boundary.length)` by the increment-and-reset structure of the loop, but CF can't infer the inductive invariant.
- Hoist `RandomAccessFile f = null` out of the try block in `HTTPSession.run()` so `finally` can close it.

Each is a pure refactor against valid inputs. Behavior diverges only on inputs the code's invariants forbid — for those, the new code is more lenient or earlier-failing than the original, but the original would have crashed anyway.

### D. Trivial bug fixes
Defensive checks added at points where the original code would NPE, throw `StringIndexOutOfBoundsException`, or silently leak on malformed input. The new behavior is to respond with `BAD_REQUEST` / `IllegalStateException` / propagate `IOException`, matching the surrounding error-handling style.

Examples:
- `IllegalStateException` if `start()` is called twice (previously: silent socket leak).
- `BAD_REQUEST` if a multipart `content-disposition` is missing the `name` or `filename` field (previously: NPE).
- `getTmpBucket()` throws `IOException` instead of returning null (previously: caller NPE).
- `decodePercent` bounds-checks the substring lookup; a truncated `%`-escape at end of string passes through literally (previously: `StringIndexOutOfBoundsException`).
- `serve(uri, ...)` only called when `pre.get("uri") != null`, mirroring the existing `method == null` check.

These are real bug fixes. The happy path is unchanged; the error path becomes informative rather than crashy.

### E. Things we deliberately did NOT do (the "no cheating" line)
- **No `@SuppressWarnings` anywhere.** Even where CF was wrong (the @Owning/@CreatesMustCallFor edge cases), we either restructured the code or left the finding in place.
- **No `.astub` stub files.** No lying about Socket.getInputStream's must-call relationship, no fake @NotOwning on JDK methods.
- **No CF flags that silence findings.** `-Awarns` is used to let multi-checker runs complete (a documented CF limitation; without it, the first checker to error aborts subsequent ones), and the Makefile re-fails the build if any finding is present. We did not use any flag that suppresses categories.
- **No `@AssumeAssertion` / `assert`-as-trust.** We tried `assert rlen <= buf.length;` for the byte buffer; CF's Index Checker doesn't recognize that form, but more importantly, an unverified assert is morally a suppression.
- **No deep refactors.** No new helper classes, no new abstractions, no changes to public-API method signatures except where genuinely required to fix a bug (e.g. `getTmpBucket()` adding `throws IOException`).
- **No semantics changes on the happy path.** Every behavior change is on an error path that was previously broken.

---

## Phase 1 — annotations only

Pristine `41 findings` → `35 findings`.

The annotations added across phase 1 (all category A or B):

| Annotation | Where | What it says |
|--|--|--|
| `@Nullable` | `hostname` field + ctor param | The parameterless ctor delegates `this(null, port)`. |
| `@MonotonicNonNull` | `myServerSocket`, `myThread` | Assigned once in `start()`; never reset. |
| `@Nullable` | `Method.lookup` return + param | Body literally `return null` on no match; body uses `equalsIgnoreCase` which is null-safe. |
| `@Nullable` | `decodeParameters(String)` param | Body explicitly null-checks the arg. |
| `@Nullable` | `decodeParms(@Nullable String parms, ...)` param | Same — body opens with `if (parms == null)`. |
| `@Nullable` | `Response.data` field + getters/setters + ctor params | Documented "may be null"; literally assigned `null` in the txt-based ctor. |
| `@MonotonicNonNull` | `Response.requestMethod` | Only set via `setRequestMethod`, may not be set at all. |
| `@Nullable` | `getTmpBucket` return | Body returns `null` on exception path. |
| `@EnsuresNonNull` + `@UnknownInitialization NanoHTTPD this` | `setAsyncRunner`, `setTempFileManagerFactory` | These setters establish the field non-null when called; safe to call mid-construction. |
| `@RequiresNonNull("myServerSocket", "myThread")` | `stop()` | Original code NPE'd if stop() preceded start(); annotation documents that. |
| `@Owning` | `myServerSocket` | NanoHTTPD owns the socket lifecycle. |
| `@InheritableMustCall("stop")` | NanoHTTPD class | Callers must call stop() to clean up. |
| `@CreatesMustCallFor("this")` | `start()` | `start()` allocates a new ServerSocket and stores it on `this`. |
| `@EnsuresCalledMethods(close)` | `stop()` | `stop()` invokes `close()` on `myServerSocket`. |

Phase 1 was deliberately strict: zero source-shape changes, only annotations. The 6 findings cleared correspond to facts CF could now verify (the `@Nullable getTmpBucket` return matches the `return null`, the `@EnsuresNonNull` setters establish the field state for callers, etc.).

The phase ended with 35 findings, of which CF analysis-limitation residuals on the @Owning/@CreatesMustCallFor interaction and the @EnsuresCalledMethods/try-catch interaction were the most stubborn.

---

## Phase 2 — trivial bug fixes + refactors

Phase 1's `35 findings` → `4 findings`.

> **Label note:** the item IDs below (`A1`, `B3`, `C7`, …) are the original
> *work-plan step* identifiers, NOT the change-taxonomy letters from the
> "Anatomy" section above. To avoid confusion the batch headers are numbered
> (Batch 1–5), and each item still cross-references its taxonomy category
> ("category C refactor", "category D bug fix").

### Batch 1 (plan section A) — CF analysis residuals (−5 findings)

These are category C refactors: zero behavior change on valid inputs.

- **A1: `Response.send()` data local-capture.** Capture `data` into `final InputStream localData = data;` at the top. The loop body's read/write calls no longer cause CF to re-widen the field narrowing.
- **A2: `stop()` close in its own try.** Separate `myServerSocket.close()` (catches `IOException`) from `myThread.join()` (catches `InterruptedException`). Did not fully clear the `[contracts.postcondition]` finding — see residual #2 below.
- **A3: `start()` re-entry guard.** Throw `IllegalStateException` if `myServerSocket != null` on entry. Category D bug fix — previously a second call to `start()` would silently leak the first socket.
- **A4: `findHeaderEnd` Math.min clamp.** `rlen = Math.min(rlen, buf.length);` at method start. Cleared the 5 byte-buffer `[array.access.unsafe.high]` findings inside the loop. Plus `@NonNegative` on the return so callers know `splitbyte` is bounded.
- **A5: `getBoundaryPositions` inline bounds.** Replace `if (b.get(i) == boundary[matchcount])` with `if (matchcount >= 0 && matchcount < boundary.length && b.get(i) == boundary[matchcount])`. The loop's structure already guarantees the bounds; this expresses them to CF.

### Batch 2 (plan section C-simple) — single-shot bug fixes (−5 findings)

Category D edits matching the existing error-handling style.

- **C1: `getTmpBucket()` throws `IOException`.** Was: caught Exception, printed to stderr, returned null. Now: rethrows as IOException. The outer `catch (IOException ioe)` in `HTTPSession.run()` already exists and handles it correctly. Cleared 3 null-dereferences of `f`.
- **C7: `decodePercent` bounds check.** Added `if (i + 3 <= str.length())` around the substring. Truncated `%`-escape at end of input passes through literally instead of crashing.
- **C8: `uri` null check.** Mirrors the existing `if (method == null)` pattern with a `BAD_REQUEST` response.

### Batch 3 (plan section B) — resource leaks (−2 findings, 2 residuals)

- **B1: `accepted` Socket in inner Runnable.** Hoisted out of try block; uses null-after-transfer pattern so the catch can close it on exception. **Did not fully clear** the corresponding `[required.method.not.called]` finding — CF moved it to the derived `inputStream` (see residual #1). The original Socket leak is fixed.
- **B3: `RandomAccessFile f`** in `HTTPSession.run()`. Hoisted to enclosing scope; close in `finally` (swallow `IOException` because the file descriptor is shared with the downstream BufferedReader, which closes it first).
- **B4: `FileOutputStream`** in `saveTmpFile`. `try (FileOutputStream fos = ...)` block.
- **B2: `DefaultTempFile.fstream`** — **NOT FIXED.** See residual #3 below. The trivial annotation `@Owning fstream` propagates the obligation through `TempFile` interface → `List<TempFile>` generic parameter → every caller that creates a TempFile. Outside the scope agreed for this phase.

### Batch 4 (plan section C-multipart) — input validation fixes (−9 findings)

All category D — defensive checks aligned with `BAD_REQUEST` style.

- **C2 + C3:** explicit null check on `contentTypeHeader` + `st` inside the multipart branch (the implication `contentType == "multipart/form-data" ⇒ both non-null` is logically true but invisible to CF).
- **C4:** `pname != null && pname.length() >= 2` check before `pname.substring(1, pname.length() - 1)`.
- **C5:** same shape for `filename`.
- **C6:** `boundarycount >= 2` defensive check alongside the existing `> bpositions.length` check.
- "boundary=" lookup: explicit `if (boundaryIdx < 0)` check before using the index.
- `mpline.substring(0, Math.min(Math.max(0, d - 2), mpline.length()))`: clamp both directions so the Index Checker accepts.

> **Preserved upstream bug (not ours):** the line `if (boundary.startsWith("\"") && boundary.startsWith("\""))` is verbatim from NanoHTTPD 2.0.0 — the second clause should clearly be `endsWith`. CF does not flag it (it's a logic bug, not a type error), and fixing it is out of scope for this annotation/finding-elimination exercise. Flagged here so a reviewer doesn't mistake it for something we introduced.

### Batch 5 — chunked-read invariant (−4 findings)

A defensive clamp on `rlen` after each accumulation in `HTTPSession.run()`'s header-read loop: `if (rlen > buf.length) { rlen = buf.length; }`. The clamp is unreachable in practice (`InputStream.read(buf, off, len)` is contractually bounded by `len`), but it gives CF the explicit invariant `rlen ≤ buf.length`, which lets it verify the subsequent `read(buf, rlen, buf.length - rlen)` and `new ByteArrayInputStream(buf, 0, rlen)` calls.

---

## The 4 residuals

Each of these is a build-time warning that the Makefile still surfaces. None are hidden.

### Residual 1 — `inputStream` MustCall (line 126)

```
[WARNING] /case-study/...:[126,36] [required.method.not.called]
  @MustCall method close may not have been invoked on inputStream or any of its aliases.
```

**Root cause:** `InputStream inputStream = accepted.getInputStream();` creates a stream whose `close()` is logically equivalent to closing the underlying socket. The async runnable closes the socket. The JDK CF stubs do not express this aliasing via `@MustCallAlias`, so CF tracks `inputStream`'s obligation independently and never sees a `close()` on the local variable name `inputStream`.

**Status:** CF analysis limitation, not a real leak. The same FD is closed via either path that exits this code.

**Closing this would require:** Either a stub file declaring `Socket.getInputStream()` as `@MustCallAlias` of `this`, or an explicit `inputStream.close()` call in the catch (which would race with the async runnable's close on the happy path).

### Residual 2 — `stop()` `[contracts.postcondition]` (line 163)

```
[WARNING] /case-study/...:[163,16] [contracts.postcondition]
  postcondition of stop is not satisfied.
  found   : no information about this.myServerSocket
  required: this.myServerSocket is @CalledMethods("close")
```

**Root cause:** `stop()` declares `@EnsuresCalledMethods(value = "this.myServerSocket", methods = "close")`. The body invokes `myServerSocket.close()` inside a try block whose catch handles `IOException`. CF's CalledMethods analysis is conservative across catch blocks even though `close()` was definitely called on every exit path.

**Status:** CF analysis limitation. The annotation is true.

**Closing this would require:** Calling `close()` outside any catch (which would propagate IOException, changing `stop()`'s API), or a restructuring CF specifically recognizes — neither is purely behavior-preserving.

### Residual 3 — `DefaultTempFile.fstream` leak (line 435)

```
[WARNING] /case-study/...:[435,22] [required.method.not.called]
  @MustCall method close may not have been invoked on new FileOutputStream(file) or any of its aliases.
```

**Root cause:** The `DefaultTempFile` constructor opens a `FileOutputStream` and stores it in the `fstream` field. The `delete()` method only deletes the file; it does not close the stream. The TempFile interface has no `close()` method. **This is a real resource leak in NanoHTTPD 2.0.0** — `fstream` is never used by any caller in the file and is never closed.

**Status:** Real bug. Not fixed in this phase because the minimum CF-acceptable annotation (`@Owning OutputStream fstream` + `@InheritableMustCall("delete")` on the class) is true but **propagates** through:

- `TempFile` interface needs `@InheritableMustCall("delete")` for the subtype relation to hold;
- `List<TempFile>` then requires the generic parameter to carry the obligation, which the Resource Leak Checker doesn't support cleanly;
- Every method that creates a TempFile (`saveTmpFile`, `getTmpBucket`, the temp-file-manager glue) needs to either declare itself the owner or transfer ownership explicitly.

That cascade is a real refactor — a half day of careful work, not a trivial bug fix. Tracked here as the highest-priority follow-up.

### Residual 4 — Chunked-read Index Checker (line 678)

```
[WARNING] /case-study/...:[678,70] [argument] incompatible argument for parameter len of InputStream.read.
  found   : int
  required: @NonNegative int
```

**Root cause:** The `len` argument is `buf.length - rlen`. Even after clamping `rlen ≤ buf.length`, CF's Index Checker does not propagate that bound through the surrounding loop, so it cannot prove `buf.length - rlen ≥ 0` at the read call site. (When we experimentally annotated an intermediate local, CF alternated between demanding `@NonNegative` and `@LTLengthOf(offset="rlen - 1", value="buf")` — i.e. it wanted both the non-negativity and the upper-bound facet, and the chain didn't close without propagating bounded-length facts through every prior statement.)

**Status:** CF analysis limitation. The invariant is true.

**Closing this would require:** A heavier Index Checker annotation pass that propagates bounded-length facts through the read pipeline. Likely tractable, but unclear it's worth the complexity for a one-finding gain.

---

## Annotations used, by Checker Framework module

The work exercised five distinct CF type-systems:

| Checker | Annotations used |
|---|---|
| Nullness | `@Nullable`, `@MonotonicNonNull`, `@EnsuresNonNull`, `@RequiresNonNull` |
| Initialization | `@UnknownInitialization` |
| Index | `@NonNegative` |
| MustCall / Resource Leak | `@Owning`, `@InheritableMustCall`, `@CreatesMustCallFor` |
| Called Methods (subsystem of Resource Leak) | `@EnsuresCalledMethods` |

10 distinct annotations. Of these, the most leveraged single annotation was `@Nullable` (11 annotation uses); the most consequential single annotation was `@InheritableMustCall("stop")` on the class, which forced every contract about lifecycle to be explicit.

---

## Lessons for future case-study work

1. **Most of the value is in category A + D.** Pure annotations expose real bugs by making implicit nullability explicit. Trivial defensive checks close the bugs honestly. The ratio in this file: ~15 honest annotations expose ~12 real bugs.

2. **Category B (lifecycle annotations) is where complexity lives.** A single `@InheritableMustCall` on a public interface cascades through generic parameters, list types, and every caller. Plan for this — don't sprinkle ownership annotations across an unannotated codebase without first thinking about how the obligation will be discharged at each site.

3. **CF analysis residuals are real.** Not every true property is verifiable. The 4 residuals here are honest: CF's analysis can't see what's true. Acknowledging them is more useful than hiding them with `@SuppressWarnings`.

4. **The Index Checker is heavy machinery.** Three of the most stubborn findings in this work were Index Checker related. The chunked-read pattern, in particular, requires propagating bounded-length invariants through method calls that the JDK stubs don't carry. Math.min/Math.max clamp idioms are the lightweight workaround.

5. **`-Awarns` + grep-the-build-log is a workable multi-checker pattern.** Out of the box, listing multiple CF checkers in `-processor` causes javac to abort after the first one's errors; subsequent checkers never run. `-Awarns` makes them all warnings, the build script then grep-counts findings and fails on any. The Makefile in this repo demonstrates the pattern.

---

## What "zero" would look like

A reasonable next phase, deliberately out of scope here:

- **Residual 3 (fstream leak):** apply the full `@InheritableMustCall("delete")` cascade through the TempFile interface, the temp-file-manager `List<TempFile>`, and the few `saveTmpFile` / `getTmpBucket` sites. ~½ day of careful CF-driven editing.
- **Residual 1 (inputStream alias):** add a small `.astub` file that declares `Socket.getInputStream` as `@MustCallAlias` of `this`. *This is annotation-only* — `.astub` files extend the CF stub database for an unannotated dependency, which is the documented CF mechanism for exactly this case. (Note: this is the *one* legitimate use of `.astub` we ruled out at the start as "might be cheating." It isn't — it's stating something true about the JDK that the JDK's stubs happen to omit. But applying it requires care to not declare *false* things about JDK methods, which is why it's deferred to a conscious decision.)
- **Residual 2 (stop postcondition):** restructure stop() to call close outside any catch, propagating IOException — minor API change, semantics-preserving on the happy path but adds a checked-exception declaration to stop().
- **Residual 4 (Index Checker on chunked read):** annotate `findHeaderEnd` / `rlen` / `buf.length` chain with explicit `@LTLengthOf`/`@NonNegative` qualifiers throughout. Tedious.

That sequence brings the file to a zero-finding state with all annotations and edits still defensible line-by-line.
