pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
    }

    stages {
        stage('Setup Environment') {
            steps {
                echo "🔧 Configuration de l'environnement..."
                sh '''
                    # Fix permissions for minikube
                    sudo chown -R $(whoami) $HOME/.minikube || true
                    sudo chmod -R u+w $HOME/.minikube || true

                    # Start/restart minikube
                    minikube status || minikube start --driver=docker --force
                    minikube update-context

                    # Set docker env
                    eval $(minikube docker-env) || true

                    # Create namespace
                    kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                '''
            }
        }

        stage('Checkout & Clean') {
            steps {
                echo "📦 Nettoyage et checkout..."
                sh '''
                    # Clean old containers
                    docker rm -f $(docker ps -aq --filter "name=test-container") 2>/dev/null || true

                    # Clean old pods stuck in terminating
                    kubectl delete pod -n ${K8S_NAMESPACE} $(kubectl get pods -n ${K8S_NAMESPACE} | grep Terminating | awk '{print $1}') --force --grace-period=0 2>/dev/null || true

                    # Clean workspace
                    rm -rf target/ node_modules/ || true
                '''
                git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
            }
        }

        stage('Build Application - SIMPLE') {
            steps {
                echo "🔨 Construction simple..."
                sh '''
                    echo "=== Build sans tests ==="
                    mvn clean package -DskipTests -q

                    # Vérifier le JAR
                    if [ ! -f target/*.jar ]; then
                        echo "❌ Aucun JAR généré!"
                        ls -la target/
                        exit 1
                    fi

                    JAR_FILE=$(ls target/*.jar | head -1)
                    echo "✅ JAR: $JAR_FILE ($(du -h $JAR_FILE | cut -f1))"
                '''
            }
        }

        stage('Test Application Locally - DEBUG') {
            steps {
                echo "🐛 Test local détaillé..."
                script {
                    sh '''
                        echo "=== Configuration Spring active ==="
                        cat src/main/resources/application.properties || echo "Fichier properties non trouvé"

                        echo ""
                        echo "=== Vérification des dépendances ==="
                        mvn dependency:tree -Dincludes=spring-boot 2>/dev/null | head -20

                        echo ""
                        echo "=== Démarrage en mode DEBUG ==="
                        # Kill any existing process
                        pkill -f "java.*target.*jar" || true
                        sleep 2

                        # Start with debug logging
                        nohup java -Xmx512m -jar target/*.jar \
                            --spring.profiles.active=default \
                            --server.port=18081 \
                            --server.servlet.context-path=${CONTEXT_PATH} \
                            --spring.datasource.url=jdbc:h2:mem:testdb \
                            --spring.datasource.driver-class-name=org.h2.Driver \
                            --spring.datasource.username=sa \
                            --spring.datasource.password= \
                            --logging.level.root=DEBUG \
                            --logging.level.org.springframework=INFO \
                            --logging.level.com.foyer=DEBUG \
                            > /tmp/spring-debug.log 2>&1 &

                        APP_PID=$!
                        echo "PID: $APP_PID"

                        # Wait longer for startup
                        echo "=== Attente démarrage (90 secondes) ==="
                        for i in {1..90}; do
                            if curl -s -f "http://localhost:18081${CONTEXT_PATH}/actuator/health" > /dev/null 2>&1; then
                                echo "✅ Application UP après $i secondes"
                                curl -s "http://localhost:18081${CONTEXT_PATH}/actuator/health" | head -5
                                break
                            fi

                            if [ $i -eq 30 ] || [ $i -eq 60 ]; then
                                echo "=== Logs intermédiaires ($i sec) ==="
                                tail -30 /tmp/spring-debug.log
                            fi

                            sleep 1

                            if [ $i -eq 90 ]; then
                                echo "❌ Timeout après 90 secondes"
                                echo "=== Derniers logs (100 lignes) ==="
                                tail -100 /tmp/spring-debug.log
                                echo "=== Recherche d'erreurs ==="
                                grep -i "error\|exception\|failed\|shutdown" /tmp/spring-debug.log | tail -20
                                kill $APP_PID 2>/dev/null || true
                                exit 1
                            fi
                        done

                        # Test multiple endpoints
                        echo ""
                        echo "=== Tests des endpoints ==="
                        echo "1. Health:"
                        curl -s "http://localhost:18081${CONTEXT_PATH}/actuator/health" | head -5

                        echo ""
                        echo "2. Info:"
                        curl -s "http://localhost:18081${CONTEXT_PATH}/actuator/info" | head -5

                        echo ""
                        echo "3. Root path:"
                        curl -s "http://localhost:18081${CONTEXT_PATH}/" -I | head -1

                        # Stop app
                        kill $APP_PID
                        sleep 3
                    '''
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                echo "🐳 Build Docker optimisé..."
                sh '''
                    # Simple Dockerfile
                    cat > Dockerfile << 'EOF'
FROM eclipse-temurin:17-jre-alpine
RUN apk add --no-cache curl bash
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=120s --retries=3 \
  CMD curl -f http://localhost:8080${CONTEXT_PATH}/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    # Build with minikube docker
                    eval $(minikube docker-env)
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    docker build -t ${IMAGE_NAME}:build-${BUILD_NUMBER} .

                    # Test image locally
                    echo "=== Test image Docker localement ==="
                    docker run -d --name test-img-${BUILD_NUMBER} \
                      -e SPRING_PROFILES_ACTIVE=default \
                      -e SPRING_DATASOURCE_URL=jdbc:h2:mem:testdb \
                      -p 18082:8080 \
                      ${IMAGE_NAME}:${IMAGE_TAG}

                    sleep 30

                    if curl -s -f "http://localhost:18082${CONTEXT_PATH}/actuator/health"; then
                        echo "✅ Image Docker fonctionne"
                        docker stop test-img-${BUILD_NUMBER}
                        docker rm test-img-${BUILD_NUMBER}
                    else
                        echo "=== Logs conteneur ==="
                        docker logs test-img-${BUILD_NUMBER} --tail=50
                        docker stop test-img-${BUILD_NUMBER} || true
                        docker rm test-img-${BUILD_NUMBER} || true
                        exit 1
                    fi
                '''

                // Push to DockerHub (if needed)
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    '''
                }
            }
        }

        stage('Clean Kubernetes Resources') {
            steps {
                echo "🧹 Nettoyage Kubernetes complet..."
                sh '''
                    # Force delete everything
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true --force --grace-period=0
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true

                    # Delete any remaining pods
                    kubectl delete pods -n ${K8S_NAMESPACE} -l app=spring-app --force --grace-period=0 2>/dev/null || true

                    # Wait for cleanup
                    sleep 15

                    echo "=== État après nettoyage ==="
                    kubectl get all -n ${K8S_NAMESPACE}
                '''
            }
        }

        stage('Deploy to Kubernetes - SIMPLE') {
            steps {
                echo "🚀 Déploiement simple..."
                script {
                    // Créer un déploiement très simple d'abord
                    sh """
                        cat > k8s-simple.yaml << EOF
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
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes,mysql"
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:mysql://mysql-service:3306/springdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&createDatabaseIfNotExist=true"
        - name: SPRING_DATASOURCE_USERNAME
          value: "root"
        - name: SPRING_DATASOURCE_PASSWORD
          value: "root123"
        - name: SERVER_SERVLET_CONTEXT_PATH
          value: "${CONTEXT_PATH}"
        - name: MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS
          value: "always"
        - name: LOGGING_LEVEL_ROOT
          value: "INFO"
        # Pas de probes au début
        # readinessProbe:
        #   httpGet:
        #     path: ${CONTEXT_PATH}/actuator/health
        #     port: 8080
        #   initialDelaySeconds: 120
        #   periodSeconds: 10
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
EOF

                        echo "=== Application configuration ==="
                        kubectl apply -f k8s-simple.yaml

                        echo "=== Attente démarrage (3 minutes) ==="
                        for i in {1..180}; do
                            POD_STATUS=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
                            if [ "\$POD_STATUS" = "Running" ]; then
                                echo "✅ Pod en cours d'exécution après \$i secondes"
                                break
                            fi
                            echo "Statut après \$i sec: \$POD_STATUS"
                            sleep 1
                        done

                        echo "=== Logs du pod ==="
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Pod: \$POD_NAME"
                            kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=100
                        fi
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "✅ Vérification..."
                script {
                    sh """
                        echo "=== État complet ==="
                        kubectl get all -n ${K8S_NAMESPACE} -o wide

                        echo ""
                        echo "=== Décrire le pod ==="
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            kubectl describe pod -n ${K8S_NAMESPACE} \$POD_NAME

                            echo ""
                            echo "=== Test depuis le pod ==="
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- \\
                                sh -c "curl -s http://localhost:8080${CONTEXT_PATH}/actuator/health || curl -s http://localhost:8080/actuator/health || echo 'Échec'"
                        fi

                        echo ""
                        echo "=== Test externe ==="
                        MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "127.0.0.1")
                        echo "Minikube IP: \$MINIKUBE_IP"

                        curl -s -m 30 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" && \\
                            echo "✅ Application accessible" || echo "⚠️ Non accessible"
                    """
                }
            }
        }
    }

    post {
        always {
            echo "🏁 Cleanup..."
            sh '''
                # Cleanup
                rm -f Dockerfile k8s-simple.yaml || true
                docker rm -f test-img-* 2>/dev/null || true

                echo "=== État final ==="
                kubectl get pods -n ${K8S_NAMESPACE} -o wide
            '''
        }

        failure {
            echo "💥 DIAGNOSTIC COMPLET..."
            script {
                sh """
                    echo "=== 1. Événements Kubernetes ==="
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -30

                    echo ""
                    echo "=== 2. Décrire tous les pods ==="
                    kubectl describe pods -n ${K8S_NAMESPACE} | grep -A 20 "Events:" || true

                    echo ""
                    echo "=== 3. Vérifier MySQL ==="
                    kubectl get pods -n ${K8S_NAMESPACE} | grep mysql

                    echo ""
                    echo "=== 4. Logs de tous les pods Spring ==="
                    for pod in \$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o name); do
                        echo "--- \$pod ---"
                        kubectl logs -n ${K8S_NAMESPACE} \$pod --tail=50 || true
                    done

                    echo ""
                    echo "=== SOLUTIONS ==="
                    echo "1. Vérifier les logs de l'application (problème de démarrage)"
                    echo "2. Vérifier la connexion à MySQL:"
                    echo "   kubectl run test-mysql -n devops --image=mysql:8.0 -it --rm -- \\"
                    echo "     mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES;'"
                    echo "3. Redémarrer minikube: minikube delete && minikube start"
                """
            }
        }
    }
}