#!/bin/bash

# Генерируем токен на 24 часа для ServiceAccount cd
kubectl create token cd -n homework --duration=24h > token

echo "Token saved to file 'token'"