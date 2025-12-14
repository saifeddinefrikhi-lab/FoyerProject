# Étape 1 : Build de l'application
FROM maven:3.9.9-eclipse-temurin-17-alpine AS builder
WORKDIR /app

# Copier les fichiers de configuration
COPY pom.xml .
# Télécharger les dépendances (cache)
RUN mvn dependency:go-offline

# Copier le code source et builder
COPY src ./src
RUN mvn clean package -DskipTests

# Étape 2 : Image finale
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Installer curl pour healthcheck
RUN apk add --no-cache curl

# Copier l'application depuis le builder
COPY --from=builder /app/target/*.jar app.jar

# Variables d'environnement par défaut
ENV SPRING_DATASOURCE_URL=jdbc:mysql://localhost:3306/springdb
ENV SPRING_DATASOURCE_USERNAME=root
ENV SPRING_DATASOURCE_PASSWORD=root123
ENV SERVER_SERVLET_CONTEXT_PATH=/

# Exposer le port
EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=90s --retries=3 \
  CMD curl -f http://localhost:8080${SERVER_SERVLET_CONTEXT_PATH}/actuator/health || exit 1

# Commande d'exécution
ENTRYPOINT ["java", "-jar", "app.jar"]