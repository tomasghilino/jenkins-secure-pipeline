def nodeImage = 'node:24.21.0-trixie-slim@sha256:8ec5d7557396cfe32d21c3f9c13072355ceab22b584578ca4bb28af31120cffe'
def scannerImage = 'sonarsource/sonar-scanner-cli:12.2.0.4256_8.1.0@sha256:a3f4215076706c95a17a68c19322ee916e40a3acd081a8c1a1e839e0194afa57'
def gitleaksImage = 'ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'

pipeline {
  agent { label 'docker' }

  options {
    skipDefaultCheckout()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    CI = 'true'
    NO_COLOR = '1'
    npm_config_cache = "${WORKSPACE}/.npm-cache"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
        }
      }
    }

    stage('Secret scan') {
      agent {
        docker {
          image gitleaksImage
          reuseNode true
          // jenkins keeps the container alive with its own command, so the gitleaks entrypoint is cleared
          args '--entrypoint= --network none'
        }
      }
      steps {
        sh 'gitleaks git --redact --verbose --no-banner --log-opts=HEAD .'
      }
    }

    stage('Node') {
      agent {
        docker {
          image nodeImage
          reuseNode true
        }
      }
      stages {
        stage('Install') {
          steps {
            dir('app') {
              sh 'npm ci --ignore-scripts'
            }
          }
        }

        stage('Lint') {
          steps {
            dir('app') {
              sh 'npm run lint -- --format unix'
              sh 'npm run format:check'
            }
          }
        }

        stage('Typecheck') {
          steps {
            dir('app') {
              sh 'npm run typecheck'
            }
          }
        }

        stage('Unit tests') {
          steps {
            dir('app') {
              sh 'npm test -- --coverage'
            }
          }
        }
      }
    }

    stage('Integration tests') {
      agent {
        docker {
          image nodeImage
          reuseNode true
          // socket of the isolated dind daemon, not the developer machine; 2375 is its docker group
          args '-v /var/run/docker.sock:/var/run/docker.sock --group-add 2375'
        }
      }
      steps {
        dir('app') {
          sh 'env -u DOCKER_HOST -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH npm run test:e2e -- --coverage'
        }
      }
    }

    stage('SonarQube analysis') {
      agent {
        docker {
          image scannerImage
          reuseNode true
          // the compose service name sonarqube only resolves in the dind network namespace
          args '--network host'
        }
      }
      steps {
        withSonarQubeEnv('sonarqube') {
          sh 'sonar-scanner'
        }
      }
    }

    stage('Quality gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Docker build') {
      steps {
        sh '''
          docker build \
            --label org.opencontainers.image.revision="$IMAGE_TAG" \
            --label org.opencontainers.image.source=https://github.com/tomasghilino/jenkins-secure-pipeline \
            -t jsp-api:"$IMAGE_TAG" \
            app
        '''
      }
    }
  }

  post {
    cleanup {
      deleteDir()
    }
  }
}
