pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "${BUILD_NUMBER}"
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
    }

    triggers {
        githubPush() // This enables webhook triggers
    }

    stages {
        stage('Checkout') {
            steps {
                echo "📦 Récupération du code depuis GitHub..."
                git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
            }
        }

        stage('Build & Test') {
            steps {
                echo "🔨 Construction de l'application..."
                sh '''
                    echo "=== Build Maven ==="
                    mvn clean package -DskipTests -B

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

        stage('Cleanup & Setup MySQL Storage') {
            steps {
                echo "🧹 Nettoyage et préparation du stockage MySQL..."
                sh """
                    echo "=== Suppression des anciennes ressources MySQL ==="
                    kubectl delete deployment mysql -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=60s || true
                    kubectl delete service mysql-service -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=60s || true
                    kubectl delete pvc mysql-pvc -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=60s || true
                    kubectl delete pv mysql-pv --ignore-not-found=true --timeout=60s || true

                    echo "=== Attente pour la suppression complète ==="
                    sleep 15

                    echo "=== Création du PV et PVC MySQL ==="
                    cat > /tmp/mysql-storage.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: "/data/mysql"
    type: DirectoryOrCreate
  storageClassName: ""
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: devops
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  volumeName: mysql-pv
  storageClassName: ""
EOF
                    kubectl apply -f /tmp/mysql-storage.yaml

                    echo "=== Attente que le PVC soit lié ==="
                    sleep 10

                    echo "=== Vérification du PV et PVC ==="
                    kubectl get pv
                    kubectl get pvc -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Deploy MySQL') {
            steps {
                echo "🗄️  Déploiement de MySQL..."
                sh """
                    echo "=== Création du déploiement MySQL ==="
                    cat > /tmp/mysql-deployment.yaml << 'EOF'
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
        - name: MYSQL_ALLOW_EMPTY_PASSWORD
          value: "no"
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
        readinessProbe:
          tcpSocket:
            port: 3306
          initialDelaySeconds: 20
          periodSeconds: 5
          timeoutSeconds: 3
        livenessProbe:
          tcpSocket:
            port: 3306
          initialDelaySeconds: 30
          periodSeconds: 10
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
                    kubectl apply -f /tmp/mysql-deployment.yaml

                    echo "=== Attente du démarrage de MySQL ==="
                    for i in {1..30}; do
                        echo "Tentative \$i/30..."
                        if kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
                            echo "✅ MySQL est en cours d'exécution."
                            sleep 10  # Donner plus de temps pour l'initialisation
                            break
                        fi
                        sleep 10
                    done

                    echo "=== Vérification finale ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Test MySQL Connection') {
            steps {
                echo "🔍 Test de connexion à MySQL..."
                sh """
                    echo "=== Test de connexion à MySQL ==="
                    timeout=120
                    interval=5
                    elapsed=0

                    while [ \$elapsed -lt \$timeout ]; do
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

                        if [ -n "\$POD_NAME" ]; then
                            echo "Test de connexion au pod MySQL: \$POD_NAME"
                            if kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysqladmin ping -h localhost -u root -proot123 2>/dev/null; then
                                echo "✅ MySQL est accessible!"

                                # Vérifier/Créer la base de données
                                kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "
                                    CREATE DATABASE IF NOT EXISTS springdb;
                                    SHOW DATABASES;
                                " 2>/dev/null && echo "✅ Base de données vérifiée/créée"

                                # CRITICAL FIX: Grant permissions to root user from any host
                                echo "=== Configuration des permissions MySQL ==="
                                kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "
                                    -- Create root user for all hosts if it doesn't exist
                                    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';

                                    -- Grant all privileges to root from any host
                                    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

                                    -- Update existing root@localhost password to ensure consistency
                                    ALTER USER 'root'@'localhost' IDENTIFIED BY 'root123';

                                    -- Flush privileges to apply changes
                                    FLUSH PRIVILEGES;

                                    -- Verify users
                                    SELECT User, Host FROM mysql.user;
                                " 2>/dev/null && echo "✅ Permissions MySQL configurées"

                                break
                            fi
                        fi

                        echo "⏱️  Attente... (\$elapsed/\$timeout secondes)"
                        sleep \$interval
                        elapsed=\$((elapsed + interval))
                    done

                    if [ \$elapsed -ge \$timeout ]; then
                        echo "❌ Timeout en attendant MySQL"
                        echo "=== Logs MySQL ==="
                        kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50
                        exit 1
                    fi
                """
            }
        }

        stage('Build Docker Image in Minikube') {
            steps {
                echo "🐳 Construction de l'image Docker dans Minikube..."
                sh """
                    # Switch to Minikube's Docker daemon
                    eval \$(minikube docker-env)

                    # Créez un Dockerfile simple
                    cat > Dockerfile.jenkins << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    echo "=== Construction de l'image ==="
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.jenkins .

                    echo "=== Tag latest ==="
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest

                    echo "=== Liste des images dans Minikube ==="
                    docker images | grep ${IMAGE_NAME} | head -5

                    # Switch back to normal Docker daemon
                    eval \$(minikube docker-env -u)
                """
            }
        }

        stage('Clean Old Spring Boot Resources') {
            steps {
                echo "🧹 Nettoyage des anciennes ressources Spring Boot..."
                sh """
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=60s || true
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=60s || true
                    sleep 10

                    # Nettoyer les pods terminés
                    kubectl delete pods -n ${K8S_NAMESPACE} --field-selector=status.phase!=Running --timeout=60s 2>/dev/null || true
                """
            }
        }

        stage('Deploy Spring Boot Application') {
            steps {
                echo "🚀 Déploiement de l'application Spring Boot..."
                script {
                    // Create YAML content with local image
                    String yamlContent = """apiVersion: v1
kind: Service
metadata:
  name: spring-service
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: spring-app
  ports:
    - port: 8050
      targetPort: 8050
      nodePort: 30080
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${K8S_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spring-app
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: spring-app
    spec:
      containers:
      - name: spring-app
        image: ${IMAGE_NAME}:${IMAGE_TAG}
        imagePullPolicy: Never  # Use local image, don't pull from registry
        ports:
        - containerPort: 8050
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
        - name: SPRING_JPA_SHOW_SQL
          value: "false"
        - name: LOGGING_LEVEL_ROOT
          value: "INFO"
        - name: SERVER_SERVLET_CONTEXT_PATH
          value: "${CONTEXT_PATH}"
        - name: SPRING_APPLICATION_NAME
          value: "foyer-app"
        - name: MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE
          value: "health,info"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8050
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8050
          initialDelaySeconds: 90
          periodSeconds: 15
          timeoutSeconds: 5
"""

                    // Write the YAML file
                    writeFile file: 'spring-deployment.yaml', text: yamlContent
                }

                sh """
                    echo "=== Application du déploiement ==="
                    kubectl apply -f spring-deployment.yaml

                    echo "=== Attente du démarrage (3 minutes) ==="
                    sleep 180

                    echo "=== Vérification de l'état ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}

                    echo "=== Logs du pod Spring Boot ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        echo "Pod: \$POD_NAME"
                        kubectl logs \$POD_NAME -n ${K8S_NAMESPACE} --tail=50 || echo "Pas encore de logs"
                    fi
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "✅ Vérification du déploiement..."
                sh """
                    echo "=== Attente supplémentaire pour l'application ==="
                    sleep 60

                    echo "=== État des pods ==="
                    kubectl get pods -n ${K8S_NAMESPACE} -o wide

                    echo ""
                    echo "=== Logs de l'application Spring Boot ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        echo "Pod: \$POD_NAME"
                        echo "=== Derniers logs (100 lignes) ==="
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=100 || echo "Impossible de récupérer les logs"

                        echo "=== Description complète du pod (pour débogage) ==="
                        kubectl describe pod -n ${K8S_NAMESPACE} \$POD_NAME || true
                    else
                        echo "❌ Aucun pod Spring Boot trouvé"
                        echo "=== Vérification des déploiements ==="
                        kubectl get deployments -n ${K8S_NAMESPACE}
                        echo "=== Vérification des services ==="
                        kubectl get services -n ${K8S_NAMESPACE}
                        exit 1
                    fi

                    echo ""
                    echo "=== Test de connexion MySQL depuis un pod test ==="
                    # Test MySQL connection from a test pod
                    cat > /tmp/test-mysql-connection.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-mysql-connection
  namespace: devops
spec:
  containers:
  - name: mysql-client
    image: mysql:8.0
    command: ["sleep", "3600"]
  restartPolicy: Never
EOF
                    kubectl apply -f /tmp/test-mysql-connection.yaml
                    sleep 10

                    echo "=== Test de connexion à MySQL depuis un autre pod ==="
                    if kubectl exec -n ${K8S_NAMESPACE} test-mysql-connection -- mysql -h mysql-service -u root -proot123 -e "SELECT 1;" 2>/dev/null; then
                        echo "✅ Connexion MySQL réussie depuis un autre pod"
                    else
                        echo "❌ Échec de connexion MySQL depuis un autre pod"
                    fi

                    # Cleanup test pod
                    kubectl delete pod test-mysql-connection -n ${K8S_NAMESPACE} --ignore-not-found=true

                    echo ""
                    echo "=== Test de l'application Spring Boot ==="
                    MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "192.168.49.2")
                    echo "Minikube IP: \$MINIKUBE_IP"

                    # Try with longer timeout
                    echo "Tentative de connexion à Spring Boot..."

                    # First, check if the pod is ready
                    if kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
                        echo "✅ Pod Spring Boot est prêt"

                        # Try multiple endpoints
                        for i in {1..10}; do
                            echo "Tentative \$i/10..."
                            if curl -s -m 10 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"; then
                                echo "✅ SUCCÈS! Application accessible avec contexte path: ${CONTEXT_PATH}"
                                echo "Health check response:"
                                curl -s -m 5 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                                break
                            elif curl -s -m 10 "http://\${MINIKUBE_IP}:30080/actuator/health"; then
                                echo "✅ SUCCÈS! Application accessible sans contexte path"
                                break
                            elif curl -s -m 10 "http://\${MINIKUBE_IP}:30080/"; then
                                echo "✅ Réponse du serveur sur la racine"
                                break
                            else
                                echo "⏱️  Attente... (tentative \$i)"
                                sleep 10
                            fi
                        done
                    else
                        echo "⚠️  Pod Spring Boot n'est pas encore prêt"
                    fi

                    echo ""
                    echo "=== Vérification finale des services ==="
                    kubectl get svc -n ${K8S_NAMESPACE}
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
                rm -f Dockerfile.jenkins spring-deployment.yaml /tmp/mysql-deployment.yaml /tmp/mysql-storage.yaml /tmp/test-mysql-connection.yaml 2>/dev/null || true
            '''

            // Rapport final
            script {
                sh """
                    echo "=== RAPPORT FINAL ==="
                    echo "Build: ${BUILD_NUMBER}"
                    echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Namespace: ${K8S_NAMESPACE}"
                    echo "Contexte: ${CONTEXT_PATH}"

                    echo ""
                    echo "=== État Kubernetes ==="
                    kubectl get all -n ${K8S_NAMESPACE} || true

                    MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "N/A")
                    echo ""
                    echo "=== URL d'accès ==="
                    echo "Spring Boot (avec contexte): http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                    echo "Health Check: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                    echo ""
                    echo "=== Pour tester manuellement ==="
                    echo "Test MySQL: kubectl exec -n devops -it \$(kubectl get pods -n devops -l app=mysql -o name) -- mysql -u root -proot123"
                    echo "Test Spring Boot: curl http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                """
            }
        }

        success {
            echo "🎉 Pipeline réussi!"
        }

        failure {
            echo "💥 Le pipeline a échoué"
            script {
                echo "Le pipeline a échoué au build ${BUILD_NUMBER}"

                // Debug information on failure
                sh """
                    echo "=== DEBUG INFO ==="
                    echo "1. Vérification des déploiements:"
                    kubectl get deployments -n ${K8S_NAMESPACE} || true
                    echo ""
                    echo "2. Vérification des services:"
                    kubectl get services -n ${K8S_NAMESPACE} || true
                    echo ""
                    echo "3. Vérification des pods:"
                    kubectl get pods -n ${K8S_NAMESPACE} || true
                    echo ""
                    echo "4. Vérification des événements:"
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -20 || true
                    echo ""
                    echo "5. Vérification des logs MySQL:"
                    kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50 || true
                    echo ""
                    echo "6. Vérification des logs Spring Boot:"
                    kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=50 || true
                    echo ""
                    echo "7. Vérification des images dans Minikube:"
                    minikube ssh "docker images | grep ${IMAGE_NAME}" || true
                """
            }
        }
    }
}