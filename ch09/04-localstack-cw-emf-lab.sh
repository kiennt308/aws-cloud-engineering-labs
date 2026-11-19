#!/usr/bin/env bash
# OrderFlow LocalStack CloudWatch EMF + Alarm Wiring Lab
# Author: Kien Nguyen | License: Apache-2.0
# Baseline: AWS CLI v2.41.1 + LocalStack v2026.10.0

set -euo pipefail

ENDPOINT_URL="${LOCALSTACK_ENDPOINT:-http://localhost:14566}"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LOG_GROUP="/orderflow/prod/telemetry"
LOG_STREAM="checkout-api-emf-01"
NAMESPACE="OrderFlow/AWS"
ALARM_NAME="orderflow-checkout-latency-emf-alarm"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_REGION}"

EVENTS_FILE="$(mktemp)"
cleanup() {
  rm -f "${EVENTS_FILE}"
}
trap cleanup EXIT

echo "[1/5] Ensuring CloudWatch Log Group ${LOG_GROUP} exists..."
if ! aws --endpoint-url "${ENDPOINT_URL}" logs describe-log-groups \
  --log-group-name-prefix "${LOG_GROUP}" \
  --query "logGroups[?logGroupName=='${LOG_GROUP}'].logGroupName" \
  --output text | grep -q "^${LOG_GROUP}$"; then
  aws --endpoint-url "${ENDPOINT_URL}" logs create-log-group \
    --log-group-name "${LOG_GROUP}"
fi

aws --endpoint-url "${ENDPOINT_URL}" logs put-retention-policy \
  --log-group-name "${LOG_GROUP}" \
  --retention-in-days 30

echo "[2/5] Ensuring Log Stream ${LOG_STREAM} exists..."
if ! aws --endpoint-url "${ENDPOINT_URL}" logs describe-log-streams \
  --log-group-name "${LOG_GROUP}" \
  --log-stream-name-prefix "${LOG_STREAM}" \
  --query "logStreams[?logStreamName=='${LOG_STREAM}'].logStreamName" \
  --output text | grep -q "^${LOG_STREAM}$"; then
  aws --endpoint-url "${ENDPOINT_URL}" logs create-log-stream \
    --log-group-name "${LOG_GROUP}" \
    --log-stream-name "${LOG_STREAM}"
fi

echo "[3/5] Publishing Embedded Metric Format (EMF) event..."
NOW_MS="$(($(date +%s) * 1000))"

EMF_MSG=$(printf '%s%s%s' \
  '{"_aws":{"Timestamp":' "${NOW_MS}" \
  ',"CloudWatchMetrics":[{"Namespace":"'"${NAMESPACE}"'"' \
  ',"Dimensions":[["Service","Environment"]],"Metrics":[' \
  '{"Name":"OrderCheckoutLatencyMs","Unit":"Milliseconds"},' \
  '{"Name":"OrderPaymentErrors","Unit":"Count"}]}]},' \
  '"Service":"checkout-api","Environment":"prod",' \
  '"OrderCheckoutLatencyMs":142,"OrderPaymentErrors":1,' \
  '"traceId":"1-673b4f10-00112233445566778899aabb",' \
  '"message":"OrderFlow checkout completed"}')

ESCAPED_MSG="${EMF_MSG//\"/\\\"}"
cat > "${EVENTS_FILE}" <<EOF
[
  {
    "timestamp": ${NOW_MS},
    "message": "${ESCAPED_MSG}"
  }
]
EOF

aws --endpoint-url "${ENDPOINT_URL}" logs put-log-events \
  --log-group-name "${LOG_GROUP}" \
  --log-stream-name "${LOG_STREAM}" \
  --log-events "file://${EVENTS_FILE}"

echo "[4/5] Creating CloudWatch Alarm ${ALARM_NAME}..."
aws --endpoint-url "${ENDPOINT_URL}" cloudwatch put-metric-alarm \
  --alarm-name "${ALARM_NAME}" \
  --alarm-description "OrderFlow checkout latency > 250ms (EMF)" \
  --namespace "${NAMESPACE}" \
  --metric-name OrderCheckoutLatencyMs \
  --dimensions Name=Service,Value=checkout-api \
               Name=Environment,Value=prod \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 250 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching

echo "[5/5] Verifying CloudWatch metrics and alarm wiring..."
aws --endpoint-url "${ENDPOINT_URL}" cloudwatch list-metrics \
  --namespace "${NAMESPACE}" \
  --output table

aws --endpoint-url "${ENDPOINT_URL}" cloudwatch describe-alarms \
  --alarm-names "${ALARM_NAME}" \
  --query "MetricAlarms[0].[AlarmName,Namespace,MetricName,StateValue]" \
  --output table

echo "LocalStack CW EMF and Alarm lab verified successfully."
