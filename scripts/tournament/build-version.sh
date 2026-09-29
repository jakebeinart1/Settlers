#!/usr/bin/env bash
# Builds the seat server for one historical commit.
#
#   scripts/tournament/build-version.sh <commit> <out-dir>
#
# Exports the commit's two packages with `git archive` (no worktree, no
# checkout: the commit's own sources, untouched), adds `seat-server.swift` as
# an extra executable target, detects which bot APIs that commit has, and
# builds in Release. Writes <out-dir>/seat-<short-sha>. Idempotent: an existing
# binary is kept, because a rebuilt anchor is a different anchor.
set -euo pipefail

commit="$1"
out="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
sha="$(git -C "$repo" rev-parse --short=7 "$commit")"
binary="$out/seat-$sha"
[[ -x "$binary" ]] && { echo "$binary (cached)"; exit 0; }

work="$(mktemp -d "${TMPDIR:-/tmp}/seat-$sha.XXXXXX")"
trap 'rm -rf "$work"' EXIT
git -C "$repo" archive "$sha" Packages/CatanEngine Packages/CatanAI | tar -x -C "$work"
pkg="$work/Packages/CatanAI"
mkdir -p "$pkg/Sources/seat-server"
cp "$here/seat-server.swift" "$pkg/Sources/seat-server/main.swift"
cat >> "$pkg/Package.swift" <<'SWIFT'

package.targets.append(.executableTarget(name: "seat-server", dependencies: ["CatanAI", "CatanEngine"]))
SWIFT

src="$work/Packages"
has() { grep -rqE "$1" "$src/$2"; }
flags=()
has 'public protocol Policy' CatanEngine/Sources && flags+=(-Xswiftc -DPOLICY_API)
has 'protocol LedgerAwarePolicy' CatanEngine/Sources && flags+=(-Xswiftc -DLEDGER_API)
has 'public struct EvaluationPolicy' CatanAI/Sources/CatanAI && flags+=(-Xswiftc -DEXPERT)
has 'rng: inout some RandomNumberGenerator' CatanAI/Sources/CatanAI/Bot.swift && flags+=(-Xswiftc -DRNG_OVERLOAD)
has 'static func evaluate\(' CatanAI/Sources/CatanAI/TradeHeuristics.swift 2>/dev/null && flags+=(-Xswiftc -DTRADE_EVAL)

swift build --package-path "$pkg" -c release --product seat-server ${flags[@]+"${flags[@]}"} >"$work/build.log" 2>&1 || {
    tail -30 "$work/build.log" >&2
    echo "build failed: $sha" >&2
    exit 1
}
mkdir -p "$out"
cp "$(swift build --package-path "$pkg" -c release --show-bin-path)/seat-server" "$binary"
printf "%s\n" ${flags[@]+"${flags[@]}"} | grep -v Xswiftc | tr '\n' ' ' > "$binary.flags"
echo "$binary"
