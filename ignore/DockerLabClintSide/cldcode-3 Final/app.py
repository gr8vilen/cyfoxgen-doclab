#!/usr/bin/env python3
"""
Docker Lab Manager - Deploy containers via HTTP API with unique IPs and Web Dashboard
"""

from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import docker
import ipaddress
import json
import logging
import os
import threading
import time
import random
import string
import subprocess

app = Flask(__name__)

# Enable CORS for all routes and origins
CORS(app, origins="*", methods=["GET", "POST", "DELETE", "OPTIONS"], 
     allow_headers=["Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With"])

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Docker client
client = docker.from_env()

# Container tracking
containers = {}
network_manager = None

# System logs for dashboard
system_logs = []
log_lock = threading.Lock()

def add_system_log(message, log_type='info'):
    """Add log to system logs with thread safety"""
    with log_lock:
        timestamp = time.strftime("%H:%M:%S")
        system_logs.append({
            'timestamp': timestamp,
            'message': message,
            'type': log_type
        })
        # Keep only last 100 logs
        if len(system_logs) > 100:
            system_logs.pop(0)
    logger.info(f"[{log_type.upper()}] {message}")

# Generate random password on startup
def generate_password():
    return ''.join(random.choices(string.ascii_letters + string.digits, k=8))

API_PASSWORD = generate_password()
print(f"\n{'='*50}")
print(f"🔐 DOCKER LAB MANAGER CREDENTIALS")
print(f"{'='*50}")
print(f"📍 URL: http://localhost:62111")
print(f"🔑 Password: {API_PASSWORD}")
print(f"{'='*50}\n")

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
            add_system_log(f"Using existing network: {self.network_name}")
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
                attachable=True
            )
            add_system_log(f"Created network: {self.network_name}")
    
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

# Dashboard HTML Template
DASHBOARD_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🐳 Docker Lab Manager - Hacker Terminal</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            background: linear-gradient(135deg, #0a0a0a 0%, #1a1a1a 100%);
            color: #00ff00;
            font-family: 'Courier New', monospace;
            min-height: 100vh;
            overflow-x: hidden;
        }
        
        .matrix-bg {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            z-index: -1;
            opacity: 0.1;
        }
        
        .header {
            background: linear-gradient(90deg, #000 0%, #001100 50%, #000 100%);
            border-bottom: 2px solid #00ff00;
            padding: 20px;
            text-align: center;
            box-shadow: 0 4px 20px rgba(0, 255, 0, 0.3);
        }
        
        .header h1 {
            color: #00ff00;
            text-shadow: 0 0 10px #00ff00;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .credentials {
            background: rgba(0, 50, 0, 0.8);
            border: 1px solid #00ff00;
            border-radius: 8px;
            padding: 15px;
            margin: 20px auto;
            max-width: 600px;
            text-align: center;
        }
        
        .credential-item {
            margin: 8px 0;
            font-size: 1.1em;
        }
        
        .password {
            color: #ffff00;
            font-weight: bold;
            text-shadow: 0 0 5px #ffff00;
        }
        
        .container {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            padding: 20px;
            height: calc(100vh - 200px);
        }
        
        .panel {
            background: rgba(0, 20, 0, 0.9);
            border: 2px solid #00ff00;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 0 20px rgba(0, 255, 0, 0.2);
        }
        
        .panel h2 {
            color: #00ff00;
            text-shadow: 0 0 8px #00ff00;
            margin-bottom: 15px;
            border-bottom: 1px solid #00ff00;
            padding-bottom: 8px;
        }
        
        .logs {
            height: calc(100% - 60px);
            overflow-y: auto;
            background: #000;
            border: 1px solid #00ff00;
            border-radius: 5px;
            padding: 10px;
            font-size: 13px;
            line-height: 1.5;
        }
        
        .log-entry {
            margin-bottom: 6px;
            opacity: 0.9;
            word-wrap: break-word;
        }
        
        .log-entry.info { color: #00ff00; }
        .log-entry.warning { color: #ffff00; }
        .log-entry.error { color: #ff0000; }
        .log-entry.deployment { color: #00ffff; }
        
        .containers-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 15px;
            height: calc(100% - 60px);
            overflow-y: auto;
        }
        
        .container-card {
            background: linear-gradient(135deg, #001100 0%, #002200 100%);
            border: 1px solid #00ff00;
            border-radius: 8px;
            padding: 15px;
            transition: all 0.3s ease;
            position: relative;
            height: 280px;
            display: flex;
            flex-direction: column;
        }
        
        .container-card:hover {
            border-color: #00ffff;
            box-shadow: 0 0 15px rgba(0, 255, 255, 0.3);
        }
        
        .container-header {
            border-bottom: 1px solid #00ff00;
            padding-bottom: 8px;
            margin-bottom: 10px;
            flex-shrink: 0;
        }
        
        .container-name {
            color: #00ffff;
            font-weight: bold;
            font-size: 1.1em;
        }
        
        .container-ip {
            color: #ffff00;
            margin-top: 4px;
        }
        
        .container-status {
            position: absolute;
            top: 10px;
            right: 10px;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 10px;
            font-weight: bold;
        }
        
        .status-running {
            background: #00ff00;
            color: #000;
        }
        
        .status-stopped {
            background: #ff0000;
            color: #fff;
        }
        
        .container-logs {
            background: #000;
            border: 1px solid #333;
            border-radius: 4px;
            padding: 10px;
            flex: 1;
            overflow-y: auto;
            font-size: 12px;
            line-height: 1.4;
            margin-top: 10px;
            min-height: 150px;
            max-height: 180px;
        }
        
        .loading-spinner {
            display: inline-block;
            width: 12px;
            height: 12px;
            border: 2px solid #333;
            border-radius: 50%;
            border-top-color: #00ff00;
            animation: spin 1s ease-in-out infinite;
            margin-right: 8px;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        .scrollbar::-webkit-scrollbar {
            width: 8px;
        }
        
        .scrollbar::-webkit-scrollbar-track {
            background: #000;
        }
        
        .scrollbar::-webkit-scrollbar-thumb {
            background: #00ff00;
            border-radius: 4px;
        }
        
        .blink {
            animation: blink 1s infinite;
        }
        
        @keyframes blink {
            0%, 50% { opacity: 1; }
            51%, 100% { opacity: 0; }
        }
        
        .terminal-cursor::after {
            content: "█";
            animation: blink 1s infinite;
            color: #00ff00;
        }
    </style>
</head>
<body>
    <canvas class="matrix-bg" id="matrix"></canvas>
    
    <div class="header">
        <h1>🐳 DOCKER LAB MANAGER</h1>
        <div class="credentials">
            <div class="credential-item">📍 <strong>IP:</strong> localhost</div>
            <div class="credential-item">🔌 <strong>Port:</strong> 62111</div>
            <div class="credential-item">🔑 <strong>Password:</strong> <span class="password">{{ password }}</span></div>
        </div>
    </div>
    
    <div class="container">
        <div class="panel">
            <h2>📊 System Logs <span class="terminal-cursor"></span></h2>
            <div class="logs scrollbar" id="systemLogs">
                <div class="log-entry info">[SYSTEM] Docker Lab Manager initialized</div>
                <div class="log-entry info">[NETWORK] Lab network ready: 172.20.0.0/16</div>
                <div class="log-entry info">[AUTH] Password generated: {{ password }}</div>
            </div>
        </div>
        
        <div class="panel">
            <h2>🚀 Active Containers <span id="containerCount">(0)</span></h2>
            <div class="containers-grid scrollbar" id="containersGrid">
                <div style="text-align: center; color: #666; margin-top: 50px;">
                    No containers deployed yet...<br>
                    <small>Use API with password to deploy containers</small>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Matrix background effect
        const canvas = document.getElementById('matrix');
        const ctx = canvas.getContext('2d');
        
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
        
        const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789@#$%^&*()';
        const fontSize = 10;
        const columns = canvas.width / fontSize;
        const drops = [];
        
        for (let x = 0; x < columns; x++) {
            drops[x] = 1;
        }
        
        function drawMatrix() {
            ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            ctx.fillStyle = '#00ff00';
            ctx.font = fontSize + 'px monospace';
            
            for (let i = 0; i < drops.length; i++) {
                const text = letters[Math.floor(Math.random() * letters.length)];
                ctx.fillText(text, i * fontSize, drops[i] * fontSize);
                
                if (drops[i] * fontSize > canvas.height && Math.random() > 0.975) {
                    drops[i] = 0;
                }
                drops[i]++;
            }
        }
        
        setInterval(drawMatrix, 35);
        
        // System logs management
        function addLog(message, type = 'info') {
            const logs = document.getElementById('systemLogs');
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = document.createElement('div');
            logEntry.className = `log-entry ${type}`;
            logEntry.innerHTML = `[${timestamp}] ${message}`;
            logs.appendChild(logEntry);
            logs.scrollTop = logs.scrollHeight;
            
            // Keep only last 100 logs
            while (logs.children.length > 100) {
                logs.removeChild(logs.firstChild);
            }
        }
        
        // Fetch system logs from server
        function updateSystemLogs() {
            fetch('/system-logs')
                .then(response => response.json())
                .then(data => {
                    const logs = document.getElementById('systemLogs');
                    // Clear existing logs except initial ones
                    while (logs.children.length > 3) {
                        logs.removeChild(logs.lastChild);
                    }
                    
                    // Add server logs
                    data.logs.forEach(log => {
                        const logEntry = document.createElement('div');
                        logEntry.className = `log-entry ${log.type}`;
                        logEntry.innerHTML = `[${log.timestamp}] ${log.message}`;
                        logs.appendChild(logEntry);
                    });
                    
                    logs.scrollTop = logs.scrollHeight;
                })
                .catch(error => {
                    console.error('Error fetching system logs:', error);
                });
        }
        
        function updateContainers() {
            fetch('/containers')
                .then(response => response.json())
                .then(data => {
                    const grid = document.getElementById('containersGrid');
                    const count = document.getElementById('containerCount');
                    
                    // Filter out management container
                    const containers = data.containers.filter(c => !c.name.includes('docker-lab-manager'));
                    count.textContent = `(${containers.length})`;
                    
                    if (containers.length === 0) {
                        grid.innerHTML = `
                            <div style="text-align: center; color: #666; margin-top: 50px;">
                                No containers deployed yet...<br>
                                <small>Use API with password to deploy containers</small>
                            </div>
                        `;
                        return;
                    }
                    
                    grid.innerHTML = '';
                    
                    containers.forEach(container => {
                        const card = document.createElement('div');
                        card.className = 'container-card';
                        card.innerHTML = `
                            <div class="container-status status-${container.status}">
                                ${container.status.toUpperCase()}
                            </div>
                            <div class="container-header">
                                <div class="container-name">📦 ${container.name}</div>
                                <div class="container-ip">🌐 ${container.ip}</div>
                                <div style="color: #888; font-size: 12px; margin-top: 4px;">
                                    ${container.image}
                                </div>
                            </div>
                            <div class="container-logs scrollbar" id="logs-${container.id}">
                                <span class="loading-spinner"></span>Loading logs...
                            </div>
                        `;
                        grid.appendChild(card);
                        
                        // Fetch container logs
                        fetch(`/containers/${container.id}/logs`)
                            .then(response => response.json())
                            .then(logData => {
                                const logDiv = document.getElementById(`logs-${container.id}`);
                                if (logDiv) {
                                    if (logData.logs && logData.logs.trim()) {
                                        const logLines = logData.logs.split('\\n').filter(line => line.trim());
                                        const recentLogs = logLines.slice(-20); // Show last 20 lines
                                        logDiv.innerHTML = recentLogs.join('<br>');
                                    } else {
                                        logDiv.innerHTML = '<span style="color: #666;">No logs available yet...</span>';
                                    }
                                }
                            })
                            .catch(() => {
                                const logDiv = document.getElementById(`logs-${container.id}`);
                                if (logDiv) logDiv.innerHTML = '<span style="color: #ff6666;">Error loading logs</span>';
                            });
                    });
                })
                .catch(error => {
                    addLog(`Error fetching containers: ${error.message}`, 'error');
                });
        }
        
        // Initial load and refresh
        updateContainers();
        updateSystemLogs();
        
        // Refresh every 3 seconds for faster updates
        setInterval(updateContainers, 3000);
        setInterval(updateSystemLogs, 2000);
        
        // Resize canvas on window resize
        window.addEventListener('resize', () => {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
        });
    </script>
</body>
</html>
'''

@app.route('/', methods=['GET'])
def dashboard():
    """Serve the dashboard"""
    return render_template_string(DASHBOARD_HTML, password=API_PASSWORD)

@app.route('/system-logs', methods=['GET'])
def get_system_logs():
    """Get system logs for dashboard"""
    with log_lock:
        return jsonify({"logs": system_logs})

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "containers": len(containers)})

@app.route('/deploy', methods=['POST'])
def deploy_container():
    """Deploy a new container with unique IP - requires password"""
    try:
        data = request.get_json()
        
        # Check password
        if not data or data.get('password') != API_PASSWORD:
            add_system_log("❌ Unauthorized deployment attempt", 'error')
            return jsonify({"error": "Invalid password"}), 401
        
        # Validate required fields
        if 'image' not in data:
            return jsonify({"error": "Missing 'image' field"}), 400
        
        image = data['image']
        name = data.get('name', f"lab-container-{int(time.time())}")
        environment = data.get('environment', {})
        volumes = data.get('volumes', {})
        command = data.get('command')
        
        add_system_log(f"🚀 Starting deployment: {name}", 'deployment')
        add_system_log(f"📥 Pulling image: {image}", 'deployment')
        
        # Pull image first to show progress
        try:
            add_system_log(f"⬇️ Downloading {image}...", 'deployment')
            client.images.pull(image)
            add_system_log(f"✅ Image {image} pulled successfully", 'deployment')
        except Exception as pull_error:
            add_system_log(f"⚠️ Using cached image or pull failed: {str(pull_error)}", 'warning')
        
        add_system_log(f"🏗️ Creating container: {name}", 'deployment')
        
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
        
        add_system_log(f"🔧 Configuring network for: {name}", 'deployment')
        
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
        
        add_system_log(f"✅ Container {name} deployed successfully", 'deployment')
        add_system_log(f"🌐 IP assigned: {container_ip}", 'deployment')
        
        if exposed_ports:
            add_system_log(f"🔌 Exposed ports: {', '.join(exposed_ports)}", 'info')
        
        return jsonify({
            "success": True,
            "container": container_info,
            "message": f"Container accessible at IP {container_ip}"
        }), 201
        
    except docker.errors.ImageNotFound:
        add_system_log(f"❌ Image '{image}' not found", 'error')
        return jsonify({"error": f"Image '{image}' not found"}), 404
    except Exception as e:
        add_system_log(f"❌ Deployment failed: {str(e)}", 'error')
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
            if network_manager:
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
    """Remove a container - requires password"""
    data = request.get_json() or {}
    
    # Check password
    if data.get('password') != API_PASSWORD:
        return jsonify({"error": "Invalid password"}), 401
    
    if container_id not in containers:
        return jsonify({"error": "Container not found"}), 404
    
    try:
        container = client.containers.get(container_id)
        container_name = containers[container_id]['name']
        
        add_system_log(f"🗑️ Removing container: {container_name}", 'warning')
        container.remove(force=True)
        
        # Release IP and remove from tracking
        container_info = containers.pop(container_id)
        network_manager.release_ip(container_info['ip'])
        
        add_system_log(f"✅ Container {container_name} removed successfully", 'info')
        
        return jsonify({"success": True, "message": "Container removed"})
        
    except docker.errors.NotFound:
        containers.pop(container_id, None)
        return jsonify({"error": "Container not found"}), 404
    except Exception as e:
        add_system_log(f"❌ Error removing container: {str(e)}", 'error')
        return jsonify({"error": str(e)}), 500

@app.route('/containers/<container_id>/logs', methods=['GET'])
def get_container_logs(container_id):
    """Get container logs"""
    if container_id not in containers:
        return jsonify({"error": "Container not found"}), 404
    
    try:
        container = client.containers.get(container_id)
        logs = container.logs(tail=100).decode('utf-8', errors='ignore')
        return jsonify({"logs": logs})
    except docker.errors.NotFound:
        return jsonify({"error": "Container not found"}), 404
    except Exception as e:
        return jsonify({"logs": f"Error retrieving logs: {str(e)}"})

@app.route('/cleanup', methods=['POST'])
def cleanup_all():
    """Remove all managed containers - requires password"""
    data = request.get_json() or {}
    
    # Check password
    if data.get('password') != API_PASSWORD:
        return jsonify({"error": "Invalid password"}), 401
    
    add_system_log("🧹 Starting cleanup of all containers", 'warning')
    
    removed = []
    for container_id in list(containers.keys()):
        try:
            container = client.containers.get(container_id)
            container_name = containers[container_id]['name']
            container.remove(force=True)
            container_info = containers.pop(container_id)
            network_manager.release_ip(container_info['ip'])
            removed.append(container_name)
            add_system_log(f"✅ Cleaned up: {container_name}", 'info')
        except docker.errors.NotFound:
            containers.pop(container_id, None)
    
    add_system_log(f"🧹 Cleanup completed. Removed {len(removed)} containers", 'info')
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
                        container_name = containers[container_id]['name']
                        add_system_log(f"🔄 Auto-cleanup: {container_name} (exited)", 'info')
                        container.remove()
                        container_info = containers.pop(container_id)
                        network_manager.release_ip(container_info['ip'])
                except docker.errors.NotFound:
                    container_info = containers.pop(container_id, None)
                    if container_info and network_manager:
                        network_manager.release_ip(container_info['ip'])
        except Exception as e:
            add_system_log(f"❌ Cleanup error: {str(e)}", 'error')

if __name__ == '__main__':
    # Initialize network manager
    network_manager = NetworkManager()
    
    # Add startup logs
    add_system_log("🐳 Docker Lab Manager starting up", 'info')
    add_system_log("🔧 Network manager initialized", 'info')
    add_system_log("🚀 Ready to deploy containers", 'info')
    
    # Start cleanup thread
    cleanup_thread = threading.Thread(target=cleanup_orphaned_containers, daemon=True)
    cleanup_thread.start()
    
    # Start Flask app on port 62111
    app.run(host='0.0.0.0', port=62111, debug=False)