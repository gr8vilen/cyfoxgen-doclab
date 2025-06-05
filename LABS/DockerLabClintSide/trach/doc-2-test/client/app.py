from flask import Flask, request, jsonify, render_template_string
import docker
import os
from functools import wraps
import secrets
import time

app = Flask(__name__)

# Generate a secure random token on startup
API_TOKEN = secrets.token_urlsafe(32)

# HTML template for the index page
INDEX_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Docker Lab API Details</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 20px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .detail-box {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            margin: 10px 0;
            border: 1px solid #dee2e6;
        }
        .detail-box code {
            background-color: #e9ecef;
            padding: 2px 4px;
            border-radius: 3px;
        }
        h1 {
            color: #2c3e50;
            margin-bottom: 20px;
        }
        h2 {
            color: #34495e;
            margin-top: 20px;
        }
        .status {
            padding: 8px;
            border-radius: 4px;
            display: inline-block;
            margin-top: 10px;
        }
        .status.running {
            background-color: #d4edda;
            color: #155724;
        }
        .status.error {
            background-color: #f8d7da;
            color: #721c24;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Docker Lab API Details</h1>
        
        <h2>Connection Information</h2>
        <div class="detail-box">
            <p><strong>API URL:</strong> <code>{{ api_url }}</code></p>
            <p><strong>Port:</strong> <code>{{ port }}</code></p>
            <p><strong>API Token:</strong> <code>{{ token }}</code></p>
        </div>

        <h2>Docker Status</h2>
        <div class="detail-box">
            <p><strong>Status:</strong> 
                <span class="status {% if docker_status == 'running' %}running{% else %}error{% endif %}">
                    {{ docker_status }}
                </span>
            </p>
            {% if docker_error %}
            <p><strong>Error:</strong> {{ docker_error }}</p>
            {% endif %}
        </div>

        <h2>Usage Instructions</h2>
        <div class="detail-box">
            <p>To connect to this API:</p>
            <ol>
                <li>Use the API URL and Port in your control panel</li>
                <li>Add the API Token in the Authorization header:<br>
                    <code>Authorization: Bearer {{ token }}</code></li>
                <li>Start managing your Docker containers!</li>
            </ol>
        </div>
    </div>
</body>
</html>
'''

# Docker client initialization with retry mechanism
def init_docker_client(max_retries=5, retry_interval=2):
    docker_socket = '/var/run/docker.sock'
    
    # Check if Docker socket exists
    if not os.path.exists(docker_socket):
        return None, f"Docker socket not found at {docker_socket}. Please make sure to mount it correctly."
    
    # Check if Docker socket is accessible
    if not os.access(docker_socket, os.R_OK | os.W_OK):
        return None, f"Docker socket at {docker_socket} is not accessible. Please check permissions."

    for attempt in range(max_retries):
        try:
            # Try to connect to Docker daemon
            client = docker.from_env()
            # Test the connection
            client.ping()
            print(f"Successfully connected to Docker daemon on attempt {attempt + 1}")
            return client, None
        except docker.errors.DockerException as e:
            error_msg = str(e)
            if 'FileNotFoundError' in error_msg:
                return None, "Docker socket not found or not accessible. Please check the container is running with '-v /var/run/docker.sock:/var/run/docker.sock'"
            elif 'PermissionError' in error_msg:
                return None, "Permission denied accessing Docker socket. Please check socket permissions."
            
            if attempt < max_retries - 1:
                print(f"Failed to connect to Docker daemon (attempt {attempt + 1}): {error_msg}")
                print(f"Retrying in {retry_interval} seconds...")
                time.sleep(retry_interval)
            else:
                print("Failed to connect to Docker daemon after all attempts")
                return None, f"Failed to connect to Docker daemon: {error_msg}"

docker_client, docker_error = init_docker_client()
docker_status = 'running' if docker_client else 'error'

def require_token(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token or token != f'Bearer {API_TOKEN}':
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

@app.route('/')
def index():
    # Get host information from request
    host = request.host.split(':')[0]  # Split to handle host:port format
    port = 5000  # We know we're running on port 5000

    return render_template_string(INDEX_TEMPLATE, 
        api_url=host,
        port=port,
        token=API_TOKEN,
        docker_status=docker_status,
        docker_error=docker_error
    )

@app.route('/containers', methods=['GET'])
@require_token
def list_containers():
    if not docker_client:
        return jsonify({'error': 'Docker client not initialized', 'details': docker_error}), 500
    
    try:
        containers = docker_client.containers.list(all=True)
        return jsonify([
            {
                'id': container.id,
                'name': container.name,
                'status': container.status,
                'image': container.image.tags[0] if container.image.tags else 'none',
                'ports': container.ports
            }
            for container in containers
        ])
    except docker.errors.APIError as e:
        return jsonify({'error': f'Docker API error: {str(e)}'}), 500

@app.route('/containers/<container_type>/start', methods=['POST'])
@require_token
def start_container(container_type):
    if not docker_client:
        return jsonify({'error': 'Docker client not initialized', 'details': docker_error}), 500

    try:
        if container_type not in ['apache', 'php']:
            return jsonify({'error': 'Invalid container type'}), 400

        # Container configurations
        configs = {
            'apache': {
                'image': 'httpd:latest',
                'ports': {'80/tcp': None},  # Random port
                'name': 'lab_apache'
            },
            'php': {
                'image': 'php:apache',
                'ports': {'80/tcp': None},  # Random port
                'name': 'lab_php'
            }
        }

        config = configs[container_type]

        # Check if container already exists
        existing = docker_client.containers.list(all=True, filters={'name': config['name']})
        if existing:
            container = existing[0]
            if container.status != 'running':
                container.start()
        else:
            container = docker_client.containers.run(
                image=config['image'],
                name=config['name'],
                ports=config['ports'],
                detach=True
            )

        # Get container info
        container.reload()
        port_info = next(iter(container.ports.values()))[0] if container.ports else None
        host_port = port_info['HostPort'] if port_info else None

        return jsonify({
            'status': 'running',
            'id': container.id,
            'name': container.name,
            'port': host_port,
            'ip': request.host.split(':')[0]
        })

    except docker.errors.APIError as e:
        return jsonify({'error': f'Docker API error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

@app.route('/containers/<container_type>/stop', methods=['POST'])
@require_token
def stop_container(container_type):
    if not docker_client:
        return jsonify({'error': 'Docker client not initialized', 'details': docker_error}), 500

    try:
        container_name = f'lab_{container_type}'
        containers = docker_client.containers.list(filters={'name': container_name})
        
        if not containers:
            return jsonify({'error': 'Container not found'}), 404

        container = containers[0]
        container.stop()

        return jsonify({
            'status': 'stopped',
            'id': container.id,
            'name': container.name
        })

    except docker.errors.APIError as e:
        return jsonify({'error': f'Docker API error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

@app.route('/containers/<container_type>/restart', methods=['POST'])
@require_token
def restart_container(container_type):
    if not docker_client:
        return jsonify({'error': 'Docker client not initialized', 'details': docker_error}), 500

    try:
        container_name = f'lab_{container_type}'
        containers = docker_client.containers.list(all=True, filters={'name': container_name})
        
        if not containers:
            return jsonify({'error': 'Container not found'}), 404

        container = containers[0]
        container.restart()
        container.reload()

        port_info = next(iter(container.ports.values()))[0] if container.ports else None
        host_port = port_info['HostPort'] if port_info else None

        return jsonify({
            'status': 'running',
            'id': container.id,
            'name': container.name,
            'port': host_port,
            'ip': request.host.split(':')[0]
        })

    except docker.errors.APIError as e:
        return jsonify({'error': f'Docker API error: {str(e)}'}), 500
    except Exception as e:
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

if __name__ == '__main__':
    # Print the API token when starting the server
    print(f'\nAPI Token: {API_TOKEN}\n')
    app.run(host='0.0.0.0', port=5000)