FROM docker.1ms.run/ubuntu

WORKDIR /app

RUN apt-get update && \
    apt-get install -y libarchive-tools imagemagick tzdata openssl && \
    rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/app

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY ./app .

RUN chmod +x /app/main

CMD ["/app/main"]