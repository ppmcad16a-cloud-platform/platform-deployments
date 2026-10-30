// Encrypted MongoDB backup -> GCS + S3 + Azure Blob (Phase 10).
// Nightly while the platform runs (cron in JCasC), or on demand.
//
// Least privilege: this job runs as jenkins/mongo-backup, which may ADD
// backup files in the three clouds but never read or delete them. It knows
// only the age PUBLIC key, so it cannot decrypt what it writes either.
// The real work is in scripts/dr/*.sh (tested outside Jenkins).

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
          serviceAccountName: mongo-backup
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
                # Where backups go
                - name: GCS_BUCKET
                  value: project-899ced78-a554-40c2-96c-mongo-backups
                - name: S3_BUCKET
                  value: ppmcad16a-mongo-backups-722867460821-ap-south-1
                - name: AZ_CONTAINER
                  value: mongo-backups
                # rclone "remotes" gcs: / s3: / az:, configured by environment variables.
                # env_auth = take credentials from the environment (keyless):
                - name: RCLONE_CONFIG_GCS_TYPE
                  value: google cloud storage
                - name: RCLONE_CONFIG_GCS_ENV_AUTH          # Workload Identity
                  value: "true"
                - name: RCLONE_CONFIG_GCS_BUCKET_POLICY_ONLY
                  value: "true"
                - name: RCLONE_CONFIG_GCS_NO_CHECK_BUCKET   # we may not list the bucket
                  value: "true"
                - name: RCLONE_CONFIG_S3_TYPE
                  value: s3
                - name: RCLONE_CONFIG_S3_PROVIDER
                  value: AWS
                - name: RCLONE_CONFIG_S3_ENV_AUTH           # AWS_ROLE_ARN + token file
                  value: "true"
                - name: RCLONE_CONFIG_S3_REGION
                  value: ap-south-1
                - name: RCLONE_CONFIG_S3_NO_CHECK_BUCKET    # we may not list buckets
                  value: "true"
                - name: RCLONE_CONFIG_S3_NO_HEAD            # we may not read objects back
                  value: "true"
                - name: RCLONE_CONFIG_AZ_TYPE
                  value: azureblob
                - name: RCLONE_CONFIG_AZ_ACCOUNT
                  value: stbackup0botwx
                - name: RCLONE_CONFIG_AZ_ENV_AUTH           # AZURE_* + token file
                  value: "true"
                - name: RCLONE_CONFIG_AZ_NO_CHECK_CONTAINER
                  value: "true"
                # Keyless logins: the GKE token in the files below is swapped
                # for short-lived AWS / Azure credentials of the backup identity.
                - name: AWS_ROLE_ARN
                  value: arn:aws:iam::722867460821:role/mongo-backup-from-gke
                - name: AWS_WEB_IDENTITY_TOKEN_FILE
                  value: /var/run/secrets/tokens/aws/token
                - name: AWS_REGION
                  value: ap-south-1
                - name: AZURE_CLIENT_ID
                  value: def7bed6-66cc-49a8-ac6e-f9c6d1c7fcd2
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
    // age PUBLIC key - can only lock backups, never open them (not a secret)
    AGE_RECIPIENT = 'age1wdyuy93fxhfdqrhzg0v5k8q34zdv4qjudzxe7uwzucqg03twnv9swhrpr6'
  }

  options {
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
  }

  stages {
    stage('Tools') {
      steps { container('curl') { sh 'sh scripts/dr/install-age.sh' } }
    }
    stage('Secret') {
      steps { container('curl') { sh 'sh scripts/dr/fetch-secret.sh mern-mongo-backup-uri .backup-uri' } }
    }
    stage('Dump + encrypt') {
      steps {
        container('mongo') {
          script {
            env.BACKUP_NAME = sh(returnStdout: true,
              script: 'MONGO_URI_FILE=.backup-uri AGE=./tools/age OUT_DIR=. bash scripts/dr/dump.sh').trim()
          }
          sh 'rm -f .backup-uri; cat "$BACKUP_NAME.manifest.json"'
        }
      }
    }
    stage('Upload to 3 clouds') {
      steps { container('rclone') { sh 'sh scripts/dr/upload.sh "$BACKUP_NAME"' } }
    }
  }

  post {
    always {
      container('mongo') { sh 'rm -f .backup-uri' }
    }
    success {
      slack(":floppy_disk: backup-mongo #${env.BUILD_NUMBER}: *${env.BACKUP_NAME}* stored in GCS + S3 + Azure Blob")
    }
    failure {
      slack(":x: backup-mongo #${env.BUILD_NUMBER} FAILED - no complete backup this run. ${env.BUILD_URL}console")
    }
  }
}
