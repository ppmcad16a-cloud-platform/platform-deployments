// Restore drill: proves a backup can really be restored.
// Downloads the NEWEST backup from ONE cloud (parameter SOURCE), checks its
// fingerprint, decrypts it, restores it into the scratch database
// mern_restore_drill, compares document counts with the manifest, and
// empties the scratch database again.
//
// Least privilege: runs as jenkins/mongo-restore - READ-only on the
// backups; the Atlas user restore-drill may touch ONLY mern_restore_drill.
// The age PRIVATE key is read from the vault at run time and deleted after.

def slack(String text) {
  container('curl') {
    withEnv(["SLACK_TEXT=${text}"]) {
      sh '''
        set +x
        if [ -z "$SLACK_WEBHOOK_URL" ]; then echo "No Slack webhook configured - skipping"; exit 0; fi
        curl -fsS -m 10 -H 'Content-Type: application/json' \
          --data "$(printf '{"text":"%s"}' "$SLACK_TEXT")" "$SLACK_WEBHOOK_URL" > /dev/null \
          && echo "Slack notified" || echo "Slack notification failed (ignored)"
      '''
    }
  }
}

pipeline {
  agent {
    kubernetes {
      yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          serviceAccountName: mongo-restore
          containers:
            - name: mongo
              image: mongo:8.0.32
              command: ["sleep"]
              args: ["infinity"]
            - name: curl
              image: curlimages/curl:8.22.0
              command: ["sleep"]
              args: ["infinity"]
              securityContext:
                runAsUser: 1000
              env:
                - name: SLACK_WEBHOOK_URL
                  valueFrom:
                    secretKeyRef:
                      name: jenkins-slack
                      key: url
                      optional: true
            - name: rclone
              image: rclone/rclone:1.75.2
              command: ["sleep"]
              args: ["infinity"]
              env:
                - name: GCS_BUCKET
                  value: project-899ced78-a554-40c2-96c-mongo-backups
                - name: S3_BUCKET
                  value: ppmcad16a-mongo-backups-722867460821-ap-south-1
                - name: AZ_CONTAINER
                  value: mongo-backups
                - name: RCLONE_CONFIG_GCS_TYPE
                  value: google cloud storage
                - name: RCLONE_CONFIG_GCS_ENV_AUTH
                  value: "true"
                - name: RCLONE_CONFIG_GCS_BUCKET_POLICY_ONLY
                  value: "true"
                - name: RCLONE_CONFIG_S3_TYPE
                  value: s3
                - name: RCLONE_CONFIG_S3_PROVIDER
                  value: AWS
                - name: RCLONE_CONFIG_S3_ENV_AUTH
                  value: "true"
                - name: RCLONE_CONFIG_S3_REGION
                  value: ap-south-1
                - name: RCLONE_CONFIG_AZ_TYPE
                  value: azureblob
                - name: RCLONE_CONFIG_AZ_ACCOUNT
                  value: stbackup0botwx
                - name: RCLONE_CONFIG_AZ_ENV_AUTH
                  value: "true"
                - name: AWS_ROLE_ARN
                  value: arn:aws:iam::722867460821:role/mongo-restore-from-gke
                - name: AWS_WEB_IDENTITY_TOKEN_FILE
                  value: /var/run/secrets/tokens/aws/token
                - name: AWS_REGION
                  value: ap-south-1
                - name: AZURE_CLIENT_ID
                  value: fb5d8642-e89b-416f-ab2c-7d7a099c7cd2
                - name: AZURE_TENANT_ID
                  value: 0fd463ca-1b22-4674-bea5-699c2e0ad98b
                - name: AZURE_FEDERATED_TOKEN_FILE
                  value: /var/run/secrets/tokens/azure/token
              volumeMounts:
                - name: aws-token
                  mountPath: /var/run/secrets/tokens/aws
                  readOnly: true
                - name: azure-token
                  mountPath: /var/run/secrets/tokens/azure
                  readOnly: true
          volumes:
            - name: aws-token
              projected:
                sources:
                  - serviceAccountToken:
                      audience: sts.amazonaws.com
                      expirationSeconds: 3600
                      path: token
            - name: azure-token
              projected:
                sources:
                  - serviceAccountToken:
                      audience: api://AzureADTokenExchange
                      expirationSeconds: 3600
                      path: token
      '''
    }
  }

  environment {
    TARGET_DB = 'mern_restore_drill'
  }

  options {
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  stages {
    stage('Validate') {
      steps {
        script {
          if (!(params.SOURCE in ['gcs', 's3', 'azure'])) {
            error("SOURCE '${params.SOURCE}' must be gcs, s3 or azure")
          }
        }
      }
    }
    stage('Tools') {
      steps { container('curl') { sh 'sh scripts/dr/install-age.sh' } }
    }
    stage('Secrets') {
      steps {
        container('curl') {
          sh 'sh scripts/dr/fetch-secret.sh mern-backup-age-key .age-key'
          sh 'sh scripts/dr/fetch-secret.sh mern-mongo-restore-drill-uri .restore-uri'
        }
      }
    }
    stage('Download newest backup') {
      steps {
        container('rclone') {
          script {
            env.BACKUP_NAME = sh(returnStdout: true, script: 'sh scripts/dr/download-latest.sh "$SOURCE"').trim()
          }
        }
      }
    }
    stage('Restore + verify') {
      steps {
        container('mongo') {
          sh '''
            MANIFEST="$BACKUP_NAME.manifest.json" ARCHIVE="$BACKUP_NAME.archive.gz.age" \
            AGE=./tools/age AGE_KEY_FILE=.age-key RESTORE_URI_FILE=.restore-uri \
            bash scripts/dr/restore-verify.sh
          '''
        }
      }
    }
  }

  post {
    always {
      // the private key and the decrypted data must not outlive the job
      container('mongo') { sh 'rm -f .age-key .restore-uri *.archive.gz.age' }
    }
    success {
      slack(":white_check_mark: restore-drill #${env.BUILD_NUMBER}: *${env.BACKUP_NAME}* from *${params.SOURCE}* restored and verified (fingerprint + document counts)")
    }
    failure {
      slack(":x: restore-drill #${env.BUILD_NUMBER} FAILED (source ${params.SOURCE}). ${env.BUILD_URL}console")
    }
  }
}
