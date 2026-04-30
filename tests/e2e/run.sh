#!/usr/bin/env bash
set -euo pipefail

# E2E test runner for all microservices.
# Usage: ./tests/e2e/run.sh [--target docker|kind]

TARGET="${1:-docker}"
if [[ "$TARGET" == "--target" ]]; then
  TARGET="${2:-docker}"
fi

PASS=0
FAIL=0

case "$TARGET" in
  docker)
    FASTIFY_URL="http://localhost:3001"
    NEXTJS_URL="http://localhost:3002"
    FASTAPI_URL="http://localhost:8000"
    ;;
  kind)
    FASTIFY_URL="http://localhost/fastify"
    NEXTJS_URL="http://localhost/nextjs"
    FASTAPI_URL="http://localhost/fastapi"
    ;;
  *)
    echo "Unknown target: $TARGET (use 'docker' or 'kind')"
    exit 1
    ;;
esac

assert_status() {
  local description="$1"
  local expected_status="$2"
  local actual_status="$3"

  if [[ "$actual_status" == "$expected_status" ]]; then
    echo "  PASS: $description (HTTP $actual_status)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected $expected_status, got $actual_status)"
    FAIL=$((FAIL + 1))
  fi
}

assert_body_contains() {
  local description="$1"
  local needle="$2"
  local body="$3"

  if grep -qF -- "$needle" <<< "$body"; then
    echo "  PASS: $description (body contains '$needle')"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (body missing '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

http_get() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$1" 2>/dev/null || echo "000"
}

http_get_body() {
  curl -s --max-time 10 "$1" 2>/dev/null || echo ""
}

http_post() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST -H "Content-Type: application/json" -d "$2" "$1" 2>/dev/null || echo "000"
}

echo "============================================="
echo "E2E Tests - Target: $TARGET"
echo "============================================="

# -- Fastify Service --
echo ""
echo "--- Fastify Service ($FASTIFY_URL) ---"

assert_status "GET /health" "200" "$(http_get "$FASTIFY_URL/health")"
assert_status "GET /ready" "200" "$(http_get "$FASTIFY_URL/ready")"
assert_status "GET /metrics" "200" "$(http_get "$FASTIFY_URL/metrics")"

BODY=$(http_get_body "$FASTIFY_URL/metrics")
assert_body_contains "Metrics contains http_request" "http_request" "$BODY"

assert_status "GET /api/items" "200" "$(http_get "$FASTIFY_URL/api/items")"

BODY=$(http_get_body "$FASTIFY_URL/api/items")
assert_body_contains "Items list has data" "data" "$BODY"

assert_status "GET /api/items/1" "200" "$(http_get "$FASTIFY_URL/api/items/1")"
assert_status "GET /api/items/999 (not found)" "404" "$(http_get "$FASTIFY_URL/api/items/999")"

assert_status "POST /api/items (valid)" "201" "$(http_post "$FASTIFY_URL/api/items" '{"name":"E2E Item","description":"test"}')"
assert_status "POST /api/items (invalid)" "400" "$(http_post "$FASTIFY_URL/api/items" '{}')"

# -- Next.js Service --
echo ""
echo "--- Next.js Service ($NEXTJS_URL) ---"

assert_status "GET /api/health" "200" "$(http_get "$NEXTJS_URL/api/health")"
assert_status "GET /api/ready" "200" "$(http_get "$NEXTJS_URL/api/ready")"
assert_status "GET /api/metrics" "200" "$(http_get "$NEXTJS_URL/api/metrics")"

BODY=$(http_get_body "$NEXTJS_URL/api/metrics")
assert_body_contains "Metrics contains http_request" "http_request" "$BODY"

assert_status "GET /api/products" "200" "$(http_get "$NEXTJS_URL/api/products")"

BODY=$(http_get_body "$NEXTJS_URL/api/products")
assert_body_contains "Products list has data" "data" "$BODY"

assert_status "GET /api/products/1" "200" "$(http_get "$NEXTJS_URL/api/products/1")"
assert_status "GET /api/products/999 (not found)" "404" "$(http_get "$NEXTJS_URL/api/products/999")"

assert_status "POST /api/products (valid)" "201" "$(http_post "$NEXTJS_URL/api/products" '{"name":"E2E Product","price":19.99,"category":"test"}')"
assert_status "POST /api/products (invalid)" "400" "$(http_post "$NEXTJS_URL/api/products" '{}')"

# -- FastAPI Service --
echo ""
echo "--- FastAPI Service ($FASTAPI_URL) ---"

assert_status "GET /health" "200" "$(http_get "$FASTAPI_URL/health")"
assert_status "GET /ready" "200" "$(http_get "$FASTAPI_URL/ready")"
assert_status "GET /metrics" "200" "$(http_get "$FASTAPI_URL/metrics")"

BODY=$(http_get_body "$FASTAPI_URL/metrics")
assert_body_contains "Metrics contains http" "http" "$BODY"

assert_status "GET /api/orders" "200" "$(http_get "$FASTAPI_URL/api/orders")"

BODY=$(http_get_body "$FASTAPI_URL/api/orders")
assert_body_contains "Orders list has data" "data" "$BODY"

assert_status "GET /api/orders/1" "200" "$(http_get "$FASTAPI_URL/api/orders/1")"
assert_status "GET /api/orders/999 (not found)" "404" "$(http_get "$FASTAPI_URL/api/orders/999")"

assert_status "POST /api/orders (valid)" "201" "$(http_post "$FASTAPI_URL/api/orders" '{"customer":"E2E User","item":"Gadget","quantity":2}')"
assert_status "POST /api/orders (invalid)" "400" "$(http_post "$FASTAPI_URL/api/orders" '{"customer":"","item":"Gadget"}')"

# -- Prometheus --
echo ""
echo "--- Prometheus ---"
if [[ "$TARGET" == "docker" ]]; then
  assert_status "Prometheus /api/v1/targets" "200" "$(http_get "http://localhost:9090/api/v1/targets")"
fi

# -- Summary --
echo ""
echo "============================================="
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "============================================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
