# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM docker.io/rust:latest AS builder

WORKDIR /app

# Cache dependencies as a separate layer
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

# Build actual source
COPY src ./src
RUN cargo build --release


# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/app /usr/local/bin/app

USER nobody

EXPOSE 8080
CMD ["app"]
