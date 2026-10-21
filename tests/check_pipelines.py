#!/usr/bin/env python3
"""Static checks for the pipeline definitions and per-target policy files.

These checks are deliberately static: neither GitLab nor Jenkins is available
here, so they assert the properties that matter for the approval gate instead
of pretending to run the pipelines.

Checks:
  * .gitlab-ci.yml is parsed as YAML and inspected structurally.
  * Jenkinsfile is inspected textually (no groovy/Jenkins parser available).
  * helper scripts are inspected for the behaviour the pipelines rely on.
  * every env/<scope>/<region>.tfvars file sets the expected keys.

Exit code is 0 only when every check passes.
"""

from __future__ import annotations

import json
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def code_only(text: str) -> str:
    """Drop full-line comments so assertions target executable lines only."""
    return "\n".join(
        line
        for line in text.splitlines()
        if not line.strip().startswith(("#", "//"))
    )


def check_gitlab_ci() -> None:
    ci = yaml.safe_load((ROOT / ".gitlab-ci.yml").read_text())

    check(
        ci.get("stages") == ["validate", "plan", "approval", "apply"],
        "gitlab: stages must be validate, plan, approval, apply in that order",
    )

    jobs = {
        name: body
        for name, body in ci.items()
        if isinstance(body, dict) and "stage" in body
    }
    for required in ("fmt", "validate", "plan", "approval", "apply"):
        check(required in jobs, f"gitlab: missing job '{required}'")

    approval = jobs.get("approval", {})
    check(
        approval.get("when") == "manual" and approval.get("allow_failure") is False,
        "gitlab: approval must be a blocking manual job (when: manual, allow_failure: false)",
    )

    needs = jobs.get("apply", {}).get("needs", [])
    check(
        any(n.get("job") == "plan" and n.get("artifacts") is True for n in needs),
        "gitlab: apply must consume the plan artifact",
    )
    check(
        any(n.get("job") == "approval" for n in needs),
        "gitlab: apply must depend on the approval job",
    )

    plan_script = " ".join(jobs.get("plan", {}).get("script", []))
    apply_script = " ".join(jobs.get("apply", {}).get("script", []))

    check("./scripts/tf-plan.sh" in plan_script, "gitlab: plan must use scripts/tf-plan.sh")
    check("./scripts/tf-apply.sh" in apply_script, "gitlab: apply must use scripts/tf-apply.sh")
    check(
        "terraform plan" not in apply_script,
        "gitlab: apply must never generate a new plan",
    )
    check(
        "id_tokens" in jobs.get("plan", {}) and "id_tokens" in jobs.get("apply", {}),
        "gitlab: plan and apply must use OIDC id_tokens",
    )

    for job in ("plan", "approval", "apply"):
        rules = jobs.get(job, {}).get("rules", [])
        check(
            any("CI_DEFAULT_BRANCH" in str(rule.get("if", "")) for rule in rules),
            f"gitlab: {job} must be restricted to the protected default branch",
        )

    artifacts = jobs.get("plan", {}).get("artifacts", {})
    check(
        artifacts.get("expire_in") == "1 day",
        "gitlab: plan artifact must expire quickly",
    )
    check(
        artifacts.get("access") == "maintainer",
        "gitlab: plan artifact access must be restricted",
    )
    check(
        all(path in artifacts.get("paths", []) for path in ("${PLAN_FILE}", "${PLAN_CHECKSUM}")),
        "gitlab: plan job must publish the plan file and its checksum",
    )

    for job in ("approval", "apply"):
        environment = str(jobs.get(job, {}).get("environment", {}).get("name", ""))
        check(
            "${WAF_SCOPE}" in environment and "${AWS_REGION}" in environment,
            f"gitlab: {job} environment must be scoped by scope and Region",
        )


def check_jenkinsfile() -> None:
    text = (ROOT / "Jenkinsfile").read_text()

    check(text.count("{") == text.count("}"), "jenkins: unbalanced braces")

    order = ["stage('Validate')", "stage('Plan')", "stage('Approval')", "stage('Apply')"]
    positions = [text.find(marker) for marker in order]
    check(all(pos >= 0 for pos in positions), "jenkins: missing expected stages")
    if not all(pos >= 0 for pos in positions):
        return

    check(positions == sorted(positions), "jenkins: stages must be Validate, Plan, Approval, Apply")

    plan = text[positions[1] : positions[2]]
    approval = text[positions[2] : positions[3]]
    apply_stage = text[positions[3] : text.find("post {")]
    apply_code = code_only(apply_stage)

    check("./scripts/tf-plan.sh" in plan, "jenkins: Plan must use scripts/tf-plan.sh")
    check("unstash " in apply_stage, "jenkins: Apply must unstash the plan file")
    check("./scripts/tf-apply.sh" in apply_stage, "jenkins: Apply must use scripts/tf-apply.sh")
    check("terraform plan" not in apply_code, "jenkins: Apply must never generate a new plan")
    check("input(" in approval, "jenkins: Approval must use a manual input step")
    check("submitter" in approval, "jenkins: Approval must restrict who can approve")
    check("timeout(" in approval, "jenkins: Approval must have a timeout")
    check("stash " in plan, "jenkins: Plan must stash the plan file")

    for name, body in (("Plan", plan), ("Approval", approval), ("Apply", apply_stage)):
        check("branch 'main'" in body, f"jenkins: {name} must be restricted to the protected branch")


def check_scripts() -> None:
    plan = (ROOT / "scripts/tf-plan.sh").read_text()
    apply = code_only((ROOT / "scripts/tf-apply.sh").read_text())
    init = (ROOT / "scripts/tf-init.sh").read_text()

    check("-var-file=" in plan, "scripts: tf-plan.sh must load the per-target policy file")
    check("env/${scope_dir}/${AWS_REGION}.tfvars" in plan, "scripts: policy path must include scope and Region")
    check('"${WAF_SCOPE}" = "REGIONAL"' in plan, "scripts: ALB must only be required for REGIONAL scope")
    check('waf_scope=${WAF_SCOPE}' in plan, "scripts: tf-plan.sh must pass the scope to Terraform")
    check("terraform plan" in plan, "scripts: tf-plan.sh must run terraform plan")

    check("terraform apply" in apply, "scripts: tf-apply.sh must run terraform apply")
    check("terraform plan" not in apply, "scripts: tf-apply.sh must never run terraform plan")
    check("sha256sum -c" in apply, "scripts: tf-apply.sh must verify the plan checksum")

    check("backend-config=\"key=" in init, "scripts: tf-init.sh must build the state key")
    check("CLOUDFRONT" in init, "scripts: tf-init.sh must validate the CloudFront Region")


def check_policy_files() -> None:
    env_dir = ROOT / "env"
    files = sorted(env_dir.glob("*/*.tfvars")) if env_dir.is_dir() else []
    check(bool(files), "env: no per-target policy files found")

    scopes = {path.parent.name for path in files}
    check("regional" in scopes, "env: missing env/regional policy files")
    check("cloudfront" in scopes, "env: missing env/cloudfront policy files")

    for path in files:
        text = path.read_text()
        check("rule_mode" in text, f"env: {path} must set rule_mode")
        check("enabled_rules" in text, f"env: {path} must set enabled_rules")
        if path.parent.name == "cloudfront":
            check('waf_scope = "CLOUDFRONT"' in text, f"env: {path} must set waf_scope = CLOUDFRONT")


def check_github_actions() -> None:
    path = ROOT / ".github" / "workflows" / "terraform.yml"
    check(path.is_file(), "github: missing .github/workflows/terraform.yml")
    if not path.is_file():
        return

    text = path.read_text()
    workflow = yaml.safe_load(text)
    jobs = workflow.get("jobs", {})

    for name in ("validate", "plan", "apply"):
        check(name in jobs, f"github: missing job '{name}'")

    check(
        str(workflow.get("permissions", {}).get("id-token")) == "write",
        "github: workflow must request id-token: write for OIDC",
    )

    plan = json.dumps(jobs.get("plan", {}))
    apply_job = jobs.get("apply", {})
    apply = json.dumps(apply_job)

    check("./scripts/tf-plan.sh" in plan, "github: plan must use scripts/tf-plan.sh")
    check("upload-artifact" in plan, "github: plan must upload the plan artifact")
    check("./scripts/tf-apply.sh" in apply, "github: apply must use scripts/tf-apply.sh")
    check("terraform plan" not in apply, "github: apply must never generate a new plan")
    check("download-artifact" in apply, "github: apply must consume the plan artifact")
    check(
        apply_job.get("environment", {}).get("name") == "production",
        "github: apply must run in the protected production environment",
    )
    check(
        "AWS_ACCESS_KEY_ID" not in text and "aws-access-key-id" not in text,
        "github: no static AWS access keys in the workflow",
    )
    check(
        "pull_request" in text and "branches" in text,
        "github: workflow must run on pull requests and pushes",
    )


def main() -> int:
    check_gitlab_ci()
    check_jenkinsfile()
    check_scripts()
    check_policy_files()
    check_github_actions()

    if failures:
        print("Pipeline checks FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("Pipeline checks passed: .gitlab-ci.yml, Jenkinsfile, scripts, env policies")
    return 0


if __name__ == "__main__":
    sys.exit(main())
