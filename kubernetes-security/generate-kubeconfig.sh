#!/bin/bash

# Имя ServiceAccount
SA_NAME="cd"
NAMESPACE="homework"

# Получаем имя секрета ServiceAccount
SECRET_NAME=$(kubectl get sa $SA_NAME -n $NAMESPACE -o jsonpath='{.secrets[0].name}')

# Если секрета нет (в новых версиях K8s), создаем его вручную
if [ -z "$SECRET_NAME" ]; then
    echo "Creating secret for ServiceAccount..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_NAME}-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF
    SECRET_NAME="${SA_NAME}-token"
    sleep 2
fi

# Получаем данные из секрета
CA_CERT=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)

# Получаем текущий контекст кластера
CURRENT_CONTEXT=$(kubectl config current-context)
CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$CURRENT_CONTEXT')].context.cluster}")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CLUSTER_NAME')].cluster.server}")

# Создаем kubeconfig
cat > kubeconfig-cd.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${SA_NAME}
  name: ${SA_NAME}-context
current-context: ${SA_NAME}-context
users:
- name: ${SA_NAME}
  user:
    token: ${TOKEN}
EOF

echo "Kubeconfig saved to kubeconfig-cd.yaml"
echo "Test it with: KUBECONFIG=./kubeconfig-cd.yaml kubectl get pods"