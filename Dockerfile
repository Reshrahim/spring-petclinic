# syntax=docker/dockerfile:1

# Build stage always runs on the native build platform and produces an
# architecture-independent JAR, so multi-platform builds cross-compile safely.
FROM --platform=$BUILDPLATFORM eclipse-temurin:17-jdk AS build
WORKDIR /workspace

COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -ntp -DskipTests dependency:go-offline

COPY src/ src/
RUN ./mvnw -B -ntp -DskipTests -Dcheckstyle.skip=true -Dspring-javaformat.skip=true package \
    && cp target/spring-petclinic-*.jar /workspace/app.jar

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /workspace/app.jar /app/app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
