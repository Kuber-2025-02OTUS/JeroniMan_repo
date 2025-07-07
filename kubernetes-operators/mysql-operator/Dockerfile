FROM python:3.9-slim

WORKDIR /app

# Копируем requirements
COPY requirements.txt .

# Устанавливаем зависимости
RUN pip install --no-cache-dir -r requirements.txt

# Копируем код оператора
COPY operator.py .

# Запускаем оператор
CMD ["python", "-u", "operator.py"]