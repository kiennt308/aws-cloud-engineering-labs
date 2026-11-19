#!/usr/bin/env bash
# OrderFlow Global - LocalStack STS ExternalId Isolation Lab
# Copyright 2026 Kien Nguyen (Apache-2.0 License)
set -euo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:14566}"
export AWS_ENDPOINT_URL="${ENDPOINT}"

ROLE_NAME="orderflow-partner-sts-$(date +%s)"
EXTERNAL_ID="orderflow-partner-ext-9482"
TRUST_FILE="$(mktemp)"
PERM_FILE="$(mktemp)"

cleanup() {
  rm -f "${TRUST_FILE}" "${PERM_FILE}"
  aws --endpoint-url "${ENDPOINT}" iam delete-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "OrderFlowPartnerRead" >/dev/null 2>&1 || true
  aws --endpoint-url "${ENDPOINT}" iam delete-role \
    --role-name "${ROLE_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[1/5] Resolving LocalStack account ID"
ACCOUNT_ID="$(aws --endpoint-url "${ENDPOINT}" sts get-caller-identity \
  --query 'Account' --output text)"

cat >"${TRUST_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "${EXTERNAL_ID}"
        }
      }
    }
  ]
}
EOF

cat >"${PERM_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::orderflow-assets-${ACCOUNT_ID}/partner/*"
    }
  ]
}
EOF

echo "[2/5] Creating IAM role ${ROLE_NAME} with ExternalId condition"
ROLE_ARN="$(aws --endpoint-url "${ENDPOINT}" iam create-role \
  --role-name "${ROLE_NAME}" \
  --assume-role-policy-document "file://${TRUST_FILE}" \
  --query 'Role.Arn' --output text)"

aws --endpoint-url "${ENDPOINT}" iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "OrderFlowPartnerRead" \
  --policy-document "file://${PERM_FILE}" >/dev/null

echo "[3/5] Asserting live IAM trust & least-privilege policy JSON"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_TRUST="$(aws --endpoint-url "${ENDPOINT}" iam get-role \
  --role-name "${ROLE_NAME}" \
  --query 'Role.AssumeRolePolicyDocument' --output json)"
LIVE_PERM="$(aws --endpoint-url "${ENDPOINT}" iam get-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "OrderFlowPartnerRead" \
  --query 'PolicyDocument' --output json)"
python3 - "${LIVE_TRUST}" "${LIVE_PERM}" "${EXTERNAL_ID}" <<'PY'
import json, sys
trust = json.loads(sys.argv[1])
perm = json.loads(sys.argv[2])
ext_id = sys.argv[3]
st = trust["Statement"][0]
assert st["Action"] == "sts:AssumeRole"
assert st["Condition"]["StringEquals"]["sts:ExternalId"] == ext_id
pst = perm["Statement"][0]
assert pst["Resource"] != "*" and "iam:PassRole" not in pst["Action"]
print("  PASS: Live trust ExternalId and scoped resource verified.")
PY

echo "[4/5] Verifying CI baseline vs escalated Access Analyzer diff"
python3 - "${SCRIPT_DIR}/04-access-analyzer-baseline-policy.json" \
  "${SCRIPT_DIR}/05-access-analyzer-candidate-policy.json" <<'PY'
import json, sys
base = json.load(open(sys.argv[1], encoding="utf-8"))
cand = json.load(open(sys.argv[2], encoding="utf-8"))
def collect_actions(doc):
    out = set()
    for stmt in doc["Statement"]:
        acts = stmt["Action"]
        out.update(acts if isinstance(acts, list) else [acts])
    return out
extra = sorted(collect_actions(cand) - collect_actions(base))
assert extra, "Expected escalated candidate actions"
print(f"  PASS: Caught escalated candidate actions: {extra}")
PY

echo "[5/5] Assuming role via STS with matching ExternalId"
KEY_PREFIX="$(aws --endpoint-url "${ENDPOINT}" sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "valid-ext-id" \
  --external-id "${EXTERNAL_ID}" \
  --query 'Credentials.AccessKeyId' --output text)"
echo "  PASS: Issued temporary STS key: ${KEY_PREFIX}"
echo "  Note: Real AWS STS blocks missing ExternalId; Community"
echo "        LocalStack mocks STS without Pro IAM enforcement."
