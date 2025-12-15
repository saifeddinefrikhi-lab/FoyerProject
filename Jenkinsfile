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
                    eval \$(minikube docker-env)
                    cat > Dockerfile.jenkins << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.jenkins .
                    eval \$(minikube docker-env -u)
                """
            }
        }

        stage('Push to DockerHub') {
            steps {
                echo "🚀 Pushing image to DockerHub..."
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker logout
                    """
                }
            }
        }

        stage('Cleanup and Deploy MySQL') {
            steps {
                echo "🗄️  Nettoyage et déploiement MySQL..."
                sh """
                    # Cleanup
                    kubectl delete all --all -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete pvc --all -n ${K8S_NAMESPACE} --ignore-not-found=true
                    sleep 10

                    # Deploy MySQL
                    cat > /tmp/mysql.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: devops
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
  namespace: devops
spec:
  selector:
    app: mysql
  ports:
    - port: 3306
      targetPort: 3306
  type: ClusterIP
EOF
                    kubectl apply -f /tmp/mysql.yaml
                    sleep 60

                    # Configure MySQL
                    MYSQL_POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}')
                    kubectl exec -n ${K8S_NAMESPACE} \$MYSQL_POD -- mysql -u root -proot123 -e "
                        CREATE DATABASE IF NOT EXISTS springdb;
                        GRANT ALL PRIVILEGES ON *.* TO 'root'@'%';
                        FLUSH PRIVILEGES;
                    "
                """
            }
        }

        stage('Deploy Spring Boot') {
            steps {
                echo "🚀 Déploiement Spring Boot..."
                sh """
                    cat > /tmp/spring.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: devops
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
          value: "jdbc:mysql://mysql-service:3306/springdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
        - name: SPRING_DATASOURCE_USERNAME
          value: "root"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "root123"
        - name: SPRING_JPA_HIBERNATE_DDL_AUTO
          value: "update"
        - name: SERVER_SERVLET_CONTEXT_PATH
          value: "${CONTEXT_PATH}"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1024Mi"
            cpu: "500m"
        startupProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
          failureThreshold: 30
---
apiVersion: v1
kind: Service
metadata:
  name: spring-service
  namespace: devops
spec:
  selector:
    app: spring-app
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30080
  type: NodePort
EOF
                    kubectl apply -f /tmp/spring.yaml

                    echo "=== Attente du démarrage (5 minutes) ==="
                    for i in \$(seq 1 30); do
                        echo "⏱️  Attente... (\$i/30)"
                        sleep 10
                    done

                    echo "=== Vérification ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Test Application') {
            steps {
                echo "✅ Test de l'application..."
                sh """
                    echo "=== Logs Spring Boot ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}')
                    kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200

                    echo ""
                    echo "=== Test de santé ==="
                    curl -s http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health || echo "Health check failed"

                    echo ""
                    echo "=== Test API ==="
                    curl -s http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers || echo "API test failed"
                """
            }
        }
    }

    post {
        always {
            echo "🏁 Pipeline terminé"
            sh '''
                rm -f Dockerfile.jenkins /tmp/mysql.yaml /tmp/spring.yaml 2>/dev/null || true
            '''
            sh """
                echo "=== RAPPORT ==="
                echo "Application: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                echo "Health: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                echo "SonarQube: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
            """
        }
        success {
            echo "✅ Pipeline réussi!"
        }
        failure {
            echo "💥 Pipeline échoué"
        }
    }
}