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

        stage('Build Docker Image') {
            steps {
                echo "🐳 Construction de l'image Docker..."
                sh """
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

                    echo "=== Liste des images ==="
                    docker images | grep ${IMAGE_NAME} | head -5
                """
            }
        }

        stage('Docker Login & Push') {
            steps {
                echo "📤 Push vers DockerHub..."
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo "\$DOCKER_PASS" | docker login -u "\$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:latest
                    """
                }
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
                    String yamlContent = """apiVersion: v1
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
                imagePullPolicy: Always
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
                startupProbe:
                  httpGet:
                    path: ${CONTEXT_PATH}/actuator/health
                    port: 8080
                  initialDelaySeconds: 60
                  periodSeconds: 10
                  failureThreshold: 30
                  timeoutSeconds: 5
                readinessProbe:
                  httpGet:
                    path: ${CONTEXT_PATH}/actuator/health
                    port: 8080
                  initialDelaySeconds: 30
                  periodSeconds: 10
                  timeoutSeconds: 5
                  failureThreshold: 3
                livenessProbe:
                  httpGet:
                    path: ${CONTEXT_PATH}/actuator/health
                    port: 8080
                  initialDelaySeconds: 90
                  periodSeconds: 20
                  timeoutSeconds: 5
                  failureThreshold: 3
                resources:
                  requests:
                    memory: "512Mi"
                    cpu: "250m"
                  limits:
                    memory: "1Gi"
                    cpu: "500m"
        """

                    writeFile file: 'spring-deployment.yaml', text: yamlContent

                    sh """
                        echo "=== Vérification du YAML ==="
                        cat spring-deployment.yaml

                        echo "=== Validation du YAML (dry-run) ==="
                        kubectl apply -f spring-deployment.yaml --dry-run=client || exit 1

                        echo "=== Application du déploiement ==="
                        kubectl apply -f spring-deployment.yaml

                        echo "=== Attente du démarrage ==="
                        sleep 30

                        echo "=== Surveillance du pod ==="
                        for i in {1..30}; do
                            echo "Tentative \$i/30..."
                            POD_STATUS=\$(kubectl get pod -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Found")
                            echo "Pod status: \$POD_STATUS"

                            if [ "\$POD_STATUS" = "Running" ]; then
                                echo "✅ Pod est en cours d'exécution"
                                break
                            elif [ "\$POD_STATUS" = "Pending" ] || [ "\$POD_STATUS" = "ContainerCreating" ]; then
                                POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                                if [ -n "\$POD_NAME" ]; then
                                    echo "=== Événements du pod ==="
                                    kubectl describe pod \$POD_NAME -n ${K8S_NAMESPACE} | grep -A 20 "Events:" || true
                                fi
                            elif [ "\$POD_STATUS" = "Error" ] || [ "\$POD_STATUS" = "Failed" ]; then
                                echo "❌ Pod a échoué"
                                POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                                if [ -n "\$POD_NAME" ]; then
                                    kubectl logs \$POD_NAME -n ${K8S_NAMESPACE} --tail=50 || true
                                fi
                                exit 1
                            fi
                            sleep 10
                        done

                        echo "=== État final ==="
                        kubectl get pods,svc,deploy -n ${K8S_NAMESPACE} -o wide
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "✅ Vérification du déploiement..."
                sh """
                    echo "=== Attente supplémentaire pour l'application ==="
                    sleep 30

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
                        kubectl describe pod -n ${K8S_NAMESPACE} \$POD_NAME | tail -50 || true
                    else
                        echo "❌ Aucun pod Spring Boot trouvé"
                        exit 1
                    fi

                    echo ""
                    echo "=== Test de l'application ==="
                    MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "192.168.49.2")
                    echo "Minikube IP: \$MINIKUBE_IP"

                    # Try multiple endpoints with retries
                    MAX_ATTEMPTS=20
                    for attempt in \$(seq 1 \$MAX_ATTEMPTS); do
                        echo ""
                        echo "Tentative de connexion \$attempt/\$MAX_ATTEMPTS..."

                        # Try health endpoint with context path
                        if curl -s -f -m 10 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"; then
                            echo "✅ SUCCÈS avec contexte path: ${CONTEXT_PATH}"
                            HEALTH_SUCCESS=true
                            break
                        elif curl -s -m 10 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"; then
                            echo "⚠️  Réponse reçue mais non-2xx avec contexte path"
                            curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                        fi

                        # Try without context path
                        if curl -s -f -m 10 "http://\${MINIKUBE_IP}:30080/actuator/health"; then
                            echo "✅ SUCCÈS sans contexte path"
                            HEALTH_SUCCESS=true
                            break
                        elif curl -s -m 10 "http://\${MINIKUBE_IP}:30080/actuator/health"; then
                            echo "⚠️  Réponse reçue mais non-2xx sans contexte path"
                            curl -s "http://\${MINIKUBE_IP}:30080/actuator/health"
                        fi

                        # Try root endpoint
                        if curl -s -f -m 10 "http://\${MINIKUBE_IP}:30080/"; then
                            echo "✅ Réponse du serveur sur la racine"
                            HEALTH_SUCCESS=true
                            break
                        fi

                        echo "⏱️  Attente 10 secondes avant nouvelle tentative..."
                        sleep 10
                    done

                    if [ -z "\$HEALTH_SUCCESS" ]; then
                        echo "❌ Échec de la connexion à l'application après \$MAX_ATTEMPTS tentatives"
                        echo "=== Derniers logs de l'application ==="
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=100 || true
                        exit 1
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
                rm -f Dockerfile.jenkins spring-deployment.yaml /tmp/mysql-*.yaml 2>/dev/null || true
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
                """
            }
        }

        success {
            echo "🎉 Pipeline réussi!"

            script {
                sh """
                    echo "=== TEST FINAL ==="
                    MINIKUBE_IP=\$(minikube ip)
                    echo "Test de l'endpoint health:"
                    curl -s -m 30 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" || echo "⚠️  L'application ne répond pas"
                """
            }
        }

        failure {
            echo "💥 Le pipeline a échoué"
            script {
                echo "Le pipeline a échoué au build ${BUILD_NUMBER}"
            }
        }
    }
}