#!/usr/bin/env bash
# ============================================================
#  cyfoxgen-doclab  —  One-file installer + terminal dashboard
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/gr8vilen/cyfoxgen-doclab/main/install.sh | bash
#    — or —
#    bash install.sh
# ============================================================

set -euo pipefail

# ───────────────────────────── COLOURS ──────────────────────
G='\033[0;32m'   # green
B='\033[0;34m'   # blue
C='\033[0;36m'   # cyan
Y='\033[0;33m'   # yellow
R='\033[0;31m'   # red
W='\033[1;37m'   # white bold
D='\033[2m'      # dim
N='\033[0m'      # reset
BOLD='\033[1m'

# ───────────────────────────── HELPERS ──────────────────────
log_step()  { echo -e "${C}${BOLD}[STEP]${N} ${W}$*${N}"; }
log_ok()    { echo -e "${G}  ✔  $*${N}"; }
log_warn()  { echo -e "${Y}  ⚠  $*${N}"; }
log_err()   { echo -e "${R}  ✘  $*${N}"; }
log_info()  { echo -e "${D}  ·  $*${N}"; }
separator() { echo -e "${D}────────────────────────────────────────────────────────${N}"; }

# ───────────────────────────── BANNER ───────────────────────
clear
echo -e "${G}"
cat << 'EOF'
   ____  ____  ____  __  __ ____  __  _  __   ____  ___  ____
  / __/ /  _/ / __/ / _]/ // ___]|  \| ||  ] /    ||   \|    |
 / /__ |  |  / /__  | [_| / |___|  \\  | [  ||  o  ||    | |  |
/_____||___| /____| |___/ \_____||_|\_||____||     ||_\__|_|__|
      D O C K E R   L A B   M A N A G E R   —   v1.0
EOF
echo -e "${N}"
separator
echo -e "  ${D}One-file installer · Auto-detects OS · Opens terminal UI${N}"
separator
echo ""

# ───────────────────────────── DETECT OS ────────────────────
log_step "Detecting operating system..."

OS=""
DISTRO=""
PKG_MGR=""

if [[ -n "${PREFIX:-}" && "${PREFIX:-}" == *"/com.termux/"* ]]; then
    OS="termux"
    log_err "Android (Termux) detected. Docker Engine cannot run natively on Android without root and custom kernels."
    log_warn "If you are trying to connect to a remote Docker host, you need to set DOCKER_HOST manually."
    log_warn "This installer is currently for Linux, macOS, and Windows WSL."
    exit 1
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    log_ok "macOS detected"
elif grep -qEi "microsoft|wsl" /proc/version 2>/dev/null; then
    OS="wsl"
    DISTRO=$(. /etc/os-release && echo "$ID")
    log_ok "Windows WSL detected (distro: $DISTRO)"
elif [[ -f /etc/os-release ]]; then
    OS="linux"
    DISTRO=$(. /etc/os-release && echo "$ID")
    log_ok "Linux detected (distro: $DISTRO)"
else
    log_err "Could not detect OS. Supported: Linux, macOS, Windows WSL"
    exit 1
fi

# Determine package manager
if [[ "$OS" == "termux" ]]; then
    PKG_MGR="pkg"
elif [[ "$OS" == "macos" ]]; then
    PKG_MGR="brew"
elif command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
else
    log_err "No supported package manager found (apt/dnf/yum/pacman/brew)"
    exit 1
fi

log_info "Package manager: $PKG_MGR"
echo ""

# ───────────────────────────── CHECK / INSTALL DEPS ─────────

# Helper: silent sudo apt-get install
apt_install() {
    sudo apt-get install -y -qq "$@" 2>&1 | grep -v "^$" | sed 's/^/  /' || true
}
dnf_install() {
    sudo dnf install -y -q "$@" 2>&1 | sed 's/^/  /' || true
}
brew_install() {
    brew install "$@" 2>&1 | tail -3 | sed 's/^/  /' || true
}

# ── 1. Python 3 ──────────────────────────────────────────────
log_step "Checking Python 3..."
if command -v python3 &>/dev/null && python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)" 2>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    log_ok "Python already installed: $PY_VER"
else
    log_warn "Python 3.8+ not found — installing..."
    case "$PKG_MGR" in
        apt)     sudo apt-get update -qq && apt_install python3 python3-pip python3-venv ;;
        dnf|yum) dnf_install python3 python3-pip ;;
        pacman)  sudo pacman -Sy --noconfirm python python-pip ;;
        brew)    brew_install python@3 ;;
    esac
    log_ok "Python 3 installed: $(python3 --version)"
fi

# ── 2. pip packages ──────────────────────────────────────────
log_step "Checking Python packages..."
MISSING_PKGS=()
for pkg in flask flask_cors docker requests; do
    python3 -c "import $pkg" 2>/dev/null || MISSING_PKGS+=("$pkg")
done

if [[ ${#MISSING_PKGS[@]} -eq 0 ]]; then
    log_ok "All Python packages present"
else
    log_warn "Installing: ${MISSING_PKGS[*]}"
    python3 -m pip install --quiet flask flask-cors docker requests 2>&1 | tail -2 | sed 's/^/  /'
    log_ok "Packages installed"
fi

# ── 3. Docker ────────────────────────────────────────────────
log_step "Checking Docker..."
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    log_ok "Docker running: v$DOCKER_VER"
else
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not found — installing..."
        case "$PKG_MGR" in
            apt)
                sudo apt-get update -qq
                apt_install ca-certificates curl gnupg lsb-release
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                  https://download.docker.com/linux/ubuntu \
                  $(lsb_release -cs) stable" | \
                  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update -qq
                apt_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
                ;;
            dnf|yum)
                sudo "$PKG_MGR" install -y -q yum-utils
                sudo yum-config-manager --add-repo \
                    https://download.docker.com/linux/centos/docker-ce.repo
                dnf_install docker-ce docker-ce-cli containerd.io
                ;;
            pacman)
                sudo pacman -Sy --noconfirm docker
                ;;
            brew)
                log_warn "On macOS, installing Docker via Homebrew Cask..."
                brew install --cask docker 2>&1 | tail -3 | sed 's/^/  /'
                log_warn "Please open Docker Desktop to finish setup, then re-run this script."
                exit 0
                ;;
        esac
        log_ok "Docker installed"
    fi

    log_warn "Starting Docker daemon..."
    if [[ "$OS" == "wsl" ]]; then
        sudo service docker start &>/dev/null || true
    else
        sudo systemctl enable docker &>/dev/null || true
        sudo systemctl start docker &>/dev/null || true
    fi

    # Add user to docker group
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        log_warn "Added $USER to docker group (may need re-login for group to apply)"
    fi

    # Use sudo docker if group not yet active
    if ! docker info &>/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
        log_warn "Using 'sudo docker' for this session"
    else
        DOCKER_CMD="docker"
    fi
    log_ok "Docker is running"
fi

DOCKER_CMD="${DOCKER_CMD:-docker}"
echo ""

# ───────────────────────────── WRITE APP.PY ─────────────────
log_step "Writing Docker Lab Manager app..."

APP_DIR="$HOME/.cyfoxgen-doclab"
mkdir -p "$APP_DIR"

cat > "$APP_DIR/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
cyfoxgen-doclab — Docker Lab Manager
API + Web Dashboard
"""

from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import docker
import ipaddress
import logging
import os
import threading
import time
import random
import string

app = Flask(__name__)
CORS(app, origins="*", methods=["GET","POST","DELETE","OPTIONS"],
     allow_headers=["Content-Type","Authorization","Accept","Origin","X-Requested-With"])

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)

client = docker.from_env()

containers  = {}
network_mgr = None
system_logs = []
log_lock    = threading.Lock()

def add_log(msg, kind='info'):
    with log_lock:
        ts = time.strftime("%H:%M:%S")
        system_logs.append({'timestamp': ts, 'message': msg, 'type': kind})
        if len(system_logs) > 200:
            system_logs.pop(0)

def gen_password(n=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=n))

API_PASSWORD = os.environ.get("LAB_PASSWORD") or gen_password()

class NetworkManager:
    def __init__(self):
        self.net_name = "lab-network"
        self.subnet   = "172.20.0.0/16"
        self.gateway  = "172.20.0.1"
        self.pool     = [str(ip) for ip in ipaddress.IPv4Network(self.subnet, strict=False).hosts()][1:500]
        self.used     = set()
        self._setup()

    def _setup(self):
        try:
            self.network = client.networks.get(self.net_name)
            add_log(f"Using existing network: {self.net_name}")
        except docker.errors.NotFound:
            self.network = client.networks.create(
                self.net_name, driver="bridge", attachable=True,
                ipam=docker.types.IPAMConfig(pool_configs=[
                    docker.types.IPAMPool(subnet=self.subnet, gateway=self.gateway)
                ])
            )
            add_log(f"Created network: {self.net_name}")

    def next_ip(self):
        for ip in self.pool:
            if ip not in self.used:
                self.used.add(ip)
                return ip
        raise Exception("IP pool exhausted")

    def release(self, ip):
        self.used.discard(ip)

DASHBOARD = '''<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>🐳 cyfoxgen DocLab</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0a0a0a;color:#00ff00;font-family:"Courier New",monospace;min-height:100vh}
canvas{position:fixed;top:0;left:0;width:100%;height:100%;z-index:-1;opacity:.08}
.hdr{background:#000;border-bottom:2px solid #00ff00;padding:18px 24px;
     box-shadow:0 4px 20px rgba(0,255,0,.25);display:flex;align-items:center;gap:20px}
.hdr h1{font-size:1.6em;text-shadow:0 0 8px #00ff00;flex:1}
.pill{background:rgba(0,40,0,.8);border:1px solid #00ff00;border-radius:6px;
      padding:6px 14px;font-size:.85em}
.pill span{color:#ffff00;font-weight:bold}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:16px;
      height:calc(100vh - 90px)}
.panel{background:rgba(0,15,0,.9);border:1px solid #00ff00;border-radius:10px;
       padding:16px;display:flex;flex-direction:column;overflow:hidden}
.panel h2{color:#00ff00;margin-bottom:10px;padding-bottom:8px;
          border-bottom:1px solid #1a3a1a;font-size:1em;flex-shrink:0}
.scroll{flex:1;overflow-y:auto;background:#000;border:1px solid #1a1a1a;
        border-radius:4px;padding:8px;font-size:12px;line-height:1.6}
.scroll::-webkit-scrollbar{width:6px}
.scroll::-webkit-scrollbar-thumb{background:#00ff00;border-radius:3px}
.log-info{color:#00cc00}.log-warning{color:#ffff00}
.log-error{color:#ff4444}.log-deployment{color:#00ffff}
.card{background:linear-gradient(135deg,#001100,#002200);border:1px solid #00ff00;
      border-radius:8px;padding:12px;margin-bottom:10px;flex-shrink:0}
.card-name{color:#00ffff;font-weight:bold;font-size:.95em}
.card-ip{color:#ffff00;font-size:.85em;margin:2px 0}
.card-img{color:#666;font-size:.8em}
.badge{display:inline-block;padding:2px 8px;border-radius:3px;
       font-size:.7em;font-weight:bold;float:right}
.badge-running{background:#00ff00;color:#000}
.badge-exited{background:#ff4444;color:#fff}
.card-logs{background:#000;border:1px solid #1a1a1a;border-radius:3px;
           padding:6px;margin-top:8px;font-size:11px;max-height:100px;overflow-y:auto;
           line-height:1.4;color:#888}
.empty{color:#444;text-align:center;margin-top:40px;font-size:.9em}
</style></head>
<body>
<canvas id="mx"></canvas>
<div class="hdr">
  <h1>🐳 cyfoxgen DocLab</h1>
  <div class="pill">Port <span>62111</span></div>
  <div class="pill">Password <span>{{ password }}</span></div>
</div>
<div class="grid">
  <div class="panel">
    <h2>📋 System Logs</h2>
    <div class="scroll" id="syslog"></div>
  </div>
  <div class="panel">
    <h2>🚀 Containers <span id="cnt" style="color:#666;font-weight:normal"></span></h2>
    <div class="scroll" id="clist"></div>
  </div>
</div>
<script>
const mx=document.getElementById('mx'),ctx=mx.getContext('2d');
mx.width=innerWidth;mx.height=innerHeight;
const cols=mx.width/10,drops=Array(Math.floor(cols)).fill(1);
const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&*';
setInterval(()=>{
  ctx.fillStyle='rgba(0,0,0,.05)';ctx.fillRect(0,0,mx.width,mx.height);
  ctx.fillStyle='#00ff00';ctx.font='10px monospace';
  drops.forEach((y,i)=>{
    ctx.fillText(chars[Math.random()*chars.length|0],i*10,y*10);
    if(y*10>mx.height&&Math.random()>.975)drops[i]=0;
    drops[i]++;
  });
},40);

async function loadLogs(){
  const r=await fetch('/system-logs');const d=await r.json();
  const el=document.getElementById('syslog');
  el.innerHTML=d.logs.map(l=>`<div class="log-${l.type}">[${l.timestamp}] ${l.message}</div>`).join('');
  el.scrollTop=el.scrollHeight;
}
async function loadContainers(){
  const r=await fetch('/containers');const d=await r.json();
  const el=document.getElementById('clist');
  const list=d.containers.filter(c=>!c.name.includes('docker-lab'));
  document.getElementById('cnt').textContent=`(${list.length})`;
  if(!list.length){el.innerHTML='<div class="empty">No containers deployed yet</div>';return;}
  el.innerHTML='';
  for(const c of list){
    const div=document.createElement('div');div.className='card';
    div.innerHTML=`
      <span class="badge badge-${c.status}">${c.status.toUpperCase()}</span>
      <div class="card-name">📦 ${c.name}</div>
      <div class="card-ip">🌐 ${c.ip}</div>
      <div class="card-img">${c.image}</div>
      <div class="card-logs" id="cl-${c.id}">loading...</div>`;
    el.appendChild(div);
    fetch(`/containers/${c.id}/logs`).then(r=>r.json()).then(d=>{
      const lg=document.getElementById('cl-'+c.id);
      if(lg)lg.innerHTML=d.logs?d.logs.split('\\n').filter(Boolean).slice(-15).join('<br>'):'<em>no logs yet</em>';
    }).catch(()=>{});
  }
}
loadLogs();loadContainers();
setInterval(loadLogs,2000);
setInterval(loadContainers,3000);
</script></body></html>'''

@app.route('/')
def dashboard():
    return render_template_string(DASHBOARD, password=API_PASSWORD)

@app.route('/system-logs')
def get_logs():
    with log_lock:
        return jsonify({"logs": list(system_logs)})

@app.route('/health')
def health():
    return jsonify({"status": "ok", "containers": len(containers), "password": API_PASSWORD})

@app.route('/deploy', methods=['POST'])
def deploy():
    data = request.get_json() or {}
    if data.get('password') != API_PASSWORD:
        add_log("Unauthorized deploy attempt", 'error')
        return jsonify({"error": "Invalid password"}), 401
    if 'image' not in data:
        return jsonify({"error": "Missing 'image'"}), 400

    image   = data['image']
    name    = data.get('name', f"lab-{int(time.time())}")
    env     = data.get('environment', {})
    vols    = data.get('volumes', {})
    cmd     = data.get('command')

    add_log(f"Deploying {name} ({image})", 'deployment')
    try:
        client.images.pull(image)
        add_log(f"Image pulled: {image}", 'deployment')
    except Exception as e:
        add_log(f"Pull warning: {e}", 'warning')

    try:
        c = client.containers.run(
            image, name=name, environment=env, volumes=vols,
            command=cmd, network=network_mgr.net_name,
            detach=True, remove=False
        )
        c.reload()
        ip = c.attrs['NetworkSettings']['Networks'][network_mgr.net_name]['IPAddress']
        ports = list((c.attrs.get('Config',{}).get('ExposedPorts') or {}).keys())
        info = {'id': c.id, 'name': name, 'image': image, 'ip': ip,
                'status': c.status, 'ports': ports, 'created': time.time()}
        containers[c.id] = info
        add_log(f"✅ {name} running at {ip}", 'deployment')
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
            containers[cid]['status'] = c.status
        except docker.errors.NotFound:
            info = containers.pop(cid)
            network_mgr.release(info['ip'])
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
        network_mgr.release(info['ip'])
        add_log(f"Removed container: {info['name']}", 'warning')
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/containers/<cid>/logs')
def container_logs(cid):
    if cid not in containers:
        return jsonify({"error": "Not found"}), 404
    try:
        c = client.containers.get(cid)
        return jsonify({"logs": c.logs(tail=100).decode('utf-8', errors='ignore')})
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
            network_mgr.release(info['ip'])
            removed.append(info['name'])
        except Exception:
            containers.pop(cid, None)
    add_log(f"Cleanup: removed {len(removed)} containers", 'warning')
    return jsonify({"success": True, "removed": removed})

def _cleanup_loop():
    while True:
        time.sleep(60)
        for cid in list(containers):
            try:
                c = client.containers.get(cid)
                if c.status == 'exited':
                    c.remove()
                    info = containers.pop(cid, {})
                    network_mgr.release(info.get('ip',''))
                    add_log(f"Auto-cleaned: {info.get('name', cid)}", 'info')
            except Exception:
                containers.pop(cid, None)

if __name__ == '__main__':
    network_mgr = NetworkManager()
    add_log("🐳 cyfoxgen DocLab started", 'info')
    add_log(f"🔑 Password: {API_PASSWORD}", 'info')
    add_log("🚀 Ready to deploy containers", 'info')
    threading.Thread(target=_cleanup_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=62111, debug=False)
PYEOF

log_ok "App written to $APP_DIR/app.py"
echo ""

# ───────────────────────────── START APP ────────────────────
log_step "Starting Docker Lab Manager..."

# Kill any existing instance
pkill -f "app.py" 2>/dev/null || true
sleep 1

# Start in background, capture log
LOG_FILE="$APP_DIR/server.log"
$DOCKER_CMD network create lab-network 2>/dev/null || true

nohup python3 "$APP_DIR/app.py" > "$LOG_FILE" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$APP_DIR/app.pid"

# Wait for it to be ready
echo -ne "  ${D}Waiting for server"
for i in {1..20}; do
    sleep 0.5
    if curl -sf http://localhost:62111/health >/dev/null 2>&1; then
        break
    fi
    echo -ne "."
done
echo -e "${N}"

if ! curl -sf http://localhost:62111/health >/dev/null 2>&1; then
    log_err "Server failed to start. Check $LOG_FILE"
    cat "$LOG_FILE" | tail -20
    exit 1
fi

# Grab the password
LAB_PASSWORD=$(curl -sf http://localhost:62111/health | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])" 2>/dev/null || echo "see server log")

log_ok "Server running (PID $APP_PID)"
echo ""

# ───────────────────────────── TERMINAL UI ──────────────────
# From here we enter the interactive terminal dashboard.
# Pure bash: no ncurses, no python-curses — just ANSI + read.

API="http://localhost:62111"
PASS="$LAB_PASSWORD"

# ── draw_header ──────────────────────────────────────────────
draw_header() {
    echo -e "${G}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║         🐳  cyfoxgen Docker Lab Manager              ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${N}"
    echo -e "  ${C}URL     ${W}http://localhost:62111${N}"
    echo -e "  ${C}Password${W}  $PASS${N}"
    separator
}

# ── fetch_status ─────────────────────────────────────────────
fetch_status() {
    local json
    json=$(curl -sf "$API/containers" 2>/dev/null) || { echo -e "${R}  ✘ Cannot reach server${N}"; return; }
    local count
    count=$(echo "$json" | python3 -c "import sys,json; cs=json.load(sys.stdin)['containers']; print(len([c for c in cs if 'lab-manager' not in c.get('name','')]))" 2>/dev/null || echo "?")
    echo -e "  ${G}Active containers: ${W}$count${N}"
    echo ""
    echo "$json" | python3 - << 'PYPARSE'
import sys, json
data = json.load(sys.stdin)
containers = [c for c in data['containers'] if 'lab-manager' not in c.get('name','')]
if not containers:
    print("  \033[2m  (no containers deployed yet)\033[0m")
else:
    for c in containers:
        status_col = '\033[0;32m' if c['status'] == 'running' else '\033[0;31m'
        reset = '\033[0m'
        bold = '\033[1m'
        cyan = '\033[0;36m'
        yellow = '\033[0;33m'
        dim = '\033[2m'
        print(f"  {bold}┌─ {cyan}{c['name']}{reset}  {status_col}[{c['status'].upper()}]{reset}")
        print(f"  {bold}│{reset}  IP     {yellow}{c['ip']}{reset}")
        print(f"  {bold}│{reset}  Image  {dim}{c['image']}{reset}")
        print(f"  {bold}└──────────────────────────────────{reset}")
        print()
PYPARSE
}

# ── fetch_logs ───────────────────────────────────────────────
fetch_logs() {
    local n="${1:-10}"
    curl -sf "$API/system-logs" 2>/dev/null | python3 - "$n" << 'PYPARSE'
import sys, json
n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
data = json.load(sys.stdin)
logs = data.get('logs', [])[-int(n):]
colors = {'info':'\033[0;32m','warning':'\033[0;33m','error':'\033[0;31m','deployment':'\033[0;36m'}
reset = '\033[0m'
dim   = '\033[2m'
for l in logs:
    col = colors.get(l.get('type','info'), colors['info'])
    print(f"  {dim}[{l['timestamp']}]{reset} {col}{l['message']}{reset}")
PYPARSE
}

# ── cmd: deploy ──────────────────────────────────────────────
cmd_deploy() {
    echo ""
    echo -e "  ${C}Docker image to deploy (e.g. nginx, ubuntu, alpine):${N}"
    echo -ne "  ${W}> ${N}"
    read -r IMAGE
    [[ -z "$IMAGE" ]] && { log_warn "No image entered"; return; }

    echo -e "  ${C}Container name (leave blank for auto):${N}"
    echo -ne "  ${W}> ${N}"
    read -r CNAME

    local PAYLOAD
    if [[ -n "$CNAME" ]]; then
        PAYLOAD="{\"password\":\"$PASS\",\"image\":\"$IMAGE\",\"name\":\"$CNAME\"}"
    else
        PAYLOAD="{\"password\":\"$PASS\",\"image\":\"$IMAGE\"}"
    fi

    echo ""
    echo -e "  ${D}Sending deploy request...${N}"
    local RESP
    RESP=$(curl -sf -X POST "$API/deploy" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>&1)

    if echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print('ok') if d.get('success') else print('fail')" 2>/dev/null | grep -q ok; then
        local IP NAME
        IP=$(echo "$RESP"   | python3 -c "import sys,json; print(json.load(sys.stdin)['container']['ip'])"   2>/dev/null)
        NAME=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['container']['name'])" 2>/dev/null)
        log_ok "Deployed: $NAME  →  $IP"
    else
        local ERR
        ERR=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error','unknown'))" 2>/dev/null || echo "$RESP")
        log_err "Deploy failed: $ERR"
    fi
}

# ── cmd: stop ────────────────────────────────────────────────
cmd_stop() {
    local LIST
    LIST=$(curl -sf "$API/containers" 2>/dev/null | python3 -c "
import sys, json
cs = json.load(sys.stdin)['containers']
cs = [c for c in cs if 'lab-manager' not in c.get('name','')]
for i,c in enumerate(cs, 1):
    print(f\"  [{i}] {c['name']}  ({c['ip']})\")
" 2>/dev/null)

    if [[ -z "$LIST" ]]; then
        log_warn "No containers running"
        return
    fi

    echo ""
    echo -e "${C}  Running containers:${N}"
    echo "$LIST"
    echo ""
    echo -e "  ${C}Enter number to stop (or 'all' for cleanup):${N}"
    echo -ne "  ${W}> ${N}"
    read -r CHOICE

    if [[ "$CHOICE" == "all" ]]; then
        curl -sf -X POST "$API/cleanup" \
            -H "Content-Type: application/json" \
            -d "{\"password\":\"$PASS\"}" >/dev/null
        log_ok "All containers removed"
        return
    fi

    local CIDS
    CIDS=$(curl -sf "$API/containers" 2>/dev/null | python3 - "$CHOICE" << 'PYPARSE'
import sys, json
idx = int(sys.argv[1]) - 1
cs = json.load(sys.stdin)['containers']
cs = [c for c in cs if 'lab-manager' not in c.get('name','')]
if 0 <= idx < len(cs):
    print(cs[idx]['id'])
PYPARSE
)

    if [[ -z "$CIDS" ]]; then
        log_err "Invalid selection"
        return
    fi

    curl -sf -X DELETE "$API/containers/$CIDS" \
        -H "Content-Type: application/json" \
        -d "{\"password\":\"$PASS\"}" >/dev/null
    log_ok "Container stopped"
}

# ── cmd: logs ────────────────────────────────────────────────
cmd_logs() {
    echo ""
    echo -e "  ${C}How many log lines? (default 20):${N}"
    echo -ne "  ${W}> ${N}"
    read -r N
    N="${N:-20}"
    echo ""
    fetch_logs "$N"
}

# ── cmd: open browser ────────────────────────────────────────
cmd_open() {
    local URL="http://localhost:62111"
    if command -v xdg-open &>/dev/null; then
        xdg-open "$URL" 2>/dev/null &
    elif command -v open &>/dev/null; then
        open "$URL" 2>/dev/null &
    else
        echo -e "  ${Y}Cannot auto-open browser. Visit: ${W}$URL${N}"
        return
    fi
    log_ok "Opened $URL in browser"
}

# ── cmd: container logs ──────────────────────────────────────
cmd_container_logs() {
    local LIST
    LIST=$(curl -sf "$API/containers" 2>/dev/null | python3 -c "
import sys, json
cs = json.load(sys.stdin)['containers']
cs = [c for c in cs if 'lab-manager' not in c.get('name','')]
for i,c in enumerate(cs, 1):
    print(f\"  [{i}] {c['name']}  ({c['ip']})\")
" 2>/dev/null)

    if [[ -z "$LIST" ]]; then
        log_warn "No containers running"
        return
    fi

    echo ""
    echo -e "${C}  Select container:${N}"
    echo "$LIST"
    echo -ne "  ${W}> ${N}"
    read -r CHOICE

    local CID
    CID=$(curl -sf "$API/containers" 2>/dev/null | python3 - "$CHOICE" << 'PYPARSE'
import sys, json
idx = int(sys.argv[1]) - 1
cs = json.load(sys.stdin)['containers']
cs = [c for c in cs if 'lab-manager' not in c.get('name','')]
if 0 <= idx < len(cs):
    print(cs[idx]['id'])
PYPARSE
)

    if [[ -z "$CID" ]]; then
        log_err "Invalid selection"
        return
    fi

    echo ""
    curl -sf "$API/containers/$CID/logs" 2>/dev/null | python3 -c "
import sys, json
logs = json.load(sys.stdin).get('logs','')
for line in logs.splitlines()[-50:]:
    print(f'  \033[2m{line}\033[0m')
"
}

# ── main loop ────────────────────────────────────────────────
MENU_ITEMS=(
    "  [1] ${W}status${N}            — show running containers"
    "  [2] ${W}deploy${N}            — start a new container"
    "  [3] ${W}stop${N}              — stop / remove a container"
    "  [4] ${W}logs${N}              — system logs"
    "  [5] ${W}container logs${N}    — logs from a specific container"
    "  [6] ${W}open browser${N}      — open the web dashboard"
    "  [7] ${W}refresh${N}           — redraw this screen"
    "  [q] ${W}quit${N}              — stop server and exit"
)

main_loop() {
    while true; do
        clear
        draw_header

        echo -e "  ${G}${BOLD}Live Status${N}"
        separator
        fetch_status
        separator

        echo ""
        echo -e "  ${C}${BOLD}Commands${N}"
        for item in "${MENU_ITEMS[@]}"; do
            echo -e "$item"
        done
        echo ""
        separator
        echo -ne "  ${W}▸ ${N}"
        read -r CMD

        case "$CMD" in
            1|status)         fetch_status; echo ""; read -rp "  Press Enter to continue..." ;;
            2|deploy)         cmd_deploy;   echo ""; read -rp "  Press Enter to continue..." ;;
            3|stop)           cmd_stop;     echo ""; read -rp "  Press Enter to continue..." ;;
            4|logs)           cmd_logs;     echo ""; read -rp "  Press Enter to continue..." ;;
            5|"container logs"|cl) cmd_container_logs; echo ""; read -rp "  Press Enter to continue..." ;;
            6|open|browser)   cmd_open;     sleep 1 ;;
            7|refresh)        : ;;
            q|quit|exit)
                echo ""
                log_warn "Stopping server (PID $APP_PID)..."
                kill "$APP_PID" 2>/dev/null || true
                log_ok "Server stopped. Goodbye."
                echo ""
                exit 0
                ;;
            *)
                log_warn "Unknown command: '$CMD'"
                sleep 1
                ;;
        esac
    done
}

# ───────────────────────────── GO! ──────────────────────────
main_loop
