FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
# xmake refuses to run as root unless explicitly allowed. CNB build containers run as root by default.
ENV XMAKE_ROOT=y

SHELL ["/bin/bash", "-lc"]

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates curl git wget unzip zip xz-utils \
    build-essential clang ninja-build \
    libarchive-dev libavif-dev; \
  rm -rf /var/lib/apt/lists/*

# Install Node.js 20 from official tarball (avoid apt pulling tzdata/python chain in minimal containers).
RUN set -eux; \
  NODE_VERSION="20.20.0"; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) node_arch="x64" ;; \
    arm64) node_arch="arm64" ;; \
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
  tar -xJf "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -C /usr/local --strip-components=1; \
  rm -f "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
  node -v; \
  npm -v

# Install pnpm via corepack (bundled with Node.js).
RUN set -eux; \
  corepack enable; \
  corepack prepare pnpm@10.27.0 --activate; \
  pnpm -v

# Install xmake from official GitHub release tarball (Ubuntu PPA doesn't apply to Debian).
RUN set -eux; \
  XMAKE_VERSION="2.9.8"; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    amd64) xmake_arch="x86_64" ;; \
    arm64) xmake_arch="aarch64" ;; \
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSLO "https://github.com/xmake-io/xmake/releases/download/v${XMAKE_VERSION}/xmake-v${XMAKE_VERSION}.linux.${xmake_arch}.tar.gz"; \
  tar -xzf "xmake-v${XMAKE_VERSION}.linux.${xmake_arch}.tar.gz"; \
  rm -f "xmake-v${XMAKE_VERSION}.linux.${xmake_arch}.tar.gz"; \
  mv "xmake-v${XMAKE_VERSION}.linux.${xmake_arch}" /opt/xmake; \
  ln -sf /opt/xmake/xmake /usr/local/bin/xmake; \
  xmake --version
