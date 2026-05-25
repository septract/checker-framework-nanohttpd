# Upstream provenance

The Java source under `src/main/java/fi/iki/elonen/` is vendored from
[NanoHTTPD](https://github.com/NanoHttpd/nanohttpd), a small embeddable
HTTP server in Java.

- **Upstream tag:** `2.0.0-Release`
- **Upstream commit:** `9be4e37109bd15724e5fc1cd753b61d90055084c`
- **Date of upstream release:** 2013
- **License:** Modified BSD (3-clause); see `UPSTREAM-LICENSE.md`.

This version was selected because:

1. It is small (one `NanoHTTPD.java` file, ~1018 lines) — feasible to
   exhaustively type-check and annotate as a case study.
2. It is old enough that the project has gone through ~10 years of
   bugfix releases since. Findings the Checker Framework reports here
   can be cross-checked against the upstream history to see whether
   the bug was later fixed (and if so, how).
3. It is genuine, in-the-wild Java code — sockets, file I/O, byte
   parsing — *not* a textbook example.

Annotations we add to this source live in-place in the vendored file.
The git diff against the original 1018-line file is therefore the
record of our annotation work.
