# Docker Lab Manager - Host Docker Access
FROM python:3.11-alpine

# Install system packages
RUN apk add --no-cache \
    curl \
    jq

# Create app directory
WORKDIR /app

# Copy application files
COPY app.py /app/
COPY requirements.txt /app/

# Create virtual environment and install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Make scripts executable - not needed anymore

# Expose the API port
EXPOSE 5000

# Use Python directly
CMD ["python", "app.py"]