# federate-k8s-cluster

> Run federated, multi-node Kubernetes clusters using KinD + Liqo inside SLURM jobs.

## 🌍 Overview

**`federate-k8s-cluster`** allows you to dynamically create multiple isolated Kubernetes clusters on SLURM worker nodes using [KinD](https://kind.sigs.k8s.io/), and federate them together using [Liqo](https://www.liqo.io/). Each SLURM worker spawns its own Kubernetes control-plane, which is interconnected with others, enabling multi-cluster application workloads.

Use it to run distributed workloads, service meshes, or multi-node benchmarking environments.

---

## ⚙️ Architecture

```
+-------------------------+
| SLURM Controller        |
+-------------------------+
        | job scheduling
        v
+-------------------------+
| SLURM Node (worker 1)   |
| - KinD cluster          |
| - Liqo Agent            |
+-------------------------+
        |
        v peering via Liqo
+-------------------------+
| SLURM Node (worker 2)   |
| - KinD cluster          |
| - Liqo Agent            |
+-------------------------+
        |
        v
+-------------------------+
| SLURM Node (worker N)   |
| - KinD cluster          |
| - Liqo Agent            |
+-------------------------+
```

---

## 🚀 Quick Start

### 1. ✅ Prerequisites

- A SLURM-based environment with multiple nodes.
- `podman` or `docker` installed on all nodes.
- `kind`, `kubectl`, `liqoctl`, and `yq` available in PATH.

```bash
dnf install -y podman jq yq kind kubectl nfs-utils
```

---

### 2. 💥 Run a Federated Job

Create a SLURM batch job like this:

```bash
#!/bin/bash
#SBATCH -N 3
#SBATCH -n 3
#SBATCH --ntasks-per-node=1

srun ./run-workload.sh ./example-workloads/workload-pod-sysbench/workload-pod-sysbench.sh /shared/kubeconfigs
```

This will:
- Start one KinD control-plane per SLURM task
- Configure kubeconfig to expose port `6443 + SLURM_PROCID` externally
- Install Liqo to federate all clusters
- Run your workload script using `kubectl --context` to the correct cluster

---

### 3. 📁 Directory Structure

```
.
├── run-workload.sh                            # Main script to run per SLURM node
├── example-workloads/
│   └── workload-pod-sysbench/
│       └── workload-pod-sysbench.sh          # Example workload (uses context)
└── /shared/kubeconfigs/                      # Shared mount for kubeconfigs
```

---

## 🧠 How It Works

- Each SLURM worker runs a KinD cluster with a unique name and API port (`6443 + PROCID`).
- The `run-workload.sh` script exposes the control-plane externally, patches the `kubeconfig`, and stores it in a shared directory.
- Liqo is installed on each cluster, and **auto-peers** them.
- Your workload uses `kubectl --context kind-liqo-<procid>` to target each specific cluster.
- Federated workloads can transparently use remote pods, services, and nodes.

---

## 🔧 Example Workload

Here's a sample:

```bash
#!/bin/bash
set -x

export K8S_CLUSTER_NAME="kind-liqo-${SLURM_PROCID}"
KUBECONFIG_PATH="${1}/kubeconfig-liqo-${SLURM_PROCID}.yaml"
export KUBECONFIG="$KUBECONFIG_PATH"

kubectl create --context "$K8S_CLUSTER_NAME" namespace bench

kubectl create -n bench --context "$K8S_CLUSTER_NAME" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: sysbench-cpu
  labels:
    app: sysbench
spec:
  containers:
  - name: sysbench
    image: severalnines/sysbench
    command: ["sysbench", "cpu", "--threads=56", "--cpu-max-prime=20000", "run"]
  restartPolicy: Never
EOF

kubectl wait -n bench --context "$K8S_CLUSTER_NAME" --for condition=Ready pod/sysbench-cpu --timeout=5m
kubectl logs -f -n bench pod/sysbench-cpu --context "$K8S_CLUSTER_NAME"
kubectl delete namespace bench --context "$K8S_CLUSTER_NAME"
```

---

## 📦 Cleanup

Clusters are deleted automatically at the end of the workload. If you need to manually delete:

```bash
kind delete cluster --name liqo-<id>
```

---

## 🛠 Tools Used

- [KinD](https://kind.sigs.k8s.io/) — Lightweight Kubernetes clusters in containers
- [Liqo](https://www.liqo.io/) — Kubernetes-native multi-cluster federation
- `SLURM` — HPC resource scheduler
- `podman` or `docker` — Container runtime
- `yq` — YAML processor (used for kubeconfig patching)

---

## 📚 Resources

- [Liqo Docs](https://docs.liqo.io)
- [Kind Docs](https://kind.sigs.k8s.io/)
- [Kubernetes Federation](https://kubernetes.io/docs/concepts/cluster-administration/federation/)

---

## 👨‍💻 Author

Made with ❤️ by [Mojjjak] for federating Kubernetes clusters across SLURM worker nodes.

---
