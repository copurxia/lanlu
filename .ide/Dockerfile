FROM ubuntu:latest

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
    libarchive-dev libavif-dev \
    gnupg dirmngr; \
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

# Install xmake via apt. If not in the base repo, add the official xmake PPA (still apt-based).
RUN set -eux; \
  if ! command -v xmake >/dev/null 2>&1; then \
    apt-get update; \
    if ! apt-get install -y --no-install-recommends xmake; then \
      codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"; \
      : "${codename:=jammy}"; \
      mkdir -p /etc/apt/keyrings; \
      curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xC8CA50B566BFBA052B13B9A770AF26A4DCBD1EB4" \
        | gpg --dearmor -o /etc/apt/keyrings/xmake-io-xmake.gpg; \
      echo "deb [signed-by=/etc/apt/keyrings/xmake-io-xmake.gpg] http://ppa.launchpad.net/xmake-io/xmake/ubuntu ${codename} main" \
        > /etc/apt/sources.list.d/xmake-io-xmake.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends xmake; \
    fi; \
    rm -rf /var/lib/apt/lists/*; \
  fi; \
  xmake --version
