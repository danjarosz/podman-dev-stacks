# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM docker.io/eclipse-temurin:21 AS builder

WORKDIR /app

COPY pom.xml ./
COPY src ./src

RUN apt-get update && apt-get install -y maven \
  && mvn package -DskipTests \
  && rm -rf /var/lib/apt/lists/*


# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM docker.io/eclipse-temurin:21-jre AS runtime

WORKDIR /app

COPY --from=builder /app/target/app.jar ./app.jar

USER nobody

EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
