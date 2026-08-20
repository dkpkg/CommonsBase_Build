#!/bin/sh
# CommonsBase_Build.Toolchain.Discover.CGlibc probe.
#
# Provider contract (see CommonsBase_Build dk.u, "Toolchain discovery"):
#   discover.sh --abi <TARGET_ABI> [--config <path>]
# Emits UTF-8 LF KEY=VALUE lines on stdout. On success writes nothing to
# stderr. On failure writes the one-line contract error followed by every
# location searched, then exits nonzero.
#
# Configuration precedence: --config path, else the project-level
# etc/dk/t/toolchains.jsonc under the current directory, else the
# user/machine-level ${XDG_CONFIG_HOME:-$HOME/.config}/dk/toolchains.jsonc,
# else the host probe.
#
# Config keys are read section-aware: the section for the requested ABI is
# the exact-ABI section if present, else the most specific matching family
# glob (Linux_*_musl beats Linux_*). Sections are pretty-printed JSONC
# objects one level under "toolchains". A value beginning with $( is a dk
# value expression and must be resolved by
# `dk0 dialog CommonsBase_Build.Toolchain.Discover.CGlibc` or replaced with a
# literal path.
set -euf

ABI=
CONFIG=
while [ $# -gt 0 ]; do
    case "$1" in
        --abi)    ABI="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        *) echo "dk toolchain: unknown argument $1" >&2; exit 2 ;;
    esac
done
if [ -z "$ABI" ]; then
    echo "dk toolchain: --abi <TARGET_ABI> is required" >&2
    exit 2
fi

contract_see='See "System toolchains (per-ABI contract)" in DK0-REFERENCE.'

# Diagnostics accumulate here and are printed to stderr only on failure.
DIAG=""
diag() { DIAG="${DIAG}  $1
"; }

fail() {
    printf '%s\n' "dk toolchain: Release.$ABI: $1 $contract_see" >&2
    [ -n "$DIAG" ] && printf '%s' "$DIAG" >&2
    exit 1
}

if [ -z "$CONFIG" ]; then
    if [ -f "etc/dk/t/toolchains.jsonc" ]; then
        CONFIG="etc/dk/t/toolchains.jsonc"
    elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/dk/toolchains.jsonc" ]; then
        CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dk/toolchains.jsonc"
    fi
fi
if [ -n "$CONFIG" ]; then
    diag "config: $CONFIG"
else
    diag "config: none found (etc/dk/t/toolchains.jsonc, \${XDG_CONFIG_HOME:-\$HOME/.config}/dk/toolchains.jsonc)"
fi

# candidate_sections: the config section keys to try for $ABI, most specific
# first (exact ABI, then family globs by specificity).
candidate_sections() {
    printf '%s\n' "$ABI"
    case "$ABI" in
        Linux_*_musl) printf 'Linux_*_musl\nLinux_*\n' ;;
        Linux_*)      printf 'Linux_*\n' ;;
        Windows_*)    printf 'Windows_*\n' ;;
        Darwin_*)     printf 'Darwin_*\n' ;;
    esac
}

# section_body SECTIONKEY < CONFIG: print the lines inside that section's
# braces. Brace-counted, so it tolerates nested objects; assumes the opening
# brace sits on the section header line (pretty-printed JSONC).
section_body() {
    _sec="$1"
    _in=0
    _depth=0
    while IFS= read -r _line; do
        if [ "$_in" = 0 ]; then
            case "$_line" in
                *"\"$_sec\""*)
                    case "$_line" in *"{"*) _in=1; _depth=1 ;; esac
                    ;;
            esac
        else
            _opens=$(printf '%s' "$_line" | tr -cd '{' | wc -c | tr -d ' ')
            _closes=$(printf '%s' "$_line" | tr -cd '}' | wc -c | tr -d ' ')
            _depth=$((_depth + _opens - _closes))
            if [ "$_depth" -le 0 ]; then break; fi
            printf '%s\n' "$_line"
        fi
    done
}

# cfg_get KEY: print KEY's value from the first matching section, if any.
cfg_get() {
    _key="$1"
    if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then return 0; fi
    for _cand in $(candidate_sections); do
        _val=$(section_body "$_cand" < "$CONFIG" \
            | sed -n 's/^[[:space:]]*"'"$_key"'"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' \
            | head -n 1)
        if [ -n "$_val" ]; then
            printf '%s\n' "$_val"
            return 0
        fi
    done
}

reject_expression() {
    # $1 = key name, $2 = value
    case "$2" in
        '$('*)
            fail "config key \"$1\" is a dk value expression; run 'dk0 dialog CommonsBase_Build.Toolchain.Discover.CGlibc' to resolve it, or replace it with a literal path."
            ;;
    esac
}

CFG_CC=$(cfg_get cc)
CFG_CXX=$(cfg_get cxx)
CFG_AS=$(cfg_get as)
CFG_AR=$(cfg_get ar)
CFG_LD=$(cfg_get ld)
reject_expression cc "$CFG_CC"
reject_expression cxx "$CFG_CXX"
reject_expression as "$CFG_AS"
reject_expression ar "$CFG_AR"
reject_expression ld "$CFG_LD"

resolve() {
    # $1 = config override, $2 = PATH-resolved default name
    if [ -n "$1" ]; then
        printf '%s\n' "$1"
    else
        command -v "$2" || true
    fi
}

case "$ABI" in
    Darwin_*)
        diag "ran: xcode-select -p"
        if ! xcode-select -p >/dev/null 2>&1 || [ ! -x /usr/bin/clang ]; then
            fail "the Xcode Command Line Tools are missing; run xcode-select --install."
        fi
        DK_TC_CC=$(resolve "$CFG_CC" clang)
        DK_TC_CXX=$(resolve "$CFG_CXX" clang++)
        DK_TC_AS=$(resolve "$CFG_AS" as)
        DK_TC_AR=$(resolve "$CFG_AR" ar)
        DK_TC_LD=$(resolve "$CFG_LD" ld)
        ;;
    Linux_*_musl)
        fail "the musl cross toolchain is bundled inside the slot; this probe has nothing to discover."
        ;;
    Linux_*)
        DK_TC_CC=$(resolve "$CFG_CC" gcc)
        DK_TC_CXX=$(resolve "$CFG_CXX" g++)
        DK_TC_AS=$(resolve "$CFG_AS" as)
        DK_TC_AR=$(resolve "$CFG_AR" ar)
        DK_TC_LD=$(resolve "$CFG_LD" ld)
        diag "PATH: ${PATH:-<empty>}"
        diag "cc: ${DK_TC_CC:-<not found on PATH>}"
        diag "as: ${DK_TC_AS:-<not found on PATH>}"
        if [ -z "$DK_TC_CC" ] || [ -z "$DK_TC_AS" ]; then
            fail "this slot resolves its C toolchain from PATH; install gcc/binutils, e.g. apt install build-essential."
        fi
        DK_TC_GLIBC_VERSION=$(getconf GNU_LIBC_VERSION 2>/dev/null | sed 's/^glibc //') || DK_TC_GLIBC_VERSION=
        if [ -z "${DK_TC_GLIBC_VERSION:-}" ]; then
            DK_TC_GLIBC_VERSION=$(ldd --version 2>/dev/null | sed -n '1s/.* \([0-9][0-9.]*\)$/\1/p') || DK_TC_GLIBC_VERSION=
        fi
        ;;
    *)
        fail "no discovery rule is defined for this ABI family."
        ;;
esac

if [ -z "${DK_TC_CC:-}" ]; then
    fail "no C compiler found."
fi

# Fast path: a fresh sibling flat cache (written by the dialog) emits the
# cached environment. A stale fingerprint is a hard error so a build never
# consumes stale values; rerun the dialog to refresh.
CACHE="etc/dk/t/resolved/$ABI.env"
CURFP="${DK_TC_GLIBC_VERSION:-}"
if [ -f "$CACHE" ]; then
    CACHEFP=$(sed -n 's/^DK_TC_FINGERPRINT=//p' "$CACHE" | head -n 1)
    if [ "$CACHEFP" = "$CURFP" ]; then
        grep -v '^DK_TC_FINGERPRINT=' "$CACHE"
        exit 0
    fi
    fail "the resolved cache is stale; rerun 'dk0 dialog CommonsBase_Build.Toolchain.Discover.CGlibc'."
fi

printf 'DK_TC_CC=%s\n' "$DK_TC_CC"
[ -n "${DK_TC_CXX:-}" ] && printf 'DK_TC_CXX=%s\n' "$DK_TC_CXX"
[ -n "${DK_TC_AS:-}" ] && printf 'DK_TC_AS=%s\n' "$DK_TC_AS"
[ -n "${DK_TC_AR:-}" ] && printf 'DK_TC_AR=%s\n' "$DK_TC_AR"
[ -n "${DK_TC_LD:-}" ] && printf 'DK_TC_LD=%s\n' "$DK_TC_LD"
[ -n "${DK_TC_GLIBC_VERSION:-}" ] && printf 'DK_TC_GLIBC_VERSION=%s\n' "$DK_TC_GLIBC_VERSION"
exit 0
