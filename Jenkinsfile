pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG  = "${BUILD_ID}"  // Use BUILD_ID instead of "latest"
        K8S_NAMESPACE = "devops"
        MAVEN_OPTS = "-Xmx1024m -XX:MaxPermSize=256m"
    }

    tools {
        maven 'M2_HOME'  // Make sure this tool is configured in Jenkins
        jdk 'JAVA_HOME'  // Make sure JDK is configured in Jenkins
    }

    triggers {
        pollSCM('* * * * *')  // Poll SCM instead of githubPush (more reliable)
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Récupération du code depuis GitHub..."
                checkout([$class: 'GitSCM',
                    branches: [[name: 'main']],
                    userRemoteConfigs: [[url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git']]
                ])
            }
        }

        stage('Clean & Compile') {
            steps {
                echo "Compilation Maven..."
                sh 'mvn clean compile -B'
            }
        }

        stage('Test') {
            steps {
                echo "Exécution des tests..."
                sh 'mvn test -B'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Package') {
            steps {
                echo "Packaging Maven..."
                sh 'mvn package -DskipTests -B'
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Construction de l'image Docker..."
                script {
                    // Make sure Dockerfile exists
                    if (fileExists('Dockerfile')) {
                        sh "docker build --no-cache -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                        sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
                    } else {
                        error "Dockerfile not found!"
                    }
                }
            }
        }

        stage('Docker Login & Push') {
            steps {
                echo "Connexion + push vers DockerHub..."
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-hub',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest
                        """
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo "Déploiement sur Kubernetes..."
                script {
                    // Check if kubectl is available
                    sh 'kubectl version --client'

                    // Update deployment
                    sh """
                        kubectl set image deployment/spring-app \
                            spring-app=${IMAGE_NAME}:${IMAGE_TAG} \
                            -n ${K8S_NAMESPACE} \
                            --record
                    """

                    // Check rollout status
                    sh """
                        kubectl rollout status deployment/spring-app \
                            -n ${K8S_NAMESPACE} \
                            --timeout=300s
                    """
                }
            }
        }

        stage('Integration Tests') {
            steps {
                echo "Exécution des tests d'intégration..."
                script {
                    // Get service URL
                    sh '''
                        kubectl get svc spring-service -n devops -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
                    '''

                    // Wait for service to be ready
                    sh '''
                        for i in {1..30}; do
                            if curl -s -f http://$(minikube ip):$(kubectl get svc spring-service -n devops -o jsonpath="{.spec.ports[0].nodePort}")/actuator/health > /dev/null; then
                                echo "Service is up!"
                                break
                            fi
                            echo "Waiting for service... ($i/30)"
                            sleep 10
                        done
                    '''

                    // Run integration tests
                    sh """
                        curl -f http://\$(minikube ip):\$(kubectl get svc spring-service -n devops -o jsonpath='{.spec.ports[0].nodePort}')/actuator/health
                        curl -f http://\$(minikube ip):\$(kubectl get svc spring-service -n devops -o jsonpath='{.spec.ports[0].nodePort}')/department/getAllDepartment
                    """
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline terminé"
            // Cleanup
            sh 'docker system prune -f'

            // Archive artifacts
            archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
        }
        success {
            echo "Build et déploiement effectués avec succès!"
            // Optional: Send success notification
        }
        failure {
            echo "Le pipeline a échoué."
            script {
                // Rollback deployment
                sh """
                    kubectl rollout undo deployment/spring-app -n ${K8S_NAMESPACE}
                    echo "Rollback effectué"
                """
            }
        }
        cleanup {
            // Clean workspace
            cleanWs()
        }
    }
}