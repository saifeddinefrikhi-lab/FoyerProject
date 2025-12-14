pipeline {
    agent any

    environment {
        IMAGE_NAME = "saiffrikhi/foyer_project"
        IMAGE_TAG  = "latest"
        K8S_NAMESPACE = "devops"
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

                // Mettre à jour l'image dans le déploiement
                sh """
                    kubectl set image deployment/spring-app \
                    spring-app=${IMAGE_NAME}:${IMAGE_TAG} \
                    -n ${K8S_NAMESPACE} \
                    --record
                """

                // Vérifier le rollout
                sh """
                    kubectl rollout status deployment/spring-app \
                    -n ${K8S_NAMESPACE} \
                    --timeout=300s
                """
            }
        }

        stage('Integration Tests') {
            steps {
                echo "Exécution des tests d'intégration..."
                script {
                    def SPRING_URL = sh(script: 'minikube service spring-service -n devops --url', returnStdout: true).trim()
                    sh """
                        curl -f ${SPRING_URL}/actuator/health
                        curl -f ${SPRING_URL}/department/getAllDepartment
                    """
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline terminé"
            // Nettoyage
            sh 'docker system prune -f'
        }
        success {
            echo "Build et déploiement effectués avec succès!"
            // Notification optionnelle
        }
        failure {
            echo "Le pipeline a échoué."
            // Rollback optionnel
            sh """
                kubectl rollout undo deployment/spring-app -n ${K8S_NAMESPACE}
            """
        }
    }
}