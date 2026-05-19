#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
UPSTREAM_ROOT="${UPSTREAM_ROOT:-$(cd "$ARM_ROOT/../upstream-lapee" && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
HYPERBEAM_REPO="${HYPERBEAM_REPO:-https://github.com/permaweb/HyperBEAM.git}"
HYPERBEAM_VERSION="${HYPERBEAM_VERSION:-$(awk -F'\\?= ' '/^HYPERBEAM_VERSION/ {print $2; exit}' "$UPSTREAM_ROOT/buildroot-external/package/hyperbeam/hyperbeam.mk")}"
SRC_DIR="${HYPERBEAM_SRC:-$BUILD_DIR/hyperbeam-src}"
REL_DIR="$SRC_DIR/_build/lapee/rel/hb"

find_release_dir() {
    if [ -x "$REL_DIR/bin/hb" ]; then
        printf '%s\n' "$REL_DIR"
        return 0
    fi
    found=$(find "$SRC_DIR/_build" -path '*/bin/hb' -type f 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then
        chmod +x "$found" 2>/dev/null || true
        dirname "$(dirname "$found")"
        return 0
    fi
    return 1
}

mkdir -p "$BUILD_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
    git clone "$HYPERBEAM_REPO" "$SRC_DIR"
fi

git -C "$SRC_DIR" fetch --tags origin
if ! git -C "$SRC_DIR" cat-file -e "$HYPERBEAM_VERSION^{commit}" 2>/dev/null; then
    git -C "$SRC_DIR" fetch origin "$HYPERBEAM_VERSION"
fi
git -C "$SRC_DIR" checkout --detach "$HYPERBEAM_VERSION"
git -C "$SRC_DIR" submodule update --init --recursive

LAPEE_HB_OVERLAY_DIR="$UPSTREAM_ROOT/hyperbeam-overlay" \
    sh "$UPSTREAM_ROOT/scripts/stage-hyperbeam-overlay.sh" "$SRC_DIR"

if [ "${LAPEE_ARM_USE_DOWNLOADED_REBAR3:-0}" = "1" ]; then
    if [ ! -x "$SRC_DIR/rebar3" ]; then
        curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o "$SRC_DIR/rebar3"
        chmod +x "$SRC_DIR/rebar3"
    fi
    REBAR="$SRC_DIR/rebar3"
elif command -v rebar3 >/dev/null 2>&1; then
    REBAR=rebar3
else
    curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o "$SRC_DIR/rebar3"
    chmod +x "$SRC_DIR/rebar3"
    REBAR="$SRC_DIR/rebar3"
fi

if ! "$REBAR" version >/dev/null 2>&1; then
    cat >&2 <<EOF
Selected rebar3 cannot run on this Erlang/OTP install: $REBAR

If you see a BEAM/version mismatch, the rebar3 escript was built for a newer
Erlang than the Pi has. Install Raspberry Pi OS rebar3 with:
  sudo apt-get install -y rebar3

Then retry:
  LAPEE_ARM_USE_RUSTUP=1 make build
EOF
    exit 1
fi

if [ "${LAPEE_ARM_USE_RUSTUP:-0}" = "1" ] && [ -x "$HOME/.cargo/bin/cargo" ]; then
    REAL_CARGO="$HOME/.cargo/bin/cargo"
    export RUSTC="${RUSTC:-$HOME/.cargo/bin/rustc}"
elif [ -x /usr/bin/cargo ]; then
    REAL_CARGO=/usr/bin/cargo
    export RUSTC="${RUSTC:-/usr/bin/rustc}"
else
    REAL_CARGO=$(command -v cargo || true)
fi

if [ -n "${REAL_CARGO:-}" ]; then
    mkdir -p "$BUILD_DIR/.lapee-arm-bin"
    make_compiler_wrapper() {
        wrapper_name="$1"
        real_compiler="$2"
        cat > "$BUILD_DIR/.lapee-arm-bin/$wrapper_name" <<EOF
#!/usr/bin/env bash
args=()
for arg in "\$@"; do
    case "\$arg" in
        -mindirect-branch|-mindirect-branch=*|-mindirect-branch-register|-mfunction-return|-mfunction-return=*|-fcf-protection|-fcf-protection=*|-msse|-msse2|-msse3|-mssse3|-msse4|-msse4.1|-msse4.2|-mavx|-mavx2|-mavx512*)
            ;;
        *)
            args+=("\$arg")
            ;;
    esac
done
exec "$real_compiler" "\${args[@]}"
EOF
        chmod +x "$BUILD_DIR/.lapee-arm-bin/$wrapper_name"
    }
    REAL_CC=$(command -v cc || true)
    REAL_CXX=$(command -v c++ || true)
    REAL_GCC=$(command -v gcc || true)
    REAL_GXX=$(command -v g++ || true)
    [ -n "$REAL_CC" ] && make_compiler_wrapper cc "$REAL_CC"
    [ -n "$REAL_CXX" ] && make_compiler_wrapper c++ "$REAL_CXX"
    [ -n "$REAL_GCC" ] && make_compiler_wrapper gcc "$REAL_GCC"
    [ -n "$REAL_GXX" ] && make_compiler_wrapper g++ "$REAL_GXX"
    REAL_CMAKE=$(command -v cmake || true)
    if [ -n "$REAL_CMAKE" ]; then
        cat > "$BUILD_DIR/.lapee-arm-bin/cmake" <<EOF
#!/usr/bin/env bash
case " \$* " in
    *" --build "*|*" -E "*|*" --version "*|*" --help "*)
        exec "$REAL_CMAKE" "\$@"
        ;;
esac
exec "$REAL_CMAKE" \
    -DTHREADS_PREFER_PTHREAD_FLAG=ON \
    -DCMAKE_THREAD_LIBS_INIT=-pthread \
    -DCMAKE_HAVE_THREADS_LIBRARY=1 \
    -DCMAKE_USE_PTHREADS_INIT=1 \
    -DCMAKE_C_COMPILER="$BUILD_DIR/.lapee-arm-bin/cc" \
    -DCMAKE_CXX_COMPILER="$BUILD_DIR/.lapee-arm-bin/c++" \
    "\$@"
EOF
        chmod +x "$BUILD_DIR/.lapee-arm-bin/cmake"
    fi
    cat > "$BUILD_DIR/.lapee-arm-bin/cargo" <<EOF
#!/usr/bin/env bash
log="$BUILD_DIR/cargo-last.log"
{
    echo "== cargo \$(date -Iseconds) =="
    echo "cwd=\$PWD"
    echo "args: \$*"
} >> "\$log"
"$REAL_CARGO" "\$@" 2> >(tee -a "\$log" >&2)
status=\$?
echo "exit=\$status" >> "\$log"
exit "\$status"
EOF
    chmod +x "$BUILD_DIR/.lapee-arm-bin/cargo"
    export PATH="$BUILD_DIR/.lapee-arm-bin:$PATH"
    export CARGO="$BUILD_DIR/.lapee-arm-bin/cargo"
    [ -n "$REAL_CC" ] && export CC="$BUILD_DIR/.lapee-arm-bin/cc"
    [ -n "$REAL_CXX" ] && export CXX="$BUILD_DIR/.lapee-arm-bin/c++"
fi
export LAPEE_TSS2_PREFIX="${LAPEE_TSS2_PREFIX:-/usr}"
export CFLAGS="${CFLAGS:-} -Wno-error=incompatible-pointer-types"
export CXXFLAGS="${CXXFLAGS:-}"
export CMAKE_REQUIRED_FLAGS="${CMAKE_REQUIRED_FLAGS:- -pthread}"
export OPENSSL_NO_VENDOR=1
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists openssl; then
    openssl_lib_dir=$(pkg-config --variable=libdir openssl)
    openssl_include_dir=$(pkg-config --variable=includedir openssl)
    export OPENSSL_LIB_DIR="${OPENSSL_LIB_DIR:-$openssl_lib_dir}"
    export OPENSSL_INCLUDE_DIR="${OPENSSL_INCLUDE_DIR:-$openssl_include_dir}"
fi
export DIAGNOSTIC="${DIAGNOSTIC:-1}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
export LAPEE_ARM_STUB_SNP_NIF="${LAPEE_ARM_STUB_SNP_NIF:-1}"

rustc_cmd="${RUSTC:-rustc}"
rustc_version=$("$rustc_cmd" --version 2>/dev/null | awk '{print $2}')
rustc_major=${rustc_version%%.*}
rustc_rest=${rustc_version#*.}
rustc_minor=${rustc_rest%%.*}
if [ -z "$rustc_version" ] || [ "$rustc_major" -lt 1 ] || { [ "$rustc_major" -eq 1 ] && [ "$rustc_minor" -lt 91 ]; }; then
    cat >&2 <<EOF
Rust $rustc_version from $rustc_cmd is too old for this HyperBEAM/LapEE build.
Required: rustc >= 1.91.

On Raspberry Pi OS, install rustup and retry with:
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  . "\$HOME/.cargo/env"
  rustup default stable
  LAPEE_ARM_USE_RUSTUP=1 make build
EOF
    exit 1
fi

cd "$SRC_DIR"
if [ "$LAPEE_ARM_STUB_SNP_NIF" = "1" ] && [ -f src/dev_snp_nif.erl ]; then
    cp src/dev_snp_nif.erl src/dev_snp_nif.erl.lapee-arm.bak
    cat > src/dev_snp_nif.erl <<'EOF'
-module(dev_snp_nif).
-export([supported/0, report/2]).

supported() ->
    {ok, false}.

report(_ReportData, _VMPL) ->
    {error, snp_nif_disabled_on_lapee_arm}.
EOF
fi
"$REBAR" as lapee compile
"$REBAR" as lapee release

REL_DIR=$(find_release_dir) || {
    echo "HyperBEAM release command finished, but no rel/hb/bin/hb was found under $SRC_DIR/_build." >&2
    exit 1
}
echo "HyperBEAM ARM release built at $REL_DIR"
