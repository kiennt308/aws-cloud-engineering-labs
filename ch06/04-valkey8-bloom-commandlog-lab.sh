#!/usr/bin/env bash
# OrderFlow Global - Valkey 8.1 Memory, COMMANDLOG & Bloom Filter Lab
# Copyright 2026 Kien Nguyen (Apache-2.0 License)
set -euo pipefail

VALKEY_IMAGE="${VALKEY_IMAGE:-valkey/valkey-bundle:8.1}"
CONTAINER_NAME="orderflow-valkey8-lab-$$"
PORT="${VALKEY_PORT:-16379}"

cleanup() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[1/5] Starting disposable Valkey 8.1 container (${VALKEY_IMAGE})"
docker run -d --name "${CONTAINER_NAME}" \
  -p "${PORT}:6379" "${VALKEY_IMAGE}" >/dev/null

for _ in $(seq 1 20); do
  if docker exec "${CONTAINER_NAME}" valkey-cli ping >/dev/null 2>&1
  then
    break
  fi
  sleep 0.5
done

vcli() {
  docker exec "${CONTAINER_NAME}" valkey-cli "$@"
}

echo "[2/5] Inspecting Valkey INFO server"
vcli INFO server | grep -E "valkey_version|arch_bits|os" || true

echo "[3/5] Benchmarking compact Hashes vs String keys (MEMORY USAGE)"
{
  for i in $(seq 1 500); do
    printf 'SET str:ord:%s:status PAID\n' "${i}"
    printf 'SET str:ord:%s:currency USD\n' "${i}"
    printf 'SET str:ord:%s:region us-east-1\n' "${i}"
    printf 'SET str:ord:%s:tier express\n' "${i}"
    printf 'SET str:ord:%s:total 4990\n' "${i}"
    printf 'HSET hash:ord:%s status PAID currency USD ' "${i}"
    printf 'region us-east-1 tier express total 4990\n'
  done
} | docker exec -i "${CONTAINER_NAME}" valkey-cli >/dev/null

STR_SUM=0
for fld in status currency region tier total; do
  B="$(vcli MEMORY USAGE "str:ord:1:${fld}")"
  STR_SUM=$((STR_SUM + B))
done
HASH_BYTES="$(vcli MEMORY USAGE hash:ord:1)"
echo "5 String keys total: ${STR_SUM}B | 1 Hash key: ${HASH_BYTES}B"

echo "[4/5] Inspecting Valkey 8.1 COMMANDLOG config & slow logs"
vcli CONFIG GET "commandlog-*"
PREV_SLOW="$(vcli CONFIG GET commandlog-execution-slower-than | tail -n1)"
vcli CONFIG SET commandlog-execution-slower-than 0 >/dev/null
vcli HGETALL hash:ord:1 >/dev/null
vcli COMMANDLOG LEN SLOW
vcli COMMANDLOG GET 3 SLOW
vcli CONFIG SET commandlog-execution-slower-than "${PREV_SLOW}" \
  >/dev/null

echo "[5/5] Verifying Bloom filter vs Set deduplication memory"
if vcli COMMAND INFO bf.reserve | grep -qi "bf.reserve"; then
  vcli BF.RESERVE orderflow:seen-orders 0.001 10000 >/dev/null
  {
    for i in $(seq 1 10000); do
      printf 'BF.ADD orderflow:seen-orders ORD-%s\n' "${i}"
      printf 'SADD orderflow:seen-set ORD-%s\n' "${i}"
    done
  } | docker exec -i "${CONTAINER_NAME}" valkey-cli >/dev/null
  BF_BYTES="$(vcli MEMORY USAGE orderflow:seen-orders)"
  SET_BYTES="$(vcli MEMORY USAGE orderflow:seen-set)"
  HIT="$(vcli BF.EXISTS orderflow:seen-orders ORD-42)"
  echo "BF.EXISTS ORD-42=${HIT} | Bloom=${BF_BYTES}B vs Set=${SET_BYTES}B"
else
  echo "valkey-bloom module not bundled; benchmarking HLL vs Set."
  {
    for i in $(seq 1 2000); do
      printf 'PFADD orderflow:seen-hll ORD-%s\n' "${i}"
      printf 'SADD orderflow:seen-set ORD-%s\n' "${i}"
    done
  } | docker exec -i "${CONTAINER_NAME}" valkey-cli >/dev/null
  HLL_BYTES="$(vcli MEMORY USAGE orderflow:seen-hll)"
  SET_BYTES="$(vcli MEMORY USAGE orderflow:seen-set)"
  echo "HyperLogLog bytes=${HLL_BYTES} vs Exact Set bytes=${SET_BYTES}"
fi
