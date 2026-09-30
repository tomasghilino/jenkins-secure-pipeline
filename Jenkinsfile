def nodeImage = 'node:24.21.0-trixie-slim@sha256:8ec5d7557396cfe32d21c3f9c13072355ceab22b584578ca4bb28af31120cffe'
def scannerImage = 'sonarsource/sonar-scanner-cli:12.2.0.4256_8.1.0@sha256:a3f4215076706c95a17a68c19322ee916e40a3acd081a8c1a1e839e0194afa57'
def gitleaksImage = 'ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
def terraformImage = 'hashicorp/terraform:1.16.4@sha256:985cdc6c1d9b0a65b83377f666efd2f740b47f02ac55be1ced3d18f7d3b0e829'
def tflintImage = 'ghcr.io/terraform-linters/tflint:v0.64.0@sha256:1c595f42d794c32c45a6ea8b58655fd66433d4ca3b1bc631c574a48d120bd19f'
def checkovImage = 'bridgecrew/checkov:3.3.20@sha256:6d20ebbcde58b2dce6e3151a6771fefa4d468281fe442475455623f5799b9f53'
// trivy releases were hijacked in march 2026, so this digest was pinned only after cosign verified
// it was signed by the aquasecurity/trivy release workflow
def trivyImage = 'ghcr.io/aquasecurity/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969'

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

        stage('Dependency audit') {
          steps {
            dir('app') {
              // report every advisory, dev tooling included, without failing the build
              sh 'npm audit --audit-level=none'
              // block high and critical advisories in the dependencies that ship in the image
              sh 'npm audit --omit=dev --audit-level=high'
              // every installed package must carry a valid npm registry signature
              sh 'npm audit signatures'
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

    stage('SonarQube') {
      // community build tracks a single branch, so analyses from other branches would overwrite dev
      when {
        branch 'dev'
      }
      stages {
        stage('Analysis') {
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
      }
    }

    stage('Terraform') {
      environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
        CHECKPOINT_DISABLE = 'true'
        TF_PLUGIN_CACHE_DIR = "${WORKSPACE}/.terraform-plugins"
      }
      stages {
        stage('Format and validate') {
          agent {
            docker {
              image terraformImage
              reuseNode true
              args '--entrypoint='
            }
          }
          steps {
            sh 'mkdir -p "$TF_PLUGIN_CACHE_DIR"'
            sh 'terraform fmt -check -recursive -diff infra'
            // every stack commits its lock file, so new stacks are picked up without editing this list
            sh '''
              for lock in infra/*/.terraform.lock.hcl infra/environments/*/.terraform.lock.hcl; do
                stack=$(dirname "$lock")
                terraform -chdir="$stack" init -backend=false -lockfile=readonly -no-color
                terraform -chdir="$stack" validate -no-color
              done
            '''
          }
        }

        stage('TFLint') {
          agent {
            docker {
              image tflintImage
              reuseNode true
              args '--entrypoint='
            }
          }
          steps {
            // the container user has no home, and tflint keeps plugins and the sigstore root that verifies them there
            // recursive mode reads .tflint.hcl from each stack folder unless the config path is absolute
            sh '''
              export HOME="$(mktemp -d)"
              tflint --init --config="$WORKSPACE/.tflint.hcl"
              tflint --recursive --chdir=infra --config="$WORKSPACE/.tflint.hcl"
            '''
          }
        }

        stage('Checkov') {
          agent {
            docker {
              image checkovImage
              reuseNode true
              args '--entrypoint= --network none'
            }
          }
          steps {
            // --skip-download keeps checkov from calling the prisma cloud api, so it runs offline
            sh 'checkov -d infra --framework terraform --external-checks-dir checkov --quiet --compact --skip-download'
          }
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
        // scanners read the image from a file, so they never need access to the docker daemon
        sh 'docker save -o jsp-api.tar jsp-api:"$IMAGE_TAG"'
      }
    }

    stage('Trivy') {
      agent {
        docker {
          image trivyImage
          reuseNode true
          args '--entrypoint='
        }
      }
      environment {
        TRIVY_CACHE_DIR = "${WORKSPACE}/.trivy-cache"
        TRIVY_IGNOREFILE = "${WORKSPACE}/.trivyignore"
      }
      stages {
        stage('Filesystem scan') {
          steps {
            // the lock file lists every dependency; installed node_modules would only repeat it
            sh 'trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --skip-dirs app/node_modules app'
          }
        }

        stage('Image scan') {
          steps {
            // full report of every severity, including accepted findings, without failing the build
            sh 'trivy image --scanners vuln --show-suppressed --input jsp-api.tar'
            // block high and critical vulnerabilities that already have a fixed version
            sh 'trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --input jsp-api.tar'
            // block any secret baked into an image layer, whatever its severity
            sh 'trivy image --scanners secret --exit-code 1 --input jsp-api.tar'
          }
        }
      }
    }
  }

  post {
    cleanup {
      deleteDir()
    }
  }
}
