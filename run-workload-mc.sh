#!/bin/bash
set -euo pipefail

# Mojjjak , Extend me and Fix the External DNS issue #

WORKLOAD_SCRIPT=${1:-}
SHARE_MOUNT=${2:-}

if [[ -z "$WORKLOAD_SCRIPT" || -z "$SHARE_MOUNT" ]]; then
  echo "Usage: $0 <workload-script> <shared-mount-path>"
  exit 1
fi

CLUSTER_NAME="liqo-${SLURM_PROCID:-$$}"
CLUSTER_ID="${SLURM_PROCID}"
CONTROL_PLANE_PORT=$((6443 + CLUSTER_ID))
WORKER_IP=$(hostname -I | awk '{print $1}')

cat > kind-config-${CLUSTER_NAME}.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 6443
        hostPort: ${CONTROL_PLANE_PORT}
        listenAddress: "${WORKER_IP}"
EOF

echo "[Task ${CLUSTER_ID}] Creating KinD cluster: $CLUSTER_NAME"
kind create cluster --name "$CLUSTER_NAME" --image kindest/node:v1.29.0 --config kind-config-${CLUSTER_NAME}.yaml --wait 60s

CONTROL_PLANE_CONTAINER="${CLUSTER_NAME}-control-plane"

CONTAINER_IP=$(podman inspect -f '{{ .NetworkSettings.IPAddress }}' "$CONTROL_PLANE_CONTAINER")


KUBECONFIG_EXPORT_PATH="${SHARE_MOUNT}/kubeconfig-liqo-${CLUSTER_ID}.yaml"
echo "[Task ${CLUSTER_ID}] Exporting kubeconfig to ${KUBECONFIG_EXPORT_PATH} ..."
kind get kubeconfig --name "$CLUSTER_NAME" > "${KUBECONFIG_EXPORT_PATH}"


sed -i "s|https://.*control-plane:6443|https://${WORKER_IP}:${CONTROL_PLANE_PORT}|g" "${KUBECONFIG_EXPORT_PATH}"


yq eval '.clusters[].cluster |= . + {"insecure-skip-tls-verify": true} | .clusters[].cluster.certificate-authority-data = null' -i "${KUBECONFIG_EXPORT_PATH}"

echo "[Task ${CLUSTER_ID}] Waiting for all nodes to be ready..."
kubectl --kubeconfig="${KUBECONFIG_EXPORT_PATH}" wait node --all --for=condition=Ready --timeout=120s

echo "[Task ${CLUSTER_ID}] Installing Liqo on cluster..."
liqoctl install kind --kubeconfig "${KUBECONFIG_EXPORT_PATH}" || {
  echo "ERROR: Liqo install failed!"
  kind delete cluster --name "$CLUSTER_NAME"
  exit 1
}

K8S_CLUSTER_NAME=$(yq eval '.["current-context"]' "${KUBECONFIG_EXPORT_PATH}")
export KUBECONFIG="${KUBECONFIG_EXPORT_PATH}"
export K8S_CLUSTER_NAME

echo "[Task ${CLUSTER_ID}] Liqo install complete. Running workload..."
bash "$WORKLOAD_SCRIPT" "$SHARE_MOUNT"
WORKLOAD_EXIT_CODE=$?

if [[ $WORKLOAD_EXIT_CODE -ne 0 ]]; then
  echo "[Task ${CLUSTER_ID}] Workload script exited with code $WORKLOAD_EXIT_CODE"
else
  echo "[Task ${CLUSTER_ID}] Workload completed successfully"
fi

# Mojjjak, We can remove this part for the permanent cluster #
echo "[Task ${CLUSTER_ID}] Cleaning up KinD cluster..."
kind delete cluster --name "$CLUSTER_NAME"

rm -f kind-config-${CLUSTER_NAME}.yaml
rm -f kubeconfig-liqo-${CLUSTER_ID}.yaml
# End

echo "[Task ${CLUSTER_ID}] Done."
exit $WORKLOAD_EXIT_CODE
