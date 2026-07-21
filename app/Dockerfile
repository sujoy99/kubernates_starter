# --- Stage 1: build the jar ---
# Full Maven + JDK image. Only exists during the build; none of its bulk
# (Maven itself, the JDK's compiler, cached dependencies) ends up in the
# final image.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

# Copy the pom first and download dependencies as their own layer.
# Docker caches layers by content hash: if only source files change later,
# this (slow) dependency download step is skipped on rebuilds.
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Now copy the actual source and build the jar. Tests already ran as their
# own gate in Phase 1 (mvn test); we skip them here so the image build is
# fast and reproducible without needing a network/DB in the build context.
COPY src ./src
RUN mvn -B package -DskipTests

# --- Stage 2: run the jar ---
# Slim JRE (no compiler, no build tools) on Alpine = small, minimal attack
# surface. This is the image we actually ship and run.
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Run as a non-root, unprivileged user. If the app (or a future
# vulnerability in a dependency) is ever compromised, it shouldn't have
# root inside the container.
RUN addgroup -S spring && adduser -S spring -G spring
USER spring

COPY --from=build /build/target/hello-service-0.1.0.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
