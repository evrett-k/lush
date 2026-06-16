virtualisation.docker.enable = true;

FROM rust:alpine AS builder

RUN apk add --no-cache \
    musl-dev \
    musl-utils \
    gcc \
    g++ \
    make \
    cmake \
    pkgconf \
    openssl-dev \
    openssl-libs-static \
    lua5.4-dev \
    perl \
    linux-headers \
    curl \
    git \
    zip \
    unzip

RUN rustup component add rustfmt clippy && \
    rustup target add \
        x86_64-unknown-linux-musl \
        i686-unknown-linux-musl \
        aarch64-unknown-linux-musl

RUN cargo install cross --locked 2>/dev/null || true

WORKDIR /src

ENV OPENSSL_STATIC=1
ENV OPENSSL_DIR=/usr
ENV PKG_CONFIG_ALL_STATIC=1
ENV RUSTFLAGS="-C target-feature=+crt-static"

CMD ["cargo", "build", "--release"]
