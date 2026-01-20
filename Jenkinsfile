pipeline {
    agent any
    
    tools {
        maven "maven3"
    }
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['blue', 'green'], description: 'Choose which environment to deploy: Blue or Green')
        choice(name: 'DOCKER_TAG', choices: ['blue', 'green'], description: 'Choose the Docker image tag for the deployment')
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between Blue and Green')
    }
    
    environment {
        IMAGE_NAME = "yogeshrathod1137/bankapp"
        TAG = "${params.DOCKER_TAG}"  // The image tag now comes from the parameter
        KUBE_NAMESPACE = 'webapps'
        SONAR_HOME = tool "sonar-scanner"
    }

    stages {
        stage('Git Checkout') {
            steps {
                git branch: 'main', credentialsId: 'git-cred', url: 'https://github.com/yogeshrathod7/Blue-Green-Deployment.git'
            }
        }
        
        stage('Compile') {
            steps {
                sh "mvn compile"
            }
        }
        
        stage('Tests') {
            steps {
                sh "mvn test -DskipTests=true"
            }
        }
        
        stage('Trivy FS_Scan') {
            steps {
                sh "trivy fs --format table -o fs.html ."
            }
        }
        
        stage('Sonarqube Analysis') {
            steps {
                     withSonarQubeEnv('sonar') {
            sh '''
                mvn clean compile
                $SONAR_HOME/bin/sonar-scanner \
                  -Dsonar.projectKey=Multitier \
                  -Dsonar.projectName=Multitier \
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
        stage('Generate SonarQube PDF Report') {
    steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
            sh '''
            set -e

            echo "Checking required tools..."
            jq --version
            wkhtmltopdf --version

            echo "Downloading SonarQube issues..."
            curl -s -u ${SONAR_TOKEN}: \
            "http://98.94.90.125:9000/api/issues/search?componentKeys=Multitier&ps=500" \
            -o sonar-report.json

            echo "Creating HTML report..."
            cat > sonar-report.html <<EOF
            <html>
            <head>
              <title>SonarQube Scan Report - Multitier</title>
              <style>
                body { font-family: Arial; }
                table { border-collapse: collapse; width: 100%; }
                th, td { border: 1px solid #ddd; padding: 8px; }
                th { background-color: #f2f2f2; }
              </style>
            </head>
            <body>
              <h1>SonarQube Scan Report</h1>
              <p>Project: Multitier</p>
              <p>Generated: $(date)</p>
              <table>
                <tr>
                  <th>Type</th>
                  <th>Severity</th>
                  <th>Component</th>
                  <th>Line</th>
                  <th>Message</th>
                </tr>
            EOF

            jq -r '.issues[] | [.type, .severity, .component, (.line // "NA"), .message] | @tsv' sonar-report.json |
            while IFS=$'\\t' read -r type severity component line message
            do
              echo "<tr><td>$type</td><td>$severity</td><td>$component</td><td>$line</td><td>$message</td></tr>" >> sonar-report.html
            done

            echo "</table></body></html>" >> sonar-report.html

            echo "Converting HTML to PDF..."
            wkhtmltopdf sonar-report.html sonar-report.pdf

            ls -lh sonar-report.pdf
            '''
        }

        archiveArtifacts artifacts: 'sonar-report.pdf'
    }
}

        
        stage('Build') {
            steps {
                sh "mvn package -DskipTests=true"
            }
        }
        
        stage('Publish artifacts to Nexus') {
            steps {
                withMaven(globalMavenSettingsConfig: 'maven-settings.xml', jdk: '', maven: 'maven3', mavenSettingsConfig: '', traceability: true) {
                    sh "mvn deploy -DskipTests=true"
                }
            }
        }
        
        stage('Docker Build and Tag Image') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                    }
                }
            }
        }
        
        stage('Trivy Image_Scan') {
            steps {
                sh "trivy image --format table -o image.html ${IMAGE_NAME}:${TAG}"
            }
        }
        
        stage('Docker Push Image') {
            steps {
                script {
                    withDockerRegistry(credentialsId: 'docker-cred') {
                        sh "docker push ${IMAGE_NAME}:${TAG}"
                    }
                }
            }
        }
        
         stage('Deploy MySQL Deployment and Service') {
            steps {
                script {
                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', contextName: '', credentialsId: 'k8-token', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6B0D87DDA3956EA17A4D9D98D3F9508D.gr7.us-east-1.eks.amazonaws.com') {
                        sh "kubectl apply -f mysql-ds.yml -n ${KUBE_NAMESPACE}"  // Ensure you have the MySQL deployment YAML ready
                    }
                }
            }
        }
        
        stage('Deploy SVC-APP') {
            steps {
                script {
                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', contextName: '', credentialsId: 'k8-token', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6B0D87DDA3956EA17A4D9D98D3F9508D.gr7.us-east-1.eks.amazonaws.com') {
                        sh """ if ! kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}; then
                                kubectl apply -f bankapp-service.yml -n ${KUBE_NAMESPACE}
                              fi
                        """
                   }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def deploymentFile = ""
                    if (params.DEPLOY_ENV == 'blue') {
                        deploymentFile = 'app-deployment-blue.yml'
                    } else {
                        deploymentFile = 'app-deployment-green.yml'
                    }

                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', contextName: '', credentialsId: 'k8-token', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6B0D87DDA3956EA17A4D9D98D3F9508D.gr7.us-east-1.eks.amazonaws.com') {
                        sh "kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }
        
        stage('Switch Traffic Between Blue & Green Environment') {
            when {
                expression { return params.SWITCH_TRAFFIC }
            }
            steps {
                script {
                    def newEnv = params.DEPLOY_ENV

                    // Always switch traffic based on DEPLOY_ENV
                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', contextName: '', credentialsId: 'k8-token', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6B0D87DDA3956EA17A4D9D98D3F9508D.gr7.us-east-1.eks.amazonaws.com') {
                        sh '''
                            kubectl patch service bankapp-service -p "{\\"spec\\": {\\"selector\\": {\\"app\\": \\"bankapp\\", \\"version\\": \\"''' + newEnv + '''\\"}}}" -n ${KUBE_NAMESPACE}
                        '''
                    }
                    echo "Traffic has been switched to the ${newEnv} environment."
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    def verifyEnv = params.DEPLOY_ENV
                    withKubeConfig(caCertificate: '', clusterName: 'devopsshack-cluster', contextName: '', credentialsId: 'k8-token', namespace: 'webapps', restrictKubeConfigAccess: false, serverUrl: 'https://6B0D87DDA3956EA17A4D9D98D3F9508D.gr7.us-east-1.eks.amazonaws.com') {
                        sh """
                        kubectl get pods -l version=${verifyEnv} -n ${KUBE_NAMESPACE}
                        kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}
                        """
                    }
                }
            }
    }
}
}
