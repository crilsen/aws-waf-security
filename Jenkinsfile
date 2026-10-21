// Declarative Jenkins pipeline for the AWS WAFv2 Regional Web ACL.
//
// Stages, in order: Validate -> Plan -> Approval -> Apply.
//
// The Plan stage writes a binary plan file and its checksum. The Apply stage
// consumes that same file; it never runs `terraform plan` again. The Approval
// stage is a blocking manual gate restricted to the users or group named in
// the APPROVERS parameter.
//
// Requirements:
//   - Multibranch Pipeline job whose protected default branch is `main`.
//   - An agent labelled `terraform` with terraform >= 1.10, aws-cli, git, and
//     sha256sum available.
//   - The agent profile may call sts:AssumeRole on the deployment role. The
//     role ARN is stored as the Jenkins secret text credential
//     `waf-deploy-role-arn` (override with the CREDENTIALS_ID parameter).
//   - No AWS credentials in this repository and none typed into parameters.

pipeline {
  agent { label 'terraform' }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
  }

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'eu-west-1', description: 'Region of the ALB and of this deployment. Also selects the state key, so each Region deploys independently.')
    string(name: 'ALB_ARN', defaultValue: '', description: 'ARN of the existing ALB. Required and must be in AWS_REGION.')
    string(name: 'LOG_BUCKET', defaultValue: '', description: 'Existing S3 bucket that receives WAF logs through Firehose.')
    string(name: 'TF_STATE_BUCKET', defaultValue: '', description: 'Existing S3 bucket that stores Terraform state.')
    string(name: 'TF_STATE_REGION', defaultValue: '', description: 'Region of the state bucket. Empty uses AWS_REGION.')
    choice(name: 'RULE_MODE', choices: ['COUNT', 'BLOCK'], description: 'COUNT only observes. BLOCK requires a new plan and a new approval.')
    string(name: 'APPROVERS', defaultValue: 'waf-approvers', description: 'Jenkins user or group allowed to approve the plan.')
    string(name: 'CREDENTIALS_ID', defaultValue: 'waf-deploy-role-arn', description: 'Jenkins credential ID holding the deployment role ARN.')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TF_INPUT = 'false'
    PLAN_FILE = 'tfplan.bin'
    PLAN_TEXT = 'tfplan.txt'
    PLAN_CHECKSUM = 'tfplan.sha256'
    TF_STATE_KEY = "aws-waf-security/${params.AWS_REGION}/terraform.tfstate"
  }

  stages {
    // Formatting and static validation need no AWS credentials.
    stage('Validate') {
      steps {
        sh '''
          set -eu
          terraform fmt -check -recursive -diff
          terraform init -backend=false -input=false
          terraform validate
        '''
      }
    }

    // Only the protected default branch may plan or apply.
    stage('Plan') {
      when {
        beforeAgent true
        branch 'main'
      }
      steps {
        withCredentials([string(credentialsId: params.CREDENTIALS_ID, variable: 'AWS_ROLE_ARN')]) {
          sh '''
            set -eu
            ./scripts/require-env.sh AWS_REGION ALB_ARN LOG_BUCKET TF_STATE_BUCKET AWS_ROLE_ARN
            : "${TF_STATE_REGION:=${AWS_REGION}}"
            export TF_STATE_REGION
            eval "$(./scripts/assume-role.sh)"
            terraform init -input=false \
              -backend-config="bucket=${TF_STATE_BUCKET}" \
              -backend-config="key=${TF_STATE_KEY}" \
              -backend-config="region=${TF_STATE_REGION}" \
              -backend-config="encrypt=true"
            terraform plan -input=false -lock-timeout=5m -out="${PLAN_FILE}" \
              -var="aws_region=${AWS_REGION}" \
              -var="alb_arn=${ALB_ARN}" \
              -var="log_bucket_name=${LOG_BUCKET}" \
              -var="rule_mode=${RULE_MODE}"
            terraform show -no-color "${PLAN_FILE}" > "${PLAN_TEXT}"
            sha256sum "${PLAN_FILE}" > "${PLAN_CHECKSUM}"
          '''
        }
        stash name: 'approved-plan', includes: "${env.PLAN_FILE},${env.PLAN_CHECKSUM}", allowEmpty: false
      }
    }

    // Blocking manual gate. The plan is already fixed at this point.
    stage('Approval') {
      when {
        beforeAgent true
        branch 'main'
      }
      steps {
        timeout(time: 24, unit: 'HOURS') {
          input(
            message: "Apply the reviewed Terraform plan for ${params.AWS_REGION}?",
            ok: 'Approve and apply',
            submitter: params.APPROVERS
          )
        }
      }
    }

    // Applies the stored plan file; never generates a new plan.
    stage('Apply') {
      when {
        beforeAgent true
        branch 'main'
      }
      steps {
        unstash 'approved-plan'
        withCredentials([string(credentialsId: params.CREDENTIALS_ID, variable: 'AWS_ROLE_ARN')]) {
          sh '''
            set -eu
            ./scripts/require-env.sh AWS_REGION TF_STATE_BUCKET AWS_ROLE_ARN
            : "${TF_STATE_REGION:=${AWS_REGION}}"
            export TF_STATE_REGION
            sha256sum -c "${PLAN_CHECKSUM}"
            eval "$(./scripts/assume-role.sh)"
            terraform init -input=false \
              -backend-config="bucket=${TF_STATE_BUCKET}" \
              -backend-config="key=${TF_STATE_KEY}" \
              -backend-config="region=${TF_STATE_REGION}" \
              -backend-config="encrypt=true"
            terraform apply -input=false "${PLAN_FILE}"
          '''
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: "${env.PLAN_TEXT}", allowEmptyArchive: true, fingerprint: true
      sh 'rm -f tfplan.bin tfplan.txt tfplan.sha256 || true'
    }
  }
}
