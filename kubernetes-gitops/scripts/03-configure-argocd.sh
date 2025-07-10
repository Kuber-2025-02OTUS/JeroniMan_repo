#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Configuring ArgoCD Project and Applications ===${NC}"

# Определяем базовую директорию
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Проверяем, что ArgoCD установлен
echo "Checking ArgoCD installation..."
if ! kubectl get deployment -n argocd argocd-server &>/dev/null; then
    echo -e "${RED}Error: ArgoCD not found!${NC}"
    echo "Please run: ./04-deploy-argocd.sh"
    exit 1
fi

# Ждем готовности ArgoCD
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Проверяем наличие манифестов
MANIFESTS_DIR="$BASE_DIR/manifests/argocd"
if [ ! -d "$MANIFESTS_DIR" ]; then
    echo -e "${RED}Error: ArgoCD manifests directory not found!${NC}"
    echo "Expected at: $MANIFESTS_DIR"
    exit 1
fi

# Спрашиваем URL репозитория
echo -e "${YELLOW}Enter your GitHub repository URL:${NC}"
echo "Example: https://github.com/username/otus_kuber-homeworks"
read -p "Repository URL: " REPO_URL

if [ -z "$REPO_URL" ]; then
    echo -e "${RED}Repository URL cannot be empty!${NC}"
    exit 1
fi

# Обновляем манифесты с правильным URL репозитория
echo "Updating manifests with your repository URL..."
sed -i.bak "s|https://github.com/YOUR_USERNAME/.*|$REPO_URL|g" "$MANIFESTS_DIR"/*.yaml
sed -i.bak "s|https://github.com/\*/otus_kuber-homeworks\*|$REPO_URL|g" "$MANIFESTS_DIR"/*.yaml

# 1. Создаем Project Otus
echo -e "${GREEN}Creating ArgoCD Project 'otus'...${NC}"
kubectl apply -f "$MANIFESTS_DIR/project-otus.yaml"

# Проверяем создание проекта
sleep 5
if kubectl get appproject otus -n argocd &>/dev/null; then
    echo -e "${GREEN}✓ Project 'otus' created successfully${NC}"
else
    echo -e "${RED}✗ Failed to create project 'otus'${NC}"
fi

# 2. Создаем Application для kubernetes-networks
echo -e "${GREEN}Creating Application 'kubernetes-networks'...${NC}"
kubectl apply -f "$MANIFESTS_DIR/app-kubernetes-networks.yaml"

# 3. Создаем Application для kubernetes-templating
echo -e "${GREEN}Creating Application 'kubernetes-templating'...${NC}"
kubectl apply -f "$MANIFESTS_DIR/app-kubernetes-templating.yaml"

# 4. Проверяем созданные ресурсы
echo -e "${YELLOW}Checking created resources...${NC}"
sleep 5

echo ""
echo "Projects:"
kubectl get appproject -n argocd

echo ""
echo "Applications:"
kubectl get applications -n argocd

# 5. Детальная информация
echo ""
echo -e "${GREEN}=== Configuration Complete! ===${NC}"
echo ""
echo "Project 'otus' details:"
kubectl get appproject otus -n argocd -o yaml | grep -A5 "spec:"

echo ""
echo "To check application status:"
echo "  ${YELLOW}kubectl get app -n argocd${NC}"
echo ""
echo "To sync kubernetes-networks manually:"
echo "  ${YELLOW}kubectl patch app kubernetes-networks -n argocd --type merge -p '{\"operation\": {\"initiatedBy\": {\"username\": \"admin\"}, \"sync\": {\"revision\": \"HEAD\"}}}'${NC}"
echo "  or"
echo "  ${YELLOW}argocd app sync kubernetes-networks${NC}"
echo ""
echo "To check application details:"
echo "  ${YELLOW}kubectl describe app kubernetes-networks -n argocd${NC}"
echo "  ${YELLOW}kubectl describe app kubernetes-templating -n argocd${NC}"
echo ""
echo "To access ArgoCD UI:"
echo "  ${YELLOW}kubectl port-forward -n argocd svc/argocd-server 8080:80${NC}"
echo "  Open: http://localhost:8080"
echo ""
echo "Applications will appear in ArgoCD UI under Project 'otus'"
echo ""
echo -e "${YELLOW}Note: kubernetes-networks requires manual sync${NC}"
echo -e "${YELLOW}Note: kubernetes-templating will sync automatically${NC}"