#!/usr/bin/env python3
"""Static checks for the pipeline definitions.

These checks are deliberately static: neither GitLab nor Jenkins is available
in this repository, so they assert the properties that matter for the approval
gate instead of pretending to run the pipelines.

Checks are split in two:
  * .gitlab-ci.yml is parsed as YAML and inspected structurally.
  * Jenkinsfile is inspected textually (no groovy/Jenkins parser here).

Exit code is 0 only when every check passes.
"""

from __future__ import annotations

import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


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

    check("terraform plan -input=false" in plan_script, "gitlab: plan job must run terraform plan")
    check(
        "terraform plan" not in apply_script,
        "gitlab: apply must never generate a new plan",
    )
    check(
        "terraform apply -input=false" in apply_script and "${PLAN_FILE}" in apply_script,
        "gitlab: apply must apply the stored plan file",
    )
    check(
        "sha256sum -c" in apply_script,
        "gitlab: apply must verify the plan checksum before applying",
    )
    check(
        '-var-file="env/${AWS_REGION}.tfvars"' in plan_script,
        "gitlab: plan must load the per-region policy file",
    )
    check(
        'test -f "env/${AWS_REGION}.tfvars"' in plan_script,
        "gitlab: plan must fail fast when the per-region policy file is missing",
    )
    check(
        "-var=\"rule_mode=" not in plan_script,
        "gitlab: rule policy must come from the reviewed per-region file, not a pipeline variable",
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


def check_jenkinsfile() -> None:
    text = (ROOT / "Jenkinsfile").read_text()

    check(text.count("{") == text.count("}"), "jenkins: unbalanced braces")

    order = ["stage('Validate')", "stage('Plan')", "stage('Approval')", "stage('Apply')"]
    positions = [text.find(marker) for marker in order]
    check(all(pos >= 0 for pos in positions), "jenkins: missing expected stages")
    if all(pos >= 0 for pos in positions):
        check(positions == sorted(positions), "jenkins: stages must be Validate, Plan, Approval, Apply")

        plan = text[positions[1] : positions[2]]
        approval = text[positions[2] : positions[3]]
        apply_stage = text[positions[3] : text.find("post {")]

        check("terraform plan -input=false" in plan, "jenkins: Plan must run terraform plan")
        check("stash " in plan, "jenkins: Plan must stash the plan file")
        check(
            '-var-file="env/${AWS_REGION}.tfvars"' in plan,
            "jenkins: Plan must load the per-region policy file",
        )
        check(
            'test -f "env/${AWS_REGION}.tfvars"' in plan,
            "jenkins: Plan must fail fast when the per-region policy file is missing",
        )
        check(
            'rule_mode=' not in plan,
            "jenkins: rule policy must come from the reviewed per-region file",
        )
        check("terraform plan" not in apply_stage, "jenkins: Apply must never generate a new plan")
        check("unstash " in apply_stage, "jenkins: Apply must unstash the plan file")
        check("terraform apply -input=false" in apply_stage, "jenkins: Apply must apply the stored plan")
        check(
            "sha256sum -c" in apply_stage,
            "jenkins: Apply must verify the plan checksum",
        )
        check("input(" in approval, "jenkins: Approval must use a manual input step")
        check("submitter" in approval, "jenkins: Approval must restrict who can approve")
        check("timeout(" in approval, "jenkins: Approval must have a timeout")

        for name, body in (("Plan", plan), ("Approval", approval), ("Apply", apply_stage)):
            check("branch 'main'" in body, f"jenkins: {name} must be restricted to the protected branch")


def check_env_files() -> None:
    env_dir = ROOT / "env"
    files = sorted(env_dir.glob("*.tfvars")) if env_dir.is_dir() else []
    check(bool(files), "env: no per-region policy files found")

    for path in files:
        text = path.read_text()
        check("rule_mode" in text, f"env: {path.name} must set rule_mode")
        check("enabled_rules" in text, f"env: {path.name} must set enabled_rules")


def main() -> int:
    check_gitlab_ci()
    check_jenkinsfile()
    check_env_files()

    if failures:
        print("Pipeline checks FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("Pipeline checks passed: .gitlab-ci.yml and Jenkinsfile")
    return 0


if __name__ == "__main__":
    sys.exit(main())
