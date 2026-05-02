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
      D O C K E R   L A B   M A N A G E R   —   v2.0
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
    PIP_FLAGS=""
    if python3 -m pip help install 2>/dev/null | grep -q "break-system-packages"; then
        PIP_FLAGS="--break-system-packages"
    fi
    python3 -m pip install --quiet $PIP_FLAGS flask flask-cors docker requests 2>&1 | tail -2 | sed 's/^/  /'
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

@app.route('/')
def index():
    return jsonify({"service": "cyfoxgen-doclab", "status": "ok", "hint": "Use the CLI dashboard"})

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


# ── Wait for server to be ready ─────────────────────────────
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

# ───────────────────────────── TERMINAL UI ──────────────────
# htop-style: alternate screen buffer, cursor-home in-place
# redraws (zero flicker), single-char keypresses (no Enter).

API="http://localhost:62111"
PASS="$LAB_PASSWORD"

# ── primitive helpers ─────────────────────────────────────────
thin_sep() {
    local cols; cols=$(tput cols 2>/dev/null || echo 100)
    printf "${D}"; printf '┄%.0s' $(seq 1 "$cols"); printf "${N}\n"
}

# ── draw_logo ─────────────────────────────────────────────────
draw_logo() {
    printf "${G}${BOLD}"
    printf "   ██████╗ ██████╗  ██████╗██╗  ██╗██╗      █████╗ ██████╗\n"
    printf "   ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██║     ██╔══██╗██╔══██╗\n"
    printf "   ██║  ██║██║   ██║██║     █████╔╝ ██║     ███████║██████╔╝\n"
    printf "   ██║  ██║██║   ██║██║     ██╔═██╗ ██║     ██╔══██║██╔══██╗\n"
    printf "   ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║██████╔╝\n"
    printf "   ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝\n"
    printf "${C}            D O C K E R   L A B   M A N A G E R   v2.0${N}\n\n"
}

# ── status bar ────────────────────────────────────────────────
draw_statusbar() {
    local now; now=$(date '+%H:%M:%S')
    thin_sep
    printf "  ${G}PID:${W}%s${N}   ${Y}KEY:${W}%s${N}   ${C}%s${N}   ${D}API: %s${N}\n" \
        "$APP_PID" "$PASS" "$now" "$API"
    thin_sep
}

# ── containers pane ───────────────────────────────────────────
render_containers() {
    local json="$1"
    printf "\n  ${G}${BOLD}● CONTAINERS${N}\n"
    printf '%s' "$json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    print('  \033[31m✘ Cannot parse response\033[0m'); sys.exit(0)
cs = [c for c in data.get('containers',[]) if 'lab-manager' not in c.get('name','')]
if not cs:
    print('  \033[2m  — no containers deployed yet —\033[0m')
else:
    G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; Y='\033[0;33m'
    W='\033[1;37m'; D='\033[2m'; N='\033[0m'; B='\033[1m'
    for c in cs:
        sc = G if c.get('status')=='running' else R
        badge = (f'{sc}▶ RUNNING{N}' if c.get('status')=='running'
                 else f'{R}■ {c.get(\"status\",\"?\").upper()}{N}')
        print(f'  {B}╭─ {C}{c.get(\"name\",\"?\")}{N}  {badge}')
        print(f'  {B}│{N}  {D}IP   {N} {Y}{c.get(\"ip\",\"?\")}{N}')
        print(f'  {B}│{N}  {D}Image{N} {D}{c.get(\"image\",\"?\")}{N}')
        print(f'  {B}╰────────────────────────────{N}')
        print()
" 2>/dev/null
}

# ── logs pane ─────────────────────────────────────────────────
render_logs() {
    local n="${1:-10}"
    printf "  ${C}${BOLD}◉ SYSTEM LOGS${D}  (last %s)${N}\n" "$n"
    curl -sf "$API/system-logs" 2>/dev/null | python3 -c "
import sys, json
n = int(sys.argv[1]) if len(sys.argv)>1 else 10
try:
    data = json.load(sys.stdin)
except Exception:
    print('  \033[31m✘ Cannot parse logs\033[0m'); sys.exit(0)
logs = data.get('logs',[])[-n:]
cols = {'info':'\033[0;32m','warning':'\033[0;33m',
        'error':'\033[0;31m','deployment':'\033[0;36m'}
D='\033[2m'; N='\033[0m'
for l in logs:
    col = cols.get(l.get('type','info'), cols['info'])
    print(f'  {D}[{l[\"timestamp\"]}]{N} {col}{l[\"message\"]}{N}')
" "arg0" "$n" 2>/dev/null
}

# ── atomic in-place repaint (htop-style, zero flicker) ───────
render_screen() {
    local json="$1" msg="${2:-}"
    # Move cursor to top-left of the alternate screen buffer
    printf '\033[H'
    draw_logo
    draw_statusbar
    render_containers "$json"
    thin_sep
    render_logs 8
    thin_sep
    printf "\n"
    if [[ -n "$msg" ]]; then
        printf "  ${Y}${BOLD}%s${N}\n\n" "$msg"
    fi
    printf "  ${G}[d]${N}eploy   ${R}[s]${N}top   ${C}[l]${N}ogs   ${W}[q]${N}uit   ${D}(auto-refresh 3s — single key, no Enter)${N}\n"
    # Erase anything below the current line (clean old content)
    printf '\033[J'
}

# ── modal: deploy ─────────────────────────────────────────────
cmd_deploy() {
    tput rmcup 2>/dev/null    # leave alt screen → show normal terminal
    tput cnorm 2>/dev/null
    printf '\033[2J\033[H'
    printf "\n  ${G}${BOLD}╔══  🚀  DEPLOY NEW CONTAINER  ══╗${N}\n\n"
    printf "  ${C}Image${N}  (e.g. nginx  ubuntu  alpine  kalilinux/kali-rolling)\n"
    printf "  ${W}▸ image  : ${N}"; read -r IMAGE
    if [[ -z "$IMAGE" ]]; then
        log_warn "Cancelled."; sleep 1
    else
        printf "  ${W}▸ name   : ${D}(blank=auto) ${N}";    read -r CNAME
        printf "  ${W}▸ command: ${D}(blank=default) ${N}"; read -r DCMD
        printf "\n"
        local PAYLOAD
        if [[ -n "$CNAME" && -n "$DCMD" ]]; then
            PAYLOAD="{\"password\":\"$PASS\",\"image\":\"$IMAGE\",\"name\":\"$CNAME\",\"command\":\"$DCMD\"}"
        elif [[ -n "$CNAME" ]]; then
            PAYLOAD="{\"password\":\"$PASS\",\"image\":\"$IMAGE\",\"name\":\"$CNAME\"}"
        else
            PAYLOAD="{\"password\":\"$PASS\",\"image\":\"$IMAGE\"}"
        fi
        printf "  ${D}⠿ Pulling & deploying...${N}\n"
        local RESP
        RESP=$(curl -sf -X POST "$API/deploy" \
            -H "Content-Type: application/json" -d "$PAYLOAD" 2>&1)
        if echo "$RESP" | python3 -c \
            "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('success') else 1)" 2>/dev/null
        then
            local IP NM
            IP=$(echo "$RESP" | python3 -c \
                "import sys,json; print(json.load(sys.stdin)['container']['ip'])"   2>/dev/null)
            NM=$(echo "$RESP" | python3 -c \
                "import sys,json; print(json.load(sys.stdin)['container']['name'])" 2>/dev/null)
            log_ok "Deployed: ${W}$NM${N}  →  ${Y}$IP${N}"
        else
            local ERR
            ERR=$(echo "$RESP" | python3 -c \
                "import sys,json; print(json.load(sys.stdin).get('error','?'))" 2>/dev/null \
                || echo "$RESP")
            log_err "Deploy failed: $ERR"
        fi
        sleep 1
    fi
    tput smcup 2>/dev/null    # back to alt screen
    tput civis 2>/dev/null
}

# ── modal: stop ───────────────────────────────────────────────
cmd_stop() {
    tput rmcup 2>/dev/null; tput cnorm 2>/dev/null
    printf '\033[2J\033[H'
    printf "\n  ${R}${BOLD}╔══  🗑  STOP / REMOVE CONTAINER  ══╗${N}\n\n"
    local JSON LIST
    JSON=$(curl -sf "$API/containers" 2>/dev/null || echo '{"containers":[]}')
    LIST=$(printf '%s' "$JSON" | python3 -c "
import sys,json
cs=json.load(sys.stdin).get('containers',[])
cs=[c for c in cs if 'lab-manager' not in c.get('name','')]
[print(f'  [{i+1}] \033[0;36m{c[\"name\"]}\033[0m  \033[2m({c[\"ip\"]})\033[0m')
 for i,c in enumerate(cs)]
" 2>/dev/null)
    if [[ -z "$LIST" ]]; then
        log_warn "No containers running."; sleep 2
    else
        printf '%s\n\n' "$LIST"
        printf "  ${C}Number to remove  or  ${W}all${C}:${N}\n"
        printf "  ${W}▸ ${N}"; read -r CHOICE
        if [[ "$CHOICE" == "all" ]]; then
            curl -sf -X POST "$API/cleanup" -H "Content-Type: application/json" \
                -d "{\"password\":\"$PASS\"}" >/dev/null
            log_ok "All containers removed."
        else
            local CID
            CID=$(printf '%s' "$JSON" | python3 -c "
import sys,json
try:
    cs=json.load(sys.stdin).get('containers',[])
    cs=[c for c in cs if 'lab-manager' not in c.get('name','')]
    print(cs[int(sys.argv[1])-1]['id'])
except: pass
" "arg0" "$CHOICE" 2>/dev/null)
            if [[ -z "$CID" ]]; then log_err "Invalid selection."; else
                curl -sf -X DELETE "$API/containers/$CID" \
                    -H "Content-Type: application/json" -d "{\"password\":\"$PASS\"}" >/dev/null
                log_ok "Container removed."
            fi
        fi
        sleep 1
    fi
    tput smcup 2>/dev/null; tput civis 2>/dev/null
}

# ── modal: container logs ─────────────────────────────────────
cmd_container_logs() {
    tput rmcup 2>/dev/null; tput cnorm 2>/dev/null
    printf '\033[2J\033[H'
    printf "\n  ${C}${BOLD}╔══  📜  CONTAINER LOGS  ══╗${N}\n\n"
    local JSON LIST
    JSON=$(curl -sf "$API/containers" 2>/dev/null || echo '{"containers":[]}')
    LIST=$(printf '%s' "$JSON" | python3 -c "
import sys,json
cs=json.load(sys.stdin).get('containers',[])
cs=[c for c in cs if 'lab-manager' not in c.get('name','')]
[print(f'  [{i+1}] \033[0;36m{c[\"name\"]}\033[0m') for i,c in enumerate(cs)]
" 2>/dev/null)
    if [[ -z "$LIST" ]]; then
        log_warn "No containers running."; sleep 2
    else
        printf '%s\n\n' "$LIST"
        printf "  ${W}▸ select: ${N}"; read -r CHOICE
        local CID
        CID=$(printf '%s' "$JSON" | python3 -c "
import sys,json
try:
    cs=json.load(sys.stdin).get('containers',[])
    cs=[c for c in cs if 'lab-manager' not in c.get('name','')]
    print(cs[int(sys.argv[1])-1]['id'])
except: pass
" "arg0" "$CHOICE" 2>/dev/null)
        if [[ -z "$CID" ]]; then log_err "Invalid."; sleep 1; else
            printf "\n"; thin_sep
            curl -sf "$API/containers/$CID/logs" 2>/dev/null | python3 -c "
import sys,json
try:
    logs=json.load(sys.stdin).get('logs','')
except: logs='Error reading logs'
for l in logs.splitlines()[-60:]:
    print(f'  \033[2m{l}\033[0m')
" 2>/dev/null
            thin_sep; printf "\n"
            read -rp "  Press Enter to return..."
        fi
    fi
    tput smcup 2>/dev/null; tput civis 2>/dev/null
}

# ── tui_exit ──────────────────────────────────────────────────
tui_exit() {
    tput rmcup 2>/dev/null    # restore original scrollback
    tput cnorm 2>/dev/null
    printf "\n"
    log_warn "Stopping API server (PID $APP_PID)..."
    kill "$APP_PID" 2>/dev/null || true
    log_ok "Server stopped. Goodbye! 👋"
    printf "\n"
    exit 0
}

# ── main htop-style live dashboard ───────────────────────────
main_loop() {
    # Switch to the terminal's alternate screen buffer
    # (same trick htop, vim, less, etc. use)
    tput smcup 2>/dev/null
    tput civis 2>/dev/null   # hide cursor

    trap 'tput rmcup 2>/dev/null; tput cnorm 2>/dev/null
          printf "\n"; log_warn "Interrupted."; exit 1' INT TERM

    local last_render=0

    while true; do
        local now_ts; now_ts=$(date +%s)

        # ── fetch & repaint every 3 seconds ──────────────────
        if (( now_ts - last_render >= 3 )); then
            local JSON
            JSON=$(curl -sf "$API/containers" 2>/dev/null || echo '{"containers":[]}')
            render_screen "$JSON"
            last_render=$now_ts
        fi

        # ── poll for a single keypress (0.3 s window) ────────
        # No Enter required — just like htop
        local KEY=""
        IFS= read -r -s -n1 -t 0.3 KEY 2>/dev/null || true

        case "$KEY" in
            d|D)  cmd_deploy;           last_render=0 ;;
            s|S)  cmd_stop;             last_render=0 ;;
            l|L)  cmd_container_logs;   last_render=0 ;;
            r|R)  last_render=0 ;;          # force immediate repaint
            q|Q)  tui_exit ;;
        esac
    done
}

# ───────────────────────────── GO! ──────────────────────────
set +e
main_loop
