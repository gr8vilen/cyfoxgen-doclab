# Docker Lab Manager
FROM docker:24-dind

# Install Python and required packages
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-flask \
    py3-requests \
    curl \
    jq \
    iptables \
    bridge-utils

# Create app directory
WORKDIR /app

# Copy application files
COPY app.py /app/
COPY requirements.txt /app/
COPY entrypoint.sh /app/

# Install Python dependencies (override externally managed environment)
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# Make scripts executable
RUN chmod +x /app/entrypoint.sh

# Expose the API port
EXPOSE 5000

# Use custom entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]