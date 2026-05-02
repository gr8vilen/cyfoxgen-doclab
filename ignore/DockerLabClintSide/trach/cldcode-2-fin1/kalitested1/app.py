#!/usr/bin/env python3
"""
Docker Lab Manager - Deploy containers via HTTP API with unique IPs
"""

from flask import Flask, request, jsonify
import docker
import ipaddress
import json
import logging
import os
import threading
import time

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Docker client
client = docker.from_env()

# Container tracking
containers = {}
network_manager = None

class NetworkManager:
    def __init__(self):
        self.network_name = "lab-network"
        self.subnet = "172.20.0.0/16"
        self.gateway = "172.20.0.1"
        self.ip_pool = self._generate_ip_pool()
        self.used_ips = set()
        self.setup_network()
    
    def _generate_ip_pool(self):
        """Generate available IP addresses"""
        network = ipaddress.IPv4Network(self.subnet, strict=False)
        # Skip network, gateway, and broadcast addresses
        return [str(ip) for ip in network.hosts()][1:254]  # Skip first IP (gateway)
    
    def setup_network(self):
        """Create or get the lab network"""
        try:
            self.network = client.networks.get(self.network_name)
            logger.info(f"Using existing network: {self.network_name}")
        except docker.errors.NotFound:
            self.network = client.networks.create(
                self.network_name,
                driver="bridge",
                ipam=docker.types.IPAMConfig(
                    pool_configs=[
                        docker.types.IPAMPool(
                            subnet=self.subnet,
                            gateway=self.gateway
                        )
                    ]
                ),
                attachable=True  # Allow containers to be attached from outside
            )
            logger.info(f"Created network: {self.network_name}")
    
    def get_next_ip(self):
        """Get next available IP address"""
        for ip in self.ip_pool:
            if ip not in self.used_ips:
                self.used_ips.add(ip)
                return ip
        raise Exception("No available IP addresses")
    
    def release_ip(self, ip):
        """Release an IP address"""
        self.used_ips.discard(ip)

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "containers": len(containers)})

@app.route('/deploy', methods=['POST'])
def deploy_container():
    """Deploy a new container with unique IP"""
    try:
        data = request.get_json()
        
        # Validate required fields
        if not data or 'image' not in data:
            return jsonify({"error": "Missing 'image' field"}), 400
        
        image = data['image']
        name = data.get('name', f"lab-container-{int(time.time())}")
        environment = data.get('environment', {})
        volumes = data.get('volumes', {})
        command = data.get('command')
        
        # NO PORT MAPPING - containers use their internal ports only
        # Each container gets its own IP, so port conflicts don't matter
        
        # Create container without port mapping
        container = client.containers.run(
            image=image,
            name=name,
            environment=environment,
            volumes=volumes,
            command=command,
            network=network_manager.network_name,
            detach=True,
            remove=False
        )
        
        # Get container IP
        container.reload()
        container_ip = container.attrs['NetworkSettings']['Networks'][network_manager.network_name]['IPAddress']
        
        # Get exposed ports from container (for info only)
        exposed_ports = []
        if container.attrs.get('Config', {}).get('ExposedPorts'):
            exposed_ports = list(container.attrs['Config']['ExposedPorts'].keys())
        
        # Store container info
        container_info = {
            'id': container.id,
            'name': name,
            'image': image,
            'ip': container_ip,
            'status': container.status,
            'exposed_ports': exposed_ports,
            'created': time.time(),
            'access_url': f"http://{container_ip}" if '80/tcp' in exposed_ports else None
        }
        containers[container.id] = container_info
        
        logger.info(f"Deployed container {name} with IP {container_ip}")
        
        return jsonify({
            "success": True,
            "container": container_info,
            "message": f"Container accessible at IP {container_ip}"
        }), 201
        
    except docker.errors.ImageNotFound:
        return jsonify({"error": f"Image '{image}' not found"}), 404
    except Exception as e:
        logger.error(f"Deployment error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/containers', methods=['GET'])
def list_containers():
    """List all managed containers"""
    # Refresh container status
    for container_id in list(containers.keys()):
        try:
            container = client.containers.get(container_id)
            containers[container_id]['status'] = container.status
        except docker.errors.NotFound:
            # Container was removed externally
            container_info = containers.pop(container_id)
            network_manager.release_ip(container_info['ip'])
    
    return jsonify({"containers": list(containers.values())})

@app.route('/containers/<container_id>', methods=['GET'])
def get_container(container_id):
    """Get specific container info"""
    if container_id not in containers:
        return jsonify({"error": "Container not found"}), 404
    
    try:
        container = client.containers.get(container_id)
        containers[container_id]['status'] = container.status
        return jsonify({"container": containers[container_id]})
    except docker.errors.NotFound:
        containers.pop(container_id, None)
        return jsonify({"error": "Container not found"}), 404

@app.route('/containers/<container_id>', methods=['DELETE'])
def remove_container(container_id):
    """Remove a container"""
    if container_id not in containers:
        return jsonify({"error": "Container not found"}), 404
    
    try:
        container = client.containers.get(container_id)
        container.remove(force=True)
        
        # Release IP and remove from tracking
        container_info = containers.pop(container_id)
        network_manager.release_ip(container_info['ip'])
        
        logger.info(f"Removed container {container_info['name']}")
        
        return jsonify({"success": True, "message": "Container removed"})
        
    except docker.errors.NotFound:
        containers.pop(container_id, None)
        return jsonify({"error": "Container not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/containers/<container_id>/logs', methods=['GET'])
def get_container_logs(container_id):
    """Get container logs"""
    if container_id not in containers:
        return jsonify({"error": "Container not found"}), 404
    
    try:
        container = client.containers.get(container_id)
        logs = container.logs(tail=100).decode('utf-8')
        return jsonify({"logs": logs})
    except docker.errors.NotFound:
        return jsonify({"error": "Container not found"}), 404

@app.route('/cleanup', methods=['POST'])
def cleanup_all():
    """Remove all managed containers"""
    removed = []
    for container_id in list(containers.keys()):
        try:
            container = client.containers.get(container_id)
            container.remove(force=True)
            container_info = containers.pop(container_id)
            network_manager.release_ip(container_info['ip'])
            removed.append(container_info['name'])
        except docker.errors.NotFound:
            containers.pop(container_id, None)
    
    return jsonify({"success": True, "removed": removed})

def cleanup_orphaned_containers():
    """Background task to clean up orphaned containers"""
    while True:
        try:
            time.sleep(60)  # Check every minute
            for container_id in list(containers.keys()):
                try:
                    container = client.containers.get(container_id)
                    if container.status == 'exited':
                        logger.info(f"Cleaning up exited container: {container.name}")
                        container.remove()
                        container_info = containers.pop(container_id)
                        network_manager.release_ip(container_info['ip'])
                except docker.errors.NotFound:
                    container_info = containers.pop(container_id, None)
                    if container_info:
                        network_manager.release_ip(container_info['ip'])
        except Exception as e:
            logger.error(f"Cleanup error: {e}")

if __name__ == '__main__':
    # Initialize network manager
    network_manager = NetworkManager()
    
    # Start cleanup thread
    cleanup_thread = threading.Thread(target=cleanup_orphaned_containers, daemon=True)
    cleanup_thread.start()
    
    # Start Flask app
    app.run(host='0.0.0.0', port=5000, debug=False)