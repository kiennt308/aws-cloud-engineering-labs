#!/usr/bin/env bash
# OrderFlow Global - LocalStack S3 Conditional Writes & KMS Envelope Lab
# Copyright 2026 Kien Nguyen (Apache-2.0 License)
set -euo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:14566}"
export AWS_ENDPOINT_URL="${ENDPOINT}"

PY_BIN="$(command -v python3 || command -v python)"
BUCKET="orderflow-assets-000000000000"
ALIAS_NAME="alias/orderflow-data-mrk"
KEY_PATH="orders/2026/11/lock-ord-9001.json"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "[1/5] Creating KMS key & alias ${ALIAS_NAME}"
KEY_ID="$(aws --endpoint-url "${ENDPOINT}" kms create-key \
  --description "OrderFlow LocalStack MRK drill key" \
  --query 'KeyMetadata.KeyId' --output text)"
if ! aws --endpoint-url "${ENDPOINT}" kms list-aliases \
  --query "Aliases[?AliasName=='${ALIAS_NAME}'].AliasName" \
  --output text | grep -qx "${ALIAS_NAME}"; then
  aws --endpoint-url "${ENDPOINT}" kms create-alias \
    --alias-name "${ALIAS_NAME}" \
    --target-key-id "${KEY_ID}"
else
  aws --endpoint-url "${ENDPOINT}" kms update-alias \
    --alias-name "${ALIAS_NAME}" \
    --target-key-id "${KEY_ID}"
fi

echo "[2/5] Creating hardened S3 bucket ${BUCKET}"
aws --endpoint-url "${ENDPOINT}" s3api create-bucket \
  --bucket "${BUCKET}" >/dev/null 2>&1 || true
aws --endpoint-url "${ENDPOINT}" s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,\
BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "[3/5] Generating KMS AES_256 data key & verifying decrypt"
DATA_KEY_JSON="${TMP_DIR}/datakey.json"
aws --endpoint-url "${ENDPOINT}" kms generate-data-key \
  --key-id "${ALIAS_NAME}" \
  --key-spec AES_256 >"${DATA_KEY_JSON}"

"${PY_BIN}" - "${DATA_KEY_JSON}" "${TMP_DIR}/cipher.bin" <<'PY'
import base64, json, sys
data = json.load(open(sys.argv[1]))
open(sys.argv[2], "wb").write(base64.b64decode(data["CiphertextBlob"]))
open(sys.argv[1] + ".pt", "w").write(data["Plaintext"])
PY

DECRYPTED_B64="$(aws --endpoint-url "${ENDPOINT}" kms decrypt \
  --ciphertext-blob "fileb://${TMP_DIR}/cipher.bin" \
  --query 'Plaintext' --output text)"
ORIG_B64="$(cat "${DATA_KEY_JSON}.pt")"
if [[ "${DECRYPTED_B64}" != "${ORIG_B64}" ]]; then
  echo "ERROR: KMS envelope decrypt mismatch!" >&2
  exit 1
fi
echo "KMS envelope generate-data-key/decrypt round-trip verified."

echo "[4/5] Testing S3 Conditional Write first upload (--if-none-match *)"
PAYLOAD="${TMP_DIR}/order.json"
printf '{"orderId":"ORD-9001","status":"LOCKED"}\n' >"${PAYLOAD}"
aws --endpoint-url "${ENDPOINT}" s3api delete-object \
  --bucket "${BUCKET}" --key "${KEY_PATH}" >/dev/null 2>&1 || true

ETAG="$(aws --endpoint-url "${ENDPOINT}" s3api put-object \
  --bucket "${BUCKET}" \
  --key "${KEY_PATH}" \
  --body "${PAYLOAD}" \
  --if-none-match "*" \
  --server-side-encryption aws:kms \
  --ssekms-key-id "${ALIAS_NAME}" \
  --query 'ETag' --output text)"
echo "First conditional write succeeded (HTTP 200), ETag=${ETAG}"

echo "[5/5] Testing competing conditional write (expect 412)"
set +e
ERR_OUT="$(aws --endpoint-url "${ENDPOINT}" s3api put-object \
  --bucket "${BUCKET}" \
  --key "${KEY_PATH}" \
  --body "${PAYLOAD}" \
  --if-none-match "*" \
  --server-side-encryption aws:kms \
  --ssekms-key-id "${ALIAS_NAME}" 2>&1)"
RC=$?
set -e

if [[ ${RC} -ne 0 ]] && \
   echo "${ERR_OUT}" | grep -qE "PreconditionFailed|412"; then
  echo "Competing write blocked cleanly with PreconditionFailed (412)."
else
  echo "Unexpected result (rc=${RC}): ${ERR_OUT}" >&2
  exit 1
fi
