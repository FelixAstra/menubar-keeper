## What changed

<!-- One or two sentences. The diff says how; this says what, and for whom. -->

## Why

<!--
The part a diff cannot carry. This repository keeps its reasoning in writing, so a body
that explains the trade-off is worth more than one that restates the change. If you
considered an alternative, name it and say why it lost.
-->

## Verification

<!--
There is no test suite yet — see docs/ROADMAP.md. A probe log is the closest thing this
project has to a test result, and it is expected when the change touches behaviour a probe
covers. One probe per launch; they drive the real menu bar and two at once means one of
them reports "the bar is already occupied".

    touch /tmp/menubarkeeper-rowstatecheck     # or selftest, toggletest, verify, …
    make install
    cat /tmp/menubarkeeper-debug.log

Paste the relevant lines below. If nothing covers this change, say so — "not covered" is a
useful answer, an empty section is not.
-->

## Checklist

- [ ] `./Scripts/build.sh` produces no errors **and no warnings** — CI greps for `warning:` and fails on a single one
- [ ] `make install` was run and the app behaves as intended, launched from `/Applications`
- [ ] `VERSION` untouched — it is bumped only in a release commit
- [ ] `CHANGELOG.md` untouched — the entry belongs in this description instead
- [ ] User-visible text added to **both** `en.lproj` and `zh-Hans.lproj`, written as sentences rather than translated from one another
- [ ] A README image was regenerated: its own `?v=N` marker bumped (each image has its own; a stale marker shows everyone the old image and reports nothing)
- [ ] No third-party dependency, no Xcode project
