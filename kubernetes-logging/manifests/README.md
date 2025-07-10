# Raw Kubernetes Manifests

Эти манифесты используются только при выборе deployment метода "raw manifests".

## Что включено

- **Loki**: Основной сервис для хранения логов
- **Promtail**: DaemonSet для сбора логов со всех нод

## Что НЕ включено

- Grafana (доступна только в Helm варианте)
- Prometheus (доступен только в Helm варианте)
- Дашборды и datasources

## Когда использовать

Используйте raw манифесты если:
- Нужен минимальный набор (только Loki + Promtail)
- Уже есть Grafana в кластере
- Хотите полный контроль над конфигурацией

## Как использовать

```bash
cd scripts
./02-deploy-with-manifests.sh