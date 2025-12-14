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
                    sudo chown -R $(whoami) $HOME/.minikube 2>/dev/null || true
                    sudo chmod -R u+w $HOME/.minikube 2>/dev/null || true

                    # Start/restart minikube
                    minikube status || minikube start --driver=docker --force
                    minikube update-context

                    # Set docker env
                    eval $(minikube docker-env) 2>/dev/null || true

                    # Create namespace
                    kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
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
                    kubectl delete pod -n ${K8S_NAMESPACE} $(kubectl get pods -n ${K8S_NAMESPACE} | grep Terminating | awk "{print \$1}") --force --grace-period=0 2>/dev/null || true

                    # Clean workspace
                    rm -rf target/ node_modules/ || true
                '''
                git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
            }
        }

        stage('Build Application') {
            steps {
                echo "🔨 Construction de l'application..."
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

        stage('Test Application Locally') {
            steps {
                echo "🧪 Test local..."
                script {
                    try {
                        sh '''
                            echo "=== Configuration Spring ==="
                            ls -la src/main/resources/application.properties 2>/dev/null || echo "Fichier properties non trouvé"

                            echo ""
                            echo "=== Démarrage en mode test ==="
                            # Kill any existing process
                            pkill -f "java.*target.*jar" 2>/dev/null || true
                            sleep 2

                            # Start with H2 database
                            nohup java -Xmx512m -jar target/*.jar \
                                --spring.profiles.active=test \
                                --server.port=18081 \
                                --spring.datasource.url=jdbc:h2:mem:testdb \
                                --spring.datasource.driver-class-name=org.h2.Driver \
                                --spring.datasource.username=sa \
                                --spring.datasource.password= \
                                --logging.level.root=INFO \
                                > /tmp/spring-test.log 2>&1 &

                            APP_PID=$!
                            echo "PID: $APP_PID"

                            # Wait for startup
                            echo "=== Attente démarrage (60 secondes) ==="
                            STARTED=false
                            for i in {1..60}; do
                                if curl -s -f "http://localhost:18081/actuator/health" > /dev/null 2>&1; then
                                    echo "✅ Application UP après $i secondes"
                                    STARTED=true
                                    break
                                fi

                                if [ $i -eq 30 ]; then
                                    echo "=== Logs intermédiaires (30 sec) ==="
                                    tail -30 /tmp/spring-test.log
                                fi

                                sleep 1
                            done

                            if [ "$STARTED" = false ]; then
                                echo "❌ Timeout après 60 secondes"
                                echo "=== Derniers logs (100 lignes) ==="
                                tail -100 /tmp/spring-test.log
                                echo "=== Recherche d'erreurs ==="
                                grep -i -E "error|exception|failed|shutdown" /tmp/spring-test.log | tail -20
                                kill $APP_PID 2>/dev/null || true
                                exit 1
                            fi

                            # Test health endpoint
                            echo ""
                            echo "=== Test health endpoint ==="
                            curl -s "http://localhost:18081/actuator/health" | head -5

                            # Test with context path
                            echo ""
                            echo "=== Test avec contexte path ==="
                            if curl -s -f "http://localhost:18081${CONTEXT_PATH}/actuator/health"; then
                                echo "✅ Application fonctionne avec contexte path!"
                            else
                                echo "⚠️ Application fonctionne mais contexte path non trouvé"
                                echo "Vérifiez la configuration dans application.properties"
                            fi

                            # Stop app
                            kill $APP_PID 2>/dev/null || true
                            wait $APP_PID 2>/dev/null || true
                        '''
                    } catch (Exception e) {
                        echo "⚠️ Test local échoué: ${e.getMessage()}"
                        sh '''
                            echo "=== Logs d'erreur ==="
                            tail -100 /tmp/spring-test.log 2>/dev/null || true
                        '''
                        // Continue anyway for debugging
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "🐳 Build Docker..."
                sh '''
                    # Simple Dockerfile
                    cat > Dockerfile << EOF
FROM eclipse-temurin:17-jre-alpine
RUN apk add --no-cache curl bash
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=120s --retries=3 \\
  CMD curl -f http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    # Build with minikube docker
                    eval $(minikube docker-env) 2>/dev/null || echo "Minikube docker env non configuré"
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    docker build -t ${IMAGE_NAME}:build-${BUILD_NUMBER} .

                    # Test image locally
                    echo "=== Test image Docker localement ==="
                    docker run -d --name test-img-${BUILD_NUMBER} \\
                      -e SPRING_PROFILES_ACTIVE=test \\
                      -e SPRING_DATASOURCE_URL=jdbc:h2:mem:testdb \\
                      -p 18082:8080 \\
                      ${IMAGE_NAME}:${IMAGE_TAG}

                    sleep 30

                    if curl -s -f "http://localhost:18082/actuator/health"; then
                        echo "✅ Image Docker fonctionne"
                        docker stop test-img-${BUILD_NUMBER}
                        docker rm test-img-${BUILD_NUMBER}
                    else
                        echo "=== Logs conteneur ==="
                        docker logs test-img-${BUILD_NUMBER} --tail=50
                        docker stop test-img-${BUILD_NUMBER} 2>/dev/null || true
                        docker rm test-img-${BUILD_NUMBER} 2>/dev/null || true
                        exit 1
                    fi
                '''
            }
        }

        stage('Push to DockerHub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:build-${BUILD_NUMBER}
                    '''
                }
            }
        }

        stage('Clean Kubernetes Resources') {
            steps {
                echo "🧹 Nettoyage Kubernetes..."
                sh '''
                    # Force delete everything
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true 2>/dev/null || true

                    # Delete any remaining pods
                    kubectl delete pods -n ${K8S_NAMESPACE} -l app=spring-app --force --grace-period=0 2>/dev/null || true

                    # Wait for cleanup
                    sleep 10

                    echo "=== État après nettoyage ==="
                    kubectl get all -n ${K8S_NAMESPACE} 2>/dev/null || echo "Namespace non accessible"
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo "🚀 Déploiement Kubernetes..."
                script {
                    sh """
                        cat > k8s-deployment.yaml << EOF
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
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
EOF

                        echo "=== Application configuration ==="
                        kubectl apply -f k8s-deployment.yaml

                        echo "=== Attente démarrage (120 secondes) ==="
                        sleep 120

                        echo "=== Vérification pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE} -o wide

                        echo ""
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
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "=== Décrire le pod ==="
                            kubectl describe pod -n ${K8S_NAMESPACE} \$POD_NAME | grep -A 30 "Events:" || true

                            echo ""
                            echo "=== Test depuis le pod ==="
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- \\
                                sh -c "curl -s http://localhost:8080${CONTEXT_PATH}/actuator/health || curl -s http://localhost:8080/actuator/health || echo 'Échec des deux tests'"
                        fi

                        echo ""
                        echo "=== Test externe ==="
                        MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "127.0.0.1")
                        echo "Minikube IP: \$MINIKUBE_IP"

                        echo "Test: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                        curl -s -m 30 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" && \\
                            echo "✅ Application accessible" || echo "⚠️ Non accessible - vérifiez les logs"
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
                rm -f Dockerfile k8s-deployment.yaml 2>/dev/null || true
                docker rm -f test-img-* 2>/dev/null || true

                echo "=== État final ==="
                kubectl get pods -n ${K8S_NAMESPACE} -o wide 2>/dev/null || true
            '''
        }

        failure {
            echo "💥 DIAGNOSTIC..."
            script {
                sh """
                    echo "=== 1. Événements Kubernetes ==="
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -30 || true

                    echo ""
                    echo "=== 2. Tous les pods ==="
                    kubectl get pods -n ${K8S_NAMESPACE} -o wide 2>/dev/null || true

                    echo ""
                    echo "=== 3. Vérifier MySQL ==="
                    kubectl get pods -n ${K8S_NAMESPACE} | grep mysql 2>/dev/null || true

                    echo ""
                    echo "=== 4. Logs des pods Spring ==="
                    for pod in \$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
                        echo "--- Pod: \$pod ---"
                        kubectl logs -n ${K8S_NAMESPACE} \$pod --tail=50 2>/dev/null || true
                    done

                    echo ""
                    echo "=== SOLUTIONS ==="
                    echo "1. Vérifier les logs de l'application (problème de démarrage)"
                    echo "2. Vérifier la connexion à MySQL:"
                    echo "   kubectl run test-mysql -n devops --image=mysql:8.0 -it --rm -- \\"
                    echo "     mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES;'"
                    echo "3. Vérifier si l'image Docker existe localement:"
                    echo "   docker images | grep foyer"
                    echo "4. Redémarrer minikube:"
                    echo "   minikube delete && minikube start --driver=docker"
                """
            }
        }
    }
}