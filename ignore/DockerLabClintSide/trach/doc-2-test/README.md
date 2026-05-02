# Docker-based Cybersecurity Lab

A revolutionary platform for cybersecurity education using Docker containers. This project consists of a server-side control panel and a client-side Docker management system.

## Architecture

### Server Side
- Static web interface for container management
- Control panel for deploying and managing Docker containers
- Demo containers: Apache server and PHP server
- Container management features: start, stop, restart
- Real-time container IP and port display

### Client Side
- Single Docker container deployment
- API endpoint exposure
- Secure communication with server
- Similar to Coolify/Portainer architecture

## Setup Instructions

### Server Side Setup
1. Navigate to the `server` directory
2. Deploy the static website to your preferred hosting (GitHub Pages or local server)
3. Configure the container templates

### Client Side Setup
1. Navigate to the `client` directory
2. Build and run the Docker container
3. Access the management interface through the provided URL

### Connection Setup
1. Deploy client-side Docker container
2. Get the API URL, port, and authentication token
3. Enter these credentials in the server control panel
4. Start managing containers through the web interface

## Security Considerations
- All communication is authenticated
- Containers run in isolated environments
- Each container has unique IP and port assignments
- Secure API token management

## Demo Containers
1. Apache Server
   - Basic web server setup
   - Unique IP and port assignment
   - Start/Stop/Restart capabilities

2. PHP Server
   - PHP development environment
   - Unique IP and port assignment
   - Start/Stop/Restart capabilities

## Contributing
Contributions are welcome! Please feel free to submit pull requests.

## License
This project is open source and available under the MIT License.