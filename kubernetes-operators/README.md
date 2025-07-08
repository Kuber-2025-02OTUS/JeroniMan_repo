# Домашнее задание: Kubernetes Operators

## Основное задание

### Созданные компоненты:

1. **CustomResourceDefinition (CRD)**
   - API Group: `otus.homework`
   - Kind: `MySQL`
   - Version: `v1`
   - Обязательные поля: image, database, password, storage_size
   - Валидация всех полей через OpenAPIV3Schema

2. **RBAC компоненты**
   - ServiceAccount: `mysql-operator` в namespace `homework`
   - ClusterRole с полными правами на все ресурсы
   - ClusterRoleBinding для связи SA с ролью

3. **Deployment оператора**
   - Namespace: `homework`
   - ServiceAccount: `mysql-operator`
   - Контейнер с кастомным оператором на Python

### Структура проекта:

```
kubernetes-operators/
├── README.md
├── deploy/
│   ├── namespace.yaml                   
│   ├── crd.yaml                   # CustomResourceDefinition для MySQL
│   ├── deploy-all-homework.yaml   # Все ресурсы для homework namespace
├── deploy-minimal/
│   └── role-minimal.yaml # Минимальные права (Role + ClusterRole)
├── test/
│   ├── mysql-sample.yaml          # Пример MySQL ресурса
│   └── test-all.sh               # Скрипт для проверки всех заданий
└── mysql-operator/                # Для задания со ** (опционально)
    ├── Dockerfile
    ├── requirements.txt
    └── operator.py
```

### Применение манифестов:

```bash
# 1. Создаем namespace
kubectl apply -f deploy/namespace.yaml

# 2. Применяем CRD
kubectl apply -f deploy/crd.yaml

# 3. Применяем все компоненты в namespace homework
kubectl apply -f deploy/deploy-all-homework.yaml

# 4. Проверяем что оператор запустился
kubectl get pods -n homework
kubectl logs -l app=mysql-operator -n homework

# 5. Создаем тестовый MySQL ресурс
kubectl apply -f test/mysql-sample.yaml

# 6. Проверяем созданные ресурсы
kubectl get mysqls -n homework
kubectl get deploy,svc,pvc -n homework
kubectl get pv | grep mysql
```

### Проверка функциональности:

```bash
# Смотрим статус MySQL ресурса
kubectl get mysql mysql-instance -n homework -o yaml

# Проверяем что создались все ресурсы
kubectl get deployment mysql-instance-mysql -n homework
kubectl get service mysql-instance-mysql -n homework
kubectl get pvc mysql-instance-mysql-pvc -n homework
kubectl get pv mysql-instance-mysql-pv

# Проверяем логи оператора
kubectl logs deployment/mysql-operator -n homework

# Удаляем MySQL ресурс
kubectl delete mysql mysql-instance -n homework

# Проверяем что все ресурсы удалились (через 30 секунд)
kubectl get deploy,svc,pvc -n homework | grep mysql-instance
kubectl get pv | grep mysql-instance
```

## Задание со * (минимальные права)

### Минимальный набор прав:

Создан файл `deploy-minimal/role-minimal.yaml` с минимальными правами:
- **Role** в namespace homework для управления namespace-ресурсами:
  - CRD `mysqls.otus.homework`
  - Deployments
  - Services
  - PersistentVolumeClaims
  - Events и ConfigMaps
- **ClusterRole** только для PersistentVolumes (кластерный ресурс)
- **RoleBinding** и **ClusterRoleBinding** для связи с ServiceAccount

### Применение:

```bash
# 1. Удаляем старый ClusterRoleBinding с полными правами
kubectl delete clusterrolebinding mysql-operator

# 2. Применяем минимальные права
kubectl apply -f deploy-minimal/role-minimal.yaml

# 3. Проверяем созданные роли
kubectl get role mysql-operator-minimal -n homework
kubectl get clusterrole mysql-operator-pv

# 4. Перезапускаем оператор
kubectl rollout restart deployment mysql-operator -n homework

# 5. Проверяем что функциональность работает
kubectl apply -f test/mysql-sample.yaml
kubectl get mysqls -n homework
kubectl get deploy,svc,pvc -n homework

# 6. Проверяем права от имени ServiceAccount
kubectl auth can-i --list --as=system:serviceaccount:homework:mysql-operator -n homework

# 6.1 Проверяем конкретные права
kubectl auth can-i create deployments --as=system:serviceaccount:homework:mysql-operator -n homework
kubectl auth can-i create services --as=system:serviceaccount:homework:mysql-operator -n homework
kubectl auth can-i create persistentvolumeclaims --as=system:serviceaccount:homework:mysql-operator -n homework
kubectl auth can-i create persistentvolumes --as=system:serviceaccount:homework:mysql-operator

# 6.2 Проверяем права на MySQL CRD
kubectl auth can-i list mysqls.otus.homework --as=system:serviceaccount:homework:mysql-operator
kubectl auth can-i create mysqls.otus.homework --as=system:serviceaccount:homework:mysql-operator -n homework

# 6.3 Проверяем что НЕ может делать (для подтверждения минимальных прав)
kubectl auth can-i create pods --as=system:serviceaccount:homework:mysql-operator -n homework
kubectl auth can-i create deployments --as=system:serviceaccount:homework:mysql-operator -n default
```

## Задание со ** (свой оператор)

### Реализованный функционал:

1. **Python оператор на базе kopf**
   - Встроен прямо в deployment (inline script)
   - При создании MySQL создает: Deployment, Service, PV, PVC
   - При удалении MySQL удаляет все созданные ресурсы
   - Детальное логирование всех операций

2. **Особенности реализации**:
   - Использует согласованные имена ресурсов: `{name}-mysql`
   - Обработка ошибок 404 при удалении
   - Поддержка всех параметров из CRD spec

3. **Deployment с кастомным оператором**:
   - Образ: `python:3.9-alpine`
   - Установка зависимостей: kopf, kubernetes
   - Код оператора встроен в deployment

### Тестирование:

```bash
# Создаем несколько MySQL инстансов
kubectl apply -f - <<EOF
apiVersion: otus.homework/v1
kind: MySQL
metadata:
  name: mysql-test-1
  namespace: homework
spec:
  image: mysql:8.0
  database: testdb1
  password: password123456
  storage_size: 500Mi
---
apiVersion: otus.homework/v1
kind: MySQL
metadata:
  name: mysql-test-2
  namespace: homework
spec:
  image: mysql:8.0
  database: testdb2
  password: anotherPassword123
  storage_size: 2Gi
EOF

# Проверяем
kubectl get mysqls -n homework
kubectl get deploy,svc,pvc -n homework

# Удаляем один инстанс
kubectl delete mysql mysql-test-1 -n homework

# Проверяем что удалились только его ресурсы
kubectl get deploy,svc,pvc -n homework
```

## Автоматическая проверка всех заданий:

```bash
# Запуск скрипта проверки
chmod +x test/test-all.sh
./test/test-all.sh
```

Скрипт проверяет:
- ✅ Наличие CRD
- ✅ Работу оператора
- ✅ Создание и удаление ресурсов
- ✅ Минимальные права
- ✅ Использование кастомного оператора

## Результаты выполнения:

### Основное задание ✅
- CRD создан с валидацией всех полей
- Оператор работает в namespace homework
- При создании MySQL создаются все ресурсы (Deployment, Service, PV, PVC)
- При удалении MySQL все ресурсы корректно удаляются
<img width="884" alt="Screenshot 2025-07-07 at 22 09 22" src="https://github.com/user-attachments/assets/c33c82bd-43e3-4885-ad3d-50c73f60fae5" />
<img width="545" alt="Screenshot 2025-07-07 at 22 38 20" src="https://github.com/user-attachments/assets/b6aa1596-fa68-43a0-b52c-2013b93e34b4" />
<img width="1412" alt="Screenshot 2025-07-07 at 22 40 42" src="https://github.com/user-attachments/assets/6fa67632-914f-46f2-9655-e094acf68a8b" />
<img width="1263" alt="Screenshot 2025-07-07 at 22 41 43" src="https://github.com/user-attachments/assets/fcd83e14-9a12-4586-9a98-0df5b4b2db2d" />

### Задание со * ✅
- Создан набор минимальных прав (Role + ClusterRole)
- Оператор успешно работает с ограниченными правами
- Права ограничены namespace homework (кроме PV)
<img width="1370" alt="Screenshot 2025-07-07 at 22 56 28" src="https://github.com/user-attachments/assets/f38fb9b5-1361-4405-9e05-874b79500fd1" />


### Задание со ** ✅
- Создан собственный оператор на Python с использованием kopf
- Код оператора встроен в deployment для простоты
- Оператор корректно обрабатывает жизненный цикл MySQL ресурсов
<img width="1260" alt="Screenshot 2025-07-07 at 22 55 19" src="https://github.com/user-attachments/assets/78857498-3ebd-4c04-b06a-ef5d5d6532f6" />
<img width="1395" alt="Screenshot 2025-07-07 at 22 57 17" src="https://github.com/user-attachments/assets/ab7a83bc-8d1b-491c-bee9-ed7a42ca984b" />


## Примечания:

1. **О готовом операторе**: Образ `roflmaoinmysoul/mysql-operator:1.0.0` имеет баг - ищет ресурсы только в namespace `default`. Поэтому был создан кастомный оператор.

2. **Namespace isolation**: Все компоненты работают в namespace `homework` для изоляции и удобства управления.

3. **PersistentVolumes**: PV являются кластерными ресурсами, поэтому для них требуется отдельный ClusterRole даже при минимальных правах.

## Полезные команды:

```bash
# Посмотреть логи оператора
kubectl logs -f deployment/mysql-operator -n homework

# Проверить права ServiceAccount
kubectl auth can-i --list --as=system:serviceaccount:homework:mysql-operator

# Удалить все MySQL ресурсы
kubectl delete mysql --all -n homework

# Полная очистка
kubectl delete namespace homework
```

## Выводы:

Kubernetes Operators - мощный паттерн для автоматизации управления приложениями. В этом задании мы:
- Научились создавать CustomResourceDefinitions с валидацией
- Поняли как работают операторы и их жизненный цикл  
- Создали свой оператор для управления MySQL
- Изучили принципы least privilege для RBAC
- Получили практический опыт отладки и тестирования операторов
