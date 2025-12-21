FROM docker.1ms.run/ubuntu

WORKDIR /app

RUN apt-get update && \
    apt-get install -y libarchive-tools imagemagick tzdata libssl-dev curl unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Deno
RUN curl -fsSL https://deno.land/install.sh | sh

ENV LD_LIBRARY_PATH=/app:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
ENV PATH="/root/.deno/bin:${PATH}"

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY ./app .

RUN chmod +x /app/main

CMD ["/app/main"]