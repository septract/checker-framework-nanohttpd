# checker-framework-nanohttpd

A hands-on exploration of the [Checker Framework](https://checkerframework.org/) —
a pluggable type-checker for Java — on real code.

Two things live here:

- **`examples/`** — four tiny, intentionally-buggy classes, one per checker
  (Nullness, Index, Regex, Resource Leak / MustCall). They exist to prove the
  toolchain is wired up correctly and to show what each checker catches in
  isolation.
- **`case-study/`** — a worked study of annotating and verifying a real HTTP
  server, [NanoHTTPD](https://github.com/NanoHttpd/nanohttpd), with those same
  four checkers.

## Please note: the case-study target is deliberately old

The vendored NanoHTTPD is **version 2.0.0-Release, from 2013**
(commit `9be4e37`). This is a deliberate choice, not an oversight.

We wanted a target that was *not* already hardened — real, in-the-wild Java
(sockets, byte parsing, file I/O) written before modern null-safety and
try-with-resources idioms were common, so the checkers would have something to
find. A current, battle-tested library would mostly produce a clean run, which
makes for a boring demo.

**This repo is not a commentary on NanoHTTPD today.** NanoHTTPD has had ~10
years of fixes and releases since 2.0.0; bugs surfaced here may well already be
fixed upstream. The point is the *method* — what it looks like to take ordinary
older Java and make its safety properties explicit and machine-checked — not
the specific findings in this specific old version.

The vendored file is checked in pristine in the first commit, so the full
annotation/fix history is visible as a clean diff against the original. See
[`case-study/UPSTREAM.md`](case-study/UPSTREAM.md) for exact provenance and
[`case-study/UPSTREAM-LICENSE.md`](case-study/UPSTREAM-LICENSE.md) for the
upstream BSD license.

## Prerequisites

- A JDK that the Checker Framework supports (8/11/17/21). The build is pinned
  to **Eclipse Temurin 21**.
- **Maven** 3.9+.

> **Portability note:** the top-level `Makefile` hard-codes `JAVA_HOME` to a
> macOS Temurin 21 path. On another OS (or a different install location), edit
> the `JAVA_HOME :=` line at the top of the `Makefile` to point at your JDK 21.

No global Checker Framework install is needed — it is pulled as a Maven
annotation processor (`org.checkerframework:checker`, version pinned in the
`pom.xml` files). Maven artifacts are cached in a project-local `.m2/`
(see `.mvn/maven.config`), so the build is self-contained.

## Running

```sh
make examples       # run all four checkers over the tiny demos
make case-study     # run all four checkers over NanoHTTPD
make help           # list targets
make examples-clean # / make case-study-clean
```

Both targets **fail on purpose** when the checkers report findings — that is
the intended signal, not a build error to be worked around. Each target writes
the full checker output to `*/target/checker.log` and prints a finding count.

### Interpreting the output

The Checker Framework reports a finding as:

```
[WARNING] .../NanoHTTPD.java:[LINE,COL] [category] message
```

For the `examples/` demos, every finding is *expected* — each file is written
to trip exactly one checker. For the `case-study/`, findings are the things the
checkers can't prove safe; the goal of the case study is to drive that set down
to as small and well-understood a remainder as possible.

(One mechanical detail: the build runs all four checkers in a single pass with
`-Awarns`, because otherwise javac aborts after the first checker that reports
an error and the others never run. The `Makefile` then re-asserts a non-zero
exit by counting findings in the log. Nothing is silenced — see below.)

## The case study, in brief

The case-study work proceeded in two phases, recorded as separate commits:

1. **Annotations only** — adding Checker Framework type qualifiers
   (`@Nullable`, `@Owning`, `@MonotonicNonNull`, …) that state facts already
   true about the code, with zero behavior change.
2. **Trivial bug fixes** — small, defensible edits (defensive null/bounds
   checks, try-with-resources, behavior-preserving local refactors) that fix
   the genuine bugs the annotations exposed.

A self-imposed rule governed the whole effort: **no cheating.** No
`@SuppressWarnings`, no stub files misrepresenting library signatures, no
compiler flags that mute findings. Where a property is true but the checker
cannot verify it, the finding is left standing and documented rather than
hidden.

The full write-up — a taxonomy of the kinds of change, a phase-by-phase
account, and an honest analysis of every remaining finding — is in
[`case-study/2026-05-25_change-analysis.md`](case-study/2026-05-25_change-analysis.md).

## Repository layout

```
.
├── Makefile                       # entry points; pins JAVA_HOME to Temurin 21
├── .mvn/maven.config              # project-local Maven repo (self-contained build)
├── examples/
│   ├── pom.xml
│   └── src/main/java/examples/
│       ├── nullness/NullnessDemo.java
│       ├── index/IndexDemo.java
│       ├── regex/RegexDemo.java
│       └── resourceleak/ResourceLeakDemo.java
└── case-study/
    ├── pom.xml
    ├── UPSTREAM.md                # provenance: NanoHTTPD 2.0.0-Release
    ├── UPSTREAM-LICENSE.md        # upstream BSD license
    ├── 2026-05-25_change-analysis.md
    └── src/main/java/fi/iki/elonen/NanoHTTPD.java
```

## License

The vendored `NanoHTTPD.java` is distributed under NanoHTTPD's original
Modified BSD license (see `case-study/UPSTREAM-LICENSE.md`). The example code
and the analysis/build scaffolding in this repository are provided for
demonstration and educational use.
