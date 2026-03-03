FROM python:3.11-slim

WORKDIR /opt/dagster/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY definitions.py .

ENV DAGSTER_HOME=/opt/dagster/dagster_home
RUN mkdir -p "${DAGSTER_HOME}"

EXPOSE 3030

CMD ["dagster", "api", "grpc", "-h", "0.0.0.0", "-p", "3030", "-m", "definitions"]
