---
name: Bug report
about: Something behaves wrong on your machine
title: ""
labels: bug
assignees: ""
---

## Environment

- macOS version:
- Chip (Apple silicon / Intel):
- Is the app installed in `/Applications`?
  <!-- macOS only honours a status item from an app installed there. Running it from
       anywhere else hides its own icon along with the others, and there is no way back. -->
- Build: stock release, or your own from `main`?

## What happens

<!-- What you did, what you expected, what you got instead. -->

## Steps to reproduce

1.
2.
3.

## Diagnostics

<!--
Turn on the probes and attach the relevant lines. The log is the project's only channel
for this — a one-step export is a known gap on the ROADMAP.

    touch /tmp/menubarkeeper-rowstatecheck     # or selftest, toggletest, verify, …
    make install
    cat /tmp/menubarkeeper-debug.log

One probe per launch: they drive the real menu bar, and two at once means one of them
reports "the bar is already occupied". A probe that was skipped says so in the log.
-->

```

```

<!--
Does it involve a hidden or hidden-elsewhere app? Per-icon granularity and a hidden app's
own menu are listed in docs/ROADMAP.md as impossible rather than missing — worth a look
before filing.
-->
