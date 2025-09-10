FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY metrics_agent.py ./metrics_agent.py
RUN useradd -m runner
USER runner
CMD ["python", "/app/metrics_agent.py"]
