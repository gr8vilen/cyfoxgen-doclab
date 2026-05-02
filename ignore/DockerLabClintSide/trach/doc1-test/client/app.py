from flask import Flask, jsonify, request
import docker
import os
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Initialize Docker client
client = docker.from_env()

# Configuration
API_PASSWORD = os.environ.get('API_PASSWORD', 'your_secure_password_here')

def authenticate(request):
    auth_password = request.headers.get('X-API-Password')
    return auth_password == API_PASSWORD

@app.route('/')
def home():
    return '''
    <html>
        <head>
            <title>Docker Management API</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                .info-box { 
                    background: #f0f0f0; 
                    padding: 20px; 
                    border-radius: 5px; 
                    margin-bottom: 20px; 
                }
                .key { font-weight: bold; }
            </style>
        </head>
        <body>
            <h1>Docker Management API</h1>
            <div class="info-box">
                <p><span class="key">API URL:</span> http://localhost:5000</p>
                <p><span class="key">Port:</span> 5000</p>
                <p><span class="key">Password:</span> ''' + API_PASSWORD + '''</p>
            </div>
            <p>Use these credentials in the main control panel to manage Docker containers.</p>
        </body>
    </html>
    '''

@app.route('/containers', methods=['GET'])
def list_containers():
    if not authenticate(request):
        return jsonify({'error': 'Unauthorized'}), 401
    
    containers = client.containers.list(all=True)
    container_list = [{
        'id': container.id,
        'name': container.name,
        'status': container.status,
        'image': container.image.tags[0] if container.image.tags else 'none',
        'ports': container.ports
    } for container in containers]
    
    return jsonify(container_list)

@app.route('/containers/start/<container_id>', methods=['POST'])
def start_container(container_id):
    if not authenticate(request):
        return jsonify({'error': 'Unauthorized'}), 401
    
    try:
        container = client.containers.get(container_id)
        container.start()
        return jsonify({'status': 'success', 'message': f'Container {container_id} started'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/containers/stop/<container_id>', methods=['POST'])
def stop_container(container_id):
    if not authenticate(request):
        return jsonify({'error': 'Unauthorized'}), 401
    
    try:
        container = client.containers.get(container_id)
        container.stop()
        return jsonify({'status': 'success', 'message': f'Container {container_id} stopped'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/containers/restart/<container_id>', methods=['POST'])
def restart_container(container_id):
    if not authenticate(request):
        return jsonify({'error': 'Unauthorized'}), 401
    
    try:
        container = client.containers.get(container_id)
        container.restart()
        return jsonify({'status': 'success', 'message': f'Container {container_id} restarted'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)