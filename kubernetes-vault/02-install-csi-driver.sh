#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Installing CSI S3 Driver ===${NC}"

# Проверяем bucket name
if [ ! -f "outputs/bucket-name.txt" ]; then
    echo -e "${RED}Error: outputs/bucket-name.txt not found!${NC}"
    exit 1
fi

BUCKET_NAME=$(cat outputs/bucket-name.txt)
echo "Using bucket: $BUCKET_NAME"

# 1. Устанавливаем CSI S3 driver
echo -e "${GREEN}Installing CSI S3 driver...${NC}"

# Клонируем репозиторий или используем kubectl apply
echo "Applying CSI driver manifests..."

# Создаем ServiceAccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: csi-s3
  namespace: kube-system
EOF

# Создаем RBAC
kubectl apply -f - <<EOF
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-s3
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "update"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "update", "patch", "create", "delete"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments/status"]
    verbs: ["patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: csi-s3
subjects:
  - kind: ServiceAccount
    name: csi-s3
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: csi-s3
  apiGroup: rbac.authorization.k8s.io
EOF

# Устанавливаем CSI driver через Helm (рекомендуемый способ)
echo -e "${GREEN}Adding Helm repository...${NC}"
helm repo add yandex https://yandex-cloud.github.io/k8s-csi-s3/charts
helm repo update

# Подготавливаем values для Helm
cat > csi-s3-values.yaml <<EOF
storageClass:
  # Создаем StorageClass отдельно
  create: false

secret:
  # Секрет создаем отдельно
  create: false

# Настройки для работы с Yandex Object Storage
kubeletPath: /var/lib/kubelet

# Ресурсы для подов
resources:
  provisioner:
    limits:
      memory: 256Mi
      cpu: 200m
    requests:
      memory: 128Mi
      cpu: 100m

  driver:
    limits:
      memory: 256Mi
      cpu: 200m
    requests:
      memory: 128Mi
      cpu: 100m
EOF

# Устанавливаем драйвер
echo -e "${GREEN}Installing CSI S3 driver via Helm...${NC}"
helm upgrade --install csi-s3 yandex/csi-s3 \
  --namespace kube-system \
  --values csi-s3-values.yaml \
  --wait

# Альтернативный вариант - установка из манифестов
# kubectl apply -k "github.com/yandex-cloud/k8s-csi-s3/deploy/kubernetes/overlays/default?ref=master"

# 2. Ждем готовности подов
echo -e "${YELLOW}Waiting for CSI driver pods...${NC}"
kubectl wait --for=condition=Ready pods -l app=csi-s3 -n kube-system --timeout=300s || true
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=csi-s3 -n kube-system --timeout=300s || true

# 3. Проверяем установку
echo -e "${GREEN}Checking CSI driver installation...${NC}"
kubectl get pods -n kube-system | grep -E "csi-s3|s3-csi"

# 4. Создаем StorageClass
echo -e "${GREEN}Creating StorageClass...${NC}"

# Обновляем storageclass.yaml с правильным bucket
cat > storageclass.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-s3
provisioner: ru.yandex.s3.csi
parameters:
  mounter: geesefs
  options: "--memory-limit 1000 --gc-interval 5"
  bucket: "${BUCKET_NAME}"
  csi.storage.k8s.io/provisioner-secret-name: csi-s3-secret
  csi.storage.k8s.io/provisioner-secret-namespace: csi
  csi.storage.k8s.io/controller-publish-secret-name: csi-s3-secret
  csi.storage.k8s.io/controller-publish-secret-namespace: csi
  csi.storage.k8s.io/node-stage-secret-name: csi-s3-secret
  csi.storage.k8s.io/node-stage-secret-namespace: csi
  csi.storage.k8s.io/node-publish-secret-name: csi-s3-secret
  csi.storage.k8s.io/node-publish-secret-namespace: csi
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

kubectl apply -f storageclass.yaml

echo -e "${GREEN}CSI S3 driver installed successfully!${NC}"
echo ""
echo "StorageClass: csi-s3"
echo "Bucket: $BUCKET_NAME"