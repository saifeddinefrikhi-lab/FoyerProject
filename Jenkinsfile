pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
        DOCKERHUB_CREDENTIALS = credentials('docker-hub')
        SONAR_HOST_URL = "http://192.168.59.100:9000"  // Remplacez par votre IP Minikube/SonarQube
        SONAR_PROJECT_KEY = "foyer-project"
        SONAR_TOKEN = credentials('sonar-token')  // Credential créé dans Jenkins
    }

    triggers {
        githubPush()
    }

    stages {
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
                    // Configuration pour l'analyse SonarQube
                    withSonarQubeEnv('SonarQube') { // Nom du serveur SonarQube configuré dans Jenkins
                        sh '''
                            echo "=== Démarrage de l'analyse SonarQube ==="

                            # Option 1: Utilisation du scanner Maven (si plugin Sonar dans pom.xml)
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
                                -DskipTests=false

                            # Attendre que l'analyse soit terminée
                            sleep 30
                        '''
                    }

                    // Attendre le résultat du Quality Gate
                    timeout(time: 10, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
        }

        stage('Build & Test') {
            steps {
                echo "🔨 Construction de l'application avec tests..."
                sh '''
                    echo "=== Build Maven avec Jacoco pour la couverture ==="

                    # Si vous voulez générer un rapport Jacoco pour SonarQube
                    # Assurez-vous que le plugin Jacoco est configuré dans pom.xml
                    mvn clean package -B

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

                    echo "=== Liste des images dans Minikube ==="
                    docker images | grep ${IMAGE_NAME} | head -5

                    # Switch back to normal Docker daemon
                    eval \$(minikube docker-env -u)
                """
            }
        }

        stage('Push to DockerHub') {
            steps {
                echo "🚀 Pushing image to DockerHub..."
                sh """
                    echo "=== Login to DockerHub ==="
                    echo "${DOCKERHUB_CREDENTIALS_PSW}" | docker login -u "${DOCKERHUB_CREDENTIALS_USR}" --password-stdin

                    echo "=== Pushing image ==="
                    docker push ${IMAGE_NAME}:${IMAGE_TAG}

                    echo "=== Logout from DockerHub ==="
                    docker logout
                """
            }
        }

        stage('Clean Old Resources - No Sudo') {
            steps {
                echo "🧹 Nettoyage des anciennes ressources (sans sudo)..."
                sh """
                    # Supprimez toutes les ressources existantes sans utiliser sudo
                    echo "=== Suppression des déploiements et services ==="
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete deployment mysql -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete service mysql-service -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete pvc mysql-pvc -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete pv mysql-pv --ignore-not-found=true
                    kubectl delete configmap --all -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete secret --all -n ${K8S_NAMESPACE} --ignore-not-found=true

                    sleep 10

                    # Vérifiez qu'il ne reste plus de pods
                    echo "=== État après nettoyage ==="
                    kubectl get pods -n ${K8S_NAMESPACE} || true
                """
            }
        }

        stage('Deploy MySQL - Alternative Storage') {
            steps {
                echo "🗄️  Déploiement de MySQL avec stockage alternatif..."
                sh """
                    echo "=== Création du PV et PVC MySQL (sans hostPath) ==="
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
    path: "/tmp/mysql-data"
    type: DirectoryOrCreate
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
EOF
                    kubectl apply -f /tmp/mysql-storage.yaml

                    echo "=== Création du déploiement MySQL ==="
                    cat > /tmp/mysql-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: devops
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
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
  namespace: devops
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
                    sleep 60

                    echo "=== Configuration des permissions MySQL ==="
                    # Attendre que le pod soit prêt
                    for i in \$(seq 1 20); do
                        POD_NAME=\$(kubectl get pods -n devops -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\$POD_NAME" ]; then
                            echo "Tentative \$i/20: Vérification du pod \$POD_NAME..."
                            if kubectl get pod -n devops \$POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Running; then
                                sleep 10  # Donner plus de temps

                                # Fix MySQL permissions
                                echo "✅ MySQL est en cours d'exécution. Configuration des permissions..."
                                kubectl exec -n devops \$POD_NAME -- mysql -u root -proot123 -e "
                                    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
                                    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
                                    FLUSH PRIVILEGES;
                                    CREATE DATABASE IF NOT EXISTS springdb;
                                    SELECT '✅ Base de données créée' as Status;
                                " 2>/dev/null || echo "⚠️  Erreur lors de la configuration, réessayer..."
                                break
                            fi
                        fi
                        echo "⏱️  Attente MySQL... (\$i/20)"
                        sleep 10
                    done

                    echo "=== Vérification finale MySQL ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}
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
          value: "jdbc:mysql://mysql-service:3306/springdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
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
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
"""

                    writeFile file: 'spring-deployment.yaml', text: yamlContent
                }

                sh """
                    echo "=== Application du déploiement ==="
                    kubectl apply -f spring-deployment.yaml

                    echo "=== Attente du démarrage (90 secondes) ==="
                    sleep 90

                    echo "=== Vérification de l'état ==="
                    kubectl get pods,svc -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Verify Deployment') {
            steps {
                echo "✅ Vérification du déploiement..."
                sh """
                    echo "=== Attente supplémentaire ==="
                    sleep 30

                    echo "=== Vérification des pods ==="
                    kubectl get pods -n ${K8S_NAMESPACE} -o wide

                    echo ""
                    echo "=== Logs Spring Boot ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$POD_NAME" ]; then
                        echo "Pod: \$POD_NAME"
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=50
                    fi

                    echo ""
                    echo "=== Test de l'application ==="
                    MINIKUBE_IP=\$(minikube ip)

                    echo "Tentative de connexion..."
                    # CORRECTED FOR LOOP - using seq instead of {1..10} expansion
                    for i in \$(seq 1 10); do
                        echo "Tentative \$i/10..."
                        if curl -s -f -m 10 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"; then
                            echo "✅ Application accessible avec contexte path!"
                            echo "=== Test de l'API Foyer ==="
                            curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
                            break
                        elif curl -s -f -m 10 "http://\${MINIKUBE_IP}:30080/actuator/health"; then
                            echo "✅ Application accessible (sans contexte path)"
                            break
                        else
                            echo "⏱️  En attente... (\$i/10)"
                            sleep 15
                        fi
                    done

                    echo ""
                    echo "=== État final ==="
                    kubectl get all -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Debug Application') {
            steps {
                echo "🐛 Debug de l'application..."
                sh """
                    echo "=== Vérification interne de l'application ==="
                    POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

                    if [ -n "\$POD_NAME" ]; then
                        echo "1. Vérification des logs d'erreur..."
                        kubectl logs -n ${K8S_NAMESPACE} \$POD_NAME --tail=200 | grep -i error || echo "Aucune erreur trouvée"

                        echo ""
                        echo "2. Test de l'application depuis l'intérieur du pod..."
                        kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- sh -c "
                            if command -v curl > /dev/null; then
                                echo 'Test avec curl depuis le pod:'
                                curl -s http://localhost:8080${CONTEXT_PATH}/actuator/health || echo 'Échec avec contexte path'
                                curl -s http://localhost:8080/actuator/health || echo 'Échec sans contexte path'
                            else
                                echo 'Installation de curl...'
                                apk add --no-cache curl 2>/dev/null || apt-get update && apt-get install -y curl 2>/dev/null
                                curl -s http://localhost:8080${CONTEXT_PATH}/actuator/health || echo 'Échec avec contexte path'
                                curl -s http://localhost:8080/actuator/health || echo 'Échec sans contexte path'
                            fi
                        "

                        echo ""
                        echo "3. Vérification des processus en cours d'exécution..."
                        kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- ps aux

                        echo ""
                        echo "4. Vérification des ports en écoute..."
                        kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- netstat -tlnp 2>/dev/null || kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- ss -tlnp 2>/dev/null || echo "Impossible de vérifier les ports"
                    fi

                    echo ""
                    echo "=== Vérification de la connexion MySQL ==="
                    MYSQL_POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                    if [ -n "\$MYSQL_POD" ]; then
                        echo "Test de connexion à MySQL depuis le pod Spring Boot..."
                        kubectl exec -n ${K8S_NAMESPACE} \$POD_NAME -- sh -c "
                            if command -v curl > /dev/null; then
                                curl -s mysql-service:3306 && echo 'MySQL accessible' || echo 'MySQL inaccessible'
                            else
                                timeout 2 bash -c 'cat < /dev/null > /dev/tcp/mysql-service/3306' 2>/dev/null && echo 'MySQL accessible' || echo 'MySQL inaccessible'
                            fi
                        "
                    fi
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
                rm -f Dockerfile.jenkins spring-deployment.yaml /tmp/mysql-deployment.yaml /tmp/mysql-storage.yaml 2>/dev/null || true
            '''

            // Rapport final
            sh """
                echo "=== RAPPORT FINAL ==="
                echo "Image Docker: ${IMAGE_NAME}:${IMAGE_TAG}"
                echo "Namespace: ${K8S_NAMESPACE}"
                echo "Contexte path: ${CONTEXT_PATH}"
                echo ""
                echo "=== Liens SonarQube ==="
                echo "Dashboard SonarQube: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
                echo "Projet SonarQube: ${SONAR_HOST_URL}/project/overview?id=${SONAR_PROJECT_KEY}"

                # Obtenir l'IP de Minikube
                MINIKUBE_IP=\$(minikube ip)
                echo ""
                echo "=== URL d'accès ==="
                echo "Application: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                echo "API Foyer: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
                echo ""
                echo "=== Pour tester manuellement ==="
                echo "1. Test MySQL: kubectl exec -n devops -it \$(kubectl get pods -n devops -l app=mysql -o name | head -1) -- mysql -u root -proot123"
                echo "2. Test Spring Boot: curl -s http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"
                echo "3. Test API: curl -s http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
            """
        }

        success {
            echo "✅ Pipeline exécuté avec succès!"
            sh """
                echo "=== QUALITÉ DU CODE ==="
                echo "✅ L'analyse SonarQube a été effectuée avec succès"
                echo "📊 Consultez le rapport: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
            """
        }

        failure {
            echo "💥 Le pipeline a échoué"
            sh """
                echo "=== DEBUG INFO ==="
                echo "1. Pods MySQL:"
                kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o wide || true
                echo ""
                echo "2. Logs MySQL:"
                kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=100 || true
                echo ""
                echo "3. Pods Spring Boot:"
                kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o wide || true
                echo ""
                echo "4. Logs Spring Boot:"
                kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=200 || true
                echo ""
                echo "5. Événements:"
                kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -20 || true
                echo ""
                echo "6. SonarQube Status:"
                echo "   URL: ${SONAR_HOST_URL}"
                echo "   Projet: ${SONAR_PROJECT_KEY}"
            """
        }
    }
}