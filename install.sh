#!/bin/sh
# install.sh
set -eu

: "${NODE_NAME:?NODE_NAME env var is required (set via downward API)}"

CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
API=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}

mkdir -p /host/opt/cni/bin /host/etc/cni/net.d

# Fetch podCIDR with proper error handling
RESPONSE=$(curl -fsS --cacert "$CA" -H "Authorization: Bearer $TOKEN" \
  "$API/api/v1/nodes/$NODE_NAME") || {
  echo "failed to fetch node info from API server" >&2
  exit 1
}

POD_CIDR=$(echo "$RESPONSE" | jq -r '.spec.podCIDR')
if [ -z "$POD_CIDR" ] || [ "$POD_CIDR" = "null" ]; then
  echo "podCIDR not assigned to node $NODE_NAME (check --allocate-node-cidrs)" >&2
  exit 1
fi

cp /sandbox-cni /host/opt/cni/bin/.sandbox-cni.tmp
chmod 0755 /host/opt/cni/bin/.sandbox-cni.tmp
mv /host/opt/cni/bin/.sandbox-cni.tmp /host/opt/cni/bin/sandbox-cni

TMP=/host/etc/cni/net.d/.10-sandbox-cni.conflist.tmp
cat > "$TMP" <<EOF
{
  "cniVersion": "1.0.0",
  "name": "sandbox-cni",
  "plugins": [
    {
      "type": "sandbox-cni",
      "delegateType": "ptp",
      "subnet": "$POD_CIDR"
    }
  ]
}
EOF
mv "$TMP" /host/etc/cni/net.d/10-sandbox-cni.conflist

echo "sandbox-cni installed on $NODE_NAME with podCIDR=$POD_CIDR"

term() { echo "shutting down"; exit 0; }
trap term TERM INT
sleep infinity &
wait $!
