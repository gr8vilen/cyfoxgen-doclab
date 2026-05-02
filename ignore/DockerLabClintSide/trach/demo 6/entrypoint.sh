#!/bin/sh

# Start Docker daemon in background
dockerd-entrypoint.sh dockerd &

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon..."
while ! docker info >/dev/null 2>&1; do
    sleep 1
done
echo "Docker daemon is ready!"

# Start the Flask application
echo "Starting Docker Lab Manager..."
cd /app
python3 app.py