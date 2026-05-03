#!/usr/bin/env bash
# ============================================================
#  cyfoxgen-doclab v3  —  Web Dashboard + REST API
#  Usage:
#    bash install.sh
#    — or —
#    curl -fsSL https://raw.githubusercontent.com/... | bash
# ============================================================

set -euo pipefail

G='\033[0;32m'; B='\033[0;34m'; C='\033[0;36m'
Y='\033[0;33m'; R='\033[0;31m'; W='\033[1;37m'
D='\033[2m'; N='\033[0m'; BOLD='\033[1m'

log_step()  { echo -e "${C}${BOLD}[STEP]${N} ${W}$*${N}"; }
log_ok()    { echo -e "${G}  ✔  $*${N}"; }
log_warn()  { echo -e "${Y}  ⚠  $*${N}"; }
log_err()   { echo -e "${R}  ✘  $*${N}"; }
log_info()  { echo -e "${D}  ·  $*${N}"; }
separator() { echo -e "${D}────────────────────────────────────────────────────────${N}"; }

clear
echo -e "${G}"
cat << 'EOF'
  ____  ___  ____  __  __ ____  __  _  __   ____  ___  ____
 / __/ /  _// __/ / _]/ // ___]|  \| ||  ] /    ||   \|    |
/ /__ |  | / /__ | [_| / |___|  \\  | [  ||  o  ||    | |  |
\____||___| \___||___/ \_____||_|\_||____||     ||_\__|_|__|
     D O C K E R   L A B   M A N A G E R   v3.0
     W E B   D A S H B O A R D   E D I T I O N
EOF
echo -e "${N}"
separator
echo -e "  ${D}Web UI · REST API · Auto-cleanup · Live stats${N}"
separator
echo ""

# ── Detect OS ──────────────────────────────────────────────────────────────────
log_step "Detecting OS..."
OS=""; DISTRO=""; PKG_MGR=""

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"; log_ok "macOS"
elif grep -qEi "microsoft|wsl" /proc/version 2>/dev/null; then
    OS="wsl"; DISTRO=$(. /etc/os-release && echo "$ID"); log_ok "WSL ($DISTRO)"
elif [[ -f /etc/os-release ]]; then
    OS="linux"; DISTRO=$(. /etc/os-release && echo "$ID"); log_ok "Linux ($DISTRO)"
else
    log_err "Unsupported OS"; exit 1
fi

if [[ "$OS" == "macos" ]]; then PKG_MGR="brew"
elif command -v apt-get &>/dev/null; then PKG_MGR="apt"
elif command -v dnf &>/dev/null; then PKG_MGR="dnf"
elif command -v pacman &>/dev/null; then PKG_MGR="pacman"
else log_err "No package manager found"; exit 1
fi
log_info "Package manager: $PKG_MGR"
echo ""

# ── Python ─────────────────────────────────────────────────────────────────────
log_step "Checking Python 3..."
if command -v python3 &>/dev/null && python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)" 2>/dev/null; then
    log_ok "Python: $(python3 --version)"
else
    log_warn "Installing Python..."
    case "$PKG_MGR" in
        apt) sudo apt-get update -qq && sudo apt-get install -y -qq python3 python3-pip python3-venv ;;
        dnf) sudo dnf install -y -q python3 python3-pip ;;
        pacman) sudo pacman -Sy --noconfirm python python-pip ;;
        brew) brew install python@3 ;;
    esac
fi

# ── Python packages ────────────────────────────────────────────────────────────
log_step "Installing Python packages..."

if ! python3 -m pip --version &>/dev/null; then
    log_warn "pip not found — installing pip..."
    case "$PKG_MGR" in
        apt) sudo apt-get update -qq && sudo apt-get install -y -qq python3-pip ;;
        dnf) sudo dnf install -y -q python3-pip ;;
        pacman) sudo pacman -Sy --noconfirm python-pip ;;
        brew) python3 -m ensurepip --upgrade || true ;;
    esac
    if ! python3 -m pip --version &>/dev/null; then
        curl -sS https://bootstrap.pypa.io/get-pip.py | python3
    fi
fi

PIP_FLAGS=""
python3 -m pip help install 2>/dev/null | grep -q "break-system-packages" && PIP_FLAGS="--break-system-packages"
python3 -m pip install --quiet $PIP_FLAGS flask flask-cors docker requests 2>&1 | tail -2 | sed 's/^/  /'
log_ok "Packages ready"
echo ""

# ── Docker ─────────────────────────────────────────────────────────────────────
log_step "Checking Docker..."
DOCKER_CMD="docker"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    log_ok "Docker: $(docker --version | awk '{print $3}' | tr -d ',')"
else
    if ! command -v docker &>/dev/null; then
        log_warn "Installing Docker..."
        case "$PKG_MGR" in
            apt)
                sudo apt-get update -qq
                sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update -qq
                sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
                ;;
            dnf) sudo dnf install -y -q docker-ce docker-ce-cli containerd.io ;;
            pacman) sudo pacman -Sy --noconfirm docker ;;
            brew) brew install --cask docker; log_warn "Open Docker Desktop first, then re-run."; exit 0 ;;
        esac
    fi
    [[ "$OS" == "wsl" ]] && sudo service docker start &>/dev/null || sudo systemctl start docker &>/dev/null || true
    groups "$USER" | grep -q docker || sudo usermod -aG docker "$USER" 2>/dev/null || true
    docker info &>/dev/null 2>&1 || DOCKER_CMD="sudo docker"
fi
echo ""

# ── App directory ──────────────────────────────────────────────────────────────
APP_DIR="$HOME/.cyfoxgen-doclab"
mkdir -p "$APP_DIR"

# ── Write backend ──────────────────────────────────────────────────────────────
log_step "Writing backend..."
cat > "$APP_DIR/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""cyfoxgen DocLab v3 — Docker Lab Manager REST API"""

from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import docker, ipaddress, logging, os, threading, time, random, string, json

app = Flask(__name__, static_folder=None)
CORS(app, origins="*")
logging.basicConfig(level=logging.WARNING)

try:
    client = docker.from_env()
    client.ping()
    DOCKER_OK = True
except Exception as e:
    print(f"[WARN] Docker not available: {e}")
    DOCKER_OK = False
    client = None

containers = {}
network_mgr = None
system_logs = []
log_lock = threading.Lock()
START_TIME = time.time()

def add_log(msg, kind='info'):
    with log_lock:
        ts = time.strftime("%H:%M:%S")
        system_logs.append({'timestamp': ts, 'message': msg, 'type': kind, 'time': time.time()})
        if len(system_logs) > 500:
            system_logs.pop(0)

def gen_password(n=8):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choices(chars, k=n))

API_PASSWORD = os.environ.get("LAB_PASSWORD") or gen_password()

class NetworkManager:
    def __init__(self):
        self.net_name = "lab-network"
        self.subnet   = "172.20.0.0/16"
        self.gateway  = "172.20.0.1"
        self.pool = [str(ip) for ip in ipaddress.IPv4Network(self.subnet).hosts()][1:1000]
        self.used = set()
        self._setup()

    def _setup(self):
        if not DOCKER_OK: return
        try:
            self.network = client.networks.get(self.net_name)
            add_log(f"Using network: {self.net_name}", 'info')
        except docker.errors.NotFound:
            self.network = client.networks.create(
                self.net_name, driver="bridge", attachable=True,
                ipam=docker.types.IPAMConfig(pool_configs=[
                    docker.types.IPAMPool(subnet=self.subnet, gateway=self.gateway)
                ])
            )
            add_log(f"Created network: {self.net_name}", 'info')

    def next_ip(self):
        for ip in self.pool:
            if ip not in self.used:
                self.used.add(ip)
                return ip
        raise Exception("IP pool exhausted")

    def release(self, ip):
        self.used.discard(ip)

# ── Routes ─────────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    dashboard = open(os.path.join(os.path.dirname(__file__), 'dashboard.html'), 'r').read()
    return dashboard

@app.route('/health')
def health():
    uptime = int(time.time() - START_TIME)
    docker_version = ""
    if DOCKER_OK:
        try:
            docker_version = client.version().get('Version', '')
        except: pass
    return jsonify({
        "status": "ok",
        "password": API_PASSWORD,
        "uptime": uptime,
        "docker_ok": DOCKER_OK,
        "docker_version": docker_version,
        "containers": len(containers)
    })

@app.route('/system-logs')
def get_logs():
    with log_lock:
        return jsonify({"logs": list(system_logs)})

@app.route('/system-info')
def system_info():
    info = {"docker_ok": DOCKER_OK, "containers_count": len(containers)}
    if DOCKER_OK:
        try:
            di = client.info()
            info.update({
                "docker_version": client.version().get('Version', '?'),
                "total_containers": di.get('Containers', 0),
                "running_containers": di.get('ContainersRunning', 0),
                "images": di.get('Images', 0),
                "memory_total": di.get('MemTotal', 0),
                "cpus": di.get('NCPU', 0),
                "os": di.get('OperatingSystem', '?'),
                "kernel": di.get('KernelVersion', '?'),
            })
        except Exception as e:
            info["error"] = str(e)
    return jsonify(info)

@app.route('/images')
def list_images():
    if not DOCKER_OK:
        return jsonify({"images": []})
    try:
        imgs = []
        for img in client.images.list():
            tags = img.tags or ['<none>:<none>']
            imgs.append({
                "id": img.id[:19],
                "tags": tags,
                "size": img.attrs.get('Size', 0),
                "created": img.attrs.get('Created', '')
            })
        return jsonify({"images": imgs})
    except Exception as e:
        return jsonify({"images": [], "error": str(e)})

@app.route('/deploy', methods=['POST'])
def deploy():
    data = request.get_json() or {}
    if data.get('password') != API_PASSWORD:
        add_log("Unauthorized deploy attempt", 'error')
        return jsonify({"error": "Invalid password"}), 401
    if 'image' not in data:
        return jsonify({"error": "Missing 'image'"}), 400

    image  = data['image']
    name   = data.get('name', f"lab-{int(time.time())}")
    env    = data.get('environment', {})
    vols   = data.get('volumes', {})
    cmd    = data.get('command')
    ports  = data.get('ports', {})

    add_log(f"Deploying {name} ({image})", 'deployment')
    try:
        client.images.pull(image)
        add_log(f"Pulled: {image}", 'deployment')
    except Exception as e:
        add_log(f"Pull warning: {e}", 'warning')

    try:
        kwargs = dict(
            name=name, environment=env, volumes=vols,
            command=cmd, network=network_mgr.net_name,
            detach=True, remove=False
        )
        if ports:
            kwargs['ports'] = ports

        c = client.containers.run(image, **kwargs)
        c.reload()
        net = c.attrs['NetworkSettings']['Networks'].get(network_mgr.net_name, {})
        ip = net.get('IPAddress', 'n/a')
        exposed = list((c.attrs.get('Config', {}).get('ExposedPorts') or {}).keys())
        info = {
            'id': c.id, 'name': name, 'image': image, 'ip': ip,
            'status': c.status, 'ports': exposed, 'created': time.time(),
            'command': str(cmd or ''), 'env_count': len(env)
        }
        containers[c.id] = info
        add_log(f"Running: {name} @ {ip}", 'deployment')
        return jsonify({"success": True, "container": info}), 201
    except docker.errors.ImageNotFound:
        return jsonify({"error": f"Image not found: {image}"}), 404
    except Exception as e:
        add_log(f"Deploy failed: {e}", 'error')
        return jsonify({"error": str(e)}), 500

@app.route('/containers')
def list_containers():
    for cid in list(containers):
        try:
            c = client.containers.get(cid)
            c.reload()
            containers[cid]['status'] = c.status
            stats_raw = c.stats(stream=False)
            cpu_delta = stats_raw['cpu_stats']['cpu_usage']['total_usage'] - stats_raw['precpu_stats']['cpu_usage']['total_usage']
            sys_delta = stats_raw['cpu_stats']['system_cpu_usage'] - stats_raw['precpu_stats']['system_cpu_usage']
            num_cpus  = stats_raw['cpu_stats'].get('online_cpus', 1)
            cpu_pct   = round((cpu_delta / sys_delta) * num_cpus * 100, 1) if sys_delta > 0 else 0
            mem_usage = stats_raw['memory_stats'].get('usage', 0)
            mem_limit = stats_raw['memory_stats'].get('limit', 1)
            mem_pct   = round((mem_usage / mem_limit) * 100, 1)
            containers[cid]['cpu_pct'] = cpu_pct
            containers[cid]['mem_mb'] = round(mem_usage / 1024 / 1024, 1)
            containers[cid]['mem_pct'] = mem_pct
        except docker.errors.NotFound:
            info = containers.pop(cid)
            network_mgr.release(info.get('ip', ''))
        except Exception:
            pass
    return jsonify({"containers": list(containers.values())})

@app.route('/containers/<cid>')
def get_container(cid):
    if cid not in containers:
        return jsonify({"error": "Not found"}), 404
    try:
        c = client.containers.get(cid)
        containers[cid]['status'] = c.status
        return jsonify({"container": containers[cid]})
    except docker.errors.NotFound:
        containers.pop(cid, None)
        return jsonify({"error": "Not found"}), 404

@app.route('/containers/<cid>/stop', methods=['POST'])
def stop_container(cid):
    data = request.get_json() or {}
    if data.get('password') != API_PASSWORD:
        return jsonify({"error": "Invalid password"}), 401
    if cid not in containers:
        return jsonify({"error": "Not found"}), 404
    try:
        c = client.containers.get(cid)
        c.stop(timeout=5)
        containers[cid]['status'] = 'exited'
        add_log(f"Stopped: {containers[cid]['name']}", 'warning')
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/containers/<cid>/restart', methods=['POST'])
def restart_container(cid):
    data = request.get_json() or {}
    if data.get('password') != API_PASSWORD:
        return jsonify({"error": "Invalid password"}), 401
    if cid not in containers:
        return jsonify({"error": "Not found"}), 404
    try:
        c = client.containers.get(cid)
        c.restart(timeout=5)
        c.reload()
        containers[cid]['status'] = c.status
        add_log(f"Restarted: {containers[cid]['name']}", 'info')
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/containers/<cid>', methods=['DELETE'])
def remove_container(cid):
    data = request.get_json() or {}
    if data.get('password') != API_PASSWORD:
        return jsonify({"error": "Invalid password"}), 401
    if cid not in containers:
        return jsonify({"error": "Not found"}), 404
    try:
        c = client.containers.get(cid)
        c.remove(force=True)
        info = containers.pop(cid)
        network_mgr.release(info.get('ip', ''))
        add_log(f"Removed: {info['name']}", 'warning')
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/containers/<cid>/logs')
def container_logs(cid):
    if cid not in containers:
        return jsonify({"error": "Not found"}), 404
    try:
        n = int(request.args.get('tail', 200))
        c = client.containers.get(cid)
        return jsonify({"logs": c.logs(tail=n).decode('utf-8', errors='ignore')})
    except Exception as e:
        return jsonify({"logs": f"Error: {e}"})

@app.route('/cleanup', methods=['POST'])
def cleanup():
    data = request.get_json() or {}
    if data.get('password') != API_PASSWORD:
        return jsonify({"error": "Invalid password"}), 401
    removed = []
    for cid in list(containers):
        try:
            client.containers.get(cid).remove(force=True)
            info = containers.pop(cid)
            network_mgr.release(info.get('ip', ''))
            removed.append(info['name'])
        except Exception:
            containers.pop(cid, None)
    add_log(f"Cleanup: removed {len(removed)} containers", 'warning')
    return jsonify({"success": True, "removed": removed})

def _cleanup_loop():
    while True:
        time.sleep(30)
        for cid in list(containers):
            try:
                c = client.containers.get(cid)
                if c.status == 'exited':
                    c.remove()
                    info = containers.pop(cid, {})
                    network_mgr.release(info.get('ip', ''))
                    add_log(f"Auto-cleaned: {info.get('name', cid)}", 'info')
            except Exception:
                containers.pop(cid, None)

if __name__ == '__main__':
    network_mgr = NetworkManager()
    add_log("cyfoxgen DocLab v3 started", 'info')
    add_log(f"Password: {API_PASSWORD}", 'info')
    add_log("Web dashboard: http://localhost:62111", 'info')
    if DOCKER_OK:
        threading.Thread(target=_cleanup_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=62111, debug=False)
PYEOF

log_ok "Backend written"

# ── Write dashboard HTML ───────────────────────────────────────────────────────
log_step "Writing web dashboard..."
cat > "$APP_DIR/dashboard.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>cyfoxgen DocLab</title>
<style>
  :root {
    --bg: #0a0f0a;
    --bg2: #0f160f;
    --bg3: #141e14;
    --border: #1a2e1a;
    --border2: #1f3a1f;
    --green: #22c55e;
    --green2: #16a34a;
    --green3: #15803d;
    --green-dim: #14532d;
    --green-glow: rgba(34,197,94,0.15);
    --text: #e2ffe2;
    --text2: #86efac;
    --text3: #4ade80;
    --text-dim: #166534;
    --red: #ef4444;
    --red-dim: #7f1d1d;
    --yellow: #eab308;
    --yellow-dim: #713f12;
    --blue: #3b82f6;
    --radius: 6px;
    --font: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: var(--font); background: var(--bg); color: var(--text); font-size: 13px; min-height: 100vh; overflow-x: hidden; }

  /* ── Top bar ───────────────────────────────── */
  #topbar {
    display: flex; align-items: center; gap: 12px;
    padding: 10px 20px; background: #000;
    border-bottom: 1px solid var(--border2);
    position: sticky; top: 0; z-index: 100;
  }
  #topbar .logo { color: var(--green); font-size: 15px; font-weight: 700; letter-spacing: 2px; flex: 0 0 auto; }
  #topbar .logo span { color: var(--text-dim); }
  #pulse { width: 8px; height: 8px; border-radius: 50%; background: var(--green); animation: pulse 2s infinite; }
  @keyframes pulse { 0%,100% { box-shadow: 0 0 0 0 var(--green-glow); } 50% { box-shadow: 0 0 0 6px transparent; } }
  #status-text { font-size: 11px; color: var(--text3); }
  .spacer { flex: 1; }
  #uptime-badge { font-size: 11px; color: var(--text-dim); border: 1px solid var(--border); padding: 2px 8px; border-radius: var(--radius); }
  #pwd-badge {
    font-size: 11px; color: var(--green); border: 1px solid var(--green-dim);
    padding: 3px 10px; border-radius: var(--radius); background: var(--green-glow);
    cursor: pointer; user-select: none;
  }
  #pwd-badge:hover { background: rgba(34,197,94,0.25); }

  /* ── Stats strip ───────────────────────────── */
  #stats-bar {
    display: flex; gap: 0;
    border-bottom: 1px solid var(--border);
    background: var(--bg2);
  }
  .stat-cell {
    flex: 1; padding: 8px 16px; border-right: 1px solid var(--border);
    display: flex; flex-direction: column; gap: 2px;
  }
  .stat-cell:last-child { border-right: none; }
  .stat-label { font-size: 10px; color: var(--text-dim); text-transform: uppercase; letter-spacing: 1px; }
  .stat-value { font-size: 18px; color: var(--green); font-weight: 700; }
  .stat-value.dim { color: var(--text3); font-size: 14px; }

  /* ── Layout ────────────────────────────────── */
  #layout { display: flex; height: calc(100vh - 82px); }

  /* ── Left sidebar ──────────────────────────── */
  #sidebar {
    width: 280px; min-width: 220px;
    background: var(--bg2); border-right: 1px solid var(--border);
    display: flex; flex-direction: column; overflow: hidden;
  }
  .pane-title {
    padding: 10px 16px; font-size: 10px; text-transform: uppercase;
    letter-spacing: 2px; color: var(--text-dim); border-bottom: 1px solid var(--border);
    display: flex; align-items: center; justify-content: space-between;
  }
  .pane-title .count-badge {
    background: var(--green-dim); color: var(--green);
    padding: 1px 6px; border-radius: 10px; font-size: 10px;
  }
  #container-list { flex: 1; overflow-y: auto; }
  #container-list::-webkit-scrollbar { width: 4px; }
  #container-list::-webkit-scrollbar-track { background: var(--bg2); }
  #container-list::-webkit-scrollbar-thumb { background: var(--border2); border-radius: 2px; }

  .c-item {
    padding: 12px 16px; border-bottom: 1px solid var(--border);
    cursor: pointer; transition: background 0.1s;
    border-left: 3px solid transparent;
  }
  .c-item:hover { background: var(--bg3); }
  .c-item.selected { background: var(--bg3); border-left-color: var(--green); }
  .c-item.running { border-left-color: var(--green); }
  .c-item.exited { border-left-color: var(--red); opacity: 0.7; }
  .c-item.paused { border-left-color: var(--yellow); }
  .c-name { font-size: 13px; color: var(--text); font-weight: 500; margin-bottom: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .c-image { font-size: 11px; color: var(--text-dim); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .c-meta { display: flex; align-items: center; gap: 6px; margin-top: 4px; }
  .badge {
    font-size: 10px; padding: 1px 6px; border-radius: 3px; font-weight: 600;
  }
  .badge.running { background: var(--green-dim); color: var(--green); }
  .badge.exited { background: var(--red-dim); color: var(--red); }
  .badge.paused { background: var(--yellow-dim); color: var(--yellow); }
  .badge.created { background: #1e3a5f; color: var(--blue); }
  .c-ip { font-size: 10px; color: var(--text-dim); margin-left: auto; }

  #empty-state {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 8px;
    color: var(--text-dim); padding: 24px; text-align: center;
  }
  #empty-state .empty-icon { font-size: 32px; opacity: 0.3; }

  /* ── Actions below list ───────────────────── */
  #sidebar-actions { padding: 12px; border-top: 1px solid var(--border); display: flex; flex-direction: column; gap: 6px; }

  /* ── Right panel ─────────────────────────── */
  #main { flex: 1; display: flex; flex-direction: column; overflow: hidden; }

  /* ── Tab bar ─────────────────────────────── */
  #tabs {
    display: flex; border-bottom: 1px solid var(--border);
    background: var(--bg2);
  }
  .tab {
    padding: 10px 20px; font-size: 11px; text-transform: uppercase;
    letter-spacing: 1px; color: var(--text-dim); cursor: pointer;
    border-bottom: 2px solid transparent; transition: all 0.15s;
  }
  .tab:hover { color: var(--text3); }
  .tab.active { color: var(--green); border-bottom-color: var(--green); }

  /* ── Tab content ─────────────────────────── */
  .tab-content { display: none; flex: 1; overflow: auto; padding: 20px; }
  .tab-content.active { display: flex; flex-direction: column; gap: 16px; }
  .tab-content::-webkit-scrollbar { width: 4px; }
  .tab-content::-webkit-scrollbar-track { background: var(--bg); }
  .tab-content::-webkit-scrollbar-thumb { background: var(--border2); border-radius: 2px; }

  /* ── Detail cards ────────────────────────── */
  .detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .detail-card {
    background: var(--bg2); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 14px;
  }
  .detail-card h3 { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-dim); margin-bottom: 10px; }
  .kv-row { display: flex; justify-content: space-between; align-items: center; padding: 4px 0; border-bottom: 1px solid var(--border); }
  .kv-row:last-child { border-bottom: none; }
  .kv-key { color: var(--text-dim); font-size: 11px; }
  .kv-val { color: var(--text3); font-size: 11px; max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; text-align: right; }
  .kv-val.highlight { color: var(--green); font-weight: 600; }

  /* ── Meter bar ─────────────────────────── */
  .meter-row { display: flex; flex-direction: column; gap: 4px; padding: 6px 0; }
  .meter-header { display: flex; justify-content: space-between; font-size: 11px; }
  .meter-label { color: var(--text-dim); }
  .meter-val { color: var(--text3); }
  .meter-bar { height: 4px; background: var(--border2); border-radius: 2px; overflow: hidden; }
  .meter-fill { height: 100%; border-radius: 2px; transition: width 0.5s ease; }
  .meter-fill.cpu { background: var(--green); }
  .meter-fill.mem { background: var(--blue); }
  .meter-fill.high { background: var(--yellow); }
  .meter-fill.critical { background: var(--red); }

  /* ── Log viewer ──────────────────────────── */
  #log-output {
    background: #000; border: 1px solid var(--border);
    border-radius: var(--radius); padding: 12px;
    font-size: 12px; color: #a3e8a3;
    overflow-y: auto; flex: 1; min-height: 300px;
    white-space: pre-wrap; word-break: break-all;
    line-height: 1.6;
  }
  #log-output::-webkit-scrollbar { width: 4px; }
  #log-output::-webkit-scrollbar-thumb { background: var(--border2); }
  .log-controls { display: flex; gap: 8px; align-items: center; }
  .log-controls select { background: var(--bg2); border: 1px solid var(--border); color: var(--text); padding: 4px 8px; border-radius: var(--radius); font-family: var(--font); font-size: 12px; }

  /* ── Deploy form ─────────────────────────── */
  #deploy-form { max-width: 680px; }
  .form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .form-group { display: flex; flex-direction: column; gap: 4px; }
  .form-group.full { grid-column: span 2; }
  label { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-dim); }
  input, textarea, select {
    background: var(--bg2); border: 1px solid var(--border2);
    color: var(--text); padding: 8px 10px; border-radius: var(--radius);
    font-family: var(--font); font-size: 12px;
    transition: border-color 0.15s;
  }
  input:focus, textarea:focus { outline: none; border-color: var(--green3); }
  input::placeholder, textarea::placeholder { color: var(--text-dim); }
  textarea { resize: vertical; min-height: 60px; }
  .form-hint { font-size: 10px; color: var(--text-dim); }
  #deploy-result {
    margin-top: 12px; padding: 10px 14px; border-radius: var(--radius);
    font-size: 12px; display: none;
  }
  #deploy-result.success { background: var(--green-dim); border: 1px solid var(--green3); color: var(--green); }
  #deploy-result.error { background: var(--red-dim); border: 1px solid var(--red); color: var(--red); }

  /* ── System info tab ─────────────────────── */
  #sysinfo-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
  .info-card {
    background: var(--bg2); border: 1px solid var(--border); border-radius: var(--radius); padding: 14px;
  }
  .info-card .ic-val { font-size: 22px; color: var(--green); font-weight: 700; margin-bottom: 4px; }
  .info-card .ic-label { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: var(--text-dim); }

  /* ── Buttons ─────────────────────────────── */
  .btn {
    padding: 7px 14px; border-radius: var(--radius); font-family: var(--font);
    font-size: 12px; cursor: pointer; border: 1px solid;
    transition: all 0.1s; display: inline-flex; align-items: center; gap: 6px;
  }
  .btn:active { transform: scale(0.97); }
  .btn-primary { background: var(--green-dim); border-color: var(--green3); color: var(--green); }
  .btn-primary:hover { background: rgba(34,197,94,0.25); }
  .btn-danger { background: var(--red-dim); border-color: var(--red); color: var(--red); }
  .btn-danger:hover { background: rgba(239,68,68,0.25); }
  .btn-warn { background: var(--yellow-dim); border-color: var(--yellow); color: var(--yellow); }
  .btn-warn:hover { background: rgba(234,179,8,0.25); }
  .btn-ghost { background: transparent; border-color: var(--border2); color: var(--text2); }
  .btn-ghost:hover { background: var(--bg3); }
  .btn-group { display: flex; gap: 8px; flex-wrap: wrap; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }

  /* ── Action buttons ──────────────────────── */
  #container-actions {
    padding: 14px 20px; background: var(--bg2); border-top: 1px solid var(--border);
    display: flex; gap: 8px; align-items: center;
  }
  #container-actions .c-name-header { flex: 1; font-size: 14px; color: var(--green); font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* ── Syslog panel ────────────────────────── */
  #syslog-panel {
    height: 140px; background: #000; border-top: 1px solid var(--border2);
    overflow-y: auto; padding: 8px 12px; font-size: 11px; line-height: 1.8;
  }
  #syslog-panel::-webkit-scrollbar { width: 4px; }
  #syslog-panel::-webkit-scrollbar-thumb { background: var(--border2); }
  .syslog-entry { display: flex; gap: 8px; }
  .syslog-ts { color: var(--text-dim); flex: 0 0 60px; }
  .syslog-msg { flex: 1; }
  .syslog-msg.deployment { color: var(--green); }
  .syslog-msg.error { color: var(--red); }
  .syslog-msg.warning { color: var(--yellow); }
  .syslog-msg.info { color: var(--text2); }

  /* ── Images tab ──────────────────────────── */
  .img-row {
    display: flex; align-items: center; gap: 12px; padding: 10px 14px;
    background: var(--bg2); border: 1px solid var(--border); border-radius: var(--radius);
  }
  .img-tag { flex: 1; color: var(--text3); }
  .img-size { color: var(--text-dim); font-size: 11px; }
  .img-id { color: var(--text-dim); font-size: 11px; font-family: monospace; }

  /* ── Responsive ─────────────────────────── */
  @media (max-width: 700px) {
    #sidebar { width: 200px; }
    .detail-grid { grid-template-columns: 1fr; }
    .form-grid { grid-template-columns: 1fr; }
    .form-group.full { grid-column: span 1; }
  }

  /* ── Loading spinner ─────────────────────── */
  .spinner { display: inline-block; width: 14px; height: 14px; border: 2px solid var(--border2); border-top-color: var(--green); border-radius: 50%; animation: spin 0.7s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── Toast ───────────────────────────────── */
  #toast {
    position: fixed; bottom: 24px; right: 24px; z-index: 999;
    background: var(--bg3); border: 1px solid var(--border2);
    padding: 10px 16px; border-radius: var(--radius);
    font-size: 12px; color: var(--text); opacity: 0;
    transition: opacity 0.3s; pointer-events: none;
    max-width: 320px;
  }
  #toast.show { opacity: 1; }
  #toast.success { border-color: var(--green3); color: var(--green); }
  #toast.error { border-color: var(--red); color: var(--red); }
  #toast.warning { border-color: var(--yellow); color: var(--yellow); }

  /* ── No selection placeholder ────────────── */
  #no-selection {
    flex: 1; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 8px;
    color: var(--text-dim); text-align: center;
  }
  #no-selection .ns-icon { font-size: 40px; opacity: 0.2; margin-bottom: 8px; }
</style>
</head>
<body>

<!-- Top bar -->
<div id="topbar">
  <div class="logo">CYFOXGEN <span>DOCLAB</span></div>
  <div id="pulse"></div>
  <div id="status-text">connecting...</div>
  <div class="spacer"></div>
  <div id="uptime-badge">uptime: --</div>
  <div id="pwd-badge" onclick="copyPassword()" title="Click to copy">KEY: ••••••••</div>
</div>

<!-- Stats strip -->
<div id="stats-bar">
  <div class="stat-cell"><div class="stat-label">Running</div><div class="stat-value" id="s-running">0</div></div>
  <div class="stat-cell"><div class="stat-label">Total</div><div class="stat-value" id="s-total">0</div></div>
  <div class="stat-cell"><div class="stat-label">Images</div><div class="stat-value dim" id="s-images">—</div></div>
  <div class="stat-cell"><div class="stat-label">Docker</div><div class="stat-value dim" id="s-docker">—</div></div>
  <div class="stat-cell"><div class="stat-label">Host CPUs</div><div class="stat-value dim" id="s-cpu">—</div></div>
  <div class="stat-cell"><div class="stat-label">Host RAM</div><div class="stat-value dim" id="s-mem">—</div></div>
</div>

<!-- Main layout -->
<div id="layout">
  <!-- Sidebar -->
  <div id="sidebar">
    <div class="pane-title">
      Containers
      <span class="count-badge" id="cnt-badge">0</span>
    </div>
    <div id="container-list">
      <div id="empty-state">
        <div class="empty-icon">▣</div>
        <div>No containers</div>
        <div style="font-size:11px;margin-top:4px">Deploy one to get started</div>
      </div>
    </div>
    <div id="sidebar-actions">
      <button class="btn btn-primary" onclick="openDeploy()">+ Deploy</button>
      <button class="btn btn-ghost" onclick="refresh()">↻ Refresh</button>
    </div>
  </div>

  <!-- Right panel -->
  <div id="main">
    <!-- No selection state -->
    <div id="no-selection">
      <div class="ns-icon">◱</div>
      <div>Select a container</div>
      <div style="font-size:11px;margin-top:4px;color:var(--text-dim)">or deploy a new one</div>
    </div>

    <!-- Container detail view (hidden until selected) -->
    <div id="detail-view" style="display:none;flex-direction:column;flex:1;overflow:hidden;">
      <!-- Action bar -->
      <div id="container-actions">
        <div class="c-name-header" id="action-name">—</div>
        <button class="btn btn-warn" id="btn-restart" onclick="restartContainer()">↺ Restart</button>
        <button class="btn btn-warn" id="btn-stop" onclick="stopContainer()">■ Stop</button>
        <button class="btn btn-danger" id="btn-remove" onclick="removeContainer()">✕ Remove</button>
      </div>

      <!-- Tabs -->
      <div id="tabs">
        <div class="tab active" onclick="switchTab('overview')">Overview</div>
        <div class="tab" onclick="switchTab('logs')">Logs</div>
      </div>

      <!-- Overview tab -->
      <div class="tab-content active" id="tab-overview">
        <div class="detail-grid">
          <div class="detail-card">
            <h3>Container Info</h3>
            <div id="kv-container"></div>
          </div>
          <div class="detail-card">
            <h3>Resource Usage</h3>
            <div id="kv-resources"></div>
          </div>
        </div>
      </div>

      <!-- Logs tab -->
      <div class="tab-content" id="tab-logs" style="flex-direction:column;">
        <div class="log-controls">
          <select id="log-tail" onchange="loadLogs()">
            <option value="50">Last 50 lines</option>
            <option value="100">Last 100 lines</option>
            <option value="200" selected>Last 200 lines</option>
            <option value="500">Last 500 lines</option>
          </select>
          <button class="btn btn-ghost" onclick="loadLogs()">↻ Refresh</button>
          <button class="btn btn-ghost" onclick="copyLogs()">⎘ Copy</button>
        </div>
        <pre id="log-output">Select a container and click Logs</pre>
      </div>
    </div>
  </div>
</div>

<!-- Sys logs panel -->
<div style="border-top:1px solid var(--border);background:#000;display:flex;align-items:center;padding:0 12px;height:24px;">
  <span style="font-size:10px;color:var(--text-dim);text-transform:uppercase;letter-spacing:1px;flex:1;">System Logs</span>
  <span style="font-size:10px;color:var(--text-dim)">auto-scroll</span>
</div>
<div id="syslog-panel"></div>

<!-- Deploy modal overlay -->
<div id="modal-overlay" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,0.8);z-index:200;align-items:center;justify-content:center;">
  <div style="background:var(--bg2);border:1px solid var(--border2);border-radius:8px;padding:24px;width:min(620px,95vw);max-height:90vh;overflow-y:auto;">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
      <div style="font-size:14px;color:var(--green);font-weight:700;letter-spacing:1px;">DEPLOY CONTAINER</div>
      <button class="btn btn-ghost" onclick="closeModal()" style="padding:4px 10px;">✕</button>
    </div>
    <div id="deploy-form">
      <div class="form-grid">
        <div class="form-group">
          <label>Image *</label>
          <input type="text" id="f-image" placeholder="nginx:latest" />
        </div>
        <div class="form-group">
          <label>Container Name</label>
          <input type="text" id="f-name" placeholder="my-container" />
        </div>
        <div class="form-group">
          <label>Command (optional)</label>
          <input type="text" id="f-cmd" placeholder="bash -c 'echo hello'" />
        </div>
        <div class="form-group">
          <label>Port Mappings</label>
          <input type="text" id="f-ports" placeholder="8080:80,443:443" />
          <div class="form-hint">host:container pairs, comma-separated</div>
        </div>
        <div class="form-group full">
          <label>Environment Variables</label>
          <textarea id="f-env" placeholder="KEY=VALUE&#10;ANOTHER=thing"></textarea>
        </div>
        <div class="form-group full">
          <label>Volume Mounts</label>
          <textarea id="f-vols" placeholder="/host/path:/container/path&#10;/data:/app/data"></textarea>
          <div class="form-hint">host:container pairs, one per line</div>
        </div>
      </div>
      <div style="margin-top:16px;display:flex;gap:8px;">
        <button class="btn btn-primary" id="btn-deploy" onclick="deployContainer()">▶ Deploy</button>
        <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
      </div>
      <div id="deploy-result"></div>
    </div>
  </div>
</div>

<!-- Toast -->
<div id="toast"></div>

<script>
const API = '';
let password = '';
let containers = [];
let selectedId = null;
let refreshInterval = null;
let currentTab = 'overview';

async function apiFetch(method, path, body = null) {
  const opts = { method, headers: {'Content-Type':'application/json'} };
  if (body) opts.body = JSON.stringify({ ...body, password });
  const r = await fetch(API + path, opts);
  return r.json();
}

function showToast(msg, type = 'info', dur = 2500) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'show ' + type;
  setTimeout(() => t.className = '', dur);
}

function copyPassword() {
  navigator.clipboard.writeText(password).then(() => showToast('Password copied!', 'success'));
}

function copyLogs() {
  const txt = document.getElementById('log-output').textContent;
  navigator.clipboard.writeText(txt).then(() => showToast('Logs copied!', 'success'));
}

function fmtBytes(b) {
  if (!b) return '—';
  if (b > 1e9) return (b/1e9).toFixed(1) + ' GB';
  if (b > 1e6) return (b/1e6).toFixed(1) + ' MB';
  return (b/1e3).toFixed(0) + ' KB';
}

function fmtUptime(s) {
  if (s < 60) return s + 's';
  if (s < 3600) return Math.floor(s/60) + 'm ' + (s%60) + 's';
  return Math.floor(s/3600) + 'h ' + Math.floor((s%3600)/60) + 'm';
}

async function init() {
  try {
    const h = await fetch(API + '/health').then(r => r.json());
    password = h.password;
    document.getElementById('pwd-badge').textContent = 'KEY: ' + password;
    document.getElementById('status-text').textContent = 'connected · api:62111';
    document.getElementById('s-docker').textContent = h.docker_version || (h.docker_ok ? 'ok' : 'offline');
    loadSysInfo();
    refresh();
    refreshInterval = setInterval(refresh, 5000);
    setInterval(refreshSysLogs, 3000);
    setInterval(async () => {
      const h2 = await fetch(API + '/health').then(r => r.json()).catch(() => null);
      if (h2) document.getElementById('uptime-badge').textContent = 'uptime: ' + fmtUptime(h2.uptime);
    }, 2000);
  } catch(e) {
    document.getElementById('status-text').textContent = 'ERROR: cannot reach API';
    showToast('Cannot connect to API server', 'error', 5000);
  }
}

async function loadSysInfo() {
  const info = await apiFetch('GET', '/system-info').catch(() => null);
  if (!info) return;
  document.getElementById('s-cpu').textContent = info.cpus || '—';
  document.getElementById('s-mem').textContent = info.memory_total ? fmtBytes(info.memory_total) : '—';
  document.getElementById('s-images').textContent = info.images ?? '—';
}

async function refresh() {
  const data = await apiFetch('GET', '/containers').catch(() => null);
  if (!data) return;
  containers = (data.containers || []).filter(c => !c.name.includes('lab-manager'));
  renderList();
  const running = containers.filter(c => c.status === 'running').length;
  document.getElementById('s-running').textContent = running;
  document.getElementById('s-total').textContent = containers.length;
  document.getElementById('cnt-badge').textContent = containers.length;
  if (selectedId) {
    const sel = containers.find(c => c.id === selectedId);
    if (sel) updateDetail(sel);
  }
}

function renderList() {
  const list = document.getElementById('container-list');
  const empty = document.getElementById('empty-state');
  const existingItems = list.querySelectorAll('.c-item');
  const existingIds = new Set([...existingItems].map(el => el.dataset.id));
  const newIds = new Set(containers.map(c => c.id));

  // Remove gone
  existingItems.forEach(el => {
    if (!newIds.has(el.dataset.id)) el.remove();
  });

  // Add/update
  containers.forEach(c => {
    let el = list.querySelector(`[data-id="${c.id}"]`);
    const isSelected = c.id === selectedId;

    const statusClass = c.status === 'running' ? 'running' : c.status === 'exited' ? 'exited' : 'paused';
    const html = `
      <div class="c-name">${c.name}</div>
      <div class="c-image">${c.image}</div>
      <div class="c-meta">
        <span class="badge ${statusClass}">${c.status}</span>
        <span class="c-ip">${c.ip}</span>
      </div>
    `;

    if (!el) {
      el = document.createElement('div');
      el.className = 'c-item';
      el.dataset.id = c.id;
      el.addEventListener('click', () => selectContainer(c.id));
      list.appendChild(el);
    }
    el.innerHTML = html;
    el.className = `c-item ${statusClass}${isSelected ? ' selected' : ''}`;
  });

  empty.style.display = containers.length === 0 ? 'flex' : 'none';
}

function selectContainer(id) {
  selectedId = id;
  document.querySelectorAll('.c-item').forEach(el => {
    el.classList.toggle('selected', el.dataset.id === id);
  });
  const c = containers.find(x => x.id === id);
  if (!c) return;

  document.getElementById('no-selection').style.display = 'none';
  document.getElementById('detail-view').style.display = 'flex';
  document.getElementById('action-name').textContent = c.name;

  const isRunning = c.status === 'running';
  document.getElementById('btn-stop').disabled = !isRunning;
  document.getElementById('btn-restart').disabled = !isRunning;

  updateDetail(c);
  if (currentTab === 'logs') loadLogs();
}

function updateDetail(c) {
  // Container KV
  const kvHtml = (rows) => rows.map(([k,v,hl]) =>
    `<div class="kv-row"><span class="kv-key">${k}</span><span class="kv-val${hl?' highlight':''}">${v}</span></div>`
  ).join('');

  const age = c.created ? fmtUptime(Math.floor(Date.now()/1000 - c.created)) : '—';
  document.getElementById('kv-container').innerHTML = kvHtml([
    ['Status', c.status, c.status === 'running'],
    ['Name', c.name],
    ['Image', c.image.split('/').pop()],
    ['IP', c.ip, true],
    ['ID', c.id.slice(0,12)+'...'],
    ['Ports', (c.ports||[]).join(', ') || 'none'],
    ['Env vars', c.env_count || 0],
    ['Uptime', age],
  ]);

  // Resources
  const cpu = c.cpu_pct ?? 0;
  const mem = c.mem_pct ?? 0;
  const cpuClass = cpu > 80 ? 'critical' : cpu > 50 ? 'high' : 'cpu';
  const memClass = mem > 80 ? 'critical' : mem > 60 ? 'high' : 'mem';
  document.getElementById('kv-resources').innerHTML = `
    <div class="meter-row">
      <div class="meter-header"><span class="meter-label">CPU</span><span class="meter-val">${cpu}%</span></div>
      <div class="meter-bar"><div class="meter-fill ${cpuClass}" style="width:${Math.min(cpu,100)}%"></div></div>
    </div>
    <div class="meter-row">
      <div class="meter-header"><span class="meter-label">Memory</span><span class="meter-val">${c.mem_mb ?? 0} MB (${mem}%)</span></div>
      <div class="meter-bar"><div class="meter-fill ${memClass}" style="width:${Math.min(mem,100)}%"></div></div>
    </div>
    ${kvHtml([
      ['Network', c.ip ? 'lab-network' : '—'],
      ['Command', c.command || '—'],
    ])}
  `;
}

async function loadLogs() {
  if (!selectedId) return;
  const tail = document.getElementById('log-tail').value;
  const out = document.getElementById('log-output');
  out.textContent = 'Loading...';
  const data = await apiFetch('GET', `/containers/${selectedId}/logs?tail=${tail}`).catch(() => null);
  out.textContent = data?.logs || '(no output)';
  out.scrollTop = out.scrollHeight;
}

function switchTab(name) {
  currentTab = name;
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
  const idx = ['overview','logs'].indexOf(name);
  document.querySelectorAll('.tab')[idx].classList.add('active');
  document.getElementById('tab-' + name).classList.add('active');
  if (name === 'logs') loadLogs();
}

async function stopContainer() {
  if (!selectedId) return;
  if (!confirm('Stop this container?')) return;
  const r = await apiFetch('POST', `/containers/${selectedId}/stop`);
  showToast(r.success ? 'Container stopped' : 'Error: ' + r.error, r.success ? 'warning' : 'error');
  refresh();
}

async function restartContainer() {
  if (!selectedId) return;
  const r = await apiFetch('POST', `/containers/${selectedId}/restart`);
  showToast(r.success ? 'Container restarted' : 'Error: ' + r.error, r.success ? 'success' : 'error');
  refresh();
}

async function removeContainer() {
  if (!selectedId) return;
  const c = containers.find(x => x.id === selectedId);
  if (!confirm(`Remove ${c?.name}? This cannot be undone.`)) return;
  const r = await apiFetch('DELETE', `/containers/${selectedId}`);
  if (r.success) {
    showToast('Container removed', 'warning');
    selectedId = null;
    document.getElementById('detail-view').style.display = 'none';
    document.getElementById('no-selection').style.display = 'flex';
  } else {
    showToast('Error: ' + r.error, 'error');
  }
  refresh();
}

function openDeploy() {
  document.getElementById('modal-overlay').style.display = 'flex';
  document.getElementById('f-image').focus();
  document.getElementById('deploy-result').style.display = 'none';
}

function closeModal() {
  document.getElementById('modal-overlay').style.display = 'none';
}

async function deployContainer() {
  const image = document.getElementById('f-image').value.trim();
  if (!image) { showToast('Image is required', 'error'); return; }

  const name = document.getElementById('f-name').value.trim() || `lab-${Date.now()}`;
  const cmd  = document.getElementById('f-cmd').value.trim();
  const envRaw = document.getElementById('f-env').value.trim();
  const volsRaw = document.getElementById('f-vols').value.trim();
  const portsRaw = document.getElementById('f-ports').value.trim();

  const environment = {};
  envRaw.split('\n').filter(Boolean).forEach(line => {
    const [k, ...v] = line.split('=');
    if (k) environment[k.trim()] = v.join('=').trim();
  });

  const volumes = {};
  volsRaw.split('\n').filter(Boolean).forEach(line => {
    const [h, c] = line.split(':');
    if (h && c) volumes[h.trim()] = { bind: c.trim(), mode: 'rw' };
  });

  const ports = {};
  portsRaw.split(',').filter(Boolean).forEach(p => {
    const [h, c] = p.trim().split(':');
    if (h && c) ports[c + '/tcp'] = h;
  });

  const btn = document.getElementById('btn-deploy');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Deploying...';

  const result = document.getElementById('deploy-result');
  result.style.display = 'none';

  try {
    const r = await apiFetch('POST', '/deploy', { image, name, environment, volumes, ports, command: cmd || undefined });
    if (r.success) {
      result.className = 'success';
      result.textContent = `✔ Deployed: ${r.container.name} @ ${r.container.ip}`;
      result.style.display = 'block';
      showToast(`Deployed ${name}!`, 'success', 3000);
      refresh();
      setTimeout(closeModal, 1500);
    } else {
      result.className = 'error';
      result.textContent = '✘ ' + (r.error || 'Unknown error');
      result.style.display = 'block';
    }
  } catch(e) {
    result.className = 'error';
    result.textContent = '✘ Network error: ' + e.message;
    result.style.display = 'block';
  }

  btn.disabled = false;
  btn.innerHTML = '▶ Deploy';
}

async function refreshSysLogs() {
  const data = await fetch(API + '/system-logs').then(r=>r.json()).catch(()=>null);
  if (!data) return;
  const panel = document.getElementById('syslog-panel');
  const logs = (data.logs || []).slice(-40);
  panel.innerHTML = logs.map(l =>
    `<div class="syslog-entry"><span class="syslog-ts">[${l.timestamp}]</span><span class="syslog-msg ${l.type}">${l.message}</span></div>`
  ).join('');
  panel.scrollTop = panel.scrollHeight;
}

// Close modal on overlay click
document.getElementById('modal-overlay').addEventListener('click', function(e) {
  if (e.target === this) closeModal();
});

// Keyboard shortcuts
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeModal();
  if (e.key === 'n' && !e.target.matches('input,textarea')) openDeploy();
  if (e.key === 'r' && !e.target.matches('input,textarea')) refresh();
});

init();
</script>
</body>
</html>
HTMLEOF

log_ok "Dashboard written"
echo ""

# ── Start backend ──────────────────────────────────────────────────────────────
log_step "Starting DocLab v3..."

pkill -f "app.py" 2>/dev/null || true
sleep 1

LOG_FILE="$APP_DIR/server.log"
$DOCKER_CMD network create lab-network 2>/dev/null || true

# Clean old containers
log_step "Removing old session containers..."
OLD=$($DOCKER_CMD ps -a --filter "network=lab-network" --format "{{.Names}}" 2>/dev/null | grep "^lab-" || true)
if [[ -n "$OLD" ]]; then
    echo "$OLD" | while read -r n; do $DOCKER_CMD rm -f "$n" >/dev/null 2>&1 && log_ok "Removed: $n" || true; done
else
    log_info "No old containers"
fi

nohup python3 "$APP_DIR/app.py" > "$LOG_FILE" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$APP_DIR/app.pid"

echo -ne "  ${D}Starting server"
for i in {1..20}; do
    sleep 0.5
    curl -sf http://localhost:62111/health >/dev/null 2>&1 && break
    echo -ne "."
done
echo -e "${N}"

if ! curl -sf http://localhost:62111/health >/dev/null 2>&1; then
    log_err "Server failed. Check: $LOG_FILE"
    tail -20 "$LOG_FILE"
    exit 1
fi

LAB_PASSWORD=$(curl -sf http://localhost:62111/health | python3 -c "import sys,json;print(json.load(sys.stdin)['password'])" 2>/dev/null || echo "see-log")

log_ok "Server running! PID: $APP_PID"
echo ""
separator
echo -e "  ${G}${BOLD}✔ cyfoxgen DocLab v3 is running!${N}"
echo ""
echo -e "  ${W}Web Dashboard:${N}  ${C}http://localhost:62111${N}"
echo -e "  ${W}API Password:${N}   ${Y}$LAB_PASSWORD${N}"
echo -e "  ${W}Server log:${N}     ${D}$LOG_FILE${N}"
echo ""
echo -e "  ${D}Stop server:   pkill -f app.py${N}"
echo -e "  ${D}View logs:     tail -f $LOG_FILE${N}"
separator
echo ""

# ── Open browser (best-effort) ─────────────────────────────────────────────────
if command -v xdg-open &>/dev/null; then
    xdg-open http://localhost:62111 &>/dev/null &
elif command -v open &>/dev/null; then
    open http://localhost:62111 &>/dev/null &
fi

log_ok "Done! Open http://localhost:62111 in your browser."