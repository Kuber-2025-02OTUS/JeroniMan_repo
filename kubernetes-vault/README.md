# Kubernetes CSI S3 - Домашнее задание

## Описание

В этом домашнем задании настроена интеграция Kubernetes с Yandex Object Storage через CSI драйвер, позволяющая использовать S3 bucket как persistent storage для подов.

## Архитектура решения

- **Kubernetes cluster**: Managed K8s в Yandex Cloud
- **S3 bucket**: Yandex Object Storage для хранения данных
- **CSI driver**: Драйвер для монтирования S3 как файловой системы
- **StorageClass**: Класс хранилища с автоматическим provisioning
- **Test workload**: Deployment и Pod для проверки работы

## Структура файлов

```
kubernetes-csi/
├── README.md                    # Этот файл
├── 00-create-infrastructure.sh  # Создание инфраструктуры
├── 01-create-s3-secret.sh      # Создание секрета с ключами S3
├── 02-install-csi-driver.sh    # Установка CSI драйвера
├── 03-deploy-test-workload.sh  # Деплой тестового приложения
├── 04-verify-s3-storage.sh     # Проверка работы
├── s3-secret.yaml              # Secret с ключами доступа к S3
├── storageclass.yaml           # StorageClass для CSI S3
├── pvc.yaml                    # PersistentVolumeClaim
├── test-deployment.yaml        # Тестовые Deployment и Pod
├── csi-s3-values.yaml         # Values для Helm chart CSI драйвера
└── outputs/                    # Директория с выходными данными
    ├── s3-access-key.json     # Ключи доступа к S3
    └── bucket-name.txt        # Имя созданного bucket
```

## Компоненты

### 1. Service Account для S3
- **Имя**: `k8s-csi-s3-sa`
- **Роль**: `storage.editor` для доступа к Object Storage
- **Ключи**: Сохранены в `outputs/s3-access-key.json`

### 2. S3 Bucket
- **Имя**: Генерируется автоматически с timestamp
- **Размер**: До 10GB
- **Storage class**: standard

### 3. Secret для доступа к S3
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: csi-s3-secret
  namespace: csi
stringData:
  accessKeyID: <key-id>
  secretAccessKey: <secret-key>
  endpoint: https://storage.yandexcloud.net
  region: ru-central1
```

### 4. StorageClass
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-s3
provisioner: ru.yandex.s3.csi
parameters:
  mounter: geesefs
  bucket: <bucket-name>
  # Ссылки на secret для разных операций
```

### 5. PVC
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: csi-s3-pvc
  namespace: csi
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: csi-s3
```

## Установка

### Предварительные требования
- Yandex Cloud CLI (`yc`)
- `kubectl`
- `helm`
- `jq`

### Шаги установки

```bash
# 1. Установка переменных окружения
export YC_CLOUD_ID=<your-cloud-id>
export YC_FOLDER_ID=<your-folder-id>
export YC_ZONE=ru-central1-a

# 2. Создание инфраструктуры
chmod +x *.sh
./00-create-infrastructure.sh

# 3. Создание секрета для S3
./01-create-s3-secret.sh

# 4. Установка CSI драйвера
./02-install-csi-driver.sh

# 5. Деплой тестового приложения
./03-deploy-test-workload.sh

# 6. Проверка работы
./04-verify-s3-storage.sh
```

## Проверка работоспособности

### 1. Проверка компонентов
```bash
# CSI драйвер
kubectl get pods -n kube-system | grep csi-s3

# StorageClass
kubectl get storageclass csi-s3

# PVC и PV
kubectl get pvc -n csi
kubectl get pv

# Тестовые поды
kubectl get pods -n csi
```

### 2. Проверка монтирования
```bash
# Список файлов в примонтированной директории
kubectl exec -n csi csi-s3-test-pod -- ls -la /data/

# Создание тестового файла
kubectl exec -n csi csi-s3-test-pod -- sh -c "echo 'Test data' > /data/test.txt"

# Чтение файла
kubectl exec -n csi csi-s3-test-pod -- cat /data/test.txt
```

### 3. Проверка в S3
```bash
# Через YC CLI
BUCKET=$(cat outputs/bucket-name.txt)
yc storage s3api list-objects --bucket $BUCKET

# Через веб-консоль
# https://console.cloud.yandex.ru/folders/<folder-id>/storage/buckets/<bucket-name>
```

### 4. Проверка логов deployment
```bash
# Логи тестового deployment (пишет файлы каждые 30 секунд)
kubectl logs -n csi -l app=csi-s3-test -f
```

## Как это работает

1. **CSI драйвер** устанавливается как DaemonSet и обеспечивает интерфейс между Kubernetes и S3
2. **StorageClass** определяет параметры для динамического создания томов
3. При создании **PVC** автоматически создается **PV** и выделяется префикс в S3 bucket
4. **Pod** монтирует S3 как обычную файловую систему через FUSE (geesefs)
5. Все файлы, записанные в примонтированную директорию, сохраняются в S3

## Особенности реализации

1. **Mounter**: Используется `geesefs` - быстрая FUSE реализация для S3
2. **Access Mode**: `ReadWriteMany` - несколько подов могут одновременно работать с одним томом
3. **Namespace**: Все ресурсы создаются в namespace `csi`
4. **Auto-provisioning**: PV создается автоматически при создании PVC

## Troubleshooting

### PVC застрял в состоянии Pending
```bash
kubectl describe pvc csi-s3-pvc -n csi
kubectl logs -n kube-system -l app=csi-s3-provisioner
```

### Pod не может примонтировать том
```bash
kubectl describe pod <pod-name> -n csi
kubectl logs -n kube-system -l app=csi-s3-driver
```

### Проверка секрета
```bash
kubectl get secret csi-s3-secret -n csi -o yaml
```

## Очистка ресурсов

```bash
# Удаление тестовых ресурсов
kubectl delete -f test-deployment.yaml
kubectl delete -f pvc.yaml
kubectl delete -f storageclass.yaml
kubectl delete secret csi-s3-secret -n csi

# Удаление CSI драйвера
helm uninstall csi-s3 -n kube-system

# Удаление namespace
kubectl delete namespace csi

# Удаление инфраструктуры (опционально)
yc managed-kubernetes cluster delete --name k8s-csi-cluster
yc storage bucket delete --name $(cat outputs/bucket-name.txt)
```

## Результаты

1. ✅ Создан S3 bucket в Yandex Object Storage
2. ✅ Создан ServiceAccount с необходимыми правами
3. ✅ Создан Secret с ключами доступа
4. ✅ Установлен CSI S3 драйвер
5. ✅ Создан StorageClass с автоматическим provisioning
6. ✅ Создан PVC использующий StorageClass
7. ✅ Развернут Pod/Deployment с примонтированным S3
8. ✅ Файлы успешно сохраняются в Object Storage