#!/usr/bin/env bash
# Provision the AWS side of OIDC trust for the GitHub Actions deploy-aws.yml
# workflow, then set the AWS_DEPLOY_ROLE_ARN secret on the GitHub repo.
#
# Prerequisites (on the machine that has AWS access to account
# csdmichael@hotmail.com):
#   - aws cli v2:   https://docs.aws.amazon.com/cli/latest/userguide/install.html
#   - gh   cli:     https://cli.github.com/
#   - aws sso login   (or `aws configure` with an admin user)
#   - gh auth login --hostname github.com
#
# Usage:
#   ./scripts/setup-aws-oidc.sh                       # defaults: us-east-1, env=dev
#   ./scripts/setup-aws-oidc.sh --region us-west-2
#   ./scripts/setup-aws-oidc.sh --skip-oidc-provider  # if the provider already exists
#
# Idempotent: re-running just updates the CloudFormation stack.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-multicloud-apim-gateway-github-oidc}"
REPO="${REPO:-csdmichael/MultiCloud-APIM-Gateway}"
ROLE_NAME="${ROLE_NAME:-GitHubActions-MultiCloudApimGateway}"
CREATE_OIDC="true"
TEMPLATE_FILE="$(dirname "$0")/setup-aws-oidc.cfn.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)              REGION="$2"; shift 2 ;;
    --stack-name)          STACK_NAME="$2"; shift 2 ;;
    --repo)                REPO="$2"; shift 2 ;;
    --role-name)           ROLE_NAME="$2"; shift 2 ;;
    --skip-oidc-provider)  CREATE_OIDC="false"; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v aws >/dev/null || { echo "ERROR: aws cli not found" >&2; exit 1; }
command -v gh  >/dev/null || { echo "ERROR: gh cli not found"  >&2; exit 1; }

ACCT=$(aws sts get-caller-identity --query Account --output text)
echo ">> AWS account: $ACCT"
echo ">> Region:      $REGION"
echo ">> Repo:        $REPO"
echo ">> Role name:   $ROLE_NAME"
echo

# Auto-detect existing OIDC provider so we don't double-create
if [[ "$CREATE_OIDC" == "true" ]]; then
  if aws iam list-open-id-connect-providers \
       --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')]" \
       --output text | grep -q token.actions.githubusercontent.com; then
    echo ">> GitHub OIDC provider already exists; setting CreateOidcProvider=false"
    CREATE_OIDC="false"
  fi
fi

echo ">> Deploying CloudFormation stack: $STACK_NAME"
aws cloudformation deploy \
  --template-file "$TEMPLATE_FILE" \
  --stack-name    "$STACK_NAME" \
  --capabilities  CAPABILITY_NAMED_IAM \
  --region        "$REGION" \
  --parameter-overrides \
      GitHubOrg=${REPO%%/*} \
      GitHubRepo=${REPO##*/} \
      RoleName="$ROLE_NAME" \
      CreateOidcProvider="$CREATE_OIDC" \
  --no-fail-on-empty-changeset

ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region     "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" \
  --output text)

echo
echo ">> Role ARN: $ROLE_ARN"

echo ">> Setting GitHub secret on $REPO"
gh secret set AWS_DEPLOY_ROLE_ARN --repo "$REPO" --body "$ROLE_ARN"

echo
echo "===== DONE ====="
echo "AWS_DEPLOY_ROLE_ARN = $ROLE_ARN"
echo
echo "NOTE: .github/workflows/deploy-aws.yml has AWS_REGION hardcoded to us-east-1."
echo "If you used a different --region, also update the workflow's env.AWS_REGION."
echo
echo "Verify with:"
echo "  gh secret list --repo $REPO"
