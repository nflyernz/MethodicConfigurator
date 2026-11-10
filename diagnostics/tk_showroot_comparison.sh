#!/usr/bin/env bash
# Build and compare Tk with and without the upstream showRootWindow fix.
#
# This file is part of ArduPilot Methodic Configurator. https://github.com/ArduPilot/MethodicConfigurator
#
# SPDX-FileCopyrightText: 2026 nflyernz <319460892+nflyernz@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

diag="$RUNNER_TEMP/amc-tk-showroot-comparison"
mkdir -p "$diag"
trap 'printf "%s\n" "$?" > "$diag/harness-exit.txt"' EXIT

tcl_revision=c655b4770b1d6d32a8cbffd6cef59db6029fe19e
tk_base=5c4fbcaf12ea3698db82f56bcd138ea36a1af43b
tk_backport=b2158f7aa04233f31a6e3ba30fe936b951f0af36
patch_sha=5d9d33ac758b9a28300537af37e503acd9166296b070e42e6cbf6d36025a1842
script=diagnostics/tk_root_idle_reproducer.py
work="$RUNNER_TEMP/amc-tk-showroot-build"
mkdir -p "$work"

{
    printf 'Tcl source: %s\nTk pre-fix source: %s\nTk backport source: %s\n' \
        "$tcl_revision" "$tk_base" "$tk_backport"
    printf 'Patch: only macosx/tkMacOSXInit.c from the Tk 9.0 backport\n'
    printf 'Patch SHA-256: %s\n' "$patch_sha"
    printf 'Platform: %s %s\n' "$(sw_vers -productVersion)" "$(uname -m)"
    xcodebuild -version
    clang --version
    uv --version
} > "$diag/build-environment.txt" 2>&1
test "$(uname -m)" = arm64

uv python install 3.15.2 > "$diag/uv-install.log" 2>&1
python_executable=$(uv python find --managed-python 3.15.2)
python_executable=$(realpath "$python_executable")
export PYTHONFAULTHANDLER=1 PYTHONUNBUFFERED=1
{
    printf 'Python executable: %s\n' "$python_executable"
    "$python_executable" - <<'PY'
import _tkinter
import os
import sys
import tkinter

print('Python:', sys.version)
print('Python real path:', os.path.realpath(sys.executable))
print('_tkinter:', _tkinter.__file__)
print('_tkinter real path:', os.path.realpath(_tkinter.__file__))
print('Compiled Tcl:', _tkinter.TCL_VERSION)
print('Compiled Tk:', _tkinter.TK_VERSION)
interp = tkinter.Tcl()
print('Runtime Tcl:', interp.call('info', 'patchlevel'))
PY
    /usr/bin/otool -L "$python_executable"
    tkinter_binary=$("$python_executable" -c 'import _tkinter; print(_tkinter.__file__)')
    /usr/bin/otool -L "$tkinter_binary"
    /usr/bin/otool -l "$tkinter_binary" | grep -A3 LC_RPATH || :
    shasum -a 256 "$python_executable" "$tkinter_binary"
} > "$diag/python-runtime.txt" 2>&1
tkinter_binary=$("$python_executable" -c 'import _tkinter; print(_tkinter.__file__)')
grep -F 'Runtime Tcl: 9.0.4' "$diag/python-runtime.txt" > /dev/null
grep -F '@rpath/libtcl9tk9.0.dylib' "$diag/python-runtime.txt" > /dev/null
grep -F '@rpath/libtcl9.0.dylib' "$diag/python-runtime.txt" > /dev/null
uv_tcl=$(realpath "$(dirname "$(dirname "$(dirname "$tkinter_binary")")")/libtcl9.0.dylib")
test -f "$uv_tcl"
shasum -a 256 "$uv_tcl" > "$diag/tcl-binary-sha256.txt"
/usr/bin/otool -L "$uv_tcl" > "$diag/tcl-binary-links.txt"

git clone --filter=blob:none --single-branch --branch core-9-0-4 \
    https://github.com/tcltk/tcl.git "$work/tcl-source" > "$diag/tcl-clone.log" 2>&1
test "$(git -C "$work/tcl-source" rev-parse HEAD)" = "$tcl_revision"
git clone --filter=blob:none --no-checkout \
    https://github.com/tcltk/tk.git "$work/tk-source" > "$diag/tk-clone.log" 2>&1
git -C "$work/tk-source" checkout --detach "$tk_base" > "$diag/tk-checkout.log" 2>&1
test "$(git -C "$work/tk-source" rev-parse HEAD)" = "$tk_base"
git -C "$work/tk-source" merge-base --is-ancestor "$tk_base" "$tk_backport"
git -C "$work/tk-source" show -s --format=fuller "$tk_base" "$tk_backport" \
    > "$diag/tk-source-commits.txt"
git -C "$work/tk-source" diff --stat "$tk_base" "$tk_backport" \
    > "$diag/full-backport-stat.txt"
git -C "$work/tk-source" diff --no-color --no-ext-diff --no-textconv \
    --binary "$tk_base" "$tk_backport" -- \
    macosx/tkMacOSXInit.c > "$diag/showroot-lifecycle.patch"
printf '%s  %s\n' "$patch_sha" "$diag/showroot-lifecycle.patch" | shasum -a 256 --check
git -C "$work/tk-source" apply --check "$diag/showroot-lifecycle.patch"
grep -F 'package require -exact tk  9.0.5' \
    "$work/tk-source/library/tk.tcl" > /dev/null
cp -R "$work/tk-source" "$work/tk-patched-source"
git -C "$work/tk-patched-source" apply "$diag/showroot-lifecycle.patch"
test "$(git -C "$work/tk-patched-source" status --porcelain)" = \
    ' M macosx/tkMacOSXInit.c'
git -C "$work/tk-patched-source" diff -- macosx/tkMacOSXInit.c \
    > "$diag/patched-source.diff"
cmp "$diag/showroot-lifecycle.patch" "$diag/patched-source.diff"
shasum -a 256 "$script" > "$diag/reproducer-sha256.txt"
cp "$script" "$diag/tk_root_idle_reproducer.py"

mkdir -p "$work/tcl-build" "$work/tk-unpatched-build" "$work/tk-patched-build"
(
    cd "$work/tcl-build"
    "$work/tcl-source/unix/configure" --enable-shared \
        --prefix="$work/install" > "$diag/tcl-configure.log" 2>&1
    make -j4 > "$diag/tcl-make.log" 2>&1
)
printf '%s\n' "$work/tcl-source/unix/configure --enable-shared --prefix=$work/install" \
    'make -j4' > "$diag/tcl-build-command.txt"

for variant in unpatched patched; do
    source_dir="$work/tk-source"
    if [ "$variant" = patched ]; then
        source_dir="$work/tk-patched-source"
    fi
    build_dir="$work/tk-$variant-build"
    (
        cd "$build_dir"
        "$source_dir/unix/configure" --enable-shared --enable-aqua \
            --with-tcl="$work/tcl-build" --prefix="$work/install" \
            > "$diag/tk-$variant-configure.log" 2>&1
        make -j4 > "$diag/tk-$variant-make.log" 2>&1
    )
    printf '%s\n' \
        "$source_dir/unix/configure --enable-shared --enable-aqua --with-tcl=$work/tcl-build --prefix=$work/install" \
        'make -j4' > "$diag/tk-$variant-build-command.txt"
    binary="$build_dir/libtcl9tk9.0.dylib"
    test -f "$binary"
    shasum -a 256 "$binary" > "$diag/tk-$variant-sha256.txt"
    /usr/bin/otool -L "$binary" > "$diag/tk-$variant-links.txt"
    /usr/bin/otool -D "$binary" > "$diag/tk-$variant-install-name.txt"
    /usr/bin/dwarfdump --uuid "$binary" > "$diag/tk-$variant-uuid.txt"
done

for trial in W1 W2; do
    variant=unpatched
    if [ "$trial" = W2 ]; then variant=patched; fi
    build_dir="$work/tk-$variant-build"
    binary="$build_dir/libtcl9tk9.0.dylib"
    printf 'DYLD_LIBRARY_PATH=%q TK_LIBRARY=%q %q -X faulthandler -u %q no-withdraw\n' \
        "$build_dir" "$work/tk-source/library" "$python_executable" "$script" \
        > "$diag/$trial-command.txt"
    set +e
    DYLD_LIBRARY_PATH="$build_dir" \
        DYLD_PRINT_LIBRARIES=1 \
        TK_LIBRARY="$work/tk-source/library" \
        "$python_executable" -X faulthandler -u "$script" no-withdraw \
        > "$diag/$trial-stdout.log" 2> "$diag/$trial-stderr.log"
    trial_status=$?
    set -e
    printf '%s\n' "$trial_status" > "$diag/$trial-exit.txt"
    printf 'Tk version: 9.0.5; Tcl version: 9.0.4; variant: %s\n' "$variant" \
        > "$diag/$trial-intended-runtime.txt"
    if grep -F "$binary" "$diag/$trial-stderr.log" > "$diag/$trial-loaded-tk.txt" \
        && grep -F "$uv_tcl" "$diag/$trial-stderr.log" > "$diag/$trial-loaded-tcl.txt" \
        && grep -F "$tkinter_binary" "$diag/$trial-stderr.log" \
            > "$diag/$trial-loaded-tkinter.txt"; then
        printf 'verified: intended Tk, unchanged Tcl, and unchanged _tkinter loaded\n' \
            > "$diag/$trial-library-verification.txt"
    else
        printf 'UNVERIFIED: inspect dyld stderr before interpreting this trial\n' \
            > "$diag/$trial-library-verification.txt"
    fi
    report_dir="$HOME/Library/Logs/DiagnosticReports"
    if [ -d "$report_dir" ]; then
        mkdir -p "$diag/$trial-crash-reports"
        find "$report_dir" -maxdepth 1 -type f \
            \( -name 'python*.ips' -o -name 'python*.crash' \) -mmin -5 \
            -exec cp {} "$diag/$trial-crash-reports/" \; || :
    fi
    printf '%s: exit %s, %s\n' "$trial" "$trial_status" "$variant"
done

git status --short > "$diag/repository-status.txt"
git diff HEAD -- > "$diag/repository-tracked.diff"
test ! -s "$diag/repository-tracked.diff"
if grep -q '^UNVERIFIED:' "$diag/W1-library-verification.txt" \
    || grep -q '^UNVERIFIED:' "$diag/W2-library-verification.txt"; then
    printf '%s\n' 'Binary-loading verification failed; do not interpret trial outcomes.' \
        > "$diag/comparison-status.txt"
    exit 1
fi
printf '%s\n' 'Both trials loaded their intended Tk and the same uv Tcl and _tkinter.' \
    > "$diag/comparison-status.txt"
