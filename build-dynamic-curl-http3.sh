#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Build Script: HTTP/3-enabled curl with ngtcp2, nghttp3, and quictls (QUIC-TLS)
#
# Purpose:
#   This script builds curl with HTTP/3 support using:
#     - quictls (OpenSSL fork with QUIC support)
#     - ngtcp2 (QUIC transport implementation)
#     - nghttp3 (HTTP/3 framing)
#     - sfparse (structured field parsing used by nghttp3)
#
# Policy and rationale:
#   - BoringSSL was initially tested but failed to expose QUIC APIs
#     (SSL_set_quic_tls_cbs, etc.), making it incompatible with curl/ngtcp2.
#   - Therefore, quictls (from Cloudflare) is used instead, pinned to the
#     `OpenSSL_1_1_1w+quic` branch which exposes the required QUIC API.
#   - ngtcp2 v1.4.0 is used because it's stable and fully supports crypto backends.
#
# Key precautions:
#   - The script is idempotent: it removes any previous source and install dirs.
#   - `quictls` must be built from the correct branch; otherwise, QUIC support
#     will be silently disabled.
#   - Explicit CPPFLAGS and LDFLAGS are passed to ngtcp2's configure to ensure
#     QUIC APIs are detected and linked properly.
#
# Result:
#   - curl will be built and installed at $HOME/local/curl-http3 with QUIC support.
# ------------------------------------------------------------------------------

# 1. Define installation paths
export INSTALL_PREFIX="$HOME/local"
export WORKDIR="$INSTALL_PREFIX/src/build-http3"
export QUICTLS_INSTALL="$INSTALL_PREFIX/quictls"
export SFPARSE_INSTALL="$INSTALL_PREFIX/sfparse"
export NGHTTP3_INSTALL="$INSTALL_PREFIX/nghttp3"
export NGTCP2_INSTALL="$INSTALL_PREFIX/ngtcp2"
export CURL_INSTALL="$INSTALL_PREFIX/curl-http3"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[1/7] Installing system dependencies..."
sudo apt update
sudo apt install -y \
  git cmake build-essential \
  pkg-config libtool autoconf automake \
  libev-dev libjemalloc-dev \
  libssl-dev zlib1g-dev \
  libnghttp2-dev python3-pybind11

echo "[2/7] Building quictls (OpenSSL_1_1_1w+quic)..."
rm -rf "$WORKDIR/quictls" "$QUICTLS_INSTALL"
git clone https://github.com/quictls/openssl quictls
cd quictls
git checkout OpenSSL_1_1_1w+quic
./config --prefix="$QUICTLS_INSTALL" --libdir=lib enable-tls1_3
make -j"$(nproc)"
make install_sw

echo "[3/7] Building sfparse..."
rm -rf "$WORKDIR/sfparse" "$SFPARSE_INSTALL"
git clone --depth 1 https://github.com/ngtcp2/sfparse
cd sfparse
autoreconf -fi
./configure --prefix="$SFPARSE_INSTALL"
make -j"$(nproc)"
make install
mkdir -p "$SFPARSE_INSTALL/include/sfparse"
cp "$SFPARSE_INSTALL/include/sfparse.h" "$SFPARSE_INSTALL/include/sfparse/"

echo "[4/7] Building nghttp3 (v1.1.0)..."
rm -rf "$WORKDIR/nghttp3" "$NGHTTP3_INSTALL"
git clone --branch v1.1.0 https://github.com/ngtcp2/nghttp3
cd nghttp3
autoreconf -fi
PKG_CONFIG_PATH="$SFPARSE_INSTALL/lib/pkgconfig" \
CPPFLAGS="-I$SFPARSE_INSTALL/include" \
./configure --prefix="$NGHTTP3_INSTALL" --with-sfparse="$SFPARSE_INSTALL"
make -j"$(nproc)"
make install

echo "[5/7] Building ngtcp2 with quictls support (v1.4.0)..."
rm -rf "$WORKDIR/ngtcp2" "$NGTCP2_INSTALL"
git clone https://github.com/ngtcp2/ngtcp2
cd ngtcp2
git checkout v1.4.0
autoreconf -fi
PKG_CONFIG_PATH="$NGHTTP3_INSTALL/lib/pkgconfig:$SFPARSE_INSTALL/lib/pkgconfig" \
CPPFLAGS="-I$QUICTLS_INSTALL/include" \
LDFLAGS="-L$QUICTLS_INSTALL/lib -Wl,-rpath,$QUICTLS_INSTALL/lib" \
./configure \
  --prefix="$NGTCP2_INSTALL" \
  --with-openssl="$QUICTLS_INSTALL" \
  --with-openssl-lib="$QUICTLS_INSTALL/lib" \
  --with-openssl-include="$QUICTLS_INSTALL/include" \
  --with-nghttp3="$NGHTTP3_INSTALL" \
  --with-crypto-lib=quictls
make -j"$(nproc)"
make install

echo "[6/7] Building curl with HTTP/3 support..."
rm -rf "$WORKDIR/curl" "$CURL_INSTALL"
git clone --depth 1 https://github.com/curl/curl
cd curl
./buildconf
PKG_CONFIG_PATH="$NGTCP2_INSTALL/lib/pkgconfig:$NGHTTP3_INSTALL/lib/pkgconfig:$SFPARSE_INSTALL/lib/pkgconfig" \
LDFLAGS="-Wl,-rpath,$QUICTLS_INSTALL/lib" \
./configure \
  --prefix="$CURL_INSTALL" \
  --with-ssl="$QUICTLS_INSTALL" \
  --with-ngtcp2="$NGTCP2_INSTALL" \
  --with-nghttp3="$NGHTTP3_INSTALL" \
  --enable-alt-svc
make -j"$(nproc)"
make install

echo "[7/7] Verifying build result..."
"$CURL_INSTALL/bin/curl" -V | grep HTTP3 && echo "✅ Build succeeded."

echo "🎉 All done. curl with HTTP/3 is installed at: $CURL_INSTALL"

