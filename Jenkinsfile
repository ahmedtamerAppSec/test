// Multibranch pipeline: build -> secret scan + SCA -> verify -> deploy (main only).
// Runs on the built-in node (label 'linux') as the 'jenkins' user. One-time server
// prerequisites are created by deploy/setup-server.sh.

pipeline {
  agent { label 'linux' }

  options {
    timestamps()
    disableConcurrentBuilds()          // the Trivy DB cache in /var/lib/trivy is shared
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
  }

  environment {
    DEPLOY_DIR      = '/opt/local-tasks'
    TRIVY_CACHE_DIR = '/var/lib/trivy'
  }

  stages {
    stage('Build') {
      steps {
        sh 'npm ci --ignore-scripts'
        sh 'npm run build'
        // Production dependencies inside build-output, so it can be deployed as-is.
        sh 'npm ci --omit=dev --ignore-scripts --prefix build-output'
      }
    }

    stage('Security scans') {
      parallel {
        stage('Secret scan (TruffleHog)') {
          steps {
            // Full git history is scanned. Unverified findings fail the build too.
            // The raw report contains the secrets themselves, so only a redacted copy is kept.
            sh '''
              set +e
              trufflehog git file://. --config trufflehog-custom.yaml --fail --no-update --json > trufflehog-raw.json
              rc=$?
              set -e
              node scripts/trufflehog-summary.js trufflehog-raw.json trufflehog-report.json
              rm -f trufflehog-raw.json
              exit $rc
            '''
          }
        }

        stage('SCA (Trivy)') {
          steps {
            sh '''
              set +e
              trivy fs --scanners vuln \
                --cache-dir "$TRIVY_CACHE_DIR" \
                --skip-dirs node_modules,build-output \
                --severity HIGH,CRITICAL \
                --exit-code 1 \
                --format json --output trivy-report.json .
              rc=$?
              set -e
              if [ -f trivy-report.json ]; then
                trivy convert --scanners vuln --format table trivy-report.json
              fi
              exit $rc
            '''
          }
        }
      }
    }

    stage('Verify') {
      steps {
        sh 'node --check app.js'
        sh 'test -f build-output/public/index.html && test -f build-output/app.js && test -d build-output/node_modules/pg'
      }
    }

    stage('Deploy') {
      when { branch 'main' }
      steps {
        sh 'rsync -a --delete --exclude nginx.windows.conf build-output/ "$DEPLOY_DIR/"'
        // Only these three commands are allowed by /etc/sudoers.d/jenkins-deploy.
        sh 'sudo -n /usr/bin/systemctl restart local-tasks'
        sh 'sudo -n /usr/sbin/nginx -t'
        sh 'sudo -n /usr/bin/systemctl reload nginx'
        sh 'curl -fsS --retry 10 --retry-delay 2 --retry-connrefused http://127.0.0.1/health'
        sh 'curl -fsS -o /dev/null http://127.0.0.1/'
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'trufflehog-report.json,trivy-report.json', allowEmptyArchive: true
    }
  }
}
