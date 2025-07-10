#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Setting up Infrastructure ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUTS_DIR="$BASE_DIR/outputs"

# 1. Проверяем кластер
echo "Checking cluster..."
if ! yc managed-kubernetes cluster get --name k8s-logging-cluster &>/dev/null; then
    echo -e "${RED}Error: Cluster k8s-logging-cluster not found!${NC}"
    echo "Please run ./00-create-infrastructure.sh first"
    exit 1
fi

CLUSTER_ID=$(yc managed-kubernetes cluster get --name k8s-logging-cluster --format json | jq -r .id)
echo "Cluster ID: $CLUSTER_ID"

# 2. Получаем kubeconfig
echo "Getting kubeconfig..."
yc managed-kubernetes cluster get-credentials \
  --id $CLUSTER_ID \
  --external \
  --force

# 3. Проверяем подключение к кластеру
echo "Checking cluster connection..."
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster!${NC}"
    exit 1
fi

# 4. Ждем готовности всех нод
echo -e "${YELLOW}Waiting for all nodes to be ready...${NC}"
EXPECTED_NODES=2  # workload-pool + infra-pool

while true; do
    READY_NODES=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
    echo "Ready nodes: $READY_NODES/$EXPECTED_NODES"

    if [ "$READY_NODES" -eq "$EXPECTED_NODES" ]; then
        echo -e "${GREEN}All nodes are ready!${NC}"
        break
    fi

    echo "Waiting for nodes to be ready..."
    sleep 10
done

# 5. Проверяем ноды
echo -e "${YELLOW}Checking nodes...${NC}"
kubectl get nodes -o wide

# 6. Проверяем taints на infra ноде
echo -e "${YELLOW}Checking infra node taints...${NC}"
INFRA_NODE=$(kubectl get nodes -l node-role=infra -o jsonpath='{.items[0].metadata.name}')
if [ -z "$INFRA_NODE" ]; then
    echo -e "${RED}Warning: No infra node found!${NC}"
else
    echo "Infra node: $INFRA_NODE"
    kubectl describe node $INFRA_NODE | grep -A5 "Taints:" || echo "No taints section found"
fi

# 7. Сохраняем информацию о нодах
echo "Saving node information..."
mkdir -p "$OUTPUTS_DIR"

kubectl get node -o wide --show-labels > "$OUTPUTS_DIR/nodes-with-labels.txt"
echo "Node labels saved to: $OUTPUTS_DIR/nodes-with-labels.txt"

kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints > "$OUTPUTS_DIR/nodes-with-taints.txt"
echo "Node taints saved to: $OUTPUTS_DIR/nodes-with-taints.txt"

# 8. Показываем сводку
echo ""
echo -e "${GREEN}=== Infrastructure Summary ===${NC}"
echo "Cluster: k8s-logging-cluster"
echo "Nodes:"
kubectl get nodes --no-headers | while read line; do
    echo "  - $line"
done

echo ""
echo "Node roles:"
echo "  Workload nodes: $(kubectl get nodes -l '!node-role' --no-headers | wc -l)"
echo "  Infra nodes: $(kubectl get nodes -l node-role=infra --no-headers | wc -l)"

echo ""
echo -e "${GREEN}Infrastructure ready!${NC}"
echo ""
echo "Output files in: $OUTPUTS_DIR"
ls -la "$OUTPUTS_DIR/"*.txt

echo ""
echo "Next step: ./02-deploy-argocd.sh"