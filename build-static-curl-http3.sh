#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Build statically-linked curl with HTTP/3 (QUIC) support
# Output: A single binary curl with no external .so dependencies (fat binary)
# ------------------------------------------------------------------------------

# 1. Path setup
export INSTALL_PREFIX="$HOME/local-static"
export WORKDIR="$INSTALL_PREFIX/src/build-static"
export QUICTLS_INSTALL="$INSTALL_PREFIX/quictls"
export SFPARSE_INSTALL="$INSTALL_PREFIX/sfparse"
export NGHTTP3_INSTALL="$INSTALL_PREFIX/nghttp3"
export NGTCP2_INSTALL="$INSTALL_PREFIX/ngtcp2"
export CURL_INSTALL="$INSTALL_PREFIX/curl-http3-static"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[1/7] Installing system dependencies..."
sudo apt update
sudo apt install -y \
  git cmake build-essential \
  pkg-config libtool autoconf automake \
  libev-dev libjemalloc-dev \
  zlib1g-dev python3-pybind11

echo "[2/7] Building static quictls (OpenSSL_1_1_1w+quic)..."
rm -rf quictls "$QUICTLS_INSTALL"
git clone https://github.com/quictls/openssl quictls
cd quictls
git checkout OpenSSL_1_1_1w+quic
./config no-shared --prefix="$QUICTLS_INSTALL" --libdir=lib enable-tls1_3
make -j"$(nproc)"
make install_sw
cd "$WORKDIR"

echo "[3/7] Building static sfparse..."
rm -rf sfparse "$SFPARSE_INSTALL"
git clone --depth 1 https://github.com/ngtcp2/sfparse
cd sfparse
autoreconf -fi
./configure --prefix="$SFPARSE_INSTALL" --enable-static --disable-shared
make -j"$(nproc)"
make install
mkdir -p "$SFPARSE_INSTALL/include/sfparse"
cp "$SFPARSE_INSTALL/include/sfparse.h" "$SFPARSE_INSTALL/include/sfparse/"
cd "$WORKDIR"

echo "[4/7] Building static nghttp3 (v1.1.0)..."
rm -rf nghttp3 "$NGHTTP3_INSTALL"
git clone --branch v1.1.0 https://github.com/ngtcp2/nghttp3
cd nghttp3
autoreconf -fi
PKG_CONFIG_PATH="$SFPARSE_INSTALL/lib/pkgconfig" \
CPPFLAGS="-I$SFPARSE_INSTALL/include" \
./configure --prefix="$NGHTTP3_INSTALL" \
            --with-sfparse="$SFPARSE_INSTALL" \
            --enable-static --disable-shared
make -j"$(nproc)"
make install
cd "$WORKDIR"

echo "[5/7] Building static ngtcp2 with quictls (v1.4.0)..."
rm -rf ngtcp2 "$NGTCP2_INSTALL"
git clone https://github.com/ngtcp2/ngtcp2
cd ngtcp2
git checkout v1.4.0
autoreconf -fi
PKG_CONFIG_PATH="$NGHTTP3_INSTALL/lib/pkgconfig:$SFPARSE_INSTALL/lib/pkgconfig" \
CPPFLAGS="-I$QUICTLS_INSTALL/include" \
LDFLAGS="-L$QUICTLS_INSTALL/lib" \
./configure --prefix="$NGTCP2_INSTALL" \
  --with-openssl="$QUICTLS_INSTALL" \
  --with-openssl-lib="$QUICTLS_INSTALL/lib" \
  --with-openssl-include="$QUICTLS_INSTALL/include" \
  --with-nghttp3="$NGHTTP3_INSTALL" \
  --with-crypto-lib=quictls \
  --enable-static --disable-shared
make -j"$(nproc)"
make install
cd "$WORKDIR"

echo "[6/7] Building statically linked curl with HTTP/3..."
rm -rf curl "$CURL_INSTALL"
git clone --depth 1 https://github.com/curl/curl
cd curl
./buildconf
PKG_CONFIG_PATH="$NGTCP2_INSTALL/lib/pkgconfig:$NGHTTP3_INSTALL/lib/pkgconfig:$SFPARSE_INSTALL/lib/pkgconfig" \
LDFLAGS="-static -L$QUICTLS_INSTALL/lib" \
CPPFLAGS="-I$QUICTLS_INSTALL/include" \
./configure \
  --prefix="$CURL_INSTALL" \
  --with-ssl="$QUICTLS_INSTALL" \
  --with-ngtcp2="$NGTCP2_INSTALL" \
  --with-nghttp3="$NGHTTP3_INSTALL" \
  --enable-alt-svc \
  --enable-static --disable-shared \
  --disable-libcurl-option \
  --without-libpsl \
  --without-zstd --without-brotli --without-libidn2 --without-librtmp
make -j"$(nproc)"
make install
cd "$WORKDIR"

echo "[7/7] Verifying static curl..."
file "$CURL_INSTALL/bin/curl"
"$CURL_INSTALL/bin/curl" -V | grep HTTP3 && echo "✅ Static build succeeded."
