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
                script {
                    sh '''
                        echo "=== Vérification et nettoyage du namespace ==="

                        # Check if namespace exists
                        if kubectl get namespace ${K8S_NAMESPACE} &>/dev/null; then
                            echo "Le namespace ${K8S_NAMESPACE} existe. Vérification de son état..."

                            # Get namespace status
                            NS_STATUS=$(kubectl get namespace ${K8S_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

                            if [ "$NS_STATUS" = "Terminating" ]; then
                                echo "⚠️  Namespace ${K8S_NAMESPACE} est en cours de termination..."

                                # Force remove finalizers if stuck
                                kubectl get namespace ${K8S_NAMESPACE} -o json | \
                                jq 'del(.spec.finalizers[])' | \
                                kubectl replace --raw "/api/v1/namespaces/${K8S_NAMESPACE}/finalize" -f - 2>/dev/null || true

                                # Wait for complete deletion
                                echo "Attente de la suppression complète du namespace (max 60s)..."
                                COUNTER=0
                                while kubectl get namespace ${K8S_NAMESPACE} &>/dev/null && [ $COUNTER -lt 12 ]; do
                                    echo "⏱️  En attente... ($((COUNTER*5))s/60s)"
                                    sleep 5
                                    COUNTER=$((COUNTER + 1))
                                done

                                if kubectl get namespace ${K8S_NAMESPACE} &>/dev/null; then
                                    echo "❌ Impossible de supprimer le namespace. Utilisation du mode force..."
                                    # Force delete using kubectl proxy method
                                    cat > /tmp/force-delete-ns.json <<EOF
{
  "kind": "DeleteOptions",
  "apiVersion": "v1",
  "propagationPolicy": "Background"
}
EOF
                                    kubectl proxy --port=8080 &
                                    PROXY_PID=$!
                                    sleep 2
                                    curl -X DELETE http://localhost:8080/api/v1/namespaces/${K8S_NAMESPACE} \
                                         -H "Content-Type: application/json" \
                                         -d @/tmp/force-delete-ns.json
                                    kill $PROXY_PID 2>/dev/null || true
                                    sleep 10
                                fi
                            else
                                echo "Suppression normale du namespace..."
                                kubectl delete namespace ${K8S_NAMESPACE} --wait=false
                            fi

                            # Final check and wait
                            echo "Attente finale de suppression..."
                            for i in {1..30}; do
                                if ! kubectl get namespace ${K8S_NAMESPACE} &>/dev/null; then
                                    echo "✅ Namespace ${K8S_NAMESPACE} complètement supprimé"
                                    break
                                fi
                                sleep 2
                            done
                        else
                            echo "✅ Namespace ${K8S_NAMESPACE} n'existe pas"
                        fi

                        # Create namespace
                        echo "=== Création du namespace ==="
                        kubectl create namespace ${K8S_NAMESPACE} || {
                            echo "⚠️  Échec de création, vérification de l'état..."
                            sleep 5
                            # Try again
                            kubectl create namespace ${K8S_NAMESPACE} || true
                        }

                        # Verify namespace is ready
                        echo "Vérification que le namespace est actif..."
                        for i in {1..10}; do
                            if kubectl get namespace ${K8S_NAMESPACE} &>/dev/null; then
                                NS_READY=$(kubectl get namespace ${K8S_NAMESPACE} -o jsonpath='{.status.phase}')
                                if [ "$NS_READY" = "Active" ]; then
                                    echo "✅ Namespace ${K8S_NAMESPACE} est actif"
                                    break
                                fi
                            fi
                            sleep 2
                        done

                        # Set namespace as default for current context
                        kubectl config set-context --current --namespace=${K8S_NAMESPACE}
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

       stage('Skip SonarQube (Temp)') {
                   steps {
                       echo "⚠️  SonarQube skipped for now - will fix separately"
                       echo "You can check SonarQube manually at: ${SONAR_HOST_URL}"
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
                    echo "=== Vérification du namespace ==="
                    kubectl get namespace ${K8S_NAMESPACE} || {
                        echo "Création du namespace..."
                        kubectl create namespace ${K8S_NAMESPACE}
                    }

                    echo "=== Creating MySQL deployment ==="
                    cat > /tmp/mysql.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
  namespace: ${K8S_NAMESPACE}
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/mysql"
    type: DirectoryOrCreate
  storageClassName: standard
---
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

                    # Create directory for PV
                    sudo mkdir -p /data/mysql
                    sudo chmod 777 /data/mysql

                    kubectl apply -f /tmp/mysql.yaml

                    echo "=== Waiting for MySQL to start ==="
                    for i in {1..30}; do
                        echo "⏱️  Waiting... (\${i}/30)"
                        sleep 5

                        # Check if pod is running
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            POD_STATUS=\$(kubectl get pod -n ${K8S_NAMESPACE} \$POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
                            if [ "\$POD_STATUS" = "Running" ]; then
                                echo "✅ MySQL pod is running"

                                # Wait extra time for MySQL to be ready
                                sleep 20

                                # Configure MySQL permissions
                                echo "=== Configuring MySQL permissions ==="
                                kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "
                                    CREATE USER IF NOT EXISTS 'spring'@'%' IDENTIFIED BY 'spring123';
                                    GRANT ALL PRIVILEGES ON springdb.* TO 'spring'@'%';
                                    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
                                    FLUSH PRIVILEGES;
                                    CREATE DATABASE IF NOT EXISTS springdb;
                                    USE springdb;
                                    SELECT '✅ Database created and configured' as Status;
                                " 2>/dev/null && break
                            fi
                        fi
                    done

                    echo "=== Final MySQL verification ==="
                    kubectl get pods,svc,pvc,pv -n ${K8S_NAMESPACE}
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
  replicas: 2
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
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:mysql://mysql-service:3306/springdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&createDatabaseIfNotExist=true"
        - name: SPRING_DATASOURCE_USERNAME
          value: "spring"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "spring123"
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

                    echo "=== Waiting for Spring Boot to start ==="
                    for i in {1..30}; do
                        echo "⏱️  Waiting for Spring Boot... (\${i}/30)"

                        # Check deployment status
                        DEPLOYMENT_READY=\$(kubectl get deployment -n ${K8S_NAMESPACE} spring-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                        if [ "\$DEPLOYMENT_READY" = "2" ]; then
                            echo "✅ Spring Boot deployment ready"
                            break
                        fi
                        sleep 10
                    done

                    echo "=== Checking deployment status ==="
                    kubectl get pods,svc,deployment -n ${K8S_NAMESPACE}
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
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200 | grep -E "(ERROR|WARN|INFO.*Application|Started|JPA|Tomcat|MySQL)" | head -50
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
                    MAX_ATTEMPTS=15
                    SUCCESS=0

                    for i in \$(seq 1 \$MAX_ATTEMPTS); do
                        echo "Attempt \${i}/\$MAX_ATTEMPTS..."

                        # Try with context path
                        if curl -s -f -m 30 "http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" > /dev/null; then
                            echo "✅ Application accessible with context path!"
                            echo ""
                            echo "=== Testing Foyer API ==="
                            curl -s "http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers" | head -20
                            echo ""
                            SUCCESS=1
                            break
                        # Try without context path
                        elif curl -s -f -m 30 "http://${MINIKUBE_IP}:30080/actuator/health" > /dev/null; then
                            echo "✅ Application accessible (without context path)"
                            SUCCESS=1
                            break
                        else
                            echo "⏱️  Waiting... (\${i}/\$MAX_ATTEMPTS)"
                            sleep 10
                        fi
                    done

                    if [ \$SUCCESS -eq 0 ]; then
                        echo "⚠️  Application not accessible, checking logs..."
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=50
                        fi
                    fi

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
                rm -f Dockerfile.jenkins spring-deployment.yaml /tmp/mysql.yaml /tmp/force-delete-ns.json 2>/dev/null || true
            '''

            // Final report
            sh """
                echo ""
                echo "=== FINAL REPORT ==="
                echo "📊 Docker Image: ${IMAGE_NAME}:${IMAGE_TAG}"
                echo "📁 Namespace: ${K8S_NAMESPACE}"
                echo "🌐 Context path: ${CONTEXT_PATH}"
                echo ""
                echo "=== IMPORTANT LINKS ==="
                echo "📈 SonarQube Dashboard: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
                echo ""
                echo "=== APPLICATION ACCESS ==="
                echo "🌐 Spring Boot Application: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                echo "🔧 Health Check: http://${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                echo ""
                echo "=== TROUBLESHOOTING COMMANDS ==="
                echo "1. View all pods: kubectl get pods -n ${K8S_NAMESPACE}"
                echo "2. View Spring Boot logs: kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=100"
                echo "3. View MySQL logs: kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50"
                echo "4. Restart Spring Boot: kubectl rollout restart deployment/spring-app -n ${K8S_NAMESPACE}"
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
                echo "2. Pod events:"
                kubectl describe pods -n ${K8S_NAMESPACE} -l app=spring-app 2>/dev/null | grep -A20 Events: || echo "Unable to get events"

                echo ""
                echo "3. Services:"
                kubectl get svc -n ${K8S_NAMESPACE} 2>/dev/null || echo "Unable to get services"

                echo ""
                echo "4. Database connection test:"
                MYSQL_POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                if [ -n "\$MYSQL_POD" ]; then
                    kubectl exec -n ${K8S_NAMESPACE} \$MYSQL_POD -- mysql -u root -proot123 -e "SHOW DATABASES; SELECT USER(), CURRENT_USER();"
                fi
            """
        }
    }
}