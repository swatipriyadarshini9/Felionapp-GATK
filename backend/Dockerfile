# Stage 1: Get GATK from the official source
FROM broadinstitute/gatk:4.5.0.0 AS gatk_source

# Stage 2: Your actual Backend Image
FROM python:3.11-slim

# Install system libraries and Java
RUN apt-get update && apt-get install -y \
    libhts-dev \
    build-essential \
    default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Copy GATK directly from the first stage (No more downloading!)
COPY --from=gatk_source /gatk /opt/gatk
RUN ln -s /opt/gatk/gatk /usr/local/bin/gatk

# Set the working directory
WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of backend code
COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
