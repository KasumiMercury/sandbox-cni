#!/bin/sh
set -eu

POD_CIDR_PREFIX='^10\.244\.'
EXTERNAL_TARGET=8.8.8.8

# Apply test Pods on separate nodes (CLUSTER_NAME injected by Taskfile)
envsubst < tests/verify-pods.yaml | kubectl apply -f -

kubectl wait --for=condition=Ready pod/verify-cp pod/verify-w --timeout=120s

# --- IP assignment ---
IP_CP=$(kubectl get pod verify-cp -o jsonpath='{.status.podIP}')
IP_W=$(kubectl get pod verify-w  -o jsonpath='{.status.podIP}')
echo "verify-cp IP: $IP_CP"
echo "verify-w  IP: $IP_W"
echo "$IP_CP" | grep -Eq "$POD_CIDR_PREFIX" || { echo "ERROR: verify-cp IP not in podCIDR"; exit 1; }
echo "$IP_W"  | grep -Eq "$POD_CIDR_PREFIX" || { echo "ERROR: verify-w  IP not in podCIDR"; exit 1; }
echo "OK: both Pods have IPs within podCIDR"

# --- cross-node ping ---
# ptp adds only per-node veth routes; inter-node routing requires an overlay or static routes.
echo "Pinging $IP_W from verify-cp..."
kubectl exec verify-cp -- ping -c 3 -W 2 "$IP_W" \
  && echo "OK: cross-node Pod-to-Pod ping succeeded" \
  || echo "WARN: cross-node ping failed (expected — ptp has no inter-node routing)"

# --- external ping ---
# ptp + host-local has no masquerade; external reachability requires separate NAT.
echo "Pinging $EXTERNAL_TARGET for external connectivity..."
kubectl exec verify-cp -- ping -c 3 -W 2 "$EXTERNAL_TARGET" \
  && echo "OK: external ping succeeded" \
  || echo "WARN: external ping failed (expected — ptp+host-local has no NAT masquerade)"

