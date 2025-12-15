pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
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

        stage('Clean Old Resources') {
            steps {
                echo "🧹 Nettoyage des anciennes ressources..."
                sh """
                    # Supprimez toutes les ressources existantes
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete deployment mysql -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete service mysql-service -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete pvc mysql-pvc -n ${K8S_NAMESPACE} --ignore-not-found=true
                    kubectl delete pv mysql-pv --ignore-not-found=true

                    sleep 10

                    # Nettoyage du stockage
                    sudo rm -rf /data/mysql/*
                    sudo mkdir -p /data/mysql
                    sudo chmod 777 /data/mysql
                """
            }
        }

        stage('Deploy MySQL') {
            steps {
                echo "🗄️  Déploiement de MySQL..."
                sh """
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
                    POD_NAME=\$(kubectl get pods -n devops -l app=mysql -o jsonpath='{.items[0].metadata.name}')

                    # Attendre que MySQL soit prêt
                    for i in {1..30}; do
                        if kubectl exec -n devops \$POD_NAME -- mysqladmin ping -h localhost -u root -proot123 2>/dev/null; then
                            echo "✅ MySQL est prêt. Configuration des permissions..."

                            # Fix MySQL permissions
                            kubectl exec -n devops \$POD_NAME -- mysql -u root -proot123 -e "
                                CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
                                GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
                                FLUSH PRIVILEGES;
                                CREATE DATABASE IF NOT EXISTS springdb;
                            "
                            echo "✅ Permissions configurées"
                            break
                        fi
                        echo "⏱️  Attente MySQL... (\$i/30)"
                        sleep 10
                    done
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

                    echo "=== Attente du démarrage (2 minutes) ==="
                    sleep 120

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

                    echo "=== Test de l'application ==="
                    MINIKUBE_IP=\$(minikube ip)

                    echo "Tentative de connexion..."
                    for i in {1..10}; do
                        echo "Tentative \$i/10..."
                        if curl -s -f "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health"; then
                            echo "✅ Application accessible!"
                            echo "=== Test de l'API Foyer ==="
                            curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
                            break
                        elif curl -s -f "http://\${MINIKUBE_IP}:30080/actuator/health"; then
                            echo "✅ Application accessible (sans contexte path)"
                            break
                        else
                            echo "⏱️  En attente..."
                            sleep 15
                        fi
                    done

                    echo ""
                    echo "=== État final ==="
                    kubectl get all -n ${K8S_NAMESPACE}
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
            script {
                sh """
                    echo "=== RAPPORT FINAL ==="
                    echo "Image Docker: ${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Namespace: ${K8S_NAMESPACE}"
                    echo "Contexte path: ${CONTEXT_PATH}"

                    MINIKUBE_IP=\$(minikube ip)
                    echo ""
                    echo "=== URL d'accès ==="
                    echo "Application: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                    echo "API Foyer: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers"
                    echo ""
                    echo "=== Pour tester manuellement ==="
                    echo "Test MySQL: kubectl exec -n devops -it \$(kubectl get pods -n devops -l app=mysql -o name) -- mysql -u root -proot123"
                """
            }
        }
    }
}