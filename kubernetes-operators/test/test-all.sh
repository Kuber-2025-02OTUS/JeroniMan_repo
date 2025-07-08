#!/bin/bash

echo "=== ПРОВЕРКА ОСНОВНОГО ЗАДАНИЯ ==="
echo "1. Проверка CRD..."
kubectl get crd mysqls.otus.homework >/dev/null 2>&1 && echo "✅ CRD создан" || echo "❌ CRD не найден"

echo -e "\n2. Проверка оператора..."
kubectl get deployment mysql-operator -n homework >/dev/null 2>&1 && echo "✅ Оператор запущен" || echo "❌ Оператор не найден"

echo -e "\n3. Создание MySQL ресурса..."
kubectl apply -f test/mysql-sample.yaml
sleep 15

echo -e "\n4. Проверка созданных ресурсов..."
# Исключаем сам оператор из подсчета
DEPLOY=$(kubectl get deploy -n homework | grep -E "mysql-instance|mysql-test" | wc -l)
SVC=$(kubectl get svc -n homework | grep -E "mysql-instance|mysql-test" | wc -l)
PVC=$(kubectl get pvc -n homework | grep -E "mysql-instance|mysql-test" | wc -l)
PV=$(kubectl get pv | grep -E "mysql-instance|mysql-test" | wc -l)

[ $DEPLOY -ge 1 ] && echo "✅ MySQL Deployment создан" || echo "❌ MySQL Deployment не создан"
[ $SVC -ge 1 ] && echo "✅ MySQL Service создан" || echo "❌ MySQL Service не создан"
[ $PVC -ge 1 ] && echo "✅ MySQL PVC создан" || echo "❌ MySQL PVC не создан"
[ $PV -ge 1 ] && echo "✅ MySQL PV создан" || echo "❌ MySQL PV не создан"

echo -e "\n5. Проверка удаления..."
kubectl delete mysql mysql-instance -n homework
echo "Ждем 30 секунд для полного удаления ресурсов..."
sleep 30

# Проверяем что MySQL ресурсы удалены (исключаем сам оператор)
DEPLOY_AFTER=$(kubectl get deploy -n homework 2>/dev/null | grep -E "mysql-instance|mysql-test" | wc -l)
SVC_AFTER=$(kubectl get svc -n homework 2>/dev/null | grep -E "mysql-instance|mysql-test" | wc -l)
PVC_AFTER=$(kubectl get pvc -n homework 2>/dev/null | grep -E "mysql-instance|mysql-test" | wc -l)
PV_AFTER=$(kubectl get pv 2>/dev/null | grep -E "mysql-instance|mysql-test" | wc -l)

echo "Осталось MySQL ресурсов: Deployments=$DEPLOY_AFTER, Services=$SVC_AFTER, PVCs=$PVC_AFTER, PVs=$PV_AFTER"

# Проверяем что сам оператор на месте
OPERATOR=$(kubectl get deploy mysql-operator -n homework --no-headers 2>/dev/null | wc -l)

if [ $DEPLOY_AFTER -eq 0 ] && [ $SVC_AFTER -eq 0 ] && [ $PVC_AFTER -eq 0 ] && [ $OPERATOR -ge 1 ]; then
    echo "✅ MySQL ресурсы удалены, оператор работает"
else
    echo "❌ Проблема с удалением ресурсов или оператор не работает"
    echo "   Оператор найден: $OPERATOR"
fi

echo -e "\n=== ПРОВЕРКА ЗАДАНИЯ СО * ==="
echo "Проверка минимальных прав..."
# Проверяем Role в namespace
kubectl get role mysql-operator-minimal -n homework >/dev/null 2>&1 && echo "✅ Минимальная роль создана" || echo "❌ Минимальная роль не найдена"
# Проверяем ClusterRole для PV
kubectl get clusterrole mysql-operator-pv >/dev/null 2>&1 && echo "✅ ClusterRole для PV создана" || echo "❌ ClusterRole для PV не найдена"

echo -e "\n=== ПРОВЕРКА ЗАДАНИЯ СО ** ==="
echo "Проверка кастомного оператора..."
IMAGE=$(kubectl get deployment mysql-operator -n homework -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$IMAGE" != *"roflmaoinmysoul"* ]]; then
    echo "✅ Используется кастомный оператор ($IMAGE)"
else
    echo "❌ Используется готовый оператор"
fi

echo -e "\n=== ИТОГОВЫЙ РЕЗУЛЬТАТ ==="
echo "Основное задание: проверьте результаты выше"
echo "Задание со *: проверьте наличие минимальной роли"
echo "Задание со **: проверьте использование кастомного оператора"