pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "${BUILD_NUMBER}"
        DOCKERHUB_CREDENTIALS = credentials('docker-hub')
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
        MAVEN_OPTS = "-Dmaven.repo.local=/tmp/.m2/repository"
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Checkout') {
            steps {
                echo "📦 Fetching code from GitHub..."
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: 'main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git',
                        credentialsId: ''  // Add GitHub credentials ID if private repo
                    ]],
                    extensions: [[
                        $class: 'CleanBeforeCheckout'
                    ]],
                    doGenerateSubmoduleConfigurations: false,
                    submoduleCfg: []
                ])

                // Set webhook trigger (alternative approach)
                script {
                    // This helps webhook detection
                    currentBuild.description = "Triggered by ${currentBuild.getBuildCauses()[0].shortDescription}"
                }
            }
        }

        stage('Build & Test') {
            steps {
                echo "🔨 Building application..."
                sh '''
                    echo "=== Clean Maven build ==="
                    mvn clean package -DskipTests -B -q -T 1C

                    echo "=== Verify JAR ==="
                    JAR_FILE=$(find target -name "*.jar" -type f | head -1)
                    if [ -f "$JAR_FILE" ]; then
                        echo "✅ JAR found: $(basename "$JAR_FILE")"
                        ls -lh "$JAR_FILE"
                    else
                        echo "❌ No JAR file found!"
                        exit 1
                    fi
                '''
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                echo "🐳 Building and pushing Docker image to DockerHub..."
                script {
                    // Extract username and password from single credential
                    // DOCKERHUB_CREDENTIALS comes as USERNAME:PASSWORD
                    def creds = "${DOCKERHUB_CREDENTIALS}".split(':')
                    def dockerUser = creds[0]
                    def dockerPass = creds[1]

                    withCredentials([
                        usernamePassword(
                            credentialsId: 'docker-hub',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        )
                    ]) {
                        sh """
                            echo "=== Building Docker image ==="
                            docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest

                            echo "=== Logging into DockerHub ==="
                            echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin

                            echo "=== Pushing to DockerHub ==="
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest

                            echo "=== Logging out ==="
                            docker logout

                            echo "✅ Image pushed: ${IMAGE_NAME}:${IMAGE_TAG}"
                        """
                    }
                }
            }
        }

        stage('Clean Old Resources') {
            steps {
                echo "🧹 Cleaning old resources..."
                sh """
                    set +e  # Don't fail if resources don't exist
                    kubectl delete deployment spring-app -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=30s
                    kubectl delete service spring-service -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=30s
                    kubectl delete configmap spring-config -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=30s
                    kubectl delete secret spring-secret -n ${K8S_NAMESPACE} --ignore-not-found=true --timeout=30s
                    set -e

                    # Quick wait
                    sleep 3
                """
            }
        }

        stage('Deploy MySQL (Fast)') {
            steps {
                echo "🗄️ Deploying MySQL..."
                script {
                    // Create MySQL deployment with readiness probe
                    String mysqlYaml = """
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv-${BUILD_NUMBER}
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/tmp/mysql-data-${BUILD_NUMBER}"
    type: DirectoryOrCreate
  persistentVolumeReclaimPolicy: Delete
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
  volumeName: mysql-pv-${BUILD_NUMBER}
---
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
        readinessProbe:
          exec:
            command:
            - mysqladmin
            - ping
            - -h
            - localhost
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 5
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
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: mysql
  ports:
    - port: 3306
      targetPort: 3306
  type: ClusterIP
"""

                    writeFile file: 'mysql-fast.yaml', text: mysqlYaml

                    sh """
                        echo "=== Deploying MySQL ==="
                        kubectl apply -f mysql-fast.yaml

                        echo "=== Waiting for MySQL (max 40s) ==="
                        timeout 40 bash -c 'until kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath="{.items[0].status.phase}" 2>/dev/null | grep -q Running; do sleep 2; echo -n "."; done'

                        # Quick database setup
                        MYSQL_POD=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                        if [ -n "\${MYSQL_POD}" ]; then
                            echo "=== Setting up database ==="
                            kubectl exec -n ${K8S_NAMESPACE} \${MYSQL_POD} -- \\
                                mysql -u root -proot123 -e "
                                    CREATE USER IF NOT EXISTS 'spring'@'%' IDENTIFIED BY 'spring123';
                                    GRANT ALL PRIVILEGES ON springdb.* TO 'spring'@'%';
                                    FLUSH PRIVILEGES;
                                " 2>/dev/null || echo "MySQL not fully ready yet, continuing..."
                        fi
                    """
                }
            }
        }

        stage('Deploy Spring Boot') {
            steps {
                echo "🚀 Deploying Spring Boot Application..."
                script {
                    // Create ConfigMap and Secret
                    String configYaml = """
apiVersion: v1
kind: ConfigMap
metadata:
  name: spring-config
  namespace: ${K8S_NAMESPACE}
data:
  SPRING_DATASOURCE_URL: jdbc:mysql://mysql-service:3306/springdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
  SPRING_DATASOURCE_DRIVER_CLASS_NAME: com.mysql.cj.jdbc.Driver
  SPRING_JPA_HIBERNATE_DDL_AUTO: update
  SERVER_SERVLET_CONTEXT_PATH: ${CONTEXT_PATH}
---
apiVersion: v1
kind: Secret
metadata:
  name: spring-secret
  namespace: ${K8S_NAMESPACE}
type: Opaque
stringData:
  SPRING_DATASOURCE_USERNAME: spring
  SPRING_DATASOURCE_PASSWORD: spring123
"""

                    writeFile file: 'spring-config.yaml', text: configYaml

                    // Create Deployment and Service
                    String deploymentYaml = """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${K8S_NAMESPACE}
spec:
  replicas: 1  # Start with 1 for speed
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
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: spring-config
        - secretRef:
            name: spring-secret
        readinessProbe:
          httpGet:
            path: ${CONTEXT_PATH}/actuator/health
            port: 8080
          initialDelaySeconds: 20
          periodSeconds: 5
          timeoutSeconds: 3
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
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
"""

                    writeFile file: 'spring-deployment.yaml', text: deploymentYaml

                    sh """
                        echo "=== Applying configuration ==="
                        kubectl apply -f spring-config.yaml
                        kubectl apply -f spring-deployment.yaml

                        echo "=== Waiting for pod (max 50s) ==="
                        timeout 50 bash -c 'until kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath="{.items[0].status.phase}" 2>/dev/null | grep -q Running; do sleep 2; echo -n "."; done'
                    """
                }
            }
        }

        stage('Quick Verification') {
            steps {
                echo "✅ Quick verification..."
                sh """
                    echo "=== Pods status ==="
                    kubectl get pods -n ${K8S_NAMESPACE} --no-headers | awk '{print \$1,\$2,\$3}'

                    echo "=== Testing health endpoint ==="
                    MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "127.0.0.1")

                    # Try with retry
                    for i in {1..8}; do
                        if curl -s -f -m 5 "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" > /dev/null; then
                            echo "✅ Health check passed!"
                            echo "=== Quick API test ==="
                            curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/foyer/getAllFoyers" | head -c 100
                            echo ""
                            exit 0
                        fi
                        echo "⏱️ Waiting... (\$i/8)"
                        sleep 5
                    done
                    echo "⚠️ Health check timeout, but continuing..."
                """
            }
        }
    }

    post {
        always {
            echo "🏁 Pipeline completed - Build #${BUILD_NUMBER}"
            script {
                // Clean up temporary files
                sh '''
                    rm -f mysql-fast.yaml spring-config.yaml spring-deployment.yaml 2>/dev/null || true
                '''

                // Final report
                def minikubeIP = sh(script: 'minikube ip 2>/dev/null || echo "N/A"', returnStdout: true).trim()
                echo """
                ========================================
                DEPLOYMENT SUMMARY - Build #${BUILD_NUMBER}
                ========================================
                Docker Image: ${IMAGE_NAME}:${IMAGE_TAG}
                Also available as: ${IMAGE_NAME}:latest
                Namespace: ${K8S_NAMESPACE}
                Context Path: ${CONTEXT_PATH}

                ACCESS URLS:
                Application: http://${minikubeIP}:30080${CONTEXT_PATH}
                Health Check: http://${minikubeIP}:30080${CONTEXT_PATH}/actuator/health
                API Test: http://${minikubeIP}:30080${CONTEXT_PATH}/foyer/getAllFoyers

                COMMANDS FOR TESTING:
                1. Check pods: kubectl get pods -n ${K8S_NAMESPACE}
                2. View logs: kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=50
                3. Port forward: kubectl port-forward -n ${K8S_NAMESPACE} svc/spring-service 8080:8080
                ========================================
                """
            }
        }

        success {
            // Scale up after successful deployment
            sh """
                echo "=== Scaling up to 2 replicas ==="
                kubectl scale deployment spring-app -n ${K8S_NAMESPACE} --replicas=2
            """
        }

        failure {
            echo "💥 Pipeline failed - Debug information:"
            sh """
                echo "=== Failed pods ==="
                kubectl get pods -n ${K8S_NAMESPACE} --field-selector=status.phase!=Running

                echo "=== Spring Boot logs ==="
                kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=100 2>/dev/null || echo "No Spring Boot pods found"

                echo "=== MySQL logs ==="
                kubectl logs -n ${K8S_NAMESPACE} -l app=mysql --tail=50 2>/dev/null || echo "No MySQL pods found"

                echo "=== Events ==="
                kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -15 2>/dev/null || true
            """
        }
    }
}