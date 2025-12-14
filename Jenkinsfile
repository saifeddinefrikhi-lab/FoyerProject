pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
        K8S_NAMESPACE = "devops"
        TIMESTAMP = sh(script: 'date +%Y%m%d%H%M%S', returnStdout: true).trim()
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

        stage('Test Local') {
            steps {
                echo "🧪 Test local de l'application..."
                script {
                    try {
                        sh '''
                            echo "=== Démarrage de l'application en local ==="
                            # Démarrez l'application en arrière-plan avec H2
                            java -jar target/*.jar \
                                --spring.datasource.url=jdbc:h2:mem:testdb \
                                --spring.datasource.driver-class-name=org.h2.Driver \
                                --spring.datasource.username=sa \
                                --spring.datasource.password= \
                                --spring.jpa.database-platform=org.hibernate.dialect.H2Dialect \
                                --spring.jpa.hibernate.ddl-auto=create-drop \
                                --server.port=8081 \
                                > /tmp/app.log 2>&1 &
                            APP_PID=$!

                            echo "Application démarrée avec PID: $APP_PID"
                            echo "Attente de démarrage (30 secondes)..."
                            sleep 30

                            echo "=== Test de l'endpoint health ==="
                            if curl -s -f http://localhost:8081/actuator/health; then
                                echo ""
                                echo "✅ Application locale fonctionne!"
                            else
                                echo "❌ Échec du test local"
                                echo "=== Logs de l'application ==="
                                tail -50 /tmp/app.log
                                kill $APP_PID 2>/dev/null || true
                                exit 1
                            fi

                            kill $APP_PID
                            sleep 5
                        '''
                    } catch (Exception e) {
                        sh '''
                            echo "=== Logs d'erreur ==="
                            tail -100 /tmp/app.log || true
                        '''
                        error "❌ Le test local a échoué"
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "🐳 Construction de l'image Docker..."
                sh '''
                    # Créez un Dockerfile simple et efficace
                    cat > Dockerfile.jenkins << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    echo "=== Construction de l'image ==="
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -t ${IMAGE_NAME}:${TIMESTAMP} -f Dockerfile.jenkins .

                    echo "=== Liste des images ==="
                    docker images | grep ${IMAGE_NAME}
                '''
            }
        }

        stage('Test Docker Image') {
            steps {
                echo "🧪 Test de l'image Docker..."
                script {
                    try {
                        sh """
                            echo "=== Démarrage du conteneur Docker ==="
                            docker run -d --name test-container-${BUILD_NUMBER} \\
                              -e SPRING_DATASOURCE_URL="jdbc:h2:mem:testdb" \\
                              -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \\
                              -e SPRING_DATASOURCE_USERNAME="sa" \\
                              -e SPRING_DATASOURCE_PASSWORD="" \\
                              -e SPRING_JPA_HIBERNATE_DDL_AUTO="create-drop" \\
                              -p 18080:8080 \\
                              ${IMAGE_NAME}:${IMAGE_TAG}

                            echo "Attente de démarrage (40 secondes)..."
                            sleep 40

                            echo "=== Test de l'application dans Docker ==="
                            if curl -s -f http://localhost:18080/actuator/health; then
                                echo ""
                                echo "✅ Image Docker fonctionne!"
                            else
                                echo "=== Logs du conteneur ==="
                                docker logs test-container-${BUILD_NUMBER} --tail=100
                                docker stop test-container-${BUILD_NUMBER} || true
                                docker rm test-container-${BUILD_NUMBER} || true
                                exit 1
                            fi

                            docker stop test-container-${BUILD_NUMBER}
                            docker rm test-container-${BUILD_NUMBER}
                        """
                    } catch (Exception e) {
                        sh """
                            echo "=== Tentative de récupération des logs ==="
                            docker logs test-container-${BUILD_NUMBER} --tail=200 || true
                            docker stop test-container-${BUILD_NUMBER} || true
                            docker rm test-container-${BUILD_NUMBER} || true
                        """
                        error "❌ Le test Docker a échoué"
                    }
                }
            }
        }

        stage('Docker Login & Push') {
            steps {
                echo "🔐 Connexion et push vers DockerHub..."
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo "=== Connexion à DockerHub ==="
                        echo "\$DOCKER_PASS" | docker login -u "\$DOCKER_USER" --password-stdin

                        echo "=== Push des images ==="
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${IMAGE_NAME}:${TIMESTAMP}

                        echo "✅ Images poussées avec succès"
                    """
                }
            }
        }

        stage('Kubernetes Deploy') {
            steps {
                echo "🚀 Déploiement sur Kubernetes..."
                script {
                    // 1. Supprimer l'ancien déploiement
                    sh """
                        echo "=== Nettoyage de l'ancien déploiement ==="
                        kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true
                        kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true
                        sleep 10
                    """

                    // 2. Créer le fichier de déploiement
                    writeFile file: 'k8s-deploy.yaml', text: """
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
# Déploiement de l'application
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${K8S_NAMESPACE}
  labels:
    app: spring-app
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
        image: ${IMAGE_NAME}:${TIMESTAMP}
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
        - name: SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT
          value: "org.hibernate.dialect.MySQL8Dialect"
        - name: SPRING_JPA_SHOW_SQL
          value: "true"
        - name: SERVER_PORT
          value: "8080"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
"""

                    // 3. Appliquer la configuration
                    sh """
                        echo "=== Application de la configuration Kubernetes ==="
                        kubectl apply -f k8s-deploy.yaml
                    """

                    // 4. Attendre le déploiement
                    timeout(time: 5, unit: 'MINUTES') {
                        script {
                            waitUntil {
                                def pods = sh(
                                    script: "kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[*].status.phase}'",
                                    returnStdout: true
                                ).trim()

                                if (pods.contains("Running")) {
                                    echo "✅ Pod en cours d'exécution"
                                    return true
                                } else if (pods.contains("Err") || pods.contains("Fail")) {
                                    error "❌ Pod en erreur"
                                }

                                echo "⏳ Attente du démarrage du pod..."
                                sleep 10
                                return false
                            }
                        }
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "✅ Vérification du déploiement..."
                script {
                    // Attendre que l'application soit prête
                    sleep 30

                    sh """
                        echo "=== État des ressources Kubernetes ==="
                        kubectl get all -n ${K8S_NAMESPACE}

                        echo ""
                        echo "=== Logs de l'application ==="
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Pod: \$POD_NAME"
                            kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=50
                        else
                            echo "Aucun pod trouvé"
                        fi

                        echo ""
                        echo "=== Test de l'application ==="
                        MINIKUBE_IP=\$(minikube ip)
                        if curl -s -f http://\${MINIKUBE_IP}:30080/actuator/health; then
                            echo ""
                            echo "✅ L'application est accessible!"
                        else
                            echo "⚠️  L'application n'est pas encore accessible, vérifiez les logs"
                        fi
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
                rm -f Dockerfile.jenkins k8s-deploy.yaml || true
                docker rm -f test-container-* 2>/dev/null || true
                docker system prune -f || true
            '''

            // Rapport final
            script {
                sh """
                    echo "=== RAPPORT FINAL ==="
                    echo "Image Docker: ${IMAGE_NAME}:${TIMESTAMP}"
                    echo "Namespace: ${K8S_NAMESPACE}"

                    echo ""
                    echo "=== État final ==="
                    kubectl get pods,svc,deploy -n ${K8S_NAMESPACE} || true
                """
            }
        }

        success {
            echo "🎉 Pipeline réussi!"

            script {
                // Obtenir l'URL d'accès
                sh """
                    echo "=== URL d'accès ==="
                    minikube service spring-service -n ${K8S_NAMESPACE} --url || echo "Service: http://\$(minikube ip):30080"
                """
            }
        }

        failure {
            echo "💥 Le pipeline a échoué"

            script {
                // Diagnostic détaillé
                sh """
                    echo "=== DIAGNOSTIC DÉTAILLÉ ==="

                    echo "1. Décrire le déploiement:"
                    kubectl describe deployment spring-app -n ${K8S_NAMESPACE} 2>/dev/null || echo "Pas de déploiement"

                    echo ""
                    echo "2. Événements récents:"
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -20 || true

                    echo ""
                    echo "3. Logs complets du dernier pod:"
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200
                    fi

                    echo ""
                    echo "=== COMMANDES DE DÉPANNAGE ==="
                    echo "1. Vérifier la connexion MySQL:"
                    echo "   kubectl run mysql-test -n devops --image=mysql:8.0 -it --rm -- mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES;'"
                    echo ""
                    echo "2. Accéder au shell du pod:"
                    echo "   kubectl exec -n devops -it \$POD_NAME -- /bin/sh"
                    echo ""
                    echo "3. Redémarrer le déploiement:"
                    echo "   kubectl rollout restart deployment/spring-app -n devops"
                """
            }
        }
    }
}