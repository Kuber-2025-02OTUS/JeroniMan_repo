# Kubernetes Vault - Домашнее задание

## Описание

В этом домашнем задании настроена интеграция HashiCorp Vault с Kubernetes для безопасного управления секретами с использованием External Secrets Operator.

## Архитектура решения

- **Consul**: 3 реплики для обеспечения HA режима и хранения данных Vault
- **Vault**: 3 реплики в HA режиме с Consul backend
- **External Secrets Operator**: для синхронизации секретов из Vault в Kubernetes
- **Kubernetes Auth**: метод аутентификации для подключения ESO к Vault

## Структура файлов

```
kubernetes-vault/
├── README.md                           # Этот файл
├── 00-create-infrastructure.sh         # Создание кластера в Yandex Cloud
├── 01-install-consul.sh               # Установка Consul
├── 02-install-vault.sh                # Установка Vault
├── 03-init-vault.sh                   # Инициализация Vault
├── 04-configure-k8s-auth.sh           # Настройка Kubernetes auth
├── 05-install-external-secrets.sh     # Установка ESO
├── 06-create-external-secrets.sh      # Создание SecretStore и ExternalSecret
├── 07-verify-setup.sh                 # Проверка работы
├── consul-values.yaml                 # Values для Consul
├── vault-values.yaml                  # Values для Vault  
├── external-secrets-values.yaml       # Values для ESO
├── vault-auth-serviceaccount.yaml     # ServiceAccount и RBAC
├── otus-policy.hcl                    # Политика Vault
├── vault-secretstore.yaml             # SecretStore манифест
└── external-secret.yaml               # ExternalSecret манифест
```

## Быстрый старт

### Предварительные требования

- Yandex Cloud CLI (`yc`)
- `kubectl`
- `helm`
- `jq`

### Установка

```bash
# Установите переменные окружения
export YC_CLOUD_ID=<your-cloud-id>
export YC_FOLDER_ID=<your-folder-id>
export YC_ZONE=ru-central1-a

# Запустите скрипты по порядку
chmod +x *.sh
./00-create-infrastructure.sh
./01-install-consul.sh
./02-install-vault.sh
./03-init-vault.sh
./04-configure-k8s-auth.sh
./05-install-external-secrets.sh
./06-create-external-secrets.sh
./07-verify-setup.sh
```

## Команды установки

### Consul
```bash
helm upgrade --install consul hashicorp/consul \
  --namespace consul \
  --values consul-values.yaml \
  --version 1.3.1 \
  --wait
```

### Vault
```bash
helm upgrade --install vault hashicorp/vault \
  --namespace vault \
  --values vault-values.yaml \
  --version 0.27.0 \
  --wait
```

### External Secrets Operator
```bash
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace vault \
  --values external-secrets-values.yaml \
  --version 0.9.11 \
  --wait
```

## Проверка работы

### 1. Проверка Consul
```bash
kubectl exec -n consul consul-server-0 -- consul members
```

### 2. Проверка Vault
```bash
kubectl exec -n vault vault-0 -- vault status
```

### 3. Проверка секрета
```bash
# Секрет в Vault
kubectl exec -n vault vault-0 -- vault kv get otus/cred

# Синхронизированный Secret в Kubernetes
kubectl get secret otus-cred -n vault -o yaml
```

### 4. Доступ к UI

#### Consul UI
```bash
kubectl port-forward -n consul svc/consul-ui 8500:80
# http://localhost:8500
```

#### Vault UI
```bash
kubectl port-forward -n vault svc/vault 8200:8200
# http://localhost:8200
# Используйте root token из vault-init-keys.json
```

## Компоненты решения

### ServiceAccount и RBAC
- **ServiceAccount**: `vault-auth` в namespace `vault`
- **ClusterRoleBinding**: связывает SA с ролью `system:auth-delegator`

### Vault Policy (otus-policy.hcl)
```hcl
path "otus/data/cred" {
  capabilities = ["read", "list"]
}
path "otus/metadata/cred" {
  capabilities = ["read", "list"]
}
```

### SecretStore
- Подключается к Vault через Kubernetes auth
- Использует ServiceAccount `vault-auth`
- Настроен на работу с KV v2 секретами

### ExternalSecret
- Создает Secret `otus-cred` в namespace `vault`
- Синхронизирует поля `username` и `password` из Vault
- Обновляется каждые 15 секунд

## Важные замечания

1. **Безопасность**: Файл `vault-init-keys.json` содержит unseal ключи и root token. НЕ коммитьте его в git!

2. **HA режим**: Все компоненты развернуты в HA режиме для обеспечения отказоустойчивости

3. **Namespace**: Все компоненты установлены в соответствующие namespace:
   - Consul: `consul`
   - Vault и ESO: `vault`

4. **Обновление секретов**: При изменении секрета в Vault, он автоматически обновляется в Kubernetes через ESO

## Troubleshooting

### SecretStore не подключается к Vault
```bash
kubectl describe secretstore vault-backend -n vault
kubectl logs -n vault -l app.kubernetes.io/name=external-secrets
```

### ExternalSecret не синхронизируется
```bash
kubectl describe externalsecret otus-cred -n vault
```

### Vault sealed
```bash
# Используйте unseal ключи из vault-init-keys.json
kubectl exec -n vault vault-0 -- vault operator unseal <key>
```

## Очистка ресурсов

```bash
# Удаление приложений
helm uninstall external-secrets -n vault
helm uninstall vault -n vault
helm uninstall consul -n consul

# Удаление namespaces
kubectl delete namespace vault consul

# Удаление кластера
yc managed-kubernetes cluster delete --name k8s-vault-cluster
```

## Результаты ДЗ

К результатам ДЗ прилагаются:
1. Команды установки helm чартов (см. выше)
2. Values файлы: `consul-values.yaml`, `vault-values.yaml`, `external-secrets-values.yaml`
3. Манифесты: `vault-auth-serviceaccount.yaml`, `vault-secretstore.yaml`, `external-secret.yaml`
4. Политика Vault: `otus-policy.hcl`
5. Скриншоты работающей системы (при необходимости)