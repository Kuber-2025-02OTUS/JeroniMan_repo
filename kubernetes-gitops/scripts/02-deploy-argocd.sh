#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Deploying ArgoCD (Fixed Version) ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Проверяем наличие Helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Helm not found! Installing Helm...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 1. Проверяем подключение к кластеру
echo "Checking cluster connection..."
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster!${NC}"
    echo "Please run: ./01-setup-infrastructure.sh"
    exit 1
fi

# 2. Проверяем infra ноды
echo "Checking infra nodes..."
INFRA_NODES=$(kubectl get nodes -l node-role=infra --no-headers | wc -l)
if [ "$INFRA_NODES" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No infra nodes found!${NC}"
    echo "ArgoCD will be scheduled on regular nodes."
    echo -n "Continue anyway? (y/n): "
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Exiting..."
        exit 0
    fi
fi

# 3. Очищаем предыдущие попытки установки
echo -e "${YELLOW}Cleaning up any previous ArgoCD installation...${NC}"
kubectl delete namespace argocd --ignore-not-found=true --wait=false 2>/dev/null || true

# Ждем удаления namespace
if kubectl get namespace argocd &>/dev/null; then
    echo "Waiting for namespace deletion..."
    TIMEOUT=30
    COUNTER=0
    while kubectl get namespace argocd &>/dev/null && [ $COUNTER -lt $TIMEOUT ]; do
        echo -n "."
        sleep 1
        COUNTER=$((COUNTER + 1))
    done
    echo ""
fi

# 4. Создаем исправленный values файл
echo -e "${GREEN}Creating fixed values file...${NC}"
mkdir -p "$BASE_DIR/helm-charts"

cat > "$BASE_DIR/helm-charts/values-argocd-fixed.yaml" <<'EOF'
# Fixed ArgoCD Helm values for Yandex Cloud Managed Kubernetes

# Глобальные настройки
global:
  domain: argocd.local

  # Все компоненты на infra нодах
  nodeSelector:
    node-role: infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule

# Redis - упрощенная конфигурация
redis:
  enabled: true

  # Используем стандартный Redis вместо HA версии
  architecture: standalone

  # Отключаем аутентификацию для упрощения
  auth:
    enabled: false

  master:
    nodeSelector:
      node-role: infra
    tolerations:
    - key: node-role
      operator: Equal
      value: infra
      effect: NoSchedule

    # Отключаем persistence для учебных целей
    persistence:
      enabled: false

    resources:
      limits:
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi

# Отключаем Redis HA
redis-ha:
  enabled: false

# Server
server:
  nodeSelector:
    node-role: infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule

  resources:
    limits:
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi

  # Отключаем TLS для упрощения
  extraArgs:
    - --insecure

  ingress:
    enabled: false

  config:
    url: "http://argocd-server.argocd.svc.cluster.local"

# Repo Server
repoServer:
  nodeSelector:
    node-role: infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule

  resources:
    limits:
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 256Mi

# Application Controller
controller:
  nodeSelector:
    node-role: infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule

  resources:
    limits:
      memory: 2Gi
    requests:
      cpu: 500m
      memory: 1Gi

# ApplicationSet Controller
applicationSet:
  enabled: true
  nodeSelector:
    node-role: infra
  tolerations:
  - key: node-role
    operator: Equal
    value: infra
    effect: NoSchedule

  resources:
    limits:
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Notifications Controller - отключаем
notifications:
  enabled: false

# Dex - отключаем
dex:
  enabled: false

# Параметры конфигурации
configs:
  params:
    server.insecure: true

  rbac:
    policy.default: role:readonly
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      g, argocd-admins, role:admin

# CRDs
crds:
  install: true
  keep: true
EOF

# 5. Пробуем добавить Helm репозиторий с retry
echo -e "${GREEN}Adding ArgoCD Helm repository...${NC}"

# Удаляем старый репозиторий если есть
helm repo remove argo 2>/dev/null || true

# Пробуем разные источники
REPO_ADDED=false
REPOS=(
    "https://argoproj.github.io/argo-helm"
    "https://raw.githubusercontent.com/argoproj/argo-helm/gh-pages"
)

for repo in "${REPOS[@]}"; do
    echo "Trying repository: $repo"
    if helm repo add argo "$repo" 2>/dev/null; then
        REPO_ADDED=true
        echo "Successfully added repository"
        break
    fi
done

# Если не удалось добавить репозиторий, скачиваем напрямую
if [ "$REPO_ADDED" = false ]; then
    echo -e "${YELLOW}Could not add Helm repository, downloading chart directly...${NC}"

    CHART_VERSION="7.3.3"
    CHART_URL="https://github.com/argoproj/argo-helm/releases/download/argo-cd-${CHART_VERSION}/argo-cd-${CHART_VERSION}.tgz"

    echo "Downloading ArgoCD chart version ${CHART_VERSION}..."
    if curl -L -o /tmp/argo-cd.tgz "$CHART_URL"; then
        CHART_PATH="/tmp/argo-cd.tgz"
        echo "Chart downloaded successfully"
    else
        echo -e "${RED}Failed to download chart${NC}"
        exit 1
    fi
else
    helm repo update
    CHART_PATH="argo/argo-cd"
fi

# 6. Создаем namespace
NAMESPACE="argocd"
echo "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE

# 7. Создаем Redis secret заранее
echo -e "${GREEN}Pre-creating Redis secret...${NC}"
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
kubectl create secret generic argocd-redis \
    --from-literal=redis-password="${REDIS_PASSWORD}" \
    --from-literal=auth="${REDIS_PASSWORD}" \
    --namespace=$NAMESPACE

# 8. Устанавливаем ArgoCD
echo -e "${GREEN}Installing ArgoCD...${NC}"
echo "This may take several minutes..."

helm upgrade --install argocd "$CHART_PATH" \
  --namespace $NAMESPACE \
  --values "$BASE_DIR/helm-charts/values-argocd-fixed.yaml" \
  --timeout 10m \
  --wait \
  --debug

# 9. Проверяем статус установки
echo -e "${YELLOW}Checking installation status...${NC}"
sleep 10

echo "ArgoCD pods:"
kubectl get pods -n $NAMESPACE -o wide

# 10. Ждем готовности всех подов
echo -e "${YELLOW}Waiting for all pods to be ready...${NC}"

# Ждем готовности каждого компонента отдельно (исключая Jobs)
echo "Waiting for ArgoCD Server..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=server -n $NAMESPACE --timeout=120s || true

echo "Waiting for ArgoCD Repo Server..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=repo-server -n $NAMESPACE --timeout=120s || true

echo "Waiting for ArgoCD Application Controller..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=application-controller -n $NAMESPACE --timeout=120s || true

echo "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=redis -n $NAMESPACE --timeout=120s || true

# Проверяем финальный статус
echo -e "${GREEN}Checking final pod status:${NC}"
kubectl get pods -n $NAMESPACE

# Проверяем что все основные компоненты работают
RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers | wc -l)
if [ "$RUNNING_PODS" -ge 5 ]; then
    echo -e "${GREEN}✓ All main ArgoCD components are running!${NC}"
else
    echo -e "${YELLOW}Some components might still be starting up...${NC}"
fi

# 11. Получаем начальный пароль admin
echo -e "${YELLOW}Getting initial admin password...${NC}"
ADMIN_PASSWORD=""

# Пробуем получить пароль несколько раз
for i in {1..5}; do
    ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n $NAMESPACE -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    if [ ! -z "$ADMIN_PASSWORD" ]; then
        break
    fi
    echo "Waiting for admin secret to be created... (attempt $i/5)"
    sleep 5
done

if [ -z "$ADMIN_PASSWORD" ]; then
    echo -e "${YELLOW}Initial admin secret not found. Using default password...${NC}"
    # В некоторых версиях ArgoCD начальный пароль может быть имя первого сервер-пода
    ADMIN_PASSWORD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].metadata.name}')
fi

echo -e "${GREEN}Initial admin password: $ADMIN_PASSWORD${NC}"
echo "Save this password! You'll need it to login."

# Сохраняем пароль
mkdir -p "$BASE_DIR/outputs"
echo "$ADMIN_PASSWORD" > "$BASE_DIR/outputs/argocd-admin-password.txt"
echo "Password saved to: $BASE_DIR/outputs/argocd-admin-password.txt"

# 12. Проверяем сервисы
echo ""
echo "ArgoCD services:"
kubectl get svc -n $NAMESPACE

# 13. Финальная проверка
echo ""
echo -e "${GREEN}=== ArgoCD Installation Complete! ===${NC}"
echo ""
echo "Installation summary:"
echo "- Namespace: $NAMESPACE"
echo "- Redis: Standalone mode without authentication"
echo "- Server: Running in insecure mode (no internal TLS)"
echo "- All components scheduled on infra nodes"
echo ""
echo "Access instructions:"
echo ""
echo "1. Port-forward to access ArgoCD UI:"
echo "   ${YELLOW}kubectl port-forward -n $NAMESPACE svc/argocd-server 8080:80${NC}"
echo ""
echo "2. Open in browser:"
echo "   ${YELLOW}http://localhost:8080${NC}"
echo ""
echo "3. Login credentials:"
echo "   Username: ${GREEN}admin${NC}"
echo "   Password: ${GREEN}$ADMIN_PASSWORD${NC}"
echo ""
echo "4. Check pod status:"
echo "   ${YELLOW}kubectl get pods -n argocd -w${NC}"
echo ""
echo "5. If any pods are not running, check logs:"
echo "   ${YELLOW}kubectl logs -n argocd <pod-name>${NC}"
echo ""
echo "Next step: Run ${GREEN}./03-configure-argocd.sh${NC} to create Project and Applications"

# Cleanup временных файлов
rm -f /tmp/argo-cd.tgz 2>/dev/null || true