FROM ubuntu:latest

WORKDIR /app

RUN set -eux; \
    apt-get update; \
    apt-get install -y \
      ca-certificates \
      ffmpeg \
      ghostscript \
      imagemagick \
      tzdata \
      libssl3 \
      libarchive13 \
      libavif16; \
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

RUN chmod +x /app/main /app/bin/deno

CMD ["/app/main"]
