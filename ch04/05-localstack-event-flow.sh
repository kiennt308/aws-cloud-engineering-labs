#!/usr/bin/env bash
# OrderFlow Global - EventBridge -> SQS FIFO -> DLQ LocalStack Lab
# Copyright 2026 Kien Nguyen (Apache-2.0 License)
set -euo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:14566}"
export AWS_ENDPOINT_URL="${ENDPOINT}"

PY_BIN="$(command -v python3 || command -v python)"
BUS_NAME="orderflow-orders-bus"
RULE_NAME="orderflow-route-order-submitted"
DLQ_NAME="orderflow-orders-dlq.fifo"
QUEUE_NAME="orderflow-orders.fifo"

ATTR_FILE="$(mktemp)"
ENTRIES_FILE="$(mktemp)"
trap 'rm -f "${ATTR_FILE}" "${ENTRIES_FILE}"' EXIT

echo "[1/6] Creating FIFO Dead-Letter Queue: ${DLQ_NAME}"
DLQ_URL="$(aws --endpoint-url "${ENDPOINT}" sqs create-queue \
  --queue-name "${DLQ_NAME}" \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --query 'QueueUrl' --output text)"
DLQ_ARN="$(aws --endpoint-url "${ENDPOINT}" sqs get-queue-attributes \
  --queue-url "${DLQ_URL}" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' --output text)"

echo "[2/6] Creating Primary FIFO Queue with maxReceiveCount=3"
REDRIVE_JSON=$("${PY_BIN}" -c 'import json,sys; print(json.dumps(
  json.dumps({"deadLetterTargetArn": sys.argv[1],
              "maxReceiveCount": "3"})))' "${DLQ_ARN}")
cat >"${ATTR_FILE}" <<EOF
{
  "FifoQueue": "true",
  "ContentBasedDeduplication": "true",
  "DeduplicationScope": "messageGroup",
  "FifoThroughputLimit": "perMessageGroupId",
  "RedrivePolicy": ${REDRIVE_JSON}
}
EOF

QUEUE_URL="$(aws --endpoint-url "${ENDPOINT}" sqs create-queue \
  --queue-name "${QUEUE_NAME}" \
  --attributes "file://${ATTR_FILE}" \
  --query 'QueueUrl' --output text)"
QUEUE_ARN="$(aws --endpoint-url "${ENDPOINT}" sqs get-queue-attributes \
  --queue-url "${QUEUE_URL}" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' --output text)"

echo "[3/6] Creating custom EventBridge bus & routing rule"
aws --endpoint-url "${ENDPOINT}" events create-event-bus \
  --name "${BUS_NAME}" >/dev/null || true
aws --endpoint-url "${ENDPOINT}" events put-rule \
  --name "${RULE_NAME}" \
  --event-bus-name "${BUS_NAME}" \
  --state ENABLED \
  --event-pattern \
    '{"source":["orderflow.checkout"],"detail-type":["OrderSubmitted"]}' \
  >/dev/null

aws --endpoint-url "${ENDPOINT}" events put-targets \
  --rule "${RULE_NAME}" \
  --event-bus-name "${BUS_NAME}" \
  --targets "[{
    \"Id\": \"OrderSubmittedFifoTarget\",
    \"Arn\": \"${QUEUE_ARN}\",
    \"SqsParameters\": {\"MessageGroupId\": \"orderflow-orders-v1\"}
  }]" >/dev/null

echo "[4/6] Publishing OrderSubmitted event to ${BUS_NAME}"
DETAIL='{"orderId":"ORD-9001","amountCents":12990}'
"${PY_BIN}" - "${BUS_NAME}" "${DETAIL}" >"${ENTRIES_FILE}" <<'PY'
import json, sys
print(json.dumps([{
    "EventBusName": sys.argv[1],
    "Source": "orderflow.checkout",
    "DetailType": "OrderSubmitted",
    "Detail": sys.argv[2],
}]))
PY
aws --endpoint-url "${ENDPOINT}" events put-events \
  --entries "file://${ENTRIES_FILE}" >/dev/null

echo "[5/6] Reading delivered message from ${QUEUE_NAME}"
RECEIVED="$(aws --endpoint-url "${ENDPOINT}" sqs receive-message \
  --queue-url "${QUEUE_URL}" \
  --attribute-names All \
  --max-number-of-messages 1 \
  --wait-time-seconds 5)"
echo "${RECEIVED}"

RECEIPT="$(echo "${RECEIVED}" | "${PY_BIN}" -c '
import json, sys
d = json.load(sys.stdin)
print(d["Messages"][0]["ReceiptHandle"])
')"
aws --endpoint-url "${ENDPOINT}" sqs delete-message \
  --queue-url "${QUEUE_URL}" \
  --receipt-handle "${RECEIPT}"

echo "[6/6] Verifying explicit MessageDeduplicationId idempotency"
DEDUP_ID="idemp-ord-9002-$(date +%s)"
aws --endpoint-url "${ENDPOINT}" sqs send-message \
  --queue-url "${QUEUE_URL}" \
  --message-body '{"orderId":"ORD-9002","amountCents":4990}' \
  --message-group-id "orderflow-orders-v1" \
  --message-deduplication-id "${DEDUP_ID}" >/dev/null
aws --endpoint-url "${ENDPOINT}" sqs send-message \
  --queue-url "${QUEUE_URL}" \
  --message-body '{"orderId":"ORD-9002","amountCents":4990}' \
  --message-group-id "orderflow-orders-v1" \
  --message-deduplication-id "${DEDUP_ID}" >/dev/null

DEPTH="$(aws --endpoint-url "${ENDPOINT}" sqs get-queue-attributes \
  --queue-url "${QUEUE_URL}" \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text)"
echo "Verified deduplicated FIFO queue depth: ${DEPTH}"
