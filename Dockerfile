# Pinned so the runtime libraries stay in step with .ide/Dockerfile, which
# builds the binary. Bump both digests together.
FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    LANG=C.UTF-8

# Small bootstrap layer for the font download. Keeping it before the main
# runtime layer means runtime package changes do not re-download the 50MB font
# archive. curl is also a runtime dependency; unzip is negligible.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    install -d /usr/local/share/fonts/harmonyos; \
    curl -fsSL "https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip" -o /tmp/HarmonyOS-Sans.zip; \
    echo "fb02c86e358cd9aad8d4dfa957ee502381e7ee2e94499a9133add4324b6ce69a  /tmp/HarmonyOS-Sans.zip" | sha256sum -c -; \
    unzip -j /tmp/HarmonyOS-Sans.zip \
      "HarmonyOS Sans/HarmonyOS_Sans/HarmonyOS_Sans_Regular.ttf" \
      "HarmonyOS Sans/HarmonyOS_Sans_SC/HarmonyOS_Sans_SC_Regular.ttf" \
      -d /usr/local/share/fonts/harmonyos; \
    rm -f /tmp/HarmonyOS-Sans.zip

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ffmpeg \
      fontconfig \
      fonts-dejavu-core \
      fonts-droid-fallback \
      ghostscript \
      imagemagick \
      libmagickcore-7.q16-10-extra \
      libarchive13t64 \
      libargon2-1 \
      libavif16 \
      libbrotli1 \
      libheif1 \
      libheif-plugin-aomenc \
      libpq5 \
      libssl3t64 \
      librocksdb9.11 \
      libmimalloc3 \
      libvips42t64 \
      tzdata; \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime; \
    echo $TZ > /etc/timezone; \
    rm -rf /var/lib/apt/lists/*

RUN fc-cache -f

# The Cangjie runtime dlopen()s the unversioned sonames, which only the -dev
# packages normally provide. Link them explicitly instead of guessing with
# `dpkg -S | head -n1`. `dpkg-architecture` lives in dpkg-dev, which is not
# installed here, so take the paths from the package file list.
RUN set -eux; \
    ssl3="$(dpkg -L libssl3t64 | grep -m1 '/libssl\.so\.3$')"; \
    crypto3="$(dpkg -L libssl3t64 | grep -m1 '/libcrypto\.so\.3$')"; \
    ln -sf "$ssl3" "$(dirname "$ssl3")/libssl.so"; \
    ln -sf "$crypto3" "$(dirname "$crypto3")/libcrypto.so"; \
    ldconfig

WORKDIR /app

COPY --chmod=0755 ./app /app

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fsS -o /dev/null "http://127.0.0.1:${PORT:-8082}/" || exit 1

# Keep the allocator override on the app process instead of the image
# environment, so healthchecks and docker exec stay on the system allocator.
CMD ["/usr/bin/env", "LD_PRELOAD=libmimalloc.so.3", "/app/main"]
