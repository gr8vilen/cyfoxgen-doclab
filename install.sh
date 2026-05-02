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
HACKLAB DOC v6.2
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
    # Caller can pass explicit port mappings; if not, we auto-map all exposed ports.
    req_ports = data.get('ports', None)

    add_log(f"\U0001f680 Deployment request: {name} (img: {image})", 'deployment')

    try:
        add_log(f"\U0001f4e5 Pulling image layers: {image}...", 'info')
        client.images.pull(image)
        add_log(f"\U0001f4e6 Image downloaded successfully.", 'info')
    except Exception as e:
        add_log(f"\u26a0\ufe0f Image pull note: {e}", 'warning')

    try:
        # Inspect image to find all exposed ports
        img_info     = client.images.get(image)
        exposed      = list((img_info.attrs.get('Config', {}).get('ExposedPorts') or {}).keys())
        # Build ports dict: {"80/tcp": None} means map to random host port
        if req_ports:
            ports_map = req_ports
        else:
            ports_map = {p: None for p in exposed}  # None = auto-assign

        add_log(f"\U0001f517 Attaching to network: {network_mgr.net_name}", 'info')
        c = client.containers.run(
            image, name=name, environment=env, volumes=vols,
            command=cmd, network=network_mgr.net_name,
            ports=ports_map,
            detach=True, remove=False
        )
        add_log(f"\U0001f6e0\ufe0f Container created: {c.short_id}", 'info')
        c.reload()

        net_info  = c.attrs['NetworkSettings']
        ip        = net_info['Networks'].get(network_mgr.net_name, {}).get('IPAddress', 'n/a')

        # Build human-readable host port mappings: {"80/tcp": "localhost:32768"}
        host_ports = {}
        raw_ports  = net_info.get('Ports') or {}
        for cport, bindings in raw_ports.items():
            if bindings:
                host_ports[cport] = f"localhost:{bindings[0]['HostPort']}"

        access = list(host_ports.values()) if host_ports else []

        info = {
            'id':         c.id,
            'name':       name,
            'image':      image,
            'ip':         ip,
            'host_ports': host_ports,
            'access':     access,
            'status':     c.status,
            'ports':      exposed,
            'created':    time.time()
        }
        containers[c.id] = info
        access_str = ', '.join(access) or ip
        add_log(f"\u2728 {name} is READY  ->  {access_str}", 'deployment')
        return jsonify({"success": True, "container": info}), 201
    except docker.errors.ImageNotFound:
        add_log(f"\u274c Error: Image '{image}' not found", 'error')
        return jsonify({"error": f"Image not found: {image}"}), 404
    except Exception as e:
        add_log(f"\u274c Deployment failed: {e}", 'error')
        return jsonify({"error": str(e)}), 500


@app.route('/containers')
def list_containers():
    for cid in list(containers):
        try:
            c = client.containers.get(cid)
            containers[cid]['status'] = c.status
            # Refresh host port mappings (they can change)
            raw_ports = c.attrs['NetworkSettings'].get('Ports') or {}
            host_ports = {}
            for cport, bindings in raw_ports.items():
                if bindings:
                    host_ports[cport] = f"localhost:{bindings[0]['HostPort']}"
            containers[cid]['host_ports'] = host_ports
            containers[cid]['access']     = list(host_ports.values())
        except docker.errors.NotFound:
            info = containers.pop(cid)
            network_mgr.release(info.get('ip', ''))
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
log_step "Writing dashboard app..."

cat > "$APP_DIR/tui.py" << 'TUIEOF'
#!/usr/bin/env python3
# uneo HACKLAB -- Display-only dashboard
# No keyboard, no mouse, no bells. Ctrl+C to exit.
import sys, os, json, time, signal, urllib.request
from datetime import datetime

PASS     = sys.argv[1] if len(sys.argv) > 1 else ""
API_PID  = sys.argv[2] if len(sys.argv) > 2 else ""
API      = "http://localhost:62111"
INTERVAL = 3

CLEAR       = "\x1b[2J\x1b[H"
HIDE_CURSOR = "\x1b[?25l"
SHOW_CURSOR = "\x1b[?25h"

def col(c): return f"\x1b[{c}m"
RESET = col(0); BOLD = col(1); DIM = col(2)
GREEN = col(92); DKGRN = col(32); RED = col(91)
YELLOW = col(93); CYAN = col(96); WHITE = col(97); GREY = col(90)

def hline(ch="\u2500", w=80):
    return DKGRN + ch * w + RESET

def api_call(method, path, body=None):
    try:
        data = json.dumps(body).encode() if body else None
        req  = urllib.request.Request(
            f"{API}{path}", data=data, method=method,
            headers={"Content-Type": "application/json"} if data else {}
        )
        with urllib.request.urlopen(req, timeout=4) as r:
            return json.loads(r.read())
    except Exception:
        return None

def draw(tick):
    try:
        cols = os.get_terminal_size().columns
    except Exception:
        cols = 80

    containers = []
    slogs = []

    resp = api_call("GET", "/containers")
    if resp and "containers" in resp:
        containers = [c for c in resp["containers"]
                      if "lab-manager" not in c.get("name", "")]

    sr = api_call("GET", "/system-logs")
    if sr:
        slogs = sr.get("logs", [])

    now     = datetime.now().strftime("%H:%M:%S")
    running = sum(1 for c in containers if c.get("status") == "running")
    pulse   = ("\u25c9", "\u25ce", "\u25c9", "\u25cb")[tick % 4] if running > 0 else "\u25cb"

    out = ["\n\n"]

    # Header
    out.append(
        f"{GREEN}{BOLD}  \u2591\u2592\u2593  UNEO HACKLAB \u2593\u2592\u2591{RESET}"
        f"   {GREEN}{pulse} LIVE{RESET}"
        f"  {DIM}\u2502{RESET}  KEY: {CYAN}{BOLD}{PASS}{RESET}"
        f"  {DIM}\u2502{RESET}  PID: {GREY}{API_PID}{RESET}"
        f"  {DIM}\u2502{RESET}  {WHITE}{now}{RESET}"
    )
    out.append(hline("\u2500", cols))

    # Stats
    last_msg = slogs[-1].get("message", "No activity") if slogs else "No activity"
    out.append(
        f"  {GREEN}\u25b6{RESET} Running: {GREEN}{running}/{len(containers)}{RESET}"
        f"   {GREEN}\u25b6{RESET} {DIM}{last_msg[:cols-30]}{RESET}"
    )
    out.append(hline("\u2500", cols))

    # Containers
    if not containers:
        out.append(f"\n  {DIM}No active containers.{RESET}\n")
    else:
        for i, c in enumerate(containers):
            status     = c.get("status", "?")
            name       = c.get("name",   "?")
            image      = c.get("image",  "?")
            ip         = c.get("ip",     "?")
            access     = c.get("access", [])       # localhost:PORT list
            host_ports = c.get("host_ports", {})
            ports      = ", ".join(c.get("ports", [])) or "none"
            cid        = c.get("id", "?")[:12]
            age_s      = int(time.time() - c.get("created", time.time()))
            age        = f"{age_s//3600}h{(age_s%3600)//60}m{age_s%60}s"
            short      = (image.split("/")[-1] if "/" in image else image)[:28]

            if status == "running":
                badge, nc = f"{GREEN}\u25cf RUNNING{RESET}", GREEN
            elif status == "exited":
                badge, nc = f"{RED}\u2715 EXITED {RESET}", RED
            else:
                badge, nc = f"{YELLOW}\u25cc {status.upper()[:7]}{RESET}", YELLOW

            out.append(f"  {badge}  {nc}{BOLD}{name}{RESET}  {DIM}{short}{RESET}")

            # Show localhost access addresses prominently (macOS can't reach internal IPs)
            if access:
                access_str = "  ".join(f"{CYAN}{a}{RESET}" for a in access)
                out.append(f"  {GREEN}\u2192 ACCESS:{RESET} {access_str}")
            else:
                out.append(f"  {YELLOW}\u26a0 No ports exposed  {DIM}(internal IP: {ip}){RESET}")

            out.append(
                f"  {DKGRN}ID:{RESET} {DIM}{cid}...{RESET}"
                f"  {DKGRN}Exposed:{RESET} {ports}"
                f"  {DKGRN}Up:{RESET} {age}"
            )
            if i < len(containers) - 1:
                out.append(hline("\u2504", cols))


    out.append(hline("\u2500", cols))

    # System logs
    out.append(f"  {BOLD}{DKGRN}SYSTEM LOGS{RESET}")
    log_colors = {"error": RED, "warning": YELLOW, "deployment": GREEN, "info": DKGRN}
    for entry in slogs[-8:]:
        ts   = entry.get("timestamp", "")
        msg  = entry.get("message",   "")
        kind = entry.get("type",      "info")
        c    = log_colors.get(kind, DKGRN)
        out.append(f"  {DIM}[{ts}]{RESET} {c}{msg[:cols-16]}{RESET}")

    out.append(hline("\u2500", cols))
    out.append(f"  {DIM}Refreshes every {INTERVAL}s  \u00b7  Ctrl+C to exit{RESET}")

    sys.stdout.write(CLEAR + "\n".join(out) + "\n")
    sys.stdout.flush()

def main():
    sys.stdout.write(HIDE_CURSOR + "\x1b[?1003l\x1b[?1002l\x1b[?1001l\x1b[?1000l")
    sys.stdout.flush()

    def cleanup(sig=None, frame=None):
        sys.stdout.write(SHOW_CURSOR + "\n")
        sys.stdout.flush()
        sys.exit(0)

    signal.signal(signal.SIGINT,  cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    tick = 0
    while True:
        draw(tick)
        tick += 1
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
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