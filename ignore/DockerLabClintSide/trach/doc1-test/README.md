# Docker-based Cybersecurity Lab

This project consists of a web-based Docker container management system with a client-server architecture.

## Project Structure

```
.
├── server/
│   └── index.html        # Control panel UI
└── client/
    ├── app.py            # Docker management API
    ├── docker-compose.yml # Container configurations
    └── requirements.txt   # Python dependencies
```

## Setup Instructions

### Server Side
1. Host the `server/index.html` file on any web server or open it directly in a browser

### Client Side

#### 1. Install Docker
For Windows:
1. Download Docker Desktop from [Docker Hub](https://hub.docker.com/editions/community/docker-ce-desktop-windows/)
2. Run the installer
3. Follow the installation wizard
4. Start Docker Desktop
5. Wait for Docker to start (check the whale icon in system tray)

For Linux:
```bash
# Update package index
sudo apt-get update

# Install prerequisites
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up stable repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
sudo usermod -aG docker $USER
```

#### 2. Install Python Dependencies
```bash
pip install -r client/requirements.txt
```

#### 3. Start the Docker Containers
```bash
cd client
docker-compose up -d
```

#### 4. Start the API Server
```bash
python app.py
```

## Usage

1. Open the control panel (server/index.html) in your web browser
2. Get the API credentials from the client app's homepage (http://localhost:5000)
3. Enter the credentials in the control panel
4. Use the interface to manage Docker containers

## Security Notes

- Change the default API password in the client's app.py
- Use HTTPS in production
- Implement proper authentication in production
- Restrict Docker API access appropriately

## Available Containers

1. Apache Server
   - Port: 8080
   - IP: 172.20.0.2

2. PHP Server
   - Port: 8081
   - IP: 172.20.0.3

## API Endpoints

- GET /containers - List all containers
- POST /containers/start/<container_id> - Start a container
- POST /containers/stop/<container_id> - Stop a container
- POST /containers/restart/<container_id> - Restart a container