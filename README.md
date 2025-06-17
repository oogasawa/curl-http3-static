
# curl-http3-static

This repository provides a fully statically linked version of `curl` with HTTP/3 (QUIC) support,
as well as a dynamically linked variant — both built from source.

## Contents

- `curl` — statically linked binary with HTTP/3 support
- `build-static-curl-http3.sh` — script to build the static curl binary
- `build-dynamic-curl-http3.sh` — script to build the dynamically linked version (shared libraries)
- `README.md` — this file

## Features

- HTTP/3 (QUIC) support via [ngtcp2](https://github.com/ngtcp2/ngtcp2) and [nghttp3](https://github.com/ngtcp2/nghttp3)
- Built against [quictls](https://github.com/quictls/openssl) (`OpenSSL_1_1_1w+quic` branch)
- Fully static or dynamically linked builds
- No root required to run the resulting binary

## Requirements

- Tested on **Ubuntu Linux 24.04**
- x86_64 architecture
- For build: basic development tools (`build-essential`, `autoconf`, `libtool`, etc.)
- No root privileges are required to run the final binary

## Usage (Static binary)

```bash
chmod +x ./curl
./curl --http3 https://example.com
````

## Example: Test HTTP/3 connection

```bash
./curl --http3-only -I https://cloudflare-quic.com
```

or 

```bash
./curl --http3 -I https://cloudflare-quic.com
```

Output should include:

```
< HTTP/3 200
```

## Build It Yourself

### Static version

To build the **statically linked** curl binary:

```bash
./build-static-curl-http3.sh
```

This will:

- Build `quictls`, `sfparse`, `nghttp3`, `ngtcp2` with `--enable-static`
- Build `curl` with `--enable-static` and `LDFLAGS=-static`
- Produce a standalone `curl` binary under:

```
$HOME/local-static/curl-http3-static/bin/curl
```

### Dynamic version

To build the **dynamically linked** curl binary (linked to `.so` libraries):

```bash
./build-dynamic-curl-http3.sh
```

This will:

- Build the same dependencies with shared libraries
- Produce a smaller binary linked against `.so` files
- Output goes to:

```
$HOME/local/curl-http3/bin/curl
```

## Distribution

The static `curl` binary can be distributed and run as a **single portable executable** without root or external dependencies.

## Caveats

- Optional libraries such as `libidn2`, `brotli`, `zstd`, and `libpsl` are intentionally omitted to simplify static linking
- Built for Ubuntu 24.04 or newer; older distros may lack required toolchain or glibc compatibility
- Not intended as a system-wide replacement for `curl`

## License

Follows the licensing of the original [curl](https://curl.se/docs/copyright.html) project (MIT-like). See included license files for third-party components.



