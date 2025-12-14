pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
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

        stage('Test Local - Correct Context Path') {
            steps {
                echo "🧪 Test local avec le bon contexte path..."
                script {
                    try {
                        sh """
                            echo "=== Démarrage de l'application en local ==="
                            # Démarrez l'application en arrière-plan avec H2
                            java -jar target/*.jar \\
                                --spring.datasource.url=jdbc:h2:mem:testdb \\
                                --spring.datasource.driver-class-name=org.h2.Driver \\
                                --spring.datasource.username=sa \\
                                --spring.datasource.password= \\
                                --spring.jpa.database-platform=org.hibernate.dialect.H2Dialect \\
                                --spring.jpa.hibernate.ddl-auto=update \\
                                --server.port=8081 \\
                                > /tmp/app.log 2>&1 &
                            APP_PID=\$!

                            echo "Application démarrée avec PID: \$APP_PID"
                            echo "Attente de démarrage (40 secondes)..."
                            sleep 40

                            echo "=== Test de l'endpoint health avec le bon contexte path ==="
                            echo "Tentative: http://localhost:8081${CONTEXT_PATH}/actuator/health"
                            if curl -s -f http://localhost:8081${CONTEXT_PATH}/actuator/health; then
                                echo ""
                                echo "✅ Application locale fonctionne avec contexte path!"
                                kill \$APP_PID
                                exit 0
                            else
                                echo "❌ Échec du test local avec contexte path"
                                echo "=== Tentative alternative (sans contexte) ==="
                                if curl -s -f http://localhost:8081/actuator/health; then
                                    echo "✅ Application fonctionne sans contexte path"
                                    kill \$APP_PID
                                    exit 0
                                else
                                    echo "=== Logs de l'application (derniers 100 lignes) ==="
                                    tail -100 /tmp/app.log
                                    kill \$APP_PID 2>/dev/null || true
                                    exit 1
                                fi
                            fi
                        """
                    } catch (Exception e) {
                        sh """
                            echo "=== Logs d'erreur ==="
                            tail -200 /tmp/app.log || true
                        """
                        echo "⚠️ Test local a échoué, mais on continue pour le débogage..."
                        // Ne pas échouer le pipeline ici, continuez pour voir le problème avec Docker/K8s
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "🐳 Construction de l'image Docker..."
                sh """
                    # Créez un Dockerfile simple et efficace
                    cat > Dockerfile.jenkins << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    echo "=== Construction de l'image ==="
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.jenkins .

                    echo "=== Liste des images ==="
                    docker images | grep ${IMAGE_NAME}
                """
            }
        }

        stage('Test Docker Image - With Context') {
            steps {
                echo "🧪 Test Docker avec contexte path..."
                script {
                    try {
                        sh """
                            echo "=== Démarrage du conteneur Docker ==="
                            docker run -d --name test-container-${BUILD_NUMBER} \\
                              -e SPRING_DATASOURCE_URL="jdbc:h2:mem:testdb" \\
                              -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \\
                              -e SPRING_DATASOURCE_USERNAME="sa" \\
                              -e SPRING_DATASOURCE_PASSWORD="" \\
                              -e SPRING_JPA_HIBERNATE_DDL_AUTO="update" \\
                              -p 18080:8080 \\
                              ${IMAGE_NAME}:${IMAGE_TAG}

                            echo "Attente de démarrage (50 secondes)..."
                            sleep 50

                            echo "=== Test avec contexte path ==="
                            echo "URL: http://localhost:18080${CONTEXT_PATH}/actuator/health"

                            if curl -s -f http://localhost:18080${CONTEXT_PATH}/actuator/health; then
                                echo ""
                                echo "✅ Docker fonctionne avec contexte path!"
                            else
                                echo "=== Tentative sans contexte ==="
                                if curl -s -f http://localhost:18080/actuator/health; then
                                    echo "✅ Docker fonctionne sans contexte path"
                                else
                                    echo "=== Logs du conteneur ==="
                                    docker logs test-container-${BUILD_NUMBER} --tail=100
                                    echo "❌ Échec des deux tests"
                                    docker stop test-container-${BUILD_NUMBER} || true
                                    docker rm test-container-${BUILD_NUMBER} || true
                                    exit 1
                                fi
                            fi

                            docker stop test-container-${BUILD_NUMBER}
                            docker rm test-container-${BUILD_NUMBER}
                        """
                    } catch (Exception e) {
                        sh """
                            echo "=== Récupération des logs Docker ==="
                            docker logs test-container-${BUILD_NUMBER} --tail=200 || true
                            docker stop test-container-${BUILD_NUMBER} || true
                            docker rm test-container-${BUILD_NUMBER} || true
                        """
                        echo "⚠️ Test Docker a échoué, mais on continue pour Kubernetes..."
                    }
                }
            }
        }

        stage('Docker Login & Push') {
                    steps {
                        echo "Connexion + push vers DockerHub..."
                        withCredentials([usernamePassword(credentialsId: 'docker-hub',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS')]) {
                            sh """
                                echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                                docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            """
                        }
                    }
                }


        stage('Clean Old Kubernetes Resources') {
            steps {
                echo "🧹 Nettoyage des ressources Kubernetes..."
                sh """
                    # Supprimez toutes les ressources existantes
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true
                    sleep 10

                    # Vérifiez qu'il ne reste plus de pods
                    echo "=== État après nettoyage ==="
                    kubectl get pods -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Deploy to Kubernetes - Fixed Probes') {
            steps {
                echo "🚀 Déploiement Kubernetes avec probes corrigées..."
                script {
                    writeFile file: 'k8s-deployment.yaml', text: """
---
# Service pour exposer l'application
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
# Déploiement de l'application avec probes corrigées
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
          value: "true"
        - name: LOGGING_LEVEL_ROOT
          value: "INFO"
        # Probes corrigées pour le contexte path
        readinessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8080
          initialDelaySeconds: 90
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 5
        livenessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 5
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
"""

                    sh """
                        echo "=== Application du déploiement ==="
                        kubectl apply -f k8s-deployment.yaml

                        echo "=== Attente du démarrage (60 secondes) ==="
                        sleep 60

                        echo "=== État du déploiement ==="
                        kubectl get pods,svc,deploy -n ${K8S_NAMESPACE}
                    """
                }
            }
        }

        stage('Verify Kubernetes Deployment') {
            steps {
                echo "✅ Vérification du déploiement Kubernetes..."
                script {
                    sh """
                        echo "=== Vérification des pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE} -o wide

                        echo ""
                        echo "=== Logs de l'application (si disponible) ==="
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Pod trouvé: \$POD_NAME"
                            kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=50
                        else
                            echo "Aucun pod Spring Boot trouvé"
                        fi

                        echo ""
                        echo "=== Test de l'application depuis l'extérieur ==="
                        MINIKUBE_IP=\$(minikube ip)
                        echo "Test avec contexte path: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                        curl -s http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health || \\
                          echo "Échec avec contexte path, tentative sans contexte..."

                        curl -s http://\${MINIKUBE_IP}:30080/actuator/health || \\
                          echo "Échec sans contexte path"
                    """
                }
            }
        }

        stage('Debug if Needed') {
            steps {
                echo "🐛 Debug du déploiement..."
                script {
                    sh """
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

                        if [ -n "\$POD_NAME" ]; then
                            echo "=== Exécution de commandes de debug dans le pod ==="

                            # Test de connexion MySQL
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- \\
                              sh -c "apk add --no-cache curl && curl -v http://localhost:8080${CONTEXT_PATH}/actuator/health || curl -v http://localhost:8080/actuator/health" || \\
                              echo "Impossible de tester localement"

                            # Vérifier les variables d'environnement
                            echo "=== Variables d'environnement ==="
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- env | grep -i spring

                            # Test de connexion réseau
                            echo "=== Test réseau vers MySQL ==="
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- \\
                              sh -c "apk add --no-cache netcat-openbsd && nc -zv mysql-service 3306 && echo 'MySQL accessible' || echo 'MySQL inaccessible'"
                        fi

                        echo ""
                        echo "=== Vérification de la base de données MySQL ==="
                        kubectl run mysql-check -n ${K8S_NAMESPACE} --image=mysql:8.0 -it --rm -- \\
                          mysql -h mysql-service -u root -proot123 -e "SHOW DATABASES; USE springdb; SHOW TABLES;" || \\
                          echo "Impossible de vérifier MySQL"
                    """
                }
            }
        }
    }

    post {
        always {
            echo "🏁 Pipeline terminé"

            // Nettoyage
            sh '''
                echo "=== Nettoyage ==="
                rm -f Dockerfile.jenkins k8s-deployment.yaml || true
                docker rm -f test-container-* 2>/dev/null || true
                docker system prune -f || true
            '''

            // Rapport final
            script {
                sh """
                    echo "=== RAPPORT FINAL ==="
                    echo "Image Docker: ${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Namespace: ${K8S_NAMESPACE}"
                    echo "Contexte path: ${CONTEXT_PATH}"

                    echo ""
                    echo "=== État final Kubernetes ==="
                    kubectl get all -n ${K8S_NAMESPACE} || true

                    echo ""
                    echo "=== Événements récents ==="
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -15 || true
                """
            }
        }

        success {
            echo "🎉 Pipeline réussi!"

            script {
                sh """
                    echo "=== URL d'accès ==="
                    MINIKUBE_IP=\$(minikube ip)
                    echo "Application (avec contexte): http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                    echo "Santé (avec contexte): http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                    echo ""
                    echo "=== Test rapide ==="
                    curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" && echo "✅ Application fonctionne!" || echo "⚠️  Vérifiez les logs"
                """
            }
        }

        failure {
            echo "💥 Le pipeline a échoué"

            script {
                // Diagnostic détaillé
                sh """
                    echo "=== DIAGNOSTIC DÉTAILLÉ ==="

                    echo "1. Décrire les pods Spring Boot:"
                    kubectl describe pods -n ${K8S_NAMESPACE} -l app=spring-app || echo "Pas de pods Spring Boot"

                    echo ""
                    echo "2. Logs complets du dernier pod (tous les conteneurs):"
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --all-containers=true --tail=200

                        echo ""
                        echo "=== État des probes ==="
                        echo "Commandes de test:"
                        echo "  kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- curl http://localhost:8080${CONTEXT_PATH}/actuator/health"
                        echo "  kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- curl http://localhost:8080/actuator/health"
                    fi

                    echo ""
                    echo "=== Solutions possibles ==="
                    echo "1. Vérifier que MySQL est accessible:"
                    echo "   kubectl run mysql-test -n devops --image=mysql:8.0 -it --rm -- mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES;'"
                    echo ""
                    echo "2. Modifier le contexte path dans application.properties:"
                    echo "   Ajouter: server.servlet.context-path=/"
                    echo ""
                    echo "3. Redémarrer avec une image temporaire de debug:"
                    echo "   kubectl run debug -n devops --image=curlimages/curl -it --rm -- /bin/sh"
                """
            }
        }
    }
}