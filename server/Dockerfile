FROM python:3.11-alpine

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY app.py .
COPY static/ ./static/

# Storage mount directory
RUN mkdir -p /storage

ENV STORAGE_ROOT=/storage
ENV PORT=8888

EXPOSE 8888

CMD ["python", "app.py"]
