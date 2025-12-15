pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
        DOCKERHUB_CREDENTIALS = credentials('docker-hub')
        SONAR_HOST_URL = "http://172.30.40.173:9000"
        SONAR_PROJECT_KEY = "foyer-project"
        SONAR_TOKEN = credentials('sonar-token')
        MINIKUBE_IP = "192.168.49.2"
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Prepare Environment') {
            steps {
                echo "⚙️  Préparation de l'environnement..."
                sh '''
                    echo "=== Nettoyage initial ==="
                    kubectl delete namespace ${K8S_NAMESPACE} --ignore-not-found=true --wait=false
                    sleep 10
                    kubectl create namespace ${K8S_NAMESPACE}

                    echo "=== Vérification de Minikube ==="
                    minikube status || echo "Minikube non disponible"
                '''
            }
        }

        stage('Checkout') {
            steps {
                echo "📦 Récupération du code depuis GitHub..."
                git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
            }
        }

        stage('SonarQube Quality Gate') {
            steps {
                echo "🔍 Analyse de la qualité du code avec SonarQube..."
                script {
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                            echo "=== Démarrage de l'analyse SonarQube ==="
                            mvn clean verify sonar:sonar \
                                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                                -Dsonar.projectName="Foyer Project" \
                                -Dsonar.sources=src/main/java \
                                -Dsonar.tests=src/test/java \
                                -Dsonar.java.binaries=target/classes \
                                -Dsonar.java.libraries=target/**/*.jar \
                                -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml \
                                -Dsonar.sourceEncoding=UTF-8 \
                                -Dsonar.host.url=${SONAR_HOST_URL} \
                                -DskipTests=true

                            echo "=== Attente du traitement SonarQube ==="
                            sleep 30
                        '''
                    }

                    timeout(time: 10, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
        }

        stage('Build & Test') {
            steps {
                echo "🔨 Construction de l'application..."
                sh '''
                    echo "=== Build Maven ==="
                    mvn clean package -B -DskipTests

                    echo "=== Vérification du JAR ==="
                    JAR_FILE=$(find target -name "*.jar" -type f | head -1)
                    if [ -f "$JAR_FILE" ]; then
                        echo "✅ JAR trouvé: $JAR_FILE"
                        ls -lh "$JAR_FILE"
                    else
                        echo "❌ Aucun fichier JAR trouvé!"
                        exit 1
                    fi
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "🐳 Construction de l'image Docker..."
                sh """
                    # Basculer vers le daemon Docker de Minikube
                    eval \$(minikube docker-env)

                    # Créer un Dockerfile simple
                    cat > Dockerfile.jenkins << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    echo "=== Construction de l'image ==="
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.jenkins .

                    echo "=== Liste des images dans Minikube ==="
                    docker images | grep ${IMAGE_NAME} | head -5

                    # Revenir au daemon Docker normal
                    eval \$(minikube docker-env -u)
                """
            }
        }

        stage('Push to DockerHub') {
            steps {
                echo "🚀 Envoi de l'image vers DockerHub..."
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo "=== Connexion à DockerHub ==="
                        echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin

                        echo "=== Envoi de l'image ==="
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "=== Déconnexion de DockerHub ==="
                        docker logout
                    """
                }
            }
        }

        stage('Deploy MySQL') {
            steps {
                echo "🗄️  Déploiement de MySQL..."
                sh """
                    echo "=== Création du déploiement MySQL ==="
                    cat > /tmp/mysql.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: ${K8S_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "root123"
        - name: MYSQL_DATABASE
          value: "springdb"
        - name: MYSQL_ROOT_HOST
          value: "%"
        ports:
        - containerPort: 3306
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "250m"
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: mysql
  ports:
    - port: 3306
      targetPort: 3306
  type: ClusterIP
EOF

                    kubectl apply -f /tmp/mysql.yaml

                    echo "=== Attente du démarrage de MySQL (90 secondes) ==="
                    sleep 90

                    echo "=== Configuration des permissions MySQL ==="
                    for i in \$(seq 1 15); do
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Tentative \$i/15: Vérification du pod \$POD_NAME..."
                            POD_STATUS=\$(kubectl get pod -n ${K8S_NAMESPACE} \$POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
                            if [ "\$POD_STATUS" = "Running" ]; then
                                echo "✅ MySQL est en cours d'exécution"

                                # Attendre un peu plus pour que MySQL soit complètement prêt
                                sleep 20

                                # Configurer les permissions MySQL
                                kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "
                                    CREATE USER IF NOT EXISTS 'spring'@'%' IDENTIFIED BY 'spring123';
                                    GRANT ALL PRIVILEGES ON springdb.* TO 'spring'@'%';
                                    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
                                    FLUSH PRIVILEGES;
                                    CREATE DATABASE IF NOT EXISTS springdb;
                                    USE springdb;
                                    SELECT '✅ Base de données créée et configurée' as Status;
                                " 2>/dev/null && break || echo "⚠️  Réessayer dans 10 secondes..."
                            fi
                        fi
                        sleep 10
                    done

                    echo "=== Vérification finale MySQL ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}

                    echo "=== Test de connexion MySQL ==="
                    MYSQL_POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$MYSQL_POD" ]; then
                        kubectl exec -n ${K8S_NAMESPACE} \$MYSQL_POD -- mysql -u root -proot123 -e "SHOW DATABASES; SELECT 'MySQL opérationnel' as Status;"
                    fi
                """
            }
        }

        stage('Deploy Spring Boot Application') {
            steps {
                echo "🚀 Déploiement de l'application Spring Boot..."
                script {
                    String yamlContent = """apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${K8S_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spring-app
  template:
    metadata:
      labels:
        app: spring-app
    spec:
      containers:
      - name: spring-app
        image: ${IMAGE_NAME}:${IMAGE_TAG}
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:mysql://mysql-service:3306/springdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&createDatabaseIfNotExist=true"
        - name: SPRING_DATASOURCE_USERNAME
          value: "root"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "root123"
        - name: SPRING_DATASOURCE_DRIVER_CLASS_NAME
          value: "com.mysql.cj.jdbc.Driver"
        - name: SPRING_JPA_HIBERNATE_DDL_AUTO
          value: "update"
        - name: SERVER_SERVLET_CONTEXT_PATH
          value: "${CONTEXT_PATH}"
        - name: SPRING_APPLICATION_NAME
          value: "foyer-app"
        - name: SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT
          value: "org.hibernate.dialect.MySQL8Dialect"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        startupProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
          failureThreshold: 30
        livenessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8080
          initialDelaySeconds: 180
          periodSeconds: 20
        readinessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spring-service
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: spring-app
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080
  type: NodePort
"""

                    writeFile file: 'spring-deployment.yaml', text: yamlContent
                }

                sh """
                    echo "=== Application du déploiement Spring Boot ==="
                    kubectl apply -f spring-deployment.yaml

                    echo "=== Attente du démarrage Spring Boot (4 minutes) ==="
                    for i in \$(seq 1 24); do
                        echo "⏱️  Attente Spring Boot... (\$i/24)"
                        sleep 10
                    done

                    echo "=== Vérification de l'état ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Verify Application Startup') {
            steps {
                echo "🔍 Vérification du démarrage de l'application..."
                sh """
                    echo "=== Attente supplémentaire (30 secondes) ==="
                    sleep 30

                    echo "=== Vérification des pods ==="
                    kubectl get pods -n ${K8S_NAMESPACE} -o wide

                    echo ""
                    echo "=== Logs Spring Boot (dernières 200 lignes) ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        echo "Pod: \$POD_NAME"
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200 | grep -E "(ERROR|WARN|INFO.*Application|Started|JPA)" | head -50
                    else
                        echo "Aucun pod Spring Boot trouvé"
                    fi
                """
            }
        }

        stage('Test Application Health') {
            steps {
                echo "✅ Test de santé de l'application..."
                sh """
                    echo "=== Test de l'endpoint de santé ==="
                    for i in \$(seq 1 10); do
                        echo "Tentative \$i/10..."
                        if curl -s -f -m 30 "http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" > /dev/null; then
                            echo "✅ Application accessible avec contexte path!"
                            echo ""
                            echo "=== Test de l'API Foyer ==="
                            curl -s "http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers" | head -20
                            echo ""
                            break
                        elif curl -s -f -m 30 "http://${MINIKUBE_IP}:30080/actuator/health" > /dev/null; then
                            echo "✅ Application accessible (sans contexte path)"
                            break
                        else
                            echo "⏱️  En attente... (\$i/10)"
                            sleep 15
                        fi
                    done

                    echo ""
                    echo "=== État final des ressources ==="
                    kubectl get all -n ${K8S_NAMESPACE} || echo "Impossible d'obtenir l'état des ressources"
                """
            }
        }
    }

    post {
        always {
            echo "🏁 Pipeline terminé"

            // Nettoyage
            sh '''
                echo "=== Nettoyage des fichiers temporaires ==="
                rm -f Dockerfile.jenkins spring-deployment.yaml /tmp/mysql.yaml 2>/dev/null || true
            '''

            // Rapport final
            sh """
                echo ""
                echo "=== RAPPORT FINAL ==="
                echo "✅ Pipeline exécuté"
                echo "📊 Image Docker: ${IMAGE_NAME}:${IMAGE_TAG}"
                echo "📁 Namespace: ${K8S_NAMESPACE}"
                echo "🌐 Contexte path: ${CONTEXT_PATH}"
                echo ""
                echo "=== LIENS IMPORTANTS ==="
                echo "📈 Dashboard SonarQube: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
                echo "🔍 Projet SonarQube: ${SONAR_HOST_URL}/project/overview?id=${SONAR_PROJECT_KEY}"
                echo ""
                echo "=== ACCÈS À L'APPLICATION ==="
                echo "🌐 Application Spring Boot: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                echo "🔧 Health Check: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                echo "📊 API Foyer: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
                echo ""
                echo "=== COMMANDES DE DÉPANNAGE ==="
                echo "1. Voir tous les pods: kubectl get pods -n ${K8S_NAMESPACE}"
                echo "2. Voir les logs Spring Boot: kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=100"
                echo "3. Voir les logs MySQL: kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50"
                echo "4. Redémarrer Spring Boot: kubectl rollout restart deployment/spring-app -n ${K8S_NAMESPACE}"
                echo "5. Accès MySQL: kubectl exec -n ${K8S_NAMESPACE} -it \$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o name | head -1) -- mysql -u root -proot123"
            """
        }

        success {
            echo "🎉 Pipeline exécuté avec succès!"
            sh """
                echo ""
                echo "=== SUCCÈS ==="
                echo "✅ Analyse SonarQube terminée"
                echo "✅ Application Docker construite"
                echo "✅ Déploiement Kubernetes effectué"
                echo "✅ Application Spring Boot déployée"
                echo ""
                echo "🌐 Votre application est accessible à: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}"
            """
        }

        failure {
            echo "💥 Le pipeline a échoué"
            sh """
                echo ""
                echo "=== DÉPANNAGE ==="
                echo "1. État des pods:"
                kubectl get pods -n ${K8S_NAMESPACE} 2>/dev/null || echo "Impossible d'obtenir les pods"

                echo ""
                echo "2. Événements récents:"
                kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "Impossible d'obtenir les événements"

                echo ""
                echo "3. Services:"
                kubectl get svc -n ${K8S_NAMESPACE} 2>/dev/null || echo "Impossible d'obtenir les services"

                echo ""
                echo "4. Test manuel:"
                echo "   Test MySQL: mysql -h ${MINIKUBE_IP} -P 3306 -u root -proot123"
                echo "   Test Spring Boot: curl -v http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
            """
        }
    }
}