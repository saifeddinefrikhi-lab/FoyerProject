pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG  = "${BUILD_NUMBER}"
        K8S_NAMESPACE = "devops"
        MAVEN_OPTS = "-Xmx1024m"
    }

    tools {
        maven 'M2_HOME'
        jdk 'JAVA_HOME'
    }

    triggers {
            githubPush() // This enables webhook triggers
        }


    stages {
        stage('Checkout') {
                    steps {
                        echo "Récupération du code depuis GitHub..."
                        git branch: 'main', url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git'
                    }
                }


        stage('Setup Environment') {
            steps {
                echo "Configuration de l'environnement..."
                script {
                    // Add Jenkins user to docker group (temporary fix)
                    sh '''
                        sudo usermod -aG docker jenkins || true
                        newgrp docker || true
                    '''

                    // Test Docker access
                    sh 'docker version || echo "Docker not accessible"'

                    // Test kubectl access
                    sh 'kubectl version --client || echo "kubectl not available"'
                }
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
                sh 'mvn test '
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
                    // Check if we can build Docker image
                    sh '''
                        if [ -f "Dockerfile" ]; then
                            echo "Dockerfile found, building image..."
                            docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        else
                            echo "ERROR: Dockerfile not found!"
                            ls -la
                            exit 1
                        fi
                    '''
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
                    // Create deployment if it doesn't exist
                    sh '''
                        if ! kubectl get deployment spring-app -n ${K8S_NAMESPACE} 2>/dev/null; then
                            echo "Creating initial deployment..."
                            kubectl create deployment spring-app \
                                --image=${IMAGE_NAME}:${IMAGE_TAG} \
                                --port=8080 \
                                -n ${K8S_NAMESPACE}

                            kubectl expose deployment spring-app \
                                --type=NodePort \
                                --port=8080 \
                                --name=spring-service \
                                -n ${K8S_NAMESPACE}
                        else
                            echo "Updating existing deployment..."
                            kubectl set image deployment/spring-app \
                                spring-app=${IMAGE_NAME}:${IMAGE_TAG} \
                                -n ${K8S_NAMESPACE} \
                                --record
                        fi

                        # Wait for rollout
                        kubectl rollout status deployment/spring-app \
                            -n ${K8S_NAMESPACE} \
                            --timeout=300s
                    '''
                }
            }
        }

        stage('Integration Tests') {
            steps {
                echo "Vérification du déploiement..."
                script {
                    // Simple health check
                    sh '''
                        echo "Waiting for pod to be ready..."
                        kubectl wait --for=condition=ready pod \
                            -l app=spring-app \
                            -n ${K8S_NAMESPACE} \
                            --timeout=120s

                        echo "Getting service URL..."
                        kubectl get svc spring-service -n ${K8S_NAMESPACE}
                    '''
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline terminé - Build #${BUILD_NUMBER}"
            // Archive artifacts
            archiveArtifacts artifacts: 'target/*.jar', fingerprint: true

            // Cleanup workspace (remove Docker prune for now)
            cleanWs()
        }
        success {
            echo "✓ Build et déploiement effectués avec succès!"
        }
        failure {
            echo "✗ Le pipeline a échoué."
            script {
                // Only rollback if deployment exists
                sh '''
                    if kubectl get deployment spring-app -n ${K8S_NAMESPACE} 2>/dev/null; then
                        echo "Attempting rollback..."
                        kubectl rollout undo deployment/spring-app -n ${K8S_NAMESPACE} || true
                    else
                        echo "No deployment to rollback"
                    fi
                '''
            }
        }
    }
}