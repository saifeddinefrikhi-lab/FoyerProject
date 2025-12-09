pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG = "latest"
    }

    triggers {
        pollSCM('* * * * *')  // vérification chaque minute
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Récupération du code depuis GitHub..."
                git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
            }
        }

        stage('Clean & Build') {
            steps {
                echo "Nettoyage + Build Maven..."
                sh 'mvn clean install -DskipTests -B'
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Construction de l'image Docker..."
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Docker Login & Push') {
            steps {
                echo "Connexion + push vers DockerHub..."
                withCredentials([usernamePassword(credentialsId: 'bf441a15-9a0e-4cb2-ba9d-937b67370965',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS')]) {
                    sh """
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    """
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                echo "Analyse de la qualité du code avec SonarQube..."
                withSonarQubeEnv('SonarQube-Server') {
                    sh 'mvn sonar:sonar -Dsonar.projectKey=tp-foyer'
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo "Déploiement sur Kubernetes..."
                script {
                    // Créer le namespace si n'existe pas
                    sh 'kubectl create namespace devops --dry-run=client -o yaml | kubectl apply -f -'

                    // Déployer MySQL
                    sh '''
                        cat <<EOF | kubectl apply -n devops -f -
                        apiVersion: v1
                        kind: PersistentVolume
                        metadata:
                          name: mysql-pv
                        spec:
                          capacity:
                            storage: 1Gi
                          accessModes:
                            - ReadWriteOnce
                          hostPath:
                            path: "/data/mysql"
                        ---
                        apiVersion: v1
                        kind: PersistentVolumeClaim
                        metadata:
                          name: mysql-pvc
                        spec:
                          accessModes:
                            - ReadWriteOnce
                          resources:
                            requests:
                              storage: 1Gi
                        ---
                        apiVersion: apps/v1
                        kind: Deployment
                        metadata:
                          name: mysql
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
                                  value: ""
                                - name: MYSQL_DATABASE
                                  value: tpfoyerdbsaif
                                ports:
                                - containerPort: 3306
                                volumeMounts:
                                - mountPath: /var/lib/mysql
                                  name: mysql-storage
                              volumes:
                              - name: mysql-storage
                                persistentVolumeClaim:
                                  claimName: mysql-pvc
                        ---
                        apiVersion: v1
                        kind: Service
                        metadata:
                          name: mysql-service
                        spec:
                          selector:
                            app: mysql
                          ports:
                            - port: 3306
                              targetPort: 3306
                          type: ClusterIP
                        EOF
                    '''

                    // Déployer Spring Boot ConfigMap
                    sh '''
                        cat <<EOF | kubectl apply -n devops -f -
                        apiVersion: v1
                        kind: ConfigMap
                        metadata:
                          name: spring-config
                        data:
                          SPRING_DATASOURCE_URL: "jdbc:mysql://mysql-service.devops.svc.cluster.local:3306/tpfoyerdbsaif?createDatabaseIfNotExist=true"
                          SPRING_JPA_HIBERNATE_DDL_AUTO: "update"
                          SPRING_JPA_SHOW_SQL: "true"
                          SPRING_JPA_PROPERTIES_HIBERNATE_DIALECT: "org.hibernate.dialect.MySQL8Dialect"
                          SPRING_JPA_PROPERTIES_HIBERNATE_FORMAT_SQL: "true"
                          SERVER_PORT: "8080"
                          SERVER_SERVLET_CONTEXT_PATH: "/tp-foyer"
                        EOF
                    '''

                    // Déployer Spring Boot Secret
                    sh '''
                        cat <<EOF | kubectl apply -n devops -f -
                        apiVersion: v1
                        kind: Secret
                        metadata:
                          name: spring-secret
                        type: Opaque
                        stringData:
                          SPRING_DATASOURCE_USERNAME: "root"
                          SPRING_DATASOURCE_PASSWORD: ""
                        EOF
                    '''

                    // Déployer Spring Boot
                    sh '''
                        cat <<EOF | kubectl apply -n devops -f -
                        apiVersion: apps/v1
                        kind: Deployment
                        metadata:
                          name: spring-app
                        spec:
                          replicas: 2
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
                                image: saiffrikhi/foyer_project:latest
                                ports:
                                - containerPort: 8080
                                env:
                                - name: SPRING_DATASOURCE_URL
                                  valueFrom:
                                    configMapKeyRef:
                                      name: spring-config
                                      key: SPRING_DATASOURCE_URL
                                - name: SPRING_DATASOURCE_USERNAME
                                  valueFrom:
                                    secretKeyRef:
                                      name: spring-secret
                                      key: SPRING_DATASOURCE_USERNAME
                                - name: SPRING_DATASOURCE_PASSWORD
                                  valueFrom:
                                    secretKeyRef:
                                      name: spring-secret
                                      key: SPRING_DATASOURCE_PASSWORD
                                - name: SERVER_PORT
                                  valueFrom:
                                    configMapKeyRef:
                                      name: spring-config
                                      key: SERVER_PORT
                        ---
                        apiVersion: v1
                        kind: Service
                        metadata:
                          name: spring-service
                        spec:
                          selector:
                            app: spring-app
                          ports:
                            - port: 8080
                              targetPort: 8080
                              nodePort: 30080
                          type: NodePort
                        EOF
                    '''

                    // Mettre à jour l'image
                    sh "kubectl set image deployment/spring-app spring-app=${IMAGE_NAME}:${IMAGE_TAG} -n devops"

                    // Vérifier le déploiement
                    sh '''
                        kubectl rollout status deployment/spring-app -n devops --timeout=300s
                        echo "Application déployée avec succès!"
                    '''
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline terminé"
        }
        success {
            echo "Build et déploiement effectués avec succès!"
        }
        failure {
            echo "Le pipeline a échoué."
        }
    }
}