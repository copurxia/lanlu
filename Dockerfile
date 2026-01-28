FROM debian:bookworm-slim

WORKDIR /app

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      ffmpeg \
      ghostscript \
      imagemagick \
      tzdata \
      libssl3 \
      libarchive13 \
      libavif15; \
    arch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"; \
    ln -sf "/usr/lib/${arch}/libssl.so.3" "/usr/lib/${arch}/libssl.so"; \
    ln -sf "/usr/lib/${arch}/libcrypto.so.3" "/usr/lib/${arch}/libcrypto.so"; \
    rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/app:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
ENV PATH="/app/bin:${PATH}"

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY ./app .

RUN chmod +x /app/main /app/bin/deno

CMD ["/app/main"]
