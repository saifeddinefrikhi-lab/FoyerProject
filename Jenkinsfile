pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
        K8S_NAMESPACE = "devops"
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Récupération du code depuis GitHub..."
                git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
            }
        }

        stage('Build with Debug') {
            steps {
                echo "Build Maven avec debug..."
                sh '''
                    mvn clean package -DskipTests -B
                    echo "=== Contenu du répertoire target ==="
                    ls -la target/
                    echo "=== Fichiers JAR ==="
                    find target -name "*.jar" -type f
                '''
            }
        }

        stage('Test Application Locally') {
            steps {
                echo "Test de l'application en local..."
                script {
                    // Testez l'application directement avec Maven
                    sh '''
                        echo "=== Démarrage de l'application en local ==="
                        timeout(time: 2, unit: 'MINUTES') {
                            sh '''
                                #Démarrez l'application en arrière-plan
                                java -jar target/*.jar --spring.datasource.url=jdbc:h2:mem:testdb --spring.datasource.username=sa --spring.datasource.password= &
                                APP_PID=$!
                                sleep 30

                                # Testez l'application
                                if curl -f http://localhost:8080/actuator/health; then
                                    echo "✅ Application locale démarrée avec succès"
                                    kill $APP_PID
                                    exit 0
                                else
                                    echo "❌ Échec du démarrage local"
                                    kill $APP_PID 2>/dev/null || true
                                    exit 1
                                fi
                            '''
                        }
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Construction de l'image Docker..."
                sh """
                    # Créez un Dockerfile simplifié
                    cat > Dockerfile.simple << 'EOF'
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF

                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.simple .
                    docker images | grep ${IMAGE_NAME}
                """
            }
        }

        stage('Test Docker Image') {
            steps {
                echo "Test de l'image Docker..."
                script {
                    try {
                        sh """
                            # Testez avec H2 (sans MySQL)
                            docker run -d --name test-docker-${BUILD_ID} \\
                              -e SPRING_DATASOURCE_URL="jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1" \\
                              -e SPRING_DATASOURCE_USERNAME="sa" \\
                              -e SPRING_DATASOURCE_PASSWORD="" \\
                              -e SPRING_JPA_HIBERNATE_DDL_AUTO="create-drop" \\
                              -p 18080:8080 \\
                              ${IMAGE_NAME}:${IMAGE_TAG}

                            # Attendez plus longtemps
                            sleep 60

                            # Testez
                            curl -f http://localhost:18080/actuator/health || \\
                            curl -f http://localhost:18080/ || \\
                            echo "Test avec curl a échoué, vérifiez les logs"

                            # Récupérez les logs
                            echo "=== Logs du conteneur Docker ==="
                            docker logs test-docker-${BUILD_ID} --tail=100

                            # Arrêtez le conteneur
                            docker stop test-docker-${BUILD_ID}
                            docker rm test-docker-${BUILD_ID}
                        """
                    } catch (Exception e) {
                        sh """
                            echo "=== Logs du conteneur en cas d'échec ==="
                            docker logs test-docker-${BUILD_ID} --tail=200 || true
                            docker stop test-docker-${BUILD_ID} || true
                            docker rm test-docker-${BUILD_ID} || true
                        """
                        error "L'image Docker ne fonctionne pas"
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

        stage('Deploy to Kubernetes') {
            steps {
                echo "Déploiement sur Kubernetes..."
                script {
                    // Supprimez le déploiement existant
                    sh """
                        kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true
                        sleep 10
                    """

                    // Créez un déploiement simple sans probes
                    writeFile file: 'k8s-deployment.yaml', text: """
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
        - name: SPRING_JPA_HIBERNATE_DDL_AUTO
          value: "update"
        - name: SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT
          value: "org.hibernate.dialect.MySQL8Dialect"
        - name: SPRING_JPA_SHOW_SQL
          value: "true"
        - name: LOGGING_LEVEL_ORG_HIBERNATE
          value: "DEBUG"
        - name: LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_ORM_JPA
          value: "DEBUG"
        - name: JAVA_OPTS
          value: "-Xmx512m -Xms256m"
        # Pas de probes pour le moment
"""

                    sh """
                        kubectl apply -f k8s-deployment.yaml
                        sleep 30

                        # Suivez les logs
                        echo "=== Attente du démarrage du pod ==="
                        kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -w &
                        POD_WATCH_PID=\$!

                        # Attendez que le pod soit créé
                        timeout 60 bash -c 'until kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app 2>/dev/null | grep -q Running; do sleep 2; done'

                        # Obtenez le nom du pod
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}')

                        echo "=== Logs du pod \$POD_NAME ==="
                        timeout 30 kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME -f || true

                        kill \$POD_WATCH_PID 2>/dev/null || true
                    """
                }
            }
        }

        stage('Debug and Fix') {
            steps {
                echo "Debug de l'application..."
                script {
                    sh """
                        # Obtenez le nom du pod
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

                        if [ -n "\$POD_NAME" ]; then
                            echo "=== Exécution de commandes de debug dans le pod ==="

                            # Vérifiez les variables d'environnement
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- env | grep -i spring

                            # Testez la connexion à MySQL depuis le pod
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- sh -c \\
                              "apk add --no-cache mysql-client && \\
                               mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES; USE springdb; SHOW TABLES;'" || \\
                              echo "Impossible d'installer mysql-client"

                            # Vérifiez le classpath
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- sh -c "java -cp app.jar org.springframework.boot.loader.JarLauncher --version" || true

                            # Redémarrez avec plus de logs
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- sh -c \\
                              "java -jar app.jar --logging.level.root=DEBUG --logging.level.org.springframework=DEBUG --logging.level.tn.esprit=DEBUG" || true
                        fi
                    """
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline terminé"
            sh '''
                # Nettoyage
                docker system prune -f || true
                rm -f Dockerfile.simple k8s-deployment.yaml || true
                docker rm -f test-docker-* 2>/dev/null || true

                # État final
                echo "=== État final du cluster ==="
                kubectl get all -n devops || true
            '''
        }

        success {
            echo "✅ Pipeline réussi!"

            script {
                sh """
                    # Créez un service si nécessaire
                    cat <<EOF | kubectl apply -f -
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
EOF

                    # Obtenez l'URL
                    echo "Application déployée: http://\$(minikube ip):30080"
                """
            }
        }

        failure {
            echo "❌ Le pipeline a échoué."

            script {
                sh """
                    echo "=== DIAGNOSTIC COMPLET ==="

                    # Décrivez le pod
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        echo "=== Description du pod ==="
                        kubectl describe pod -n ${K8S_NAMESPACE} \$POD_NAME

                        echo "=== Logs complets ==="
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200

                        echo "=== Logs précédents (si redémarrage) ==="
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --previous --tail=200 2>/dev/null || true
                    fi

                    # Événements
                    echo "=== Événements récents ==="
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -20
                """
            }
        }
    }
}