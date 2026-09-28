# Contributing to MenuBarKeeper

Thanks for taking a look. This is a small app with an unusual amount of hard-won knowledge
behind it, and most of what you need is not visible in the code.

## Read these before you write anything

| Document | Why |
|---|---|
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Known gaps — and a section of things that are **impossible rather than missing**. Several plausible ideas are on that list. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | What lives where, and the decisions behind it. |
| [`docs/TECHNICAL-FINDINGS.md`](docs/TECHNICAL-FINDINGS.md) | The reverse-engineered private API, and the pitfalls that cost real time. |

If your idea is in "what cannot be fixed", it is not a question of effort. Per-icon
granularity, a hidden app's own menu and the Mac App Store are closed doors.

## Getting set up

```bash
xcode-select --install   # once — Xcode command line tools, nothing else

git clone git@github.com:FelixAstra/menubar-keeper.git
cd menubar-keeper

make cert                # once per machine — see below
make install             # build, copy to /Applications, launch
```

There is no Xcode project and there are no dependencies. `Scripts/build.sh` compiles
everything under `Sources/` with `swiftc` and assembles the bundle by hand, which is why the
whole build fits in one file. `make help` lists the targets.

**Run it from `/Applications`, always.** macOS only honours a status item from an app
installed there. Run it from anywhere else and its own icon gets hidden along with the
others, leaving no way back. `make install` puts it in the right place for you.

**Why `make cert`.** An ad-hoc signature is keyed to the binary's hash, so every rebuild
looks like a brand new app to macOS and it asks for Accessibility permission again. One local
self-signed certificate fixes that for good. The certificate lives in `Scripts/signing/`,
which is gitignored — it is yours, not the project's.

The edit loop is `make install`. It is a clean full rebuild (~15 s); there is no incremental
build, and at this size that is deliberate rather than an omission.

## What CI will check

```bash
./Scripts/build.sh         # must compile with zero warnings
./Scripts/package-dmg.sh   # must produce a DMG
```

Warnings are not advisory here. CI greps the build log for `warning:` and fails the job on a
single one, so a working change that introduces an unused variable still does not merge.

There is no test suite yet — see the ROADMAP. What exists instead is a set of probes in
[`Sources/Support/Diagnostics.swift`](Sources/Support/Diagnostics.swift) that drive the real
app and report to a log:

```bash
touch /tmp/menubarkeeper-rowstatecheck    # or selftest, toggletest, verify, …
make install
cat /tmp/menubarkeeper-debug.log
rm -f /tmp/menubarkeeper-*
```

The flag is a marker file rather than an environment variable because `open` does not carry
the shell's environment into the app. Running the binary directly also accepts the variable
form: `MBK_ROWSTATECHECK=1 /Applications/MenuBarKeeper.app/Contents/MacOS/MenuBarKeeper`.

The interactive probes drive the menu bar itself, so **only one may run per launch** — two at
once means one probe's reveal becomes the other's "the bar is already occupied". A probe that
was skipped says so in the log rather than failing silently.

If you change behaviour that a probe covers, run that probe and paste the relevant lines into
the pull request. It is the closest thing this project has to a test result.

## Adding or changing user-visible text

Every readable string goes through `L10n` and needs an entry in **both** tables:

- `Resources/en.lproj/Localizable.strings`
- `Resources/zh-Hans.lproj/Localizable.strings`

A missing key renders as the key itself. That is on purpose: a gap shows up in the UI instead
of silently rendering an empty label, so if you see `row.state.hidden` on screen, that is the
mechanism telling you which table you forgot.

Write both sentences rather than translating one into the other. The two languages are given
equal weight here, and a literal translation reads as one.

## Commits

The history uses conventional prefixes, lowercase, imperative, with no trailing full stop:

```
feat: make the menu bar mark a choice, and default it to the capsule
fix: stop the window's footer overlapping in English
docs(demo): say what the render actually costs
ci: put the changelog on the release pages
```

A scope is optional and used when the change is confined to one area. The subject says what
changed; the body says **why** — most of the value in this repository is in the reasoning, so
a body that explains the trade-off is worth more than one that restates the diff.

## Pull requests

Branch from `main` and name the branch after the change (`feat/launch-at-login`). Open a pull
request against `main` rather than pushing to it directly, even with write access — the point
of the PR is the review, and CI runs on it either way.

Keep one concern per pull request. If a change is large enough that its diff cannot be read
in one sitting, it is probably two changes.

## Files a feature should leave alone

- **`VERSION`** — bumped only in a release commit. `.github/workflows/release.yml` refuses to
  publish when the tag disagrees with this file, and that failure happens **after** the tag is
  pushed, so it never shows up locally. A feature PR that bumps `VERSION` breaks the next
  release in a way nobody sees until it is too late.
- **`CHANGELOG.md`** — the version section is written at release time. Do not add your entry
  to an existing section; describe your change in the pull request instead.
- **The `?v=N` marker on README images** — GitHub's image proxy caches by URL, so a
  regenerated image with an unchanged marker means everyone keeps seeing the old one and
  **nothing reports an error**. If your change alters an image's bytes, bump that image's
  marker. Each image has its own; leave the others where they are.

## What not to commit

`.gitignore` already covers `build/`, `*.dmg`, `Scripts/signing/`, `_archive/`,
`tools/demo/frames/` and `node_modules`. If you create a local signing certificate, it stays
on your machine — do not un-ignore it, and do not `git add -f` it back.

## Two things that are not up for negotiation

**No third-party dependencies, no Xcode project.** `make icon` draws the app icon's rounded
square with Core Graphics rather than depending on an image library, and that is the standard
the rest of the project is held to. If you believe a dependency is genuinely unavoidable, open
an issue before writing the code.

**The private framework is research, not API.** The app drives `MenuBarClientCore` and reads
the system accessibility tree. Neither is stable, and behaviour verified on one macOS release
is not verified on the next. Changes there need re-verification on a real menu bar — which is
what the probes exist for.

## Reporting a bug

Include your macOS version, your chip, whether the app is running from `/Applications`, and
the contents of `/tmp/menubarkeeper-debug.log`. Turning on diagnostics is described above. A
one-step export is a known gap on the ROADMAP, so for now the log file is the channel.

## License

Contributions are accepted under the [MIT license](LICENSE).
