FROM ubuntu:latest

WORKDIR /app

RUN set -eux; \
    apt-get update; \
    apt-get install -y \
      ca-certificates \
      curl \
      ffmpeg \
      fontconfig \
      ghostscript \
      imagemagick \
      libarchive13 \
      libavif16 \
      libheif1 \
      libssl3 \
      librocksdb8.9 \
      libvips \
      tzdata \
      unzip; \
    mkdir -p /usr/local/share/fonts/harmonyos; \
    curl -fsSL "https://developer.huawei.com/images/download/general/HarmonyOS-Sans.zip" -o /tmp/HarmonyOS-Sans.zip; \
    unzip -j /tmp/HarmonyOS-Sans.zip \
      "HarmonyOS Sans/HarmonyOS_Sans/HarmonyOS_Sans_Regular.ttf" \
      "HarmonyOS Sans/HarmonyOS_Sans_SC/HarmonyOS_Sans_SC_Regular.ttf" \
      -d /usr/local/share/fonts/harmonyos; \
    rm -f /tmp/HarmonyOS-Sans.zip; \
    fc-cache -f; \
    ssl3="$(dpkg -S 'libssl.so.3' | head -n1 | sed 's/.*: //')"; \
    crypto3="$(dpkg -S 'libcrypto.so.3' | head -n1 | sed 's/.*: //')"; \
    ln -sf "${ssl3}" "$(dirname "${ssl3}")/libssl.so"; \
    ln -sf "${crypto3}" "$(dirname "${crypto3}")/libcrypto.so"; \
    rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/app:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
ENV PATH="/app/bin:${PATH}"

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY ./app .

RUN chmod +x /app/main

CMD ["/app/main"]
