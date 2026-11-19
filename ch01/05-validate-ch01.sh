#!/usr/bin/env bash
# OrderFlow Global - Chapter 1 Governance & Perimeter Validation Lab
# Copyright 2026 Kien Nguyen (Apache-2.0 License)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:14566}"
export AWS_ENDPOINT_URL="${ENDPOINT}"

echo "[1/4] Validating Ch. 1 JSON policy syntax with python3"
for policy in \
  "${SCRIPT_DIR}/02-scp-workload-guardrails.json" \
  "${SCRIPT_DIR}/03-rcp-data-perimeter.json" \
  "${SCRIPT_DIR}/04-declarative-policy-ec2-vpc.json"; do
  python3 -m json.tool "${policy}" >/dev/null
  echo "  OK: $(basename "${policy}")"
done

echo "[2/4] Asserting RCP org-perimeter and TLS keys"
python3 - "${SCRIPT_DIR}/03-rcp-data-perimeter.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
stmts = doc["Statement"]
org_cond = stmts[0]["Condition"]
assert org_cond["StringNotEqualsIfExists"]["aws:PrincipalOrgID"] == (
    "${aws:ResourceOrgID}"
)
assert org_cond["BoolIfExists"]["aws:PrincipalIsAWSService"] == "false"
assert stmts[1]["Condition"]["Bool"]["aws:SecureTransport"] == "false"
print("  OK: RCP contains PrincipalOrgID, Service, and TLS guards.")
PY

echo "[3/4] Querying LocalStack STS caller identity"
ACCOUNT_ID="$(aws --endpoint-url "${ENDPOINT}" sts get-caller-identity \
  --query 'Account' --output text)"
BUCKET_NAME="orderflow-ch01-check-${ACCOUNT_ID}"
POLICY_FILE="$(mktemp)"

cleanup() {
  rm -f "${POLICY_FILE}"
  aws --endpoint-url "${ENDPOINT}" s3api delete-bucket \
    --bucket "${BUCKET_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[4/4] Verifying S3 public-access-block & org-scoped bucket policy"
aws --endpoint-url "${ENDPOINT}" s3api create-bucket \
  --bucket "${BUCKET_NAME}" >/dev/null

aws --endpoint-url "${ENDPOINT}" s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,\
BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws --endpoint-url "${ENDPOINT}" s3api put-bucket-ownership-controls \
  --bucket "${BUCKET_NAME}" \
  --ownership-controls \
  'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

cat >"${POLICY_FILE}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyOutsideOrg",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalOrgID": "o-orderflow01"
        }
      }
    }
  ]
}
EOF

aws --endpoint-url "${ENDPOINT}" s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy "file://${POLICY_FILE}"

aws --endpoint-url "${ENDPOINT}" s3api get-public-access-block \
  --bucket "${BUCKET_NAME}"
aws --endpoint-url "${ENDPOINT}" s3api get-bucket-ownership-controls \
  --bucket "${BUCKET_NAME}"
POLICY_JSON="$(aws --endpoint-url "${ENDPOINT}" s3api \
  get-bucket-policy --bucket "${BUCKET_NAME}" \
  --query 'Policy' --output text)"
python3 - "${POLICY_JSON}" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
stmt = doc["Statement"][0]
assert stmt["Effect"] == "Deny"
assert stmt["Condition"]["StringNotEquals"]["aws:PrincipalOrgID"] == (
    "o-orderflow01"
)
print("  OK: Live S3 bucket policy enforces aws:PrincipalOrgID.")
PY
echo "Chapter 1 governance checks completed cleanly."
