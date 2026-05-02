Docker Lab Manager - Usage Guide
Build and Run
bash
# Build the image
docker build -t docker-lab-manager .

# Run with docker-compose (recommended)
docker-compose up -d

# Or run directly
docker run -d --privileged -p 5000:5000 --name docker-lab-manager docker-lab-manager
API Endpoints
Deploy a Container
bash
# Deploy nginx with unique IP
curl -X POST http://localhost:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{
    "image": "nginx:alpine",
    "name": "my-nginx",
    "ports": {"80/tcp": 8080},
    "environment": {"ENV": "development"}
  }'

# Deploy with custom command
curl -X POST http://localhost:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{
    "image": "alpine:latest",
    "name": "test-container",
    "command": ["sleep", "3600"]
  }'

# Deploy database with volumes
curl -X POST http://localhost:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{
    "image": "postgres:13",
    "name": "my-postgres",
    "ports": {"5432/tcp": 5432},
    "environment": {
      "POSTGRES_DB": "testdb",
      "POSTGRES_USER": "user",
      "POSTGRES_PASSWORD": "password"
    },
    "volumes": {
      "postgres_data": "/var/lib/postgresql/data"
    }
  }'
List All Containers
bash
curl http://localhost:5000/containers
Get Specific Container
bash
curl http://localhost:5000/containers/<container_id>
Get Container Logs
bash
curl http://localhost:5000/containers/<container_id>/logs
Remove Container
bash
curl -X DELETE http://localhost:5000/containers/<container_id>
Health Check
bash
curl http://localhost:5000/health
Cleanup All Containers
bash
curl -X POST http://localhost:5000/cleanup
Response Examples
Successful Deployment
json
{
  "success": true,
  "container": {
    "id": "a1b2c3d4e5f6",
    "name": "my-nginx",
    "image": "nginx:alpine",
    "ip": "172.20.0.2",
    "status": "running",
    "ports": {"80/tcp": 8080},
    "created": 1672531200.0
  }
}
Container List
json
{
  "containers": [
    {
      "id": "a1b2c3d4e5f6",
      "name": "my-nginx",
      "image": "nginx:alpine",
      "ip": "172.20.0.2",
      "status": "running",
      "ports": {"80/tcp": 8080},
      "created": 1672531200.0
    },
    {
      "id": "b2c3d4e5f6g7",
      "name": "my-postgres",
      "image": "postgres:13",
      "ip": "172.20.0.3",
      "status": "running",
      "ports": {"5432/tcp": 5432},
      "created": 1672531260.0
    }
  ]
}
Features
Unique IPs: Each container gets a unique IP from the 172.20.0.0/16 subnet
HTTP API: Deploy containers via simple HTTP POST requests
Container Management: List, inspect, and remove containers
Auto-cleanup: Automatically removes exited containers
Port Mapping: Support for port forwarding
Environment Variables: Pass environment variables to containers
Volume Mounting: Support for volume mounting
Custom Commands: Override container entrypoint commands
Logging: View container logs via API
Network Details
Subnet: 172.20.0.0/16
Gateway: 172.20.0.1
Container IPs: 172.20.0.2 - 172.20.255.254
Network Name: lab_network
Security Notes
This container runs in privileged mode (required for Docker-in-Docker)
Use in trusted environments only
Consider implementing authentication for production use
Container cleanup happens automatically but can be triggered manually
