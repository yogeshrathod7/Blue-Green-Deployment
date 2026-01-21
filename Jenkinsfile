pipeline {
    agent any

    tools {
        maven "maven3"
    }

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['blue', 'green'], description: 'Choose environment to deploy')
        choice(name: 'DOCKER_TAG', choices: ['blue', 'green'], description: 'Choose Docker image tag')
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between Blue/Green')
    }

    environment {
        IMAGE_NAME = "yogeshrathod1137/bankapp"
        TAG = "${params.DOCKER_TAG}"
        KUBE_NAMESPACE = "webapps"

        SONAR_HOME = tool "sonar-scanner"
        SONAR_PROJECT_KEY = "Multitier"
        SONAR_PROJECT_NAME = "Multitier"
        SONAR_SERVER_URL = "http://98.94.90.125:9000"
    }

    stages {

        stage('Git Checkout') {
            steps {
                git branch: 'main',
                    credentialsId: 'git-cred',
                    url: 'https://github.com/yogeshrathod7/Blue-Green-Deployment.git'
            }
        }

        stage('Compile') {
            steps {
                sh 'mvn compile'
            }
        }

        stage('Tests') {
            steps {
                sh 'mvn test -DskipTests=true'
            }
        }

        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs --format table -o fs.html .'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh '''
                    mvn clean compile
                    $SONAR_HOME/bin/sonar-scanner \
                      -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                      -Dsonar.projectName=${SONAR_PROJECT_NAME} \
                      -Dsonar.java.binaries=target/classes
                    '''
                }
            }
        }

        stage('Quality Gate Check') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: false
                }
            }
        }

        stage('Generate SonarQube HTML Report') {
            steps {
                step([
                    $class: 'SonarQubeReport',
                    reportTask: [
                        projectKey: "${SONAR_PROJECT_KEY}",
                        projectName: "${SONAR_PROJECT_NAME}",
                        serverUrl: "${SONAR_SERVER_URL}"
                    ]
                ])
            }
        }

        stage('Generate SonarQube PDF Report') {
            steps {
                sh '''
                if [ -f sonar-report.html ]; then
                    wkhtmltopdf sonar-report.html sonar-report.pdf
                else
                    echo "ERROR: SonarQube HTML report not found"
                    exit 1
                fi
                '''
            }
        }

        stage('Build Package') {
            steps {
                sh 'mvn package -DskipTests=true'
            }
        }

        stage('Publish Artifacts to Nexus') {
            steps {
                withMaven(globalMavenSettingsConfig: 'maven-settings.xml',
                          maven: 'maven3',
                          traceability: true) {
                    sh 'mvn deploy -DskipTests=true'
                }
            }
        }

        stage('Docker Build') {
            steps {
                withDockerRegistry(credentialsId: 'docker-cred') {
                    sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh "trivy image --format table -o image.html ${IMAGE_NAME}:${TAG}"
            }
        }

        stage('Docker Push') {
            steps {
                withDockerRegistry(credentialsId: 'docker-cred') {
                    sh "docker push ${IMAGE_NAME}:${TAG}"
                }
            }
        }

        stage('Deploy MySQL') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'devopsshack-cluster',
                               namespace: "${KUBE_NAMESPACE}",
                               serverUrl: 'https://<EKS_ENDPOINT>') {
                    sh "kubectl apply -f mysql-ds.yml -n ${KUBE_NAMESPACE}"
                }
            }
        }

        stage('Deploy Service') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'devopsshack-cluster',
                               namespace: "${KUBE_NAMESPACE}",
                               serverUrl: 'https://<EKS_ENDPOINT>') {
                    sh '''
                    if ! kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}; then
                        kubectl apply -f bankapp-service.yml -n ${KUBE_NAMESPACE}
                    fi
                    '''
                }
            }
        }

        stage('Deploy Application') {
            steps {
                script {
                    def deploymentFile = params.DEPLOY_ENV == 'blue'
                        ? 'app-deployment-blue.yml'
                        : 'app-deployment-green.yml'

                    withKubeConfig(credentialsId: 'k8-token',
                                   clusterName: 'devopsshack-cluster',
                                   namespace: "${KUBE_NAMESPACE}",
                                   serverUrl: 'https://<EKS_ENDPOINT>') {
                        sh "kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }

        stage('Switch Traffic') {
            when {
                expression { params.SWITCH_TRAFFIC }
            }
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'devopsshack-cluster',
                               namespace: "${KUBE_NAMESPACE}",
                               serverUrl: 'https://<EKS_ENDPOINT>') {
                    sh '''
                    kubectl patch svc bankapp-service \
                    -p "{\"spec\":{\"selector\":{\"app\":\"bankapp\",\"version\":\"''' + params.DEPLOY_ENV + '''\"}}}" \
                    -n ${KUBE_NAMESPACE}
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                withKubeConfig(credentialsId: 'k8-token',
                               clusterName: 'devopsshack-cluster',
                               namespace: "${KUBE_NAMESPACE}",
                               serverUrl: 'https://<EKS_ENDPOINT>') {
                    sh '''
                    kubectl get pods -n ${KUBE_NAMESPACE}
                    kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: '''
                sonar-report.html,
                sonar-report.pdf,
                fs.html,
                image.html
            ''', fingerprint: true
        }
    }
}
