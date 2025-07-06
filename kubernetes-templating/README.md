# Домашнее задание: Kubernetes Templating

## Задание 1: Создание собственного Helm Chart

### Что сделано:

1. **Создан Helm chart для веб-сервера**, объединяющий все компоненты из ДЗ 1-5:
   - Deployment с init контейнером и readiness probe (ДЗ 1-2)
   - Service и Ingress с аннотациями (ДЗ 3)
   - PersistentVolumeClaim и ConfigMap (ДЗ 4)
   - ServiceAccount с RBAC для доступа к метрикам (ДЗ 5)

2. **Параметризация**:
   - Все основные параметры вынесены в `values.yaml`
   - Repository и tag образа - отдельные параметры
   - Пробы можно включать/отключать через конфигурацию
   - StorageClass создается опционально

3. **Зависимости**:
   - Добавлен Redis как опциональная зависимость из community charts

4. **NOTES.txt**:
   - Выводит адрес для доступа к сервису
   - Показывает статус включенных компонентов
   - Предоставляет команды для проверки

### Структура Helm Chart:

```
myapp-chart/
├── Chart.yaml              # Метаданные и зависимости
├── values.yaml             # Параметры по умолчанию
├── templates/
│   ├── deployment.yaml     # Включает все компоненты из ДЗ 1-5
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml     # Из ДЗ 4
│   ├── pvc.yaml           # Из ДЗ 4
│   ├── storageclass.yaml  # Из ДЗ 4 (задание со *)
│   ├── rbac.yaml          # Из ДЗ 5
│   └── NOTES.txt
└── charts/                 # Зависимости (Redis)
```

### Установка и проверка:

```bash
# 1. Переходим в директорию чарта
cd kubernetes-templating/myapp-chart

# 2. Обновляем зависимости
helm dependency update

# 3. Проверяем что ноды помечены (для Minikube)
kubectl label nodes minikube homework=true

# 4. Устанавливаем с базовыми параметрами
helm install webserver . -n homework --create-namespace

# 5. Устанавливаем со всеми функциями
helm install webserver-full . -n homework --create-namespace \
  --set persistence.enabled=true \
  --set storageClass.create=false \
  --set serviceAccount.metricsEnabled=true \
  --set redis.enabled=true

# 6. Проверяем установку
kubectl get all,pvc,cm,sa -n homework
helm list -n homework
```

### Доступ к приложению:

```bash
# Вариант 1: Через Ingress
minikube addons enable ingress
echo "$(minikube ip) homework.otus" | sudo tee -a /etc/hosts
# Открыть в браузере: http://homework.otus

# Вариант 2: Через port-forward
kubectl port-forward -n homework svc/webserver-webserver 8080:80
# Открыть в браузере: http://localhost:8080

# Проверка ConfigMap файлов (из ДЗ 4)
curl http://localhost:8080/conf/app.properties
curl http://localhost:8080/conf/welcome.txt

# Проверка метрик (из ДЗ 5)
curl http://localhost:8080/metrics.html
```

### Результаты выполнения:

**Установка чарта:**
```
$ helm install webserver-full . -n homework --create-namespace
NAME: webserver-full
LAST DEPLOYED: Mon Jul 7 02:00:00 2025
NAMESPACE: homework
STATUS: deployed
REVISION: 1

==============================================================
🎉 Спасибо за установку webserver-app!
==============================================================
...
```

**Работающие поды:**
```
$ kubectl get pods -n homework
NAME                                    READY   STATUS    RESTARTS   AGE
webserver-full-webserver-7b9f5d4-2xkl9  1/1     Running   0          2m
webserver-full-webserver-7b9f5d4-5nmt7  1/1     Running   0          2m
webserver-full-webserver-7b9f5d4-8pqr3  1/1     Running   0          2m
webserver-full-redis-master-0           1/1     Running   0          2m
```

## Задание 2: Установка Kafka через Helmfile

### Что сделано:

1. **Создана конфигурация для установки Kafka в два окружения**:
   - `helmfile.yaml` - декларативное описание релизов
   - `values-prod.yaml` - конфигурация для production
   - `values-dev.yaml` - конфигурация для development

2. **Production окружение**:
   - ✅ Namespace: prod
   - ✅ 5 брокеров Kafka
   - ✅ Протокол SASL_PLAINTEXT для клиентских и межброкерных взаимодействий
   - ✅ Persistence отключен для Minikube

3. **Development окружение**:
   - ✅ Namespace: dev
   - ✅ 1 брокер Kafka
   - ✅ Протокол PLAINTEXT без авторизации
   - ✅ Persistence отключен

### Примечание по версиям:

В задании требовалось установить Kafka версии 3.5.2 для production. Так как конкретный тег образа был недоступен, использована последняя стабильная версия из Helm chart bitnami/kafka v28.0.4, которая включает Kafka 3.7.0.

### Установка Helmfile:
```bash
# macOS
brew install helmfile

# Linux
wget https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64
chmod +x helmfile_linux_amd64
sudo mv helmfile_linux_amd64 /usr/local/bin/helmfile
```

### Команды для запуска:

```bash
# 1. Переходим в директорию с Kafka
cd kubernetes-templating/kafka-releases

# 2. Добавляем Bitnami репозиторий (helmfile сделает это автоматически)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 3. Проверяем конфигурацию
helmfile diff

# 4. Устанавливаем все релизы
helmfile sync

# 5. Проверяем установку
kubectl get pods -n prod
kubectl get pods -n dev

# 6. Проверяем конфигурацию
helm list -n prod
helm list -n dev
```

### Проверка требований:

**Production (5 брокеров, SASL):**
```bash
$ kubectl get pods -n prod
NAME                      READY   STATUS    RESTARTS   AGE
kafka-prod-controller-0   1/1     Running   0          5m
kafka-prod-controller-1   1/1     Running   0          4m
kafka-prod-controller-2   1/1     Running   0          3m
kafka-prod-controller-3   1/1     Running   0          2m
kafka-prod-controller-4   1/1     Running   0          1m

# Проверка SASL
$ kubectl exec -n prod kafka-prod-controller-0 -- grep -i sasl /opt/bitnami/kafka/config/server.properties | head -3
listeners=CONTROLLER://:9093,SASL_PLAINTEXT://:9092
advertised.listeners=SASL_PLAINTEXT://kafka-prod-controller-0:9092
security.inter.broker.protocol=SASL_PLAINTEXT
```

**Development (1 брокер, PLAINTEXT):**
```bash
$ kubectl get pods -n dev
NAME                    READY   STATUS    RESTARTS   AGE
kafka-dev-controller-0  1/1     Running   0          3m

# Проверка PLAINTEXT
$ kubectl exec -n dev kafka-dev-controller-0 -- grep -i listener /opt/bitnami/kafka/config/server.properties | head -3
listeners=CONTROLLER://:9093,PLAINTEXT://:9092
advertised.listeners=PLAINTEXT://kafka-dev-controller-0:9092
```

## Полезные команды

### Для работы с Helm:
```bash
# Обновить релиз
helm upgrade webserver ./myapp-chart -n homework

# Откатить к предыдущей версии
helm rollback webserver 1 -n homework

# Посмотреть сгенерированные манифесты
helm template webserver ./myapp-chart

# Удалить релиз
helm uninstall webserver -n homework
```

### Для работы с Helmfile:
```bash
# Установить только prod
helmfile -l name=kafka-prod sync

# Посмотреть что будет установлено
helmfile template

# Удалить все релизы
helmfile destroy
```

### Для проверки Kafka:
```bash
# Создать топик в dev (без авторизации)
kubectl exec -n dev kafka-dev-controller-0 -- \
  kafka-topics.sh --create --topic test-topic \
  --bootstrap-server localhost:9092

# Список топиков
kubectl exec -n dev kafka-dev-controller-0 -- \
  kafka-topics.sh --list --bootstrap-server localhost:9092
```

## Структура финальных файлов:

```
kubernetes-templating/
├── README.md
├── myapp-chart/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── configmap.yaml
│   │   ├── pvc.yaml
│   │   ├── storageclass.yaml
│   │   ├── rbac.yaml
│   │   └── NOTES.txt
│   └── charts/
│       └── redis-*.tgz
└── kafka-releases/
    ├── helmfile.yaml
    ├── values-prod.yaml
    └── values-dev.yaml
```

## Выводы

1. **Helm** значительно упрощает управление приложениями в Kubernetes:
   - Параметризация манифестов для разных окружений
   - Управление зависимостями (Redis в нашем случае)
   - Версионирование релизов и возможность отката
   - Объединение всех компонентов из ДЗ 1-5 в один управляемый пакет

2. **Helmfile** добавляет декларативный подход к управлению множеством Helm релизов:
   - Удобное управление несколькими окружениями (prod/dev)
   - Автоматизация для CI/CD процессов
   - Консистентность конфигураций между окружениями

3. **Практический опыт**:
   - Научились создавать собственные Helm charts с нуля
   - Интегрировали компоненты из всех предыдущих ДЗ
   - Использовали community charts как зависимости
     - Настроили Kafka для разных окружений с разными требованиями безопасности