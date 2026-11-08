#!/usr/bin/env bash
# Local checks: format, lint, strict types, build. Studio tests run through the
# Studio MCP (see tests/studio). Usage: bash scripts/check.sh
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0
step() { printf '\n== %s\n' "$1"; }
run() { "$@" || fail=1; }

step "Format (StyLua)"
run stylua --check src tests/studio

step "Lint (Selene)"
run selene src tests/studio

step "Strict types (luau-lsp)"
LSP=$(sed -n 's/^luau-lsp = "[^@]*@\(.*\)"/\1/p' rokit.toml)
DEFS="${SFT_DEFS:-$HOME/.cache/skyfold/globalTypes-$LSP.d.luau}"
if [ ! -s "$DEFS" ]; then
	mkdir -p "$(dirname "$DEFS")"
	curl -fsSL --retry 3 -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$LSP/scripts/globalTypes.d.luau" || true
fi
TMP=$(mktemp -d)
if rojo sourcemap default.project.json -o "$TMP/sourcemap.json" >/dev/null; then
	run luau-lsp analyze --platform roblox --sourcemap "$TMP/sourcemap.json" --definitions "@roblox=$DEFS" --base-luaurc .luaurc src tests/studio
else
	fail=1
fi

step "Build (Rojo)"
run rojo build default.project.json -o "$TMP/SeekForTreasure.rbxl"
rm -rf "$TMP"

echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$fail"
