#!/bin/bash

echo "=== Cleaning up Kubernetes Logging resources ==="

# Читаем имя бакета
BUCKET_NAME=$(cat ../outputs/bucket-name.txt 2>/dev/null)

# 1. Удаляем Kubernetes ресурсы
echo "Deleting Kubernetes resources..."
kubectl delete namespace loki-stack --ignore-not-found=true

# 2. Получаем ID кластера для удаления node groups
CLUSTER_ID=$(yc managed-kubernetes cluster get --name k8s-logging-cluster --format json 2>/dev/null | jq -r .id)

# 3. Удаляем node groups
if [ ! -z "$CLUSTER_ID" ] && [ "$CLUSTER_ID" != "null" ]; then
    echo "Deleting node groups..."
    # Получаем список node groups для этого кластера
    NODE_GROUPS=$(yc managed-kubernetes node-group list --folder-id $YC_FOLDER_ID --format json | \
                  jq -r --arg cluster_id "$CLUSTER_ID" '.[] | select(.cluster_id == $cluster_id) | .name')

    for ng in $NODE_GROUPS; do
        echo "Deleting node group: $ng"
        yc managed-kubernetes node-group delete --name $ng --async 2>/dev/null || true
    done
fi

# 4. Ждем удаления node groups
echo "Waiting for node groups deletion..."
sleep 60

# 5. Удаляем кластер
echo "Deleting cluster..."
yc managed-kubernetes cluster delete --name k8s-logging-cluster 2>/dev/null || true

# 6. Удаляем подсеть (только нашу)
echo "Deleting subnet..."
yc vpc subnet delete --name k8s-logging-subnet 2>/dev/null || true

# 7. Удаляем сеть только если она наша
NETWORK_NAME=$(yc vpc network list --format json | jq -r '.[] | select(.name == "k8s-logging-network") | .name')
if [ ! -z "$NETWORK_NAME" ]; then
    echo "Deleting network..."
    yc vpc network delete --name k8s-logging-network 2>/dev/null || true
fi

# 8. Удаляем S3 бакет
if [ ! -z "$BUCKET_NAME" ]; then
    echo "Deleting S3 bucket: $BUCKET_NAME"
    yc storage bucket delete --name $BUCKET_NAME 2>/dev/null || true
fi

# 9. Удаляем Container Registry (опционально)
read -p "Delete Container Registry? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    REGISTRY_ID=$(yc container registry list --format json | jq -r '.[] | select(.name == "k8s-logging-registry") | .id')
    if [ ! -z "$REGISTRY_ID" ]; then
        yc container registry delete --id $REGISTRY_ID
    fi
fi

# 10. Удаляем сервисные аккаунты
echo "Deleting service accounts..."
yc iam service-account delete --name k8s-cluster-sa 2>/dev/null || true
yc iam service-account delete --name loki-s3-sa 2>/dev/null || true

echo "Cleanup completed!"