FROM docker.1ms.run/ubuntu

WORKDIR /app

# 配置清华镜像源（兼容 Ubuntu 24.04+ 的 DEB822 格式）
RUN apt-get update && \
    apt-get install -y ffmpeg ghostscript imagemagick tzdata libssl-dev libarchive13 libavif16 && \
    rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/app:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
ENV PATH="/app/bin:${PATH}"

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY ./app .

RUN chmod +x /app/main /app/bin/deno

CMD ["/app/main"]
