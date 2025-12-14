# Étape 1 : Construction de l'application avec Maven
FROM maven:3.9.9-eclipse-temurin-17-alpine AS build
WORKDIR /app

# Copier les fichiers de configuration Maven
COPY pom.xml .
COPY src ./src

# Construire l'application (skip tests pour accélérer)
RUN mvn clean package -DskipTests

# Étape 2 : Création de l'image d'exécution
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Copier le JAR depuis l'étape de build
COPY --from=build /app/target/*.jar app.jar

# Exposer le port de l'application
EXPOSE 8080

# Commande pour exécuter l'application
ENTRYPOINT ["java", "-jar", "app.jar"]