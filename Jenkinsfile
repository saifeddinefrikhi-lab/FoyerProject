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
                script {
                    sh '''
                        echo "=== Vérification de l'état du namespace ==="
                        if kubectl get namespace devops &> /dev/null; then
                            echo "Le namespace devops existe. Suppression des ressources..."

                            # 1. Delete PVCs first
                            echo "Suppression des PVCs..."
                            kubectl delete pvc --all -n devops --ignore-not-found=true || true

                            # 2. Wait for PVCs to be released
                            sleep 10

                            # 3. Delete namespace
                            echo "Suppression du namespace..."
                            kubectl delete namespace devops --ignore-not-found=true

                            # 4. Wait for complete deletion
                            echo "Attente de la suppression complète du namespace..."
                            TIMEOUT=60
                            COUNT=0
                            while kubectl get namespace devops &> /dev/null && [ $COUNT -lt $TIMEOUT ]; do
                                echo "En attente... ($COUNT/$TIMEOUT)"
                                sleep 5
                                COUNT=$((COUNT + 5))
                            done

                            if [ $COUNT -eq $TIMEOUT ]; then
                                echo "⚠️ Timeout lors de la suppression du namespace. Forcer la suppression..."
                                kubectl delete namespace devops --ignore-not-found=true --force --grace-period=0 || true
                            fi

                            echo "✅ Namespace devops supprimé"
                        fi

                        echo "=== Création du namespace ==="
                        kubectl create namespace devops
                        sleep 5
                        kubectl get namespace devops
                    '''
                }
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
                script {
                    withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh """
                            # Switch to Minikube's Docker daemon
                            eval \$(minikube docker-env)

                            # Create a simple Dockerfile
                            cat > Dockerfile.jenkins << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                            echo "=== Building image ==="
                            docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.jenkins .

                            echo "=== Listing images in Minikube ==="
                            docker images | grep ${IMAGE_NAME} | head -5

                            # Switch back to normal Docker daemon
                            eval \$(minikube docker-env -u)
                        """
                    }
                }
            }
        }

        stage('Push to DockerHub') {
            steps {
                echo "🚀 Pushing image to DockerHub..."
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo "=== Login to DockerHub ==="
                        echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin

                        echo "=== Pushing image ==="
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}

                        echo "=== Logout from DockerHub ==="
                        docker logout
                    """
                }
            }
        }

        stage('Deploy MySQL') {
            steps {
                echo "🗄️  Déploiement de MySQL..."
                sh """
                    echo "=== Creating MySQL deployment ==="
                    cat > /tmp/mysql.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: ${K8S_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: standard
---
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
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "250m"
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
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

                    echo "=== Waiting for MySQL to start (120 seconds) ==="
                    for i in {1..24}; do
                        echo "⏱️  Waiting... (\${i}/24)"
                        sleep 5
                    done

                    echo "=== Checking MySQL status ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}

                    echo "=== Configuring MySQL permissions ==="
                    for i in {1..20}; do
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Attempt \${i}/20: Checking pod \$POD_NAME..."
                            POD_STATUS=\$(kubectl get pod -n ${K8S_NAMESPACE} \$POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
                            if [ "\$POD_STATUS" = "Running" ]; then
                                echo "✅ MySQL is running. Configuring permissions..."

                                # Wait a bit more for MySQL to be fully ready
                                sleep 20

                                # Configure MySQL permissions
                                kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "
                                    CREATE USER IF NOT EXISTS 'spring'@'%' IDENTIFIED BY 'spring123';
                                    GRANT ALL PRIVILEGES ON springdb.* TO 'spring'@'%';
                                    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
                                    FLUSH PRIVILEGES;
                                    CREATE DATABASE IF NOT EXISTS springdb;
                                    USE springdb;
                                    SELECT '✅ Database created and configured' as Status;
                                " 2>/dev/null && break || echo "⚠️  Retrying in 10 seconds..."
                            fi
                        fi
                        sleep 10
                    done

                    echo "=== Final MySQL verification ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}

                    echo "=== Testing MySQL connection ==="
                    MYSQL_POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$MYSQL_POD" ]; then
                        kubectl exec -n ${K8S_NAMESPACE} \$MYSQL_POD -- mysql -u root -proot123 -e "SHOW DATABASES; SELECT 'MySQL operational' as Status;"
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
                    echo "=== Applying Spring Boot deployment ==="
                    kubectl apply -f spring-deployment.yaml

                    echo "=== Waiting for Spring Boot to start (4 minutes) ==="
                    for i in {1..24}; do
                        echo "⏱️  Waiting for Spring Boot... (\${i}/24)"
                        sleep 10
                    done

                    echo "=== Checking deployment status ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}
                """
            }
        }
        stage('Diagnose Issues') {
            steps {
                echo "🩺 Diagnostic des problèmes..."
                sh """
                    echo "=== Diagnostic complet ==="

                    # Vérifier l'état des ressources
                    echo "1. État des ressources cluster:"
                    kubectl get all -n ${K8S_NAMESPACE} 2>/dev/null || echo "Cluster inaccessible"

                    echo ""
                    echo "2. Détails du pod Spring Boot:"
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        kubectl describe pod -n ${K8S_NAMESPACE} \$POD_NAME
                    fi

                    echo ""
                    echo "3. Logs complets Spring Boot:"
                    if [ -n "\$POD_NAME" ]; then
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME
                    fi

                    echo ""
                    echo "4. Test de connexion à MySQL depuis l'intérieur du pod:"
                    if [ -n "\$POD_NAME" ]; then
                        kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- sh -c "
                            echo 'Test de connexion réseau à MySQL...'
                            nc -z -v mysql-service 3306
                            echo ''
                            echo 'Test de résolution DNS...'
                            nslookup mysql-service || cat /etc/resolv.conf
                        " 2>/dev/null || echo "Impossible d'exécuter les tests"
                    fi
                """
            }
        }

        stage('Verify Application Startup') {
            steps {
                echo "🔍 Vérification du démarrage de l'application..."
                sh """
                    echo "=== Additional wait (30 seconds) ==="
                    sleep 30

                    echo "=== Checking pods ==="
                    kubectl get pods -n ${K8S_NAMESPACE} -o wide

                    echo ""
                    echo "=== Spring Boot logs (last 200 lines) ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        echo "Pod: \$POD_NAME"
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200 | grep -E "(ERROR|WARN|INFO.*Application|Started|JPA)" | head -50
                    else
                        echo "No Spring Boot pod found"
                    fi
                """
            }
        }

        stage('Test Application Health') {
            steps {
                echo "✅ Test de santé de l'application..."
                sh """
                    echo "=== Testing health endpoint ==="
                    for i in {1..10}; do
                        echo "Attempt \${i}/10..."
                        if curl -s -f -m 30 "http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" > /dev/null; then
                            echo "✅ Application accessible with context path!"
                            echo ""
                            echo "=== Testing Foyer API ==="
                            curl -s "http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers" | head -20
                            echo ""
                            break
                        elif curl -s -f -m 30 "http://${MINIKUBE_IP}:30080/actuator/health" > /dev/null; then
                            echo "✅ Application accessible (without context path)"
                            break
                        else
                            echo "⏱️  Waiting... (\${i}/10)"
                            sleep 15
                        fi
                    done

                    echo ""
                    echo "=== Final resource status ==="
                    kubectl get all -n ${K8S_NAMESPACE} || echo "Unable to get resource status"
                """
            }
        }
    }

    post {
        always {
            echo "🏁 Pipeline terminé"

            // Cleanup
            sh '''
                echo "=== Cleaning temporary files ==="
                rm -f Dockerfile.jenkins spring-deployment.yaml /tmp/mysql.yaml 2>/dev/null || true
            '''

            // Final report
            sh """
                echo ""
                echo "=== FINAL REPORT ==="
                echo "✅ Pipeline executed"
                echo "📊 Docker Image: ${IMAGE_NAME}:${IMAGE_TAG}"
                echo "📁 Namespace: ${K8S_NAMESPACE}"
                echo "🌐 Context path: ${CONTEXT_PATH}"
                echo ""
                echo "=== IMPORTANT LINKS ==="
                echo "📈 SonarQube Dashboard: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
                echo "🔍 SonarQube Project: ${SONAR_HOST_URL}/project/overview?id=${SONAR_PROJECT_KEY}"
                echo ""
                echo "=== APPLICATION ACCESS ==="
                echo "🌐 Spring Boot Application: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                echo "🔧 Health Check: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                echo "📊 Foyer API: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
                echo ""
                echo "=== TROUBLESHOOTING COMMANDS ==="
                echo "1. View all pods: kubectl get pods -n ${K8S_NAMESPACE}"
                echo "2. View Spring Boot logs: kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=100"
                echo "3. View MySQL logs: kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50"
                echo "4. Restart Spring Boot: kubectl rollout restart deployment/spring-app -n ${K8S_NAMESPACE}"
                echo "5. MySQL access: kubectl exec -n ${K8S_NAMESPACE} -it \$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o name | head -1) -- mysql -u root -proot123"
            """
        }

        success {
            echo "🎉 Pipeline exécuté avec succès!"
            sh """
                echo ""
                echo "=== SUCCESS ==="
                echo "✅ SonarQube analysis completed"
                echo "✅ Docker application built"
                echo "✅ Kubernetes deployment performed"
                echo "✅ Spring Boot application deployed"
                echo ""
                echo "🌐 Your application is accessible at: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}"
            """
        }

        failure {
            echo "💥 Le pipeline a échoué"
            sh """
                echo ""
                echo "=== TROUBLESHOOTING ==="
                echo "1. Pod status:"
                kubectl get pods -n ${K8S_NAMESPACE} 2>/dev/null || echo "Unable to get pods"

                echo ""
                echo "2. Recent events:"
                kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "Unable to get events"

                echo ""
                echo "3. Services:"
                kubectl get svc -n ${K8S_NAMESPACE} 2>/dev/null || echo "Unable to get services"

                echo ""
                echo "4. Manual tests:"
                echo "   Test MySQL: mysql -h ${MINIKUBE_IP} -P 3306 -u root -proot123"
                echo "   Test Spring Boot: curl -v http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
            """
        }
    }

}

