#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Deploying Loki Stack from Yandex Cloud Marketplace ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Проверяем outputs
if [ ! -d "$BASE_DIR/outputs" ]; then
   echo -e "${RED}Error: outputs directory not found!${NC}"
   exit 1
fi

# Проверяем файлы
BUCKET_NAME=$(cat "$BASE_DIR/outputs/bucket-name.txt")
SA_KEY_FILE="$BASE_DIR/outputs/loki-s3-key.json"

if [ ! -f "$SA_KEY_FILE" ]; then
    echo -e "${RED}Error: S3 key file not found!${NC}"
    exit 1
fi

# 1. Добавляем Helm репозитории (для Prometheus если нужно)
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Создаем директорию для чартов
mkdir -p "$BASE_DIR/helm-charts"
cd "$BASE_DIR/helm-charts"

# 3. Скачиваем Loki из Yandex Marketplace
echo -e "${YELLOW}Downloading Loki chart from Yandex Cloud Marketplace...${NC}"

# Очищаем старые версии
rm -rf loki/

# Скачиваем из Yandex Marketplace
if ! helm pull oci://cr.yandex/yc-marketplace/yandex-cloud/grafana/loki/chart/loki \
  --version 1.2.0-7 \
  --untar; then
    echo -e "${RED}Failed to download Loki from Yandex Marketplace${NC}"
    echo "Please check your authentication to cr.yandex"
    exit 1
fi

echo -e "${GREEN}Successfully downloaded Loki chart${NC}"

# 4. Создаем values файл с affinity
cat > loki-stack-affinity.yaml <<'EOF'
# Размещение на infra нодах
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role
          operator: In
          values:
          - infra

tolerations:
- key: node-role
  operator: Equal
  value: infra
  effect: NoSchedule

# Для всех компонентов
loki:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-role
            operator: In
            values:
            - infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule

promtail:
  tolerations:
  - effect: NoSchedule
    operator: Exists
  - effect: NoExecute
    operator: Exists

grafana:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-role
            operator: In
            values:
            - infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule
EOF

# 5. Проверяем values.yaml чарта
if [ -f "loki/values.yaml" ]; then
    echo "Default values.yaml found in chart"
else
    echo -e "${YELLOW}Creating default values.yaml${NC}"
    cat > loki/values.yaml <<'EOF'
# Базовые настройки для Yandex Cloud
global:
  image:
    registry: cr.yandex
  dnsService: "coredns"
  clusterDomain: "cluster.local"

loki:
  auth_enabled: false

  server:
    http_listen_port: 3100
    grpc_listen_port: 9096

  storage:
    type: s3

  schema_config:
    configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: loki_index_
        period: 24h

  limits_config:
    retention_period: 720h
    enforce_metric_name: false
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20
EOF
fi

# 6. Создаем namespace
kubectl create namespace loki-stack --dry-run=client -o yaml | kubectl apply -f -

# 7. Устанавливаем Loki
echo -e "${GREEN}Installing Loki from Yandex Marketplace...${NC}"

# Устанавливаем с минимальным таймаутом для отладки
helm upgrade --install loki ./loki \
  --namespace loki-stack \
  --set global.bucketname=$BUCKET_NAME \
  --set-file global.serviceaccountawskeyvalue=$SA_KEY_FILE \
  --values loki-stack-affinity.yaml \
  --timeout 5m \
  --debug \
  --atomic=false \
  --wait=false

# 8. Проверяем статус
echo -e "${YELLOW}Checking deployment status...${NC}"
sleep 10

echo "Pods in loki-stack namespace:"
kubectl get pods -n loki-stack -o wide

echo ""
echo "Events:"
kubectl get events -n loki-stack --sort-by='.lastTimestamp' | tail -20

echo ""
echo "To check logs:"
echo "  kubectl logs -n loki-stack -l app.kubernetes.io/name=loki"
echo ""
echo "To describe problematic pods:"
echo "  kubectl describe pod -n loki-stack <pod-name>"

# 9. Ждем готовности подов
echo -e "${YELLOW}Waiting for Loki pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=loki -n loki-stack --timeout=300s || true

# 10. Проверяем что запустилось
echo -e "${GREEN}=== Current Status ===${NC}"
echo ""
echo "Loki pods:"
kubectl get pods -n loki-stack -l app.kubernetes.io/name=loki -o wide || kubectl get pods -n loki-stack | grep loki

echo ""
echo "All services:"
kubectl get svc -n loki-stack

# 11. Инструкции для доступа
echo ""
echo -e "${GREEN}=== Access Instructions ===${NC}"
echo ""
echo "1. Port-forward для доступа к Loki API:"
echo "   ${YELLOW}kubectl port-forward -n loki-stack svc/loki 3100:3100${NC}"
echo ""
echo "   Затем проверьте:"
echo "   - Статус: ${YELLOW}curl http://localhost:3100/ready${NC}"
echo "   - Метрики: ${YELLOW}curl http://localhost:3100/metrics | grep loki${NC}"
echo "   - Конфиг: ${YELLOW}curl http://localhost:3100/config${NC}"
echo ""
echo "2. Если есть Grafana:"
echo "   ${YELLOW}kubectl port-forward -n loki-stack svc/loki-grafana 3000:80${NC}"
echo "   Откройте: http://localhost:3000 (admin/admin)"
echo ""
echo "3. Проверка логов Loki:"
echo "   ${YELLOW}kubectl logs -n loki-stack -l app.kubernetes.io/name=loki --tail=50${NC}"
echo ""
echo "4. Тест отправки лога в Loki:"
echo '   curl -X POST http://localhost:3100/loki/api/v1/push \'
echo '     -H "Content-Type: application/json" \'
echo '     -d '"'"'{"streams": [{"stream": {"job": "test"}, "values": [["'"'"'$(date +%s)000000000'"'"'", "test log message"]]}]}'"'"
echo ""
echo "5. Чтение тестового лога:"
echo '   curl -G -s "http://localhost:3100/loki/api/v1/query" --data-urlencode '"'"'query={job="test"}'"'"' | jq'