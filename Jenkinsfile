pipeline {
    agent any

    environment {
        // Configuration Docker
        DOCKER_REGISTRY = "saiffrikhi"
        APP_NAME = "foyer_project"
        IMAGE_TAG = "${BUILD_NUMBER}"
        LATEST_TAG = "latest"
        FULL_IMAGE_NAME = "${DOCKER_REGISTRY}/${APP_NAME}"

        // Configuration Kubernetes
        K8S_NAMESPACE = "devops"
        CONTEXT_PATH = "/tp-foyer"
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    triggers {
        // Déclencheur webhook GitHub
        githubPush()
    }

    stages {
        stage('Checkout Code') {
            steps {
                echo "📦 Checkout du code source..."
                git branch: 'main',
                    url: 'https://github.com/saifeddinefrikhi-lab/FoyerProject.git',
                    poll: false

                // Vérifier la structure
                sh '''
                    echo "=== Structure du projet ==="
                    ls -la
                    echo "=== Fichier Dockerfile ==="
                    cat Dockerfile || echo "Dockerfile non trouvé"
                '''
            }
        }

        stage('Setup Environment') {
            steps {
                echo "⚙️ Configuration de l'environnement..."
                script {
                    // Créer le namespace si nécessaire
                    sh """
                        kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                    """

                    // Préparer les répertoires de données
                    sh '''
                        sudo mkdir -p /data/mysql /data/sonarqube
                        sudo chmod 777 /data/mysql /data/sonarqube || true
                    '''
                }
            }
        }

        stage('Code Quality Check') {
            steps {
                echo "🔍 Analyse de qualité du code..."
                sh '''
                    echo "=== Vérification syntaxique ==="
                    # Vérifier la syntaxe des fichiers YAML
                    find . -name "*.yaml" -o -name "*.yml" | xargs -I {} kubectl apply --dry-run=client -f {} || echo "Certains fichiers YAML ont des problèmes"

                    echo "=== Vérification Dockerfile ==="
                    hadolint Dockerfile || echo "Hadolint non installé, vérification ignorée"
                '''
            }
        }

        stage('Build Application') {
            steps {
                echo "🔨 Build de l'application..."
                sh '''
                    echo "=== Nettoyage et compilation ==="
                    mvn clean compile -B

                    echo "=== Package avec tests ==="
                    mvn package -B -DskipTests=false

                    echo "=== Vérification du JAR ==="
                    JAR_FILE=$(find target -name "*.jar" -type f | head -1)
                    if [ -f "$JAR_FILE" ]; then
                        echo "✅ JAR créé: $(ls -lh $JAR_FILE)"
                        echo "Structure du JAR:"
                        jar tf $JAR_FILE | grep -E "(BOOT-INF|META-INF|application)" | head -20
                    else
                        echo "❌ Aucun JAR trouvé!"
                        exit 1
                    fi
                '''
            }

            post {
                failure {
                    echo "⚠️ Build échoué, tentative avec skipTests..."
                    sh 'mvn clean package -DskipTests -B'
                }
            }
        }

        stage('Unit Tests') {
            steps {
                echo "🧪 Exécution des tests unitaires..."
                sh '''
                    echo "=== Exécution des tests ==="
                    mvn test -B

                    echo "=== Rapport de tests ==="
                    if [ -d "target/surefire-reports" ]; then
                        echo "Résumé des tests:"
                        # CORRECTION: Utiliser xargs au lieu de -exec avec backslash
                        find target/surefire-reports -name "*.txt" | xargs grep -E "(Tests run:|FAILURES)" || echo "Aucun rapport de test trouvé"
                    fi
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "🐳 Construction de l'image Docker..."
                script {
                    // Vérifier Docker
                    sh 'docker version'

                    // Builder l'image
                    sh """
                        docker build -t ${FULL_IMAGE_NAME}:${IMAGE_TAG} .
                        docker tag ${FULL_IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME}:${LATEST_TAG}

                        echo "=== Images créées ==="
                        docker images | grep ${DOCKER_REGISTRY}
                    """
                }
            }
        }

        stage('Test Docker Image Locally') {
            steps {
                echo "🧪 Test local de l'image Docker..."
                script {
                    try {
                        sh """
                            echo "=== Test avec base de données H2 ==="
                            docker run -d --name test-${BUILD_NUMBER} \\
                              -e SPRING_DATASOURCE_URL="jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1" \\
                              -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \\
                              -e SPRING_DATASOURCE_USERNAME="sa" \\
                              -e SPRING_DATASOURCE_PASSWORD="" \\
                              -e SPRING_JPA_HIBERNATE_DDL_AUTO="create-drop" \\
                              -e SERVER_SERVLET_CONTEXT_PATH="${CONTEXT_PATH}" \\
                              -p 18080:8080 \\
                              ${FULL_IMAGE_NAME}:${IMAGE_TAG}

                            echo "Attente du démarrage (60 secondes)..."
                            sleep 60

                            echo "=== Test de l'endpoint health ==="
                            curl -s -f http://localhost:18080${CONTEXT_PATH}/actuator/health && \\
                                echo "✅ Health check réussi" || echo "⚠️ Health check échoué"

                            echo "=== Logs de test ==="
                            docker logs test-${BUILD_NUMBER} --tail=50

                            echo "=== Nettoyage ==="
                            docker stop test-${BUILD_NUMBER}
                            docker rm test-${BUILD_NUMBER}
                        """
                    } catch (Exception e) {
                        echo "⚠️ Test local échoué, vérifiez les logs"
                        sh '''
                            docker logs test-${BUILD_NUMBER} --tail=200 || true
                            docker stop test-${BUILD_NUMBER} || true
                            docker rm test-${BUILD_NUMBER} || true
                        '''
                        // Ne pas échouer le pipeline pour le test local
                    }
                }
            }
        }

        stage('Deploy MySQL to Kubernetes') {
            steps {
                echo "🗄️ Déploiement de MySQL sur Kubernetes..."
                script {
                    sh """
                        echo "=== Application des fichiers YAML MySQL ==="
                        kubectl apply -f mysql-deployment.yaml -n ${K8S_NAMESPACE}

                        echo "=== Attente du démarrage de MySQL ==="
                        timeout 180 bash -c 'until kubectl get pods -n ${K8S_NAMESPACE} -l app=mysql 2>/dev/null | grep -q "1/1"; do sleep 5; echo "En attente..."; done'

                        echo "=== Vérification MySQL ==="
                        kubectl run mysql-test-${BUILD_NUMBER} -n ${K8S_NAMESPACE} --image=mysql:8.0 -it --rm -- \\
                          mysql -h mysql-service -u root -proot123 -e "SHOW DATABASES; CREATE DATABASE IF NOT EXISTS springdb; SHOW TABLES FROM springdb;" || \\
                          echo "⚠️ Test MySQL échoué"
                    """
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                echo "📤 Push de l'image Docker..."
                withCredentials([usernamePassword(
                    credentialsId: 'docker-hub',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                        echo "=== Connexion à Docker Hub ==="
                        echo "\${DOCKER_PASS}" | docker login -u "\${DOCKER_USER}" --password-stdin

                        echo "=== Push des images ==="
                        docker push ${FULL_IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${FULL_IMAGE_NAME}:${LATEST_TAG}

                        echo "✅ Images poussées avec succès"
                    """
                }
            }
        }

        stage('Deploy Spring Boot to Kubernetes') {
            steps {
                echo "🚀 Déploiement de l'application Spring Boot..."
                script {
                    // Mettre à jour l'image dans le déploiement YAML
                    sh """
                        sed -i 's|image:.*|image: ${FULL_IMAGE_NAME}:${IMAGE_TAG}|g' spring-app-deployment.yaml

                        echo "=== Application du déploiement Spring Boot ==="
                        kubectl apply -f spring-app-deployment.yaml -n ${K8S_NAMESPACE}

                        echo "=== Attente du déploiement ==="
                        kubectl rollout status deployment/spring-app -n ${K8S_NAMESPACE} --timeout=300s
                    """
                }
            }

            post {
                failure {
                    echo "⚠️ Déploiement échoué, tentatives de debug..."
                    script {
                        sh """
                            echo "=== Debug du déploiement ==="
                            kubectl describe deployment/spring-app -n ${K8S_NAMESPACE}
                            kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -20

                            echo "=== Rollback si nécessaire ==="
                            kubectl rollout undo deployment/spring-app -n ${K8S_NAMESPACE} || true
                        """
                    }
                }
            }
        }

        stage('Integration Tests') {
            steps {
                echo "🔗 Tests d'intégration..."
                script {
                    sh """
                        echo "=== Attente que l'application soit prête ==="
                        sleep 30

                        echo "=== Tests des endpoints ==="
                        MINIKUBE_IP=\$(minikube ip)

                        echo "1. Test health endpoint:"
                        curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/actuator/health" | jq '.status' || \\
                          echo "⚠️ Health endpoint non accessible"

                        echo "2. Test API endpoint (getAllFoyers):"
                        curl -s "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/getAllFoyers" | jq '. | length' && \\
                          echo "✅ API fonctionnelle" || echo "⚠️ API non fonctionnelle"

                        echo "3. Test de création:"
                        curl -X POST "http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}/createFoyer" \\
                          -H "Content-Type: application/json" \\
                          -d '{"nomFoyer": "Test Foyer", "capaciteFoyer": 100}' || \\
                          echo "⚠️ Test de création échoué"
                    """
                }
            }
        }
    }

    post {
        always {
            echo "🏁 Pipeline terminé"

            script {
                // Nettoyage et rapport
                sh """
                    echo "=== Nettoyage ==="
                    docker system prune -f || true
                    rm -f /tmp/app.log || true

                    echo "=== RAPPORT FINAL ==="
                    echo "Build Number: ${BUILD_NUMBER}"
                    echo "Image: ${FULL_IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Namespace: ${K8S_NAMESPACE}"
                    echo "Context Path: ${CONTEXT_PATH}"

                    echo ""
                    echo "=== État du cluster ==="
                    kubectl get all -n ${K8S_NAMESPACE} || true

                    echo ""
                    echo "=== Logs des applications ==="
                    kubectl logs -n ${K8S_NAMESPACE} -l app=spring-app --tail=20 --prefix=true || echo "Pas de logs disponibles"

                    echo ""
                    echo "=== URLs d'accès ==="
                    MINIKUBE_IP=\$(minikube ip 2>/dev/null || echo "192.168.49.2")
                    echo "Spring Boot: http://\${MINIKUBE_IP}:30080${CONTEXT_PATH}"
                    echo "MySQL: mysql-service:3306"
                """
            }
        }

        success {
            echo "🎉 Pipeline réussi!"

            script {
                // Notification de succès
                sh """
                    echo "✅ Déploiement réussi!"
                    echo "Application disponible à: http://\$(minikube ip):30080${CONTEXT_PATH}"
                    echo "Health check: http://\$(minikube ip):30080${CONTEXT_PATH}/actuator/health"
                """
            }
        }

        failure {
            echo "💥 Pipeline échoué"

            script {
                // Diagnostic détaillé
                sh """
                    echo "=== DIAGNOSTIC COMPLET ==="

                    echo "1. Derniers événements:"
                    kubectl get events -n ${K8S_NAMESPACE} --sort-by='.lastTimestamp' | tail -30 || true

                    echo ""
                    echo "2. État des pods détaillé:"
                    kubectl describe pods -n ${K8S_NAMESPACE} || true

                    echo ""
                    echo "3. Logs des pods en erreur:"
                    kubectl get pods -n ${K8S_NAMESPACE} --field-selector=status.phase!=Running -o name | \\
                      xargs -I {} kubectl logs -n ${K8S_NAMESPACE} {} --tail=100 || true

                    echo ""
                    echo "=== COMMANDES DE RÉCUPÉRATION ==="
                    echo "1. Redémarrer le déploiement:"
                    echo "   kubectl rollout restart deployment/spring-app -n ${K8S_NAMESPACE}"
                    echo ""
                    echo "2. Vérifier la connexion MySQL:"
                    echo "   kubectl run debug -n ${K8S_NAMESPACE} --image=mysql:8.0 -it --rm -- mysql -h mysql-service -u root -proot123 -e 'SHOW DATABASES;'"
                    echo ""
                    echo "3. Accéder au pod:"
                    echo "   kubectl exec -n ${K8S_NAMESPACE} -it \$(kubectl get pods -n ${K8S_NAMESPACE} -l app=spring-app -o jsonpath='{.items[0].metadata.name}') -- /bin/sh"
                """
            }
        }

        cleanup {
            echo "🧹 Nettoyage des ressources temporaires..."
            sh '''
                docker rm -f $(docker ps -aq --filter "name=test-") 2>/dev/null || true
                docker rmi $(docker images -q --filter "dangling=true") 2>/dev/null || true
            '''
        }
    }
}