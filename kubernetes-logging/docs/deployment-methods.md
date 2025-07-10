# Deployment Methods Comparison

## Обзор

В проекте реализовано два метода развертывания Loki Stack:

1. **Helm Charts** - использование готовых чартов с кастомизацией через values
2. **Raw Manifests** - прямое применение Kubernetes манифестов

## Сравнение методов

| Критерий | Helm Charts | Raw Manifests |
|----------|-------------|---------------|
| **Компоненты** | Loki + Promtail + Grafana + Prometheus (опц.) | Loki + Promtail |
| **Сложность установки** | Низкая (одна команда) | Средняя (несколько шагов) |
| **Гибкость настройки** | Средняя (через values) | Высокая (полный контроль) |
| **Обновление** | Простое (`helm upgrade`) | Ручное изменение манифестов |
| **Откат** | Встроенный (`helm rollback`) | Ручной через git |
| **Визуализация** | Grafana включена | Требует отдельной установки |
| **Дашборды** | Преднастроенные | Нужно создавать |
| **Управление секретами** | Автоматическое | Ручное |
| **Зависимости** | Управляются Helm | Ручное управление |

## Helm Charts метод

### Преимущества

1. **Быстрая установка**
   ```bash
   helm install loki ./loki-stack -n loki-stack
   ```

2. **Готовая интеграция**
   - Grafana автоматически настроена с Loki datasource
   - Включены базовые дашборды
   - Правильные метки и аннотации для ServiceMonitor

3. **Простое обновление**
   ```bash
   helm upgrade loki ./loki-stack -n loki-stack
   ```

4. **Версионирование**
   - История релизов
   - Возможность отката к предыдущим версиям

### Недостатки

1. **Меньше контроля**
   - Некоторые настройки могут быть недоступны
   - Сложнее отлаживать проблемы

2. **Избыточность**
   - Устанавливаются компоненты, которые могут не использоваться

3. **Зависимость от Chart**
   - Нужно ждать обновления чарта для новых версий

### Структура values

```yaml
loki:
  enabled: true
  persistence:
    enabled: true
    size: 10Gi
  
promtail:
  enabled: true
  
grafana:
  enabled: true
  adminPassword: admin
  
# Кастомные настройки для YC
nodeSelector:
  node-role: infra
tolerations:
  - key: node-role
    value: infra
    effect: NoSchedule
```

### Команды управления

```bash
# Установка
helm install loki ./loki-stack -n loki-stack -f values-loki.yaml

# Обновление конфигурации
helm upgrade loki ./loki-stack -n loki-stack -f values-loki.yaml

# Просмотр истории
helm history loki -n loki-stack

# Откат к версии 1
helm rollback loki 1 -n loki-stack

# Удаление
helm uninstall loki -n loki-stack
```

## Raw Manifests метод

### Преимущества

1. **Полный контроль**
   - Точно знаете что развернуто
   - Можете изменить любой параметр

2. **Прозрачность**
   - Все конфигурации видны в манифестах
   - Легче понять структуру

3. **Независимость**
   - Не зависите от поддержки чарта
   - Можете использовать последние версии образов

4. **Модульность**
   - Легко добавлять/удалять компоненты
   - Можно разворачивать по частям

### Недостатки

1. **Больше ручной работы**
   - Нужно самостоятельно управлять всеми ресурсами
   - Следить за совместимостью версий

2. **Нет автоматической интеграции**
   - Grafana нужно настраивать отдельно
   - Дашборды создавать вручную

3. **Сложнее обновлять**
   - Нужно вручную изменять версии образов
   - Следить за изменениями в конфигурации

### Структура манифестов

```
manifests/
├── namespace.yaml          # Общий namespace
├── loki/
│   ├── configmap.yaml     # Конфигурация Loki
│   ├── deployment.yaml    # Deployment с nodeSelector
│   └── service.yaml       # Services для API
└── promtail/
    ├── configmap.yaml     # Конфигурация Promtail
    ├── daemonset.yaml     # DaemonSet для всех нод
    └── rbac.yaml         # Права для чтения логов
```

### Команды управления

```bash
# Установка
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/loki/
kubectl apply -f manifests/promtail/

# Обновление
kubectl apply -f manifests/

# Перезапуск
kubectl rollout restart deployment/loki -n loki-stack
kubectl rollout restart daemonset/promtail -n loki-stack

# Удаление
kubectl delete -f manifests/
```

## Рекомендации по выбору

### Используйте Helm если:

- ✅ Нужен полный стек мониторинга с Grafana
- ✅ Важна скорость развертывания
- ✅ Планируете регулярные обновления
- ✅ Нужны готовые дашборды
- ✅ Команда знакома с Helm

### Используйте Raw Manifests если:

- ✅ Нужен максимальный контроль
- ✅ Уже есть Grafana в кластере
- ✅ Хотите минимальную конфигурацию
- ✅ Изучаете как работает Loki
- ✅ Нужны специфичные настройки

## Миграция между методами

### Из Raw Manifests в Helm

1. Сохраните данные из S3 (если важно)
2. Удалите существующие ресурсы:
   ```bash
   kubectl delete -f manifests/
   ```
3. Установите через Helm с теми же параметрами S3:
   ```bash
   helm install loki ./loki-stack -n loki-stack -f values-loki.yaml
   ```

### Из Helm в Raw Manifests

1. Экспортируйте текущую конфигурацию:
   ```bash
   helm get manifest loki -n loki-stack > current-config.yaml
   ```
2. Удалите Helm релиз:
   ```bash
   helm uninstall loki -n loki-stack
   ```
3. Примените манифесты:
   ```bash
   kubectl apply -f manifests/
   ```

## Особенности для Yandex Cloud

Оба метода адаптированы для Yandex Managed Kubernetes:

1. **Используются публичные образы**
   - Обход проблемы с доступом к registry
   - Не требуется настройка imagePullSecrets

2. **NodeSelector и Tolerations**
   - Компоненты размещаются на infra нодах
   - Promtail запускается на всех нодах

3. **S3 конфигурация**
   - Endpoint: `storage.yandexcloud.net:443`
   - Region: `ru-central1`
   - Credentials через service account

4. **Ресурсы**
   - Учтены ограничения Managed K8s
   - Оптимизированы requests/limits

## Итоги

- **Helm** - выбор для production и быстрого старта
- **Raw Manifests** - выбор для обучения и полного контроля

Оба метода полностью функциональны и поддерживают все требования домашнего задания.