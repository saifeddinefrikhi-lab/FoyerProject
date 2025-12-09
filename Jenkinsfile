pipeline {
	agent any

	environment {
		IMAGE_NAME = "saiffrikhi/foyer_project"
		IMAGE_TAG  = "latest"
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

		// Ajouter ce stage après "Docker Login & Push"
            stage('Deploy to Kubernetes') {
                steps {
                    echo "Déploiement sur Kubernetes..."
                    script {
                        // Appliquer les configurations Kubernetes
                        sh """
                            kubectl apply -f mysql-deployment.yaml -n devops
                            kubectl apply -f spring-configmap.yaml -n devops
                            kubectl apply -f spring-secret.yaml -n devops

                            # Mettre à jour l'image du deployment Spring Boot
                            kubectl set image deployment/spring-app spring-app=${IMAGE_NAME}:${IMAGE_TAG} -n devops

                            # Redémarrer le deployment pour prendre en compte les changements
                            kubectl rollout restart deployment/spring-app -n devops
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

	}






	post {
		always {
			echo "Pipeline terminé"
		}
		success {
			echo "Build et Push effectués avec succès!"
		}
		failure {
			echo "Le pipeline a échoué."
		}
	}
}
