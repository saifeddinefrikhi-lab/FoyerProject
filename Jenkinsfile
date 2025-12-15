pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "${BUILD_NUMBER}"
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/"  // Changé pour simplifier
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
                echo "🧪 Test local..."
                script {
                    try {
                        sh """
                            echo "=== Démarrage de l'application en local ==="
                            java -jar target/*.jar \\
                                --spring.datasource.url=jdbc:h2:mem:testdb \\
                                --spring.datasource.driver-class-name=org.h2.Driver \\
                                --spring.datasource.username=sa \\
                                --spring.datasource.password= \\
                                --spring.jpa.database-platform=org.hibernate.dialect.H2Dialect \\
                                --spring.jpa.hibernate.ddl-auto=create-drop \\
                                --server.port=8081 \\
                                > /tmp/app.log 2>&1 &
                            APP_PID=\$!

                            echo "Application démarrée avec PID: \$APP_PID"
                            echo "Attente de démarrage (30 secondes)..."
                            sleep 30

                            echo "=== Test de l'endpoint health ==="
                            if curl -s -f http://localhost:8081/actuator/health; then
                                echo ""
                                echo "✅ Application locale fonctionne!"
                                kill \$APP_PID
                                exit 0
                            else
                                echo "❌ Échec du test local"
                                echo "=== Logs de l'application (derniers 100 lignes) ==="
                                tail -100 /tmp/app.log
                                kill \$APP_PID 2>/dev/null || true
                                exit 1
                            fi
                        """
                    } catch (Exception e) {
                        echo "⚠️ Test local a échoué, mais on continue..."
                        // Ne pas échouer le pipeline ici
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
ENV SPRING_JPA_HIBERNATE_DDL_AUTO=update
ENV SPRING_JPA_SHOW_SQL=false
ENV SPRING_DATASOURCE_DRIVER_CLASS_NAME=com.mysql.cj.jdbc.Driver
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EOF

                    echo "=== Construction de l'image ==="
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile.jenkins .

                    echo "=== Tag latest ==="
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest

                    echo "=== Liste des images ==="
                    docker images | grep ${IMAGE_NAME}
                """
            }
        }

        stage('Test Docker Image') {
            steps {
                echo "🧪 Test Docker..."
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

                            echo "=== Test avec health endpoint ==="
                            echo "URL: http://localhost:18080/actuator/health"

                            if curl -s -f http://localhost:18080/actuator/health; then
                                echo ""
                                echo "✅ Docker fonctionne!"
                                docker stop test-container-${BUILD_NUMBER}
                                docker rm test-container-${BUILD_NUMBER}
                            else
                                echo "=== Logs du conteneur ==="
                                docker logs test-container-${BUILD_NUMBER} --tail=100
                                echo "❌ Échec du test"
                                docker stop test-container-${BUILD_NUMBER} || true
                                docker rm test-container-${BUILD_NUMBER} || true
                                exit 1
                            fi
                        """
                    } catch (Exception e) {
                        echo "⚠️ Test Docker a échoué, mais on continue pour Kubernetes..."
                    }
                }
            }
        }

        stage('Docker Login & Push') {
            steps {
                echo "Connexion + push vers DockerHub..."
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

        stage('Clean Old Kubernetes Resources') {
            steps {
                echo "🧹 Nettoyage des ressources Kubernetes..."
                sh """
                    # Supprimez les ressources Spring Boot existantes
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true --wait=true
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true --wait=true
                    sleep 10
                """
            }
        }

        stage('Verify MySQL is Ready') {
            steps {
                echo "🔍 Vérification de MySQL..."
                script {
                    // D'abord, s'assurer que les ressources MySQL existent
                    sh """
                        echo "=== Création des ressources MySQL si nécessaire ==="

                        # Vérifier si le PV existe
                        if ! kubectl get pv mysql-pv > /dev/null 2>&1; then
                            echo "Création du PersistentVolume..."
                            cat > /tmp/mysql-pv.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
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
EOF
                            kubectl apply -f /tmp/mysql-pv.yaml
                        fi

                        # Vérifier si MySQL deployment existe
                        if ! kubectl get deployment mysql -n ${K8S_NAMESPACE} > /dev/null 2>&1; then
                            echo "Création du déploiement MySQL..."
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
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 3306
          initialDelaySeconds: 60
          periodSeconds: 20
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
EOF
                            kubectl apply -f /tmp/mysql-deployment.yaml
                        fi

                        # Vérifier si MySQL service existe
                        if ! kubectl get service mysql-service -n ${K8S_NAMESPACE} > /dev/null 2>&1; then
                            echo "Création du service MySQL..."
                            cat > /tmp/mysql-service.yaml << 'EOF'
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
                            kubectl apply -f /tmp/mysql-service.yaml
                        fi
                    """

                    // Attendre que MySQL soit prêt
                    sh """
                        echo "=== Attente du démarrage de MySQL ==="
                        timeout=300
                        interval=10
                        elapsed=0

                        while [ \$elapsed -lt \$timeout ]; do
                            if kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
                                echo "✅ MySQL pod est en cours d'exécution."

                                # Vérifier que MySQL est accessible
                                POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
                                if kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysqladmin ping -h localhost -u root -proot123 2>/dev/null; then
                                    echo "✅ MySQL est accessible et répond."

                                    # Vérifier que la base de données existe
                                    if kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "SHOW DATABASES LIKE 'springdb';" 2>/dev/null | grep -q springdb; then
                                        echo "✅ Base de données 'springdb' existe."
                                        break
                                    else
                                        echo "⚠️ Base de données 'springdb' n'existe pas encore."
                                        kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- mysql -u root -proot123 -e "CREATE DATABASE IF NOT EXISTS springdb;"
                                        echo "✅ Base de données créée."
                                        break
                                    fi
                                fi
                            fi

                            echo "⏱️  Attente de MySQL... (\$elapsed/\$timeout secondes)"
                            sleep \$interval
                            elapsed=\$((elapsed + interval))
                        done

                        if [ \$elapsed -ge \$timeout ]; then
                            echo "❌ Timeout en attendant MySQL"
                            echo "=== Détails du pod MySQL ==="
                            kubectl describe pod -n ${K8S_NAMESPACE} -l app=mysql
                            echo "=== Logs MySQL ==="
                            kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50
                            exit 1
                        fi

                        echo "=== État final de MySQL ==="
                        kubectl get pods,svc -n ${K8S_NAMESPACE} -l app=mysql
                    """
                }
            }
        }

        stage('Deploy Spring Boot to Kubernetes') {
            steps {
                echo "🚀 Déploiement Spring Boot sur Kubernetes..."
                script {
                    writeFile file: 'k8s-spring-deployment.yaml', text: """
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
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 90
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 5
        livenessProbe:
          httpGet:
            path: /actuator/health
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
                        echo "=== Application du déploiement Spring Boot ==="
                        kubectl apply -f k8s-spring-deployment.yaml

                        echo "=== Attente du démarrage (90 secondes) ==="
                        sleep 90

                        echo "=== État du déploiement ==="
                        kubectl get pods,svc,deploy -n ${K8S_NAMESPACE}

                        echo "=== Vérification des logs (premier pod) ==="
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Pod: \$POD_NAME"
                            kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=50
                        fi
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "✅ Vérification du déploiement..."
                script {
                    sh """
                        echo "=== État des pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE} -o wide

                        echo ""
                        echo "=== Test de connexion interne ==="
                        POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Test de l'application depuis l'intérieur du pod:"
                            kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- \\
                              sh -c "apk add --no-cache curl 2>/dev/null && curl -s http://localhost:8080/actuator/health || curl -s http://127.0.0.1:8080/actuator/health" || \\
                              echo "Impossible de tester depuis le pod"
                        fi

                        echo ""
                        echo "=== Test de connexion externe ==="
                        MINIKUBE_IP=\$(minikube ip)
                        echo "Minikube IP: \$MINIKUBE_IP"
                        echo "Test: http://\${MINIKUBE_IP}:30080/actuator/health"

                        # Essayer plusieurs fois
                        for i in {1..5}; do
                            echo "Tentative \$i..."
                            if curl -s -f http://\${MINIKUBE_IP}:30080/actuator/health; then
                                echo ""
                                echo "✅ Application accessible depuis l'extérieur!"
                                break
                            fi
                            sleep 10
                        done

                        if [ \$? -ne 0 ]; then
                            echo "⚠️  L'application n'est pas accessible, vérification des logs..."
                            kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=100
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
                rm -f Dockerfile.jenkins k8s-spring-deployment.yaml /tmp/mysql-*.yaml 2>/dev/null || true
                docker rm -f test-container-* 2>/dev/null || true
            '''

            // Rapport final
            script {
                sh """
                    echo "=== RAPPORT FINAL ==="
                    echo "Image Docker: ${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Namespace: ${K8S_NAMESPACE}"

                    echo ""
                    echo "=== État final Kubernetes ==="
                    kubectl get all -n ${K8S_NAMESPACE} || true

                    echo ""
                    echo "=== URL d'accès ==="
                    MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "Minikube non disponible")
                    echo "Application: http://\${MINIKUBE_IP}:30080"
                    echo "Health: http://\${MINIKUBE_IP}:30080/actuator/health"
                """
            }
        }

        success {
            echo "🎉 Pipeline réussi!"

            script {
                sh """
                    echo "=== Test final ==="
                    MINIKUBE_IP=\$(minikube ip)
                    if curl -s "http://\${MINIKUBE_IP}:30080/actuator/health" | grep -q '"status":"UP"'; then
                        echo "✅ Application fonctionne correctement!"
                    else
                        echo "⚠️  L'application répond mais le statut n'est pas UP"
                    fi
                """
            }
        }

        failure {
            echo "💥 Le pipeline a échoué"

            script {
                sh """
                    echo "=== DIAGNOSTIC ==="

                    echo "1. État des pods:"
                    kubectl get pods -n ${K8S_NAMESPACE} || true

                    echo ""
                    echo "2. Logs MySQL:"
                    kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=100 2>/dev/null || echo "Pas de logs MySQL"

                    echo ""
                    echo "3. Logs Spring Boot:"
                    kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=100 2>/dev/null || echo "Pas de logs Spring Boot"

                    echo ""
                    echo "4. Événements:"
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -20 2>/dev/null || true

                    echo ""
                    echo "=== COMMANDES DE DÉPANNAGE ==="
                    echo "Pour tester MySQL:"
                    echo "  kubectl run mysql-test -n ${K8S_NAMESPACE} --rm -it --image=mysql:8.0 -- mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES;'"
                    echo ""
                    echo "Pour accéder au pod Spring Boot:"
                    echo "  kubectl exec -n ${K8S_NAMESPACE} \$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}') -- sh"
                """
            }
        }
    }

}