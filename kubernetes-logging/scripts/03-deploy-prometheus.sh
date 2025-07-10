#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Deploying kube-prometheus-stack ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Проверяем наличие Helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Helm not found! Please install Helm first.${NC}"
    echo "Run: ./install-helm.sh"
    exit 1
fi

# 1. Проверяем, что Loki установлен
echo "Checking Loki installation..."
if ! kubectl get svc -n loki-stack loki-loki-distributed-gateway &>/dev/null; then
    echo -e "${YELLOW}Warning: Loki gateway service not found.${NC}"
    echo "Grafana datasource for Loki might not work correctly."
    echo -n "Continue anyway? (y/n): "
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Exiting..."
        exit 0
    fi
fi

# 2. Добавляем Helm репозиторий
echo "Adding prometheus-community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. Создаем namespace для Prometheus (или используем loki-stack)
echo -e "${YELLOW}Where to install kube-prometheus-stack?${NC}"
echo "1) In loki-stack namespace (together with Loki)"
echo "2) In separate monitoring namespace"
echo -n "Enter choice [1-2]: "
read -r choice

case $choice in
    1)
        NAMESPACE="loki-stack"
        echo "Using existing namespace: $NAMESPACE"
        ;;
    2)
        NAMESPACE="monitoring"
        echo "Creating namespace: $NAMESPACE"
        kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
        ;;
    *)
        echo "Invalid choice. Using loki-stack namespace."
        NAMESPACE="loki-stack"
        ;;
esac

# 4. Проверяем values файл
VALUES_FILE="$BASE_DIR/helm-charts/prometheus-values.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    echo -e "${RED}Values file not found: $VALUES_FILE${NC}"
    echo "Creating default values file..."
    mkdir -p "$BASE_DIR/helm-charts"

    # Создаем минимальный values файл
    cat > "$VALUES_FILE" <<'EOF'
# Minimal configuration for kube-prometheus-stack
prometheus:
  prometheusSpec:
    nodeSelector:
      node-role: infra
    tolerations:
    - key: node-role
      operator: Equal
      value: infra
      effect: NoSchedule

grafana:
  enabled: true
  adminPassword: prom-operator

alertmanager:
  alertmanagerSpec:
    nodeSelector:
      node-role: infra
    tolerations:
    - key: node-role
      operator: Equal
      value: infra
      effect: NoSchedule

# Disable components that don't work in Managed K8s
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
EOF
fi

# 5. Устанавливаем kube-prometheus-stack
echo -e "${GREEN}Installing kube-prometheus-stack...${NC}"
echo "This may take several minutes..."

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace $NAMESPACE \
  --values "$VALUES_FILE" \
  --timeout 10m \
  --wait

# 6. Проверяем статус установки
echo -e "${YELLOW}Checking installation status...${NC}"
sleep 10

echo "Prometheus pods:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=prometheus -o wide

echo ""
echo "Grafana pods:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=grafana -o wide

echo ""
echo "AlertManager pods:"
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=alertmanager -o wide

echo ""
echo "All services:"
kubectl get svc -n $NAMESPACE | grep -E "(prometheus|grafana|alertmanager)"

# 7. Создаем ServiceMonitor для Loki (если в разных namespace)
if [ "$NAMESPACE" != "loki-stack" ]; then
    echo -e "${YELLOW}Creating ServiceMonitor for Loki...${NC}"

    kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: loki-metrics
  namespace: $NAMESPACE
  labels:
    app: loki
spec:
  namespaceSelector:
    matchNames:
    - loki-stack
  selector:
    matchLabels:
      app.kubernetes.io/name: loki
  endpoints:
  - port: http-metrics
    interval: 30s
    path: /metrics
EOF
fi

# 8. Инструкции для доступа
echo ""
echo -e "${GREEN}=== Installation Complete! ===${NC}"
echo ""
echo "Access instructions:"
echo ""
echo "1. Prometheus UI:"
echo "   ${YELLOW}kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090${NC}"
echo "   URL: http://localhost:9090"
echo ""
echo "2. Grafana UI:"
echo "   ${YELLOW}kubectl port-forward -n $NAMESPACE svc/prometheus-grafana 3000:80${NC}"
echo "   URL: http://localhost:3000"
echo "   Login: admin / prom-operator"
echo ""
echo "3. AlertManager UI:"
echo "   ${YELLOW}kubectl port-forward -n $NAMESPACE svc/prometheus-kube-prometheus-alertmanager 9093:9093${NC}"
echo "   URL: http://localhost:9093"
echo ""
echo "Useful Grafana dashboards:"
echo "- Kubernetes / Compute Resources / Cluster"
echo "- Kubernetes / Compute Resources / Namespace (Pods)"
echo "- Node Exporter / Nodes"
echo ""
echo "To add Loki datasource in Grafana manually:"
echo "1. Go to Configuration -> Data Sources"
echo "2. Add data source -> Loki"
echo "3. URL: http://loki-loki-distributed-gateway.loki-stack.svc.cluster.local"
echo ""
echo "Check logs:"
echo "  ${YELLOW}kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=prometheus-operator${NC}"
echo "  ${YELLOW}kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=prometheus${NC}"