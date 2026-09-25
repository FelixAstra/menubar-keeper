#!/usr/bin/env bash
#
# Prints one CHANGELOG.md section on stdout, without its heading and without the link
# definitions at the foot of the file, trimmed of leading and trailing blank lines.
#
# Exists because the release pages and the changelog were two different documents: the
# tag-triggered job asked GitHub to generate notes, and with no pull requests to list the
# release came out holding a compare link and nothing else. The changelog is the hand-written
# record the README points readers at, so it is the one that should appear on the release.
#
#   ./Scripts/changelog-section.sh 1.4.0            # from ./CHANGELOG.md
#   ./Scripts/changelog-section.sh 1.4.0 other.md
#
# Prints nothing and exits 0 when the version has no section, so callers can test for empty
# output instead of handling a failure — a missing section is a fallback, not an error.

set -euo pipefail

version="${1:?usage: changelog-section.sh <version> [changelog.md]}"
file="${2:-CHANGELOG.md}"

[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }

awk -v v="$version" '
    # The section starts at its heading: "## [1.4.0] - 2026-09-25".
    index($0, "## [" v "]") == 1 { found = 1; next }
    # Any other version heading ends it.
    found && /^## \[/ { exit }
    # So does the link-definition block at the foot of the file, "[1.4.0]: https://…",
    # which would otherwise be swallowed by whichever section comes last.
    found && /^\[[^]]+\]:[[:space:]]/ { exit }
    found { line[++n] = $0 }
    END {
        if (n == 0) exit
        while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--      # trailing blanks
        first = 1
        while (first <= n && line[first] ~ /^[[:space:]]*$/) first++   # leading blanks
        for (i = first; i <= n; i++) print line[i]
    }
' "$file"
