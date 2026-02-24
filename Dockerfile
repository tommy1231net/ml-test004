FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# シンプルに python main.py で起動させる
CMD ["python", "main.py"]