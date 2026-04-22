"""
Tests for terraform-aws-openclaw module.

These tests verify:
- Infrastructure components (ALB, ASG, Cognito, EFS, Secrets Manager, CloudWatch)
- End-to-end deployment of OpenClaw behind an ALB with Cognito authentication
"""

import json
import time
from os import path as osp, remove
from shutil import rmtree
from textwrap import dedent

import pytest
from infrahouse_core.aws.asg import ASG
from infrahouse_core.timeout import timeout
from pytest_infrahouse import terraform_apply

from tests.conftest import LOG, TERRAFORM_ROOT_DIR

INSTANCE_READY_TIMEOUT = 900  # 15 minutes for instance to become InService
INSTANCE_POLL_INTERVAL = 30


def wait_for_instance_in_service(asg: ASG, wait_timeout: int = INSTANCE_READY_TIMEOUT):
    """Wait for all instances in the ASG to reach InService state.

    The lifecycle hook holds instances in Pending:Wait until the setup
    script completes and calls ih-aws autoscaling complete.

    :param asg: ASG object with instances to wait on.
    :param wait_timeout: Maximum seconds to wait.
    :raises TimeoutError: if instances don't reach InService in time.
    """
    LOG.info("Waiting for ASG instances to reach InService...")

    with timeout(wait_timeout):
        while True:
            instances = asg.instances
            pending = [
                inst for inst in instances if inst.lifecycle_state != "InService"
            ]
            if not pending:
                LOG.info(
                    "All %d instances are InService",
                    len(instances),
                )
                return
            LOG.info(
                "Waiting for %d instance(s): %s",
                len(pending),
                {inst.instance_id: inst.lifecycle_state for inst in pending},
            )
            time.sleep(INSTANCE_POLL_INTERVAL)


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_module(
    service_network,
    subzone,
    test_role_arn,
    keep_after,
    aws_region,
    aws_provider_version,
):
    """
    Test the OpenClaw module end-to-end.

    This test verifies:
    - Module can be planned and applied successfully
    - ALB, ASG, Cognito, EFS, Secrets Manager, CloudWatch resources are created
    - Cloud-init finishes on the instance
    - OpenClaw service is running and healthy behind the ALB
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "openclaw")

    # Clean up state files to ensure fresh terraform init
    state_files = [
        osp.join(terraform_module_dir, ".terraform"),
        osp.join(terraform_module_dir, ".terraform.lock.hcl"),
    ]
    for state_file in state_files:
        try:
            if osp.isdir(state_file):
                rmtree(state_file)
            elif osp.isfile(state_file):
                remove(state_file)
        except FileNotFoundError:
            pass

    # Generate terraform.tf with specified AWS provider version
    with open(osp.join(terraform_module_dir, "terraform.tf"), "w") as fp:
        fp.write(dedent(f"""
                terraform {{
                  required_version = "~> 1.5"
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                      configuration_aliases = [
                        aws.dns
                      ]
                    }}
                    tls = {{
                      source  = "hashicorp/tls"
                      version = "~> 4.0"
                    }}
                    random = {{
                      source  = "hashicorp/random"
                      version = "~> 3.0"
                    }}
                  }}
                }}
                """))

    # Generate terraform.tfvars
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(dedent(f"""
                region             = "{aws_region}"
                subnet_public_ids  = {json.dumps(subnet_public_ids)}
                subnet_private_ids = {json.dumps(subnet_private_ids)}
                zone_id            = "{zone_id}"
                """))
        if test_role_arn:
            fp.write(dedent(f"""
                role_arn = "{test_role_arn}"
                """))

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info("Terraform output: %s", json.dumps(tf_output, indent=4))

        # Verify infrastructure outputs
        assert tf_output["url"]["value"], "URL should not be empty"
        assert tf_output["url"]["value"].startswith("https://"), "URL should be HTTPS"
        assert tf_output["asg_name"]["value"], "ASG name should not be empty"
        assert tf_output["cognito_user_pool_id"][
            "value"
        ], "Cognito user pool ID should not be empty"
        assert tf_output["cognito_domain_url"][
            "value"
        ], "Cognito domain URL should not be empty"
        assert tf_output["secret_arn"]["value"], "Secret ARN should not be empty"
        assert tf_output["secret_name"]["value"], "Secret name should not be empty"
        assert tf_output["alb_dns_name"]["value"], "ALB DNS name should not be empty"
        assert tf_output["alb_arn"]["value"], "ALB ARN should not be empty"
        assert tf_output["instance_role_name"][
            "value"
        ], "Instance role name should not be empty"
        assert tf_output["backend_security_group_id"][
            "value"
        ], "Backend security group ID should not be empty"
        assert tf_output["efs_file_system_id"][
            "value"
        ], "EFS file system ID should not be empty"
        assert tf_output["cloudwatch_log_group_name"][
            "value"
        ], "CloudWatch log group name should not be empty"

        asg_name = tf_output["asg_name"]["value"]

        # Wait for instance to complete setup (lifecycle hook)
        openclaw_asg = ASG(asg_name, region=aws_region, role_arn=test_role_arn)
        wait_for_instance_in_service(openclaw_asg)

        # Verify OpenClaw service is running
        instance = openclaw_asg.instances[0]
        exit_code, cout, cerr = instance.execute_command(
            "systemctl is-active openclaw.service"
        )
        LOG.info(
            "openclaw.service status: exit_code=%d, stdout=%s, stderr=%s",
            exit_code,
            cout,
            cerr,
        )
        assert (
            exit_code == 0
        ), f"openclaw.service should be active: stdout={cout}, stderr={cerr}"

        # Verify OpenClaw is listening on port 5173
        exit_code, cout, cerr = instance.execute_command(
            "curl -sf -o /dev/null -w '%{http_code}' http://localhost:5173/"
        )
        LOG.info(
            "OpenClaw health check: exit_code=%d, stdout=%s, stderr=%s",
            exit_code,
            cout,
            cerr,
        )
        assert (
            exit_code == 0
        ), f"OpenClaw should respond on port 5173: stdout={cout}, stderr={cerr}"

        # Verify EFS is mounted
        exit_code, cout, cerr = instance.execute_command(
            "cat /proc/mounts | grep openclaw || echo 'NO_MATCH'"
        )
        LOG.info(
            "EFS mount check: exit_code=%d, stdout=%s, stderr=%s",
            exit_code,
            cout,
            cerr,
        )
        assert "openclaw" in cout, (
            f"EFS should be mounted at /home/openclaw/.openclaw: "
            f"stdout={cout}, stderr={cerr}"
        )

        # Verify openclaw.json exists on EFS
        exit_code, cout, cerr = instance.execute_command(
            "test -f /home/openclaw/.openclaw/openclaw.json"
        )
        assert (
            exit_code == 0
        ), f"openclaw.json should exist on EFS: stdout={cout}, stderr={cerr}"

        LOG.info("All end-to-end verifications passed")
        LOG.info(
            "\n"
            "========================================\n"
            " URL:       %s\n"
            " Username:  devnull@infrahouse.com\n"
            " A temporary password was sent to devnull@infrahouse.com\n"
            "========================================",
            tf_output["url"]["value"],
        )
