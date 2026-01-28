FROM debian:trixie-slim

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
      libavif16; \
    ssl3="$(dpkg -L libssl3 | grep -m1 '/libssl\.so\.3$')"; \
    crypto3="$(dpkg -L libssl3 | grep -m1 '/libcrypto\.so\.3$')"; \
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
