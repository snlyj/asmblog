# Stage 1: Assemble & statically link pure x86-64 ELF binary (zero libc)
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends binutils && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY build.sh ./
COPY src/ ./src/

RUN bash build.sh --strip && ls -lh /src/asmblog

# Stage 2: Ultra-minimal FROM scratch image (~74 KiB binary layer!)
FROM scratch

COPY --from=builder /src/asmblog /asmblog

WORKDIR /site
EXPOSE 8080

ENTRYPOINT ["/asmblog"]
CMD ["serve", "-d", "/site"]
