#!/bin/sh
# CommonsBase_Build.Toolchain.Discover.CGlibc probe.
#
# Provider contract (see CommonsBase_Build dk.u, "Toolchain discovery"):
#   discover.sh --abi <TARGET_ABI> [--config <path>]
# Emits UTF-8 LF KEY=VALUE lines on stdout. On failure exits nonzero with a
# one-line stderr message naming the per-ABI contract.
#
# Configuration precedence: --config path, else the project-level
# etc/dk/t/toolchains.jsonc under the current directory, else the
# user/machine-level ${XDG_CONFIG_HOME:-$HOME/.config}/dk/toolchains.jsonc,
# else the host probe.
#
# DRAFT limitation (pending the dk0 dialog rule): config keys are read with
# a line-oriented scan, one "key": "value" pair per line, blind to which
# toolchains section a key sits in. A value beginning with $( is a dk value
# expression and must be resolved by
# `dk0 dialog CommonsBase_Build.Toolchain.Discover.CGlibc` or replaced with
# a literal path.
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

if [ -z "$CONFIG" ]; then
    if [ -f "etc/dk/t/toolchains.jsonc" ]; then
        CONFIG="etc/dk/t/toolchains.jsonc"
    elif [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/dk/toolchains.jsonc" ]; then
        CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dk/toolchains.jsonc"
    fi
fi

# cfg_get KEY: print the last "KEY": "VALUE" occurrence in $CONFIG, if any.
cfg_get() {
    if [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; then
        sed -n 's/^[[:space:]]*"'"$1"'"[[:space:]]*:[[:space:]]*"\(.*\)".*$/\1/p' "$CONFIG" | tail -n 1
    fi
}

reject_expression() {
    # $1 = key name, $2 = value
    case "$2" in
        '$('*)
            echo "dk toolchain: Release.$ABI: config key \"$1\" is a dk value expression; run 'dk0 dialog CommonsBase_Build.Toolchain.Discover.CGlibc' to resolve it, or replace it with a literal path. $contract_see" >&2
            exit 1
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
        if ! xcode-select -p >/dev/null 2>&1 || [ ! -x /usr/bin/clang ]; then
            echo "dk toolchain: Release.$ABI: the Xcode Command Line Tools are missing; run xcode-select --install. $contract_see" >&2
            exit 1
        fi
        DK_TC_CC=$(resolve "$CFG_CC" clang)
        DK_TC_CXX=$(resolve "$CFG_CXX" clang++)
        DK_TC_AS=$(resolve "$CFG_AS" as)
        DK_TC_AR=$(resolve "$CFG_AR" ar)
        DK_TC_LD=$(resolve "$CFG_LD" ld)
        ;;
    Linux_*_musl)
        echo "dk toolchain: Release.$ABI: the musl cross toolchain is bundled inside the slot; this probe has nothing to discover. $contract_see" >&2
        exit 1
        ;;
    Linux_*)
        DK_TC_CC=$(resolve "$CFG_CC" gcc)
        DK_TC_CXX=$(resolve "$CFG_CXX" g++)
        DK_TC_AS=$(resolve "$CFG_AS" as)
        DK_TC_AR=$(resolve "$CFG_AR" ar)
        DK_TC_LD=$(resolve "$CFG_LD" ld)
        if [ -z "$DK_TC_CC" ] || [ -z "$DK_TC_AS" ]; then
            echo "dk toolchain: Release.$ABI: this slot resolves its C toolchain from PATH; install gcc/binutils, e.g. apt install build-essential. $contract_see" >&2
            exit 1
        fi
        DK_TC_GLIBC_VERSION=$(getconf GNU_LIBC_VERSION 2>/dev/null | sed 's/^glibc //') || DK_TC_GLIBC_VERSION=
        if [ -z "${DK_TC_GLIBC_VERSION:-}" ]; then
            DK_TC_GLIBC_VERSION=$(ldd --version 2>/dev/null | sed -n '1s/.* \([0-9][0-9.]*\)$/\1/p') || DK_TC_GLIBC_VERSION=
        fi
        ;;
    *)
        echo "dk toolchain: Release.$ABI: no discovery rule is defined for this ABI family. $contract_see" >&2
        exit 1
        ;;
esac

if [ -z "${DK_TC_CC:-}" ]; then
    echo "dk toolchain: Release.$ABI: no C compiler found. $contract_see" >&2
    exit 1
fi

printf 'DK_TC_CC=%s\n' "$DK_TC_CC"
[ -n "${DK_TC_CXX:-}" ] && printf 'DK_TC_CXX=%s\n' "$DK_TC_CXX"
[ -n "${DK_TC_AS:-}" ] && printf 'DK_TC_AS=%s\n' "$DK_TC_AS"
[ -n "${DK_TC_AR:-}" ] && printf 'DK_TC_AR=%s\n' "$DK_TC_AR"
[ -n "${DK_TC_LD:-}" ] && printf 'DK_TC_LD=%s\n' "$DK_TC_LD"
[ -n "${DK_TC_GLIBC_VERSION:-}" ] && printf 'DK_TC_GLIBC_VERSION=%s\n' "$DK_TC_GLIBC_VERSION"
exit 0
