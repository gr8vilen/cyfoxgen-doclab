#!/usr/bin/env bash
# ============================================================
#  uneo-HACKLAB  —  One-file installer + terminal dashboard
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/gr8vilen/uneo-HACKLAB/main/install.sh | bash
#    — or —
#    bash install.sh
# ============================================================

set -euo pipefail

# ───────────────────────────── COLOURS ──────────────────────
G='\033[0;32m'
B='\033[0;34m'
C='\033[0;36m'
Y='\033[0;33m'
R='\033[0;31m'
W='\033[1;37m'
D='\033[2m'
N='\033[0m'
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

 _     _      _____ ____ 
/ \ /\/ \  /|/  __//  _ \
| | ||| |\ |||  \  | / \|
| \_/|| | \|||  /_ | \_/|
\____/\_/  \|\____\\____/
HACKLAB DOC v3
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
    if command -v docker &>/dev/null; then
        log_ok "Termux detected (Docker command found)"
    else
        log_err "Android (Termux) detected. Docker Engine cannot run natively on Android."
        log_warn "If using a remote host, install the docker client: 'pkg install docker'"
        log_warn "Then set 'DOCKER_HOST' and re-run."
        exit 1
    fi
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

if [[ "$OS" == "termux" ]]; then
    PKG_MGR="pkg"
elif [[ "$OS" == "macos" ]]; then
    if command -v brew &>/dev/null; then
        PKG_MGR="brew"
    else
        log_err "Homebrew (brew) not found on macOS. Please install it first: https://brew.sh"
        exit 1
    fi
elif command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
elif command -v apk &>/dev/null; then
    PKG_MGR="apk"
else
    log_err "No supported package manager found (apt/dnf/yum/pacman/brew/apk)"
    exit 1
fi

log_info "Package manager: $PKG_MGR"
echo ""

# ───────────────────────────── CHECK / INSTALL DEPS ─────────

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
        pkg)     pkg install -y python python-pip curl ;;
        apk)     apk add --no-cache python3 py3-pip curl ;;
        apt)     sudo apt-get update -qq && apt_install python3 python3-pip python3-venv curl ;;
        dnf|yum) dnf_install python3 python3-pip curl ;;
        pacman)  sudo pacman -Sy --noconfirm python python-pip curl ;;
        brew)    brew_install python@3 curl ;;
    esac
    log_ok "Python 3 installed: $(python3 --version)"
fi

# ── 2. pip packages ──────────────────────────────────────────
log_step "Checking Python packages..."
MISSING_PKGS=()
for pkg in flask flask_cors docker requests textual; do
    python3 -c "import $pkg" 2>/dev/null || MISSING_PKGS+=("$pkg")
done

if [[ ${#MISSING_PKGS[@]} -eq 0 ]]; then
    log_ok "All Python packages present"
else
    log_warn "Installing: ${MISSING_PKGS[*]}"
    PIP_FLAGS=""
    if python3 -m pip help install 2>/dev/null | grep -q "break-system-packages"; then
        PIP_FLAGS="--break-system-packages"
    fi
    python3 -m pip install --quiet $PIP_FLAGS flask flask-cors docker requests "textual>=0.47.0" 2>&1 | tail -2 | sed 's/^/  /'
    log_ok "Packages installed"
fi

# ── 3. Docker ────────────────────────────────────────────────
log_step "Checking Docker..."
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    log_ok "Docker running: v$DOCKER_VER"
else
    if ! command -v docker &>/dev/null; then
        if [[ "$OS" == "termux" ]]; then
            log_err "Docker client not found. Please run 'pkg install docker' and set DOCKER_HOST."
            exit 1
        fi
        log_warn "Docker not found — installing..."
        case "$PKG_MGR" in
            apk)
                apk add --no-cache docker
                ;;
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
    elif [[ "$OS" == "macos" ]]; then
        if ! docker info &>/dev/null; then
            open -a Docker
            log_info "Opening Docker Desktop... Please wait for it to start."
            for i in {1..30}; do
                echo -ne "."
                sleep 2
                if docker info &>/dev/null; then echo ""; break; fi
            done
        fi
    else
        sudo systemctl enable docker &>/dev/null || true
        sudo systemctl start docker &>/dev/null || true
    fi

    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        log_warn "Added $USER to docker group (may need re-login for group to apply)"
    fi

    if ! docker info &>/dev/null 2>&1; then
        if [[ "$OS" == "macos" ]]; then
            log_err "Docker is not responding. Please ensure Docker Desktop is running."
            log_err "Check: Settings > Advanced > Allow the default Docker socket to be used"
            exit 1
        fi
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

APP_DIR="$HOME/.uneo-HACKLAB"
mkdir -p "$APP_DIR"

cat > "$APP_DIR/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
uneo-HACKLAB — Docker Lab Manager
Pure REST API (no web UI — CLI dashboard only)
"""

from flask import Flask, request, jsonify
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

try:
    client = docker.from_env()
    client.ping()
except Exception:
    # Fallback for macOS socket paths
    found = False
    for path in [f"{os.path.expanduser('~')}/.docker/run/docker.sock", "/var/run/docker.sock"]:
        if os.path.exists(path):
            try:
                client = docker.DockerClient(base_url=f"unix://{path}")
                client.ping()
                found = True
                break
            except: continue
    if not found:
        raise

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

def gen_password(n=6):
    return ''.join(random.choices(string.digits, k=n))

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

@app.route('/')
def index():
    return jsonify({"service": "uneo-HACKLAB", "status": "ok", "hint": "Use the CLI dashboard"})

@app.route('/system-logs')
def get_logs():
    with log_lock:
        return jsonify({"logs": list(system_logs)})

@app.route('/health')
def health():
    add_log("API Health check", 'info')
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

    add_log(f"🚀 Deployment request: {name} (img: {image})", 'deployment')
    
    try:
        add_log(f"📥 Pulling image layers: {image}...", 'info')
        client.images.pull(image)
        add_log(f"📦 Image downloaded successfully.", 'info')
    except Exception as e:
        add_log(f"⚠️ Image pull note: {e}", 'warning')

    try:
        add_log(f"🔗 Attaching to network: {network_mgr.net_name}", 'info')
        c = client.containers.run(
            image, name=name, environment=env, volumes=vols,
            command=cmd, network=network_mgr.net_name,
            detach=True, remove=False
        )
        add_log(f"🛠️ Container created: {c.short_id}", 'info')
        c.reload()
        ip = c.attrs['NetworkSettings']['Networks'][network_mgr.net_name]['IPAddress']
        ports = list((c.attrs.get('Config',{}).get('ExposedPorts') or {}).keys())
        info = {'id': c.id, 'name': name, 'image': image, 'ip': ip,
                'status': c.status, 'ports': ports, 'created': time.time()}
        containers[c.id] = info
        add_log(f"✨ {name} is READY at {ip}", 'deployment')
        return jsonify({"success": True, "container": info}), 201
    except docker.errors.ImageNotFound:
        add_log(f"❌ Error: Image '{image}' not found", 'error')
        return jsonify({"error": f"Image not found: {image}"}), 404
    except Exception as e:
        add_log(f"❌ Deployment failed: {e}", 'error')
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
        add_log("Unauthorized cleanup attempt", 'error')
        return jsonify({"error": "Invalid password"}), 401
    add_log("🧹 Starting session cleanup...", 'warning')
    removed = []
    for cid in list(containers):
        try:
            client.containers.get(cid).remove(force=True)
            info = containers.pop(cid)
            network_mgr.release(info['ip'])
            removed.append(info['name'])
            add_log(f"Removed: {info['name']}", 'info')
        except Exception:
            containers.pop(cid, None)
    add_log(f"✅ Cleanup finished. Removed {len(removed)} containers", 'deployment')
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
    add_log("🐳 uneo HACKLAB started", 'info')
    add_log(f"🔑 Password: {API_PASSWORD}", 'info')
    add_log("🚀 Ready to deploy containers", 'info')
    threading.Thread(target=_cleanup_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=62111, debug=False)
PYEOF

log_ok "App written to $APP_DIR/app.py"
echo ""

# ───────────────────────────── START APP ────────────────────
log_step "Starting Docker Lab Manager..."

# ── Kill leftover containers from previous session ──────────
log_step "Removing containers from previous session..."
OLD_CONTAINERS=$($DOCKER_CMD ps -a --filter "network=lab-network" \
    --format "{{.Names}}" 2>/dev/null | grep -v "^$" || true)
if [[ -n "$OLD_CONTAINERS" ]]; then
    echo "$OLD_CONTAINERS" | while read -r cname; do
        $DOCKER_CMD rm -f "$cname" >/dev/null 2>&1 && log_ok "Removed: $cname" || true
    done
else
    log_info "No old containers found"
fi
echo ""

pkill -f "app.py" 2>/dev/null || true
sleep 1

LOG_FILE="$APP_DIR/server.log"
$DOCKER_CMD network create lab-network 2>/dev/null || true

if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
    if command -v sg &>/dev/null; then
        nohup sg docker -c "python3 \"$APP_DIR/app.py\"" > "$LOG_FILE" 2>&1 &
    else
        sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        nohup python3 "$APP_DIR/app.py" > "$LOG_FILE" 2>&1 &
    fi
else
    nohup python3 "$APP_DIR/app.py" > "$LOG_FILE" 2>&1 &
fi
APP_PID=$!
echo "$APP_PID" > "$APP_DIR/app.pid"

echo -ne "  ${D}Waiting for server"
for i in {1..20}; do
    sleep 0.5
    if curl -sf http://localhost:62111/health >/dev/null 2>&1; then break; fi
    echo -ne "."
done
echo -e "${N}"

if ! curl -sf http://localhost:62111/health >/dev/null 2>&1; then
    log_err "Server failed to start. Check $LOG_FILE"
    tail -20 "$LOG_FILE"
    exit 1
fi

LAB_PASSWORD=$(curl -sf http://localhost:62111/health | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['password'])" 2>/dev/null || echo "see server log")

log_ok "Server running (PID $APP_PID)"
echo ""

# ───────────────────────────── WRITE TUI.PY ─────────────────
log_step "Writing Textual TUI app..."

cat > "$APP_DIR/tui.py" << 'TUIEOF'
#!/usr/bin/env python3
"""
uneo HACKLAB — Textual TUI v4
Responsive split-pane layout with live logs, status badges, and animated header.
Keys: q=quit  r=refresh  s=stop selected  d=deploy  up/down=navigate
"""
import sys
import os
import json
import time
import threading
import urllib.request
from datetime import datetime

PASS    = sys.argv[1] if len(sys.argv) > 1 else ""
API_PID = sys.argv[2] if len(sys.argv) > 2 else ""
API     = "http://localhost:62111"

def api(method, path, body=None):
    try:
        data = json.dumps(body).encode() if body else None
        req  = urllib.request.Request(
            f"{API}{path}", data=data, method=method,
            headers={"Content-Type": "application/json"} if data else {}
        )
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())
    except Exception:
        return None

# ── Textual imports ────────────────────────────────────────────────────────────
from textual.app        import App, ComposeResult
from textual.widgets    import Footer, Header, Static, ListView, ListItem, Label, RichLog
from textual.containers import Horizontal, Vertical, ScrollableContainer
from textual.binding    import Binding
from textual.reactive   import reactive
from textual            import work, on
from textual.color      import Color
from rich.text          import Text
from rich.style         import Style
from rich.panel         import Panel
from rich               import box

# ── Stylesheet ─────────────────────────────────────────────────────────────────
CSS = """
/* ── Root ─────────────────────────────────────────────────────────── */
Screen {
    background: #080f08;
    layers: base overlay;
    cursor: default;
}

#top-spacer {
    height: 2;
    background: transparent;
}

/* ── Top header bar ───────────────────────────────────────────────── */
#header-bar {
    height: 3;
    background: #000000;
    border-bottom: tall #1aff6e;
    content-align: left middle;
    padding: 0 2;
    color: #1aff6e;
    text-style: bold;
}

/* ── Stats strip ──────────────────────────────────────────────────── */
#stats-bar {
    height: 1;
    background: #0a180a;
    border-bottom: solid #0d3a0d;
    content-align: left middle;
    padding: 0 2;
    color: #2d9e2d;
}

/* ── Main body split ──────────────────────────────────────────────── */
#body {
    height: 1fr;
    margin-top: 0;
}

/* ── Left pane: container list ────────────────────────────────────── */
#left-pane {
    width: 36;
    min-width: 24;
    background: #050d05;
    border-right: tall #0d3a0d;
    overflow-y: auto;
}

#pane-title-left {
    height: 2;
    background: #0a1a0a;
    border-bottom: solid #0d3a0d;
    content-align: left middle;
    padding: 0 2;
    color: #1aff6e;
    text-style: bold;
}

/* ── Container list items ─────────────────────────────────────────── */
.c-item {
    height: 5;
    padding: 0 1;
    border-bottom: solid #0a1a0a;
    background: #050d05;
}

.c-item:hover {
    background: #0a1e0a;
}

.c-item.-selected {
    background: #0d2e0d;
    border-left: thick #1aff6e;
}

.c-item.running {
    border-left: thick #1aff6e;
}

.c-item.exited {
    border-left: thick #8b0000;
}

.c-item.paused {
    border-left: thick #b8860b;
}

/* ── Right pane: details + logs ───────────────────────────────────── */
#right-pane {
    width: 1fr;
    background: #050d05;
}

/* ── Detail panel (top-right) ─────────────────────────────────────── */
#detail-panel {
    height: 10;
    background: #060e06;
    border-bottom: tall #0d3a0d;
    padding: 1 2;
    overflow: hidden;
}

#pane-title-detail {
    height: 2;
    background: #0a1a0a;
    border-bottom: solid #0d3a0d;
    content-align: left middle;
    padding: 0 2;
    color: #7fff7f;
    text-style: bold;
}

/* ── Logs panel (bottom-right) ────────────────────────────────────── */
#pane-title-logs {
    height: 2;
    background: #0a1a0a;
    border-bottom: solid #0d3a0d;
    content-align: left middle;
    padding: 0 2;
    color: #2d9e2d;
    text-style: bold;
}

#log-view {
    height: 1fr;
    background: #030803;
    padding: 0 1;
    overflow-y: auto;
    scrollbar-color: #1aff6e #0a1a0a;
    scrollbar-background: #0a1a0a;
    scrollbar-corner-color: #0a1a0a;
}

/* ── Empty state ──────────────────────────────────────────────────── */
#empty-state {
    height: 1fr;
    content-align: center middle;
    color: #1a3a1a;
    text-style: italic;
}

/* ── System log panel (full width, collapsible) ────────────────────── */
#syslog-panel {
    height: 8;
    background: #030803;
    border-top: tall #0a2a0a;
    dock: bottom;
    display: block; /* Visible by default */
}

#syslog-panel.visible {
    display: block;
}

#syslog-view {
    height: 1fr;
    padding: 0 2;
    overflow-y: auto;
}

/* ── Footer ───────────────────────────────────────────────────────── */
Footer {
    background: #000000;
    color: #1aff6e;
    border-top: tall #0d3a0d;
}

Footer > .footer--key {
    background: #0d3a0d;
    color: #1aff6e;
}

Footer > .footer--highlight {
    background: #1aff6e;
    color: #000000;
}
"""

# ── Container list item widget ─────────────────────────────────────────────────
class ContainerItem(Static):
    """A single row in the container list."""

    def __init__(self, cinfo: dict) -> None:
        super().__init__()
        self.cinfo = cinfo
        self._cid  = cinfo["id"]
        self._cid12 = cinfo["id"][:12]

    def render(self) -> Text:
        c      = self.cinfo
        status = c.get("status", "unknown")
        name   = c.get("name", "?")
        image  = c.get("image", "?")
        ip     = c.get("ip", "?")

        if status == "running":
            badge_style = Style(color="#1aff6e", bold=True)
            badge = "● RUNNING"
            name_style = Style(color="#ccffcc", bold=True)
        elif status == "exited":
            badge_style = Style(color="#ff4444")
            badge = "✕ EXITED "
            name_style = Style(color="#886666")
        else:
            badge_style = Style(color="#ffcc00")
            badge = "◌ " + status.upper()[:7]
            name_style = Style(color="#aaaa77")

        t = Text()
        t.append(f" {badge}", style=badge_style)
        t.append("\n")
        t.append(f" {name[:28]}", style=name_style)
        t.append("\n")
        short_img = image.split("/")[-1][:26] if "/" in image else image[:26]
        t.append(f" {short_img}", style=Style(color="#336633", italic=True))
        t.append("\n")
        t.append(f" {ip}", style=Style(color="#1a6e1a"))
        return t

    def update_info(self, cinfo: dict) -> None:
        self.cinfo = cinfo
        self.refresh()

# ── Main TUI App ───────────────────────────────────────────────────────────────
class HACKLABTUI(App):
    CSS      = CSS
    TITLE    = "uneo HACKLAB"
    BINDINGS = [
        Binding("q",          "quit",       "Quit",       show=True,  priority=True),
        Binding("r",          "refresh",    "Refresh",    show=True),
        Binding("s",          "stop",       "Stop",       show=True),
        Binding("l",          "toggle_log", "Logs",       show=True),
        Binding("h",          "show_help",  "Help",       show=True),
        Binding("up",         "cursor_up",  "Up",         show=False),
        Binding("down",       "cursor_down","Down",       show=False),
        Binding("k",          "cursor_up",  "Up",         show=False),
        Binding("j",          "cursor_down","Down",       show=False),
    ]

    _containers:    list  = []
    _selected_idx:  int   = 0
    _syslog_visible: bool = True  # Start with logs visible
    _tick:          int   = 0
    _last_activity: str   = "Starting..."

    # ── Compose ─────────────────────────────────────────────────────────────
    def compose(self) -> ComposeResult:
        yield Static("", id="top-spacer")
        yield Static(
            f"  uneo HACKLAB  |  KEY: {PASS}  |  PID: {API_PID}",
            id="header-bar"
        )
        yield Static("", id="stats-bar")
        with Horizontal(id="body"):
            # Left: container list
            with Vertical(id="left-pane"):
                yield Static("  CONTAINERS", id="pane-title-left")
                yield Static(
                    "\n\n  [bold #1aff6e]No active containers.[/]\n\n",
                    id="empty-state"
                )
            # Right: detail + logs
            with Vertical(id="right-pane"):
                yield Static("  SELECT A CONTAINER", id="pane-title-detail")
                yield Static(
                    "\n  ← Select a container from the left panel.",
                    id="detail-panel"
                )
                yield Static("  STDOUT / STDERR", id="pane-title-logs")
                yield RichLog(id="log-view", highlight=True, markup=False, wrap=True)
        # Syslog drawer (hidden by default)
        with Vertical(id="syslog-panel"):
            yield Static("  ▲ SYSTEM LOGS  [L] to toggle", id="pane-title-syslog")
            yield RichLog(id="syslog-view", highlight=False, markup=False, wrap=True)
        yield Footer()

    # ── Mount ────────────────────────────────────────────────────────────────
    def on_mount(self) -> None:
        self._update_header()
        self.set_interval(4, self._scheduled_refresh)
        self.set_interval(1, self._update_header)
        self._do_refresh()


    # ── Header / stats ───────────────────────────────────────────────────────
    def _update_header(self) -> None:
        self._tick += 1
        now = datetime.now().strftime("%H:%M:%S")
        running = sum(1 for c in self._containers if c.get("status") == "running")
        total   = len(self._containers)

        # Animated pulse dot
        pulse = ("◉", "◎", "◉", "○")[self._tick % 4] if running > 0 else "○"

        self.query_one("#header-bar", Static).update(
            f"  ░▒▓  UNEO HACKLAB ▓▒░   {pulse} LIVE   "
            f"│  KEY: {PASS}  │  PID: {API_PID}  │  {now}"
        )
        self.query_one("#stats-bar", Static).update(
            f"  [#1aff6e]▶[/] Running: {running}/{total}  "
            f" [#1aff6e]▶[/] Selected: {self._containers[self._selected_idx]['name'] if self._containers else '—'}  "
            f" [#1aff6e]▶[/] Last Activity: {self._last_activity}"
        )

    # ── Scheduled & manual refresh ───────────────────────────────────────────
    def _scheduled_refresh(self) -> None:
        self._do_refresh()

    def action_refresh(self) -> None:
        self._do_refresh()
        # self.notify("Refreshed", severity="information", timeout=1)

    @work(thread=True)
    def _do_refresh(self) -> None:
        resp = api("GET", "/containers")
        cs   = []
        if resp and "containers" in resp:
            cs = [c for c in resp["containers"]
                  if "lab-manager" not in c.get("name", "")]

        # Fetch logs for selected container
        logs_text = ""
        if cs and self._selected_idx < len(cs):
            sel = cs[self._selected_idx]
            r   = api("GET", f"/containers/{sel['id']}/logs")
            if r:
                logs_text = r.get("logs", "")

        # Fetch system logs
        slogs = []
        sr = api("GET", "/system-logs")
        if sr:
            slogs = sr.get("logs", [])
        
        self.call_from_thread(self._redraw, cs, logs_text, slogs)

    def _redraw(self, cs: list, logs_text: str, slogs: list) -> None:
        self._containers = cs
        left = self.query_one("#left-pane", Vertical)
        empty = self.query_one("#empty-state", Static)

        if not cs:
            empty.display = True
            # Remove all container items
            for w in list(left.query(ContainerItem)):
                w.remove()
            self._clear_detail()
            return

        empty.display = False

        # Sync container items
        existing = {w.id: w for w in left.query(ContainerItem)}
        want_ids = {f"ci-{c['id'][:12]}" for c in cs}

        # Remove stale
        for wid, w in list(existing.items()):
            if wid not in want_ids:
                w.remove()

        # Add or update
        for i, c in enumerate(cs):
            wid = f"ci-{c['id'][:12]}"
            if wid in existing:
                existing[wid].update_info(c)
                # Update CSS class
                w = existing[wid]
                w.remove_class("running", "exited", "paused")
                w.add_class(c.get("status", "unknown"))
                w.remove_class("-selected")
                if i == self._selected_idx:
                    w.add_class("-selected")
            else:
                item = ContainerItem(c)
                item.id = wid
                item.add_class("c-item")
                item.add_class(c.get("status", "unknown"))
                if i == self._selected_idx:
                    item.add_class("-selected")
                left.mount(item)

        # Clamp selection
        if self._selected_idx >= len(cs):
            self._selected_idx = max(0, len(cs) - 1)

        # Update detail pane
        self._update_detail(cs[self._selected_idx] if cs else None)

        # Update log pane
        log_widget = self.query_one("#log-view", RichLog)
        log_widget.clear()
        lines = [l for l in logs_text.splitlines() if l.strip()][-60:]
        for line in lines:
            log_widget.write(line)
        if not lines:
            log_widget.write("— no output yet —")

        # Update syslog
        syslog_widget = self.query_one("#syslog-view", RichLog)
        syslog_widget.clear()
        last_msg = "No activity"
        for entry in slogs[-30:]:
            ts   = entry.get("timestamp", "")
            msg  = entry.get("message", "")
            kind = entry.get("type", "info")
            last_msg = msg
            color = {
                "error":      "#ff4444",
                "warning":    "#ffcc00",
                "deployment": "#1aff6e",
                "info":       "#2d9e2d",
            }.get(kind, "#2d9e2d")
            syslog_widget.write(
                Text.assemble(
                    (f"[{ts}] ", Style(color="#1a6e1a")),
                    (msg, Style(color=color)),
                )
            )

        # Update stats bar with latest activity
        if slogs:
            self._last_activity = slogs[-1].get("message", "No activity")

    def _update_detail(self, c) -> None:
        detail  = self.query_one("#detail-panel", Static)
        title_w = self.query_one("#pane-title-detail", Static)
        log_w   = self.query_one("#pane-title-logs", Static)

        if c is None:
            detail.update("  ← Select a container.")
            title_w.update("  CONTAINER DETAIL")
            log_w.update("  LOGS")
            return

        status  = c.get("status", "?")
        name    = c.get("name", "?")
        image   = c.get("image", "?")
        ip      = c.get("ip", "?")
        cid     = c.get("id", "?")[:16]
        ports   = ", ".join(c.get("ports", [])) or "none"
        created = c.get("created", 0)
        age_s   = int(time.time() - created) if created else 0
        age     = f"{age_s//3600}h {(age_s%3600)//60}m {age_s%60}s"

        if status == "running":
            status_line = Text.assemble(("● RUNNING", Style(color="#1aff6e", bold=True)))
            title_w.update(f"  ◉ {name.upper()}")
        else:
            status_line = Text.assemble(("✕ " + status.upper(), Style(color="#ff4444", bold=True)))
            title_w.update(f"  ✕ {name.upper()}")

        log_w.update(f"  LOGS — {name}")

        t = Text()
        t.append(" Status  : ", style=Style(color="#2d9e2d"))
        t.append_text(status_line)
        t.append("\n Name    : ", style=Style(color="#2d9e2d"))
        t.append(name, style=Style(color="#ccffcc", bold=True))
        t.append("\n Image   : ", style=Style(color="#2d9e2d"))
        t.append(image, style=Style(color="#7fff7f", italic=True))
        t.append("\n IP      : ", style=Style(color="#2d9e2d"))
        t.append(ip, style=Style(color="#1aff6e"))
        t.append("\n ID      : ", style=Style(color="#2d9e2d"))
        t.append(cid + "...", style=Style(color="#336633"))
        t.append("\n Ports   : ", style=Style(color="#2d9e2d"))
        t.append(ports, style=Style(color="#669966"))
        t.append("\n Uptime  : ", style=Style(color="#2d9e2d"))
        t.append(age, style=Style(color="#669966"))
        detail.update(t)

    def _clear_detail(self) -> None:
        self.query_one("#detail-panel", Static).update(
            "  No containers running."
        )
        self.query_one("#log-view", RichLog).clear()

    # ── Cursor navigation ─────────────────────────────────────────────────────
    def action_cursor_up(self) -> None:
        if not self._containers:
            return
        self._selected_idx = max(0, self._selected_idx - 1)
        self._do_refresh()

    def action_cursor_down(self) -> None:
        if not self._containers:
            return
        self._selected_idx = min(len(self._containers) - 1, self._selected_idx + 1)
        self._do_refresh()

    # ── Stop action ──────────────────────────────────────────────────────────
    def action_stop(self) -> None:
        if not self._containers:
            return
        c = self._containers[self._selected_idx]
        if c.get("status") != "running":
            self._last_activity = f"⚠️ {c['name']} is not running."
            return
        self._last_activity = f"⏳ Stopping {c.get('name')}…"
        self._do_stop(c)

    @work(thread=True)
    def _do_stop(self, c: dict) -> None:
        resp = api("DELETE", f"/containers/{c['id']}", {"password": PASS})
        if resp and resp.get("success"):
            self._last_activity = f"✅ Stopped: {c.get('name')}"
        else:
            err = (resp.get("error", "?") if resp else "no response")
            self._last_activity = f"❌ Stop failed: {err}"
        self._do_refresh()

    # ── Toggle syslog ────────────────────────────────────────────────────────
    def action_toggle_log(self) -> None:
        self._syslog_visible = not self._syslog_visible
        panel = self.query_one("#syslog-panel", Vertical)
        if self._syslog_visible:
            panel.add_class("visible")
        else:
            panel.remove_class("visible")

    # ── Help ─────────────────────────────────────────────────────────────────
    def action_show_help(self) -> None:
        self._last_activity = "Help: Q=Quit R=Refresh S=Stop L=Logs H=Help ↑/↓=Nav"

    # ── Quit ─────────────────────────────────────────────────────────────────
    def action_quit(self) -> None:
        if API_PID:
            try:
                os.kill(int(API_PID), 15)
            except Exception:
                pass
        self.exit()


if __name__ == "__main__":
    HACKLABTUI().run()
TUIEOF

log_ok "TUI written to $APP_DIR/tui.py"
echo ""

# ───────────────────── CLEANUP OLD CONTAINERS ────────────────
log_step "Cleaning up containers from previous session..."
CLEANUP_RESP=$(curl -sf -X POST http://localhost:62111/cleanup \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$LAB_PASSWORD\"}" 2>/dev/null || echo "{}")
CLEANED=$(echo "$CLEANUP_RESP" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(len(d.get('removed',[])))" 2>/dev/null || echo "0")
log_ok "Removed $CLEANED old container(s)"
echo ""

# ───────────────────────────── LAUNCH TUI ───────────────────
log_step "Launching HACKLAB TUI..."
echo ""
python3 "$APP_DIR/tui.py" "$LAB_PASSWORD" "$APP_PID"

log_ok "Session ended."