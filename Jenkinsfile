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
//   - The WAF policy for each Region lives in env/<region>.tfvars, reviewed and
//     versioned. It is not a pipeline parameter: changing policy goes through a
//     commit, a plan, and an approval.

pipeline {
  agent { label 'terraform' }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
  }

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'eu-west-1', description: 'Target Region. CLOUDFRONT must be us-east-1.')
    choice(name: 'WAF_SCOPE', choices: ['REGIONAL', 'CLOUDFRONT'], description: 'REGIONAL protects an ALB; CLOUDFRONT is the global scope attached through the distribution web_acl_id.')
    string(name: 'ALB_ARN', defaultValue: '', description: 'ARN of the existing ALB. Required for REGIONAL scope, ignored for CLOUDFRONT.')
    string(name: 'LOG_BUCKET', defaultValue: '', description: 'Existing S3 bucket that receives WAF logs through Firehose.')
    string(name: 'TF_STATE_BUCKET', defaultValue: '', description: 'Existing S3 bucket that stores Terraform state.')
    string(name: 'TF_STATE_REGION', defaultValue: '', description: 'Region of the state bucket. Empty uses AWS_REGION.')
    string(name: 'APPROVERS', defaultValue: 'waf-approvers', description: 'Jenkins user or group allowed to approve the plan.')
    string(name: 'CREDENTIALS_ID', defaultValue: 'waf-deploy-role-arn', description: 'Jenkins credential ID holding the deployment role ARN.')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TF_INPUT = 'false'
    PLAN_FILE = 'tfplan.bin'
    PLAN_TEXT = 'tfplan.txt'
    PLAN_CHECKSUM = 'tfplan.sha256'
    // scripts/tf-plan.sh consumes TF_LOG_BUCKET; this job exposes LOG_BUCKET.
    TF_LOG_BUCKET = "${params.LOG_BUCKET}"
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
          // Validates the target, assumes the role, initializes the backend for
          // this scope and Region, plans from the reviewed policy file, and
          // writes the plan, its text rendering, and its checksum.
          sh './scripts/tf-plan.sh'
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
          // Verifies the checksum and applies the stored plan file. It never
          // runs terraform plan.
          sh './scripts/tf-apply.sh'
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
