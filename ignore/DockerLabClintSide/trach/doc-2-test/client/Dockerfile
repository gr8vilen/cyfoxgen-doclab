FROM python:3.9-slim

# Install system dependencies and Docker CLI
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    lsb-release && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create app directory and set permissions
WORKDIR /app
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Create non-root user and add to host's docker group
RUN useradd -u 1000 -m appuser && \
    # Create docker group with same GID as host (999 is common)
    groupadd -g 999 docker || true && \
    usermod -aG docker appuser

# Copy application code
COPY . .

# Set ownership of the application directory
RUN chown -R appuser:docker /app

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]

# Note: Run this container with:
# docker run -v /var/run/docker.sock:/var/run/docker.sock -p 5000:5000 cfgcli