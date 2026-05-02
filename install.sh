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

# ───────────────────────────── WRITE TUI.PY ─────────────────
log_step "Writing Textual TUI app..."

cat > "$APP_DIR/tui.py" << 'TUIEOF'
#!/usr/bin/env python3
"""
cyfoxgen DocLab — Textual TUI
Monitoring dashboard: system logs (left) + container cards with logs (right).
Usage: python3 tui.py <password> <api_pid>
"""

import sys, os, json, time, threading
import urllib.request, urllib.error

PASS    = sys.argv[1] if len(sys.argv) > 1 else ""
API_PID = sys.argv[2] if len(sys.argv) > 2 else ""
API     = "http://localhost:62111"

# ── API helpers ───────────────────────────────────────────────
def api(method, path, body=None):
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

# ── Textual ───────────────────────────────────────────────────
from textual.app        import App, ComposeResult
from textual.widgets    import Header, Footer, Static, RichLog, Label
from textual.containers import Horizontal, Vertical, Container, ScrollableContainer
from textual.screen     import ModalScreen
from textual.binding    import Binding
from textual            import work, on
from textual.reactive   import reactive
from rich.text          import Text
from rich.panel         import Panel
from rich               import box as rbox

# ── CSS ───────────────────────────────────────────────────────
CSS = """
Screen { background: #0a0a0a; }

#logo {
    height: 8;
    color: #00ff41;
    text-style: bold;
    border-bottom: solid #1c3a1c;
    padding: 0 2;
}

#statusbar {
    height: 1;
    background: #001800;
    color: #00ff41;
    padding: 0 2;
}

#main {
    height: 1fr;
}

/* ── Left: system logs ── */
#logs-panel {
    width: 2fr;
    border: solid #00ff41;
    border-title-color: #00ff41;
    border-title-style: bold;
    background: #050f05;
}

/* ── Right: containers ── */
#containers-panel {
    width: 3fr;
    border: solid #00ccff;
    border-title-color: #00ccff;
    border-title-style: bold;
    background: #05080f;
    overflow-y: auto;
}

.empty-msg {
    color: #444444;
    padding: 2 4;
}

/* Container card */
.ccard {
    border: solid #1a3a1a;
    background: #060f06;
    margin: 1 1;
    padding: 0 1;
    height: auto;
}

.ccard.running {
    border: solid #00ff41;
}

.ccard.exited {
    border: solid #ff4444;
}

.card-header {
    height: 3;
    background: #001200;
    padding: 0 1;
}

.card-name   { color: #00ffff; text-style: bold; }
.card-ip     { color: #ffff00; }
.card-image  { color: #555555; }
.badge-run   { color: #000000; background: #00ff41; text-style: bold; }
.badge-exit  { color: #ffffff; background: #ff4444; text-style: bold; }

.card-log {
    height: 6;
    background: #010901;
    border-top: solid #1a2a1a;
    padding: 0 1;
    overflow: hidden;
}

/* ── Modals ── */
StopScreen  { align: center middle; }
#stop-box {
    width: 54;
    height: auto;
    border: double #ff4444;
    background: #0f0303;
    padding: 1 2;
}
.stop-title { color: #ff4444; text-style: bold; margin-bottom: 1; }

Footer { background: #001100; color: #00cc44; }
"""

from textual.widgets import Button

# ── Stop Modal ────────────────────────────────────────────────
class StopScreen(ModalScreen):
    BINDINGS = [Binding("escape", "dismiss", "Cancel")]

    def __init__(self, cinfo: dict):
        super().__init__()
        self.cinfo = cinfo

    def compose(self) -> ComposeResult:
        c = self.cinfo
        with Container(id="stop-box"):
            yield Label("🗑  Stop Container", classes="stop-title")
            yield Label(f"  Name : {c.get('name','?')}")
            yield Label(f"  IP   : {c.get('ip','?')}")
            yield Label(f"  Image: {c.get('image','?')}", classes="field-hint")
            yield Label("")
            yield Label("  Press  Y  to confirm  or  Escape to cancel")
            with Horizontal(classes="btn-row"):
                yield Button("Y — Stop", id="yes", classes="go")
                yield Button("✕ Cancel", id="nop", classes="cancel")

    @on(Button.Pressed, "#yes")
    def confirm(self): self.dismiss(True)

    @on(Button.Pressed, "#nop")
    def cancel(self):  self.dismiss(False)

    def on_key(self, ev):
        if ev.key == "y": self.dismiss(True)

# ── Container Card widget ─────────────────────────────────────
class ContainerCard(Static):
    """One card per container — shows status badge, IP, image, recent logs."""

    def __init__(self, cinfo: dict):
        super().__init__()
        self.cinfo = cinfo
        status = cinfo.get("status", "unknown")
        self.add_class("ccard")
        self.add_class("running" if status == "running" else "exited")

    def compose(self) -> ComposeResult:
        c      = self.cinfo
        status = c.get("status", "?")
        is_run = status == "running"
        badge  = Text(" ▶ RUNNING ", style="bold black on #00ff41") if is_run \
            else Text(f" ■ {status.upper()} ", style="bold white on #ff4444")

        with Horizontal(classes="card-header"):
            yield Label(Text.assemble(
                Text("📦 ", style=""),
                Text(c.get("name", "?"), style="bold cyan"),
                Text("  "),
                badge,
            ), classes="card-name")

        yield Label(
            Text.assemble(
                Text("🌐 ", style=""),
                Text(c.get("ip", "?"), style="yellow"),
                Text("   ", style=""),
                Text(c.get("image", "?"), style="dim"),
            ),
            classes="card-ip",
        )
        yield RichLog(id=f"clog-{c['id'][:12]}", classes="card-log",
                      wrap=False, highlight=False, markup=False)

    def on_mount(self):
        self._load_logs()

    @work(thread=True)
    def _load_logs(self):
        cid  = self.cinfo.get("id", "")
        resp = api("GET", f"/containers/{cid}/logs")
        raw  = (resp.get("logs", "") if resp else "") or ""
        lines = [l for l in raw.splitlines() if l.strip()][-15:]
        def update():
            try:
                rlog = self.query_one(f"#clog-{cid[:12]}", RichLog)
                if not lines:
                    rlog.write("[dim]no logs yet[/dim]")
                else:
                    for line in lines:
                        rlog.write(line)
                rlog.scroll_end(animate=False)
            except Exception:
                pass
        self.call_from_thread(update)

# ── Main App ──────────────────────────────────────────────────
class DocLabTUI(App):
    CSS      = CSS
    TITLE    = "cyfoxgen DocLab"
    BINDINGS = [
        Binding("s", "stop",    "Stop",    show=True),
        Binding("r", "refresh", "Refresh", show=True),
        Binding("q", "quit",    "Quit",    show=True),
    ]

    _containers: list = []

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Static(self._banner(), id="logo")
        yield Static("", id="statusbar")
        with Horizontal(id="main"):
            # Left — system log stream
            with Container(id="logs-panel"):
                yield RichLog(id="syslog", wrap=True,
                              highlight=False, markup=True)
            # Right — container cards (populated dynamically by _paint_containers)
            with ScrollableContainer(id="containers-panel"):
                pass
        yield Footer()

    def on_mount(self):
        self.query_one("#logs-panel").border_title = "◉  SYSTEM LOGS"
        self.query_one("#containers-panel").border_title = "● CONTAINERS"
        self.set_interval(3, self._refresh)
        self._refresh()

    def _banner(self) -> str:
        return (
            "  ██████╗  ██████╗  ██████╗██╗      █████╗ ██████╗ \n"
            "  ██╔══██╗██╔═══██╗██╔════╝██║     ██╔══██╗██╔══██╗\n"
            "  ██║  ██║██║   ██║██║     ██║     ███████║██████╔╝\n"
            "  ██║  ██║██║   ██║██║     ██║     ██╔══██║██╔══██╗\n"
            "  ██████╔╝╚██████╔╝╚██████╗███████╗██║  ██║██████╔╝\n"
            "  ╚═════╝  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝╚═════╝ \n"
            "        D O C K E R   L A B   M A N A G E R   v2.0  "
        )

    # ── Data refresh ─────────────────────────────────────────
    def _refresh(self):
        self._fetch_syslogs()
        self._fetch_containers()

    @work(thread=True)
    def _fetch_syslogs(self):
        resp = api("GET", "/system-logs")
        logs = resp.get("logs", []) if resp else []
        self.call_from_thread(self._paint_syslogs, logs)

    def _paint_syslogs(self, logs):
        colors = {
            "info":       "green",
            "warning":    "yellow",
            "error":      "red",
            "deployment": "cyan",
        }
        rlog = self.query_one("#syslog", RichLog)
        rlog.clear()
        for l in logs[-60:]:
            col = colors.get(l.get("type", "info"), "green")
            ts  = l.get("timestamp", "")
            msg = l.get("message", "")
            rlog.write(f"[dim][{ts}][/dim] [{col}]{msg}[/{col}]")
        rlog.scroll_end(animate=False)

    @work(thread=True)
    def _fetch_containers(self):
        resp = api("GET", "/containers")
        cs   = []
        if resp and "containers" in resp:
            cs = [c for c in resp["containers"]
                  if "lab-manager" not in c.get("name", "")]
        self.call_from_thread(self._paint_containers, cs)

    def _paint_containers(self, cs):
        self._containers = cs

        # Status bar
        now = time.strftime("%H:%M:%S")
        self.query_one("#statusbar", Static).update(
            f"  PID: {API_PID}   KEY: {PASS}   {now}"
            f"   {len(cs)} container(s) active"
        )

        # Container panel title
        self.query_one("#containers-panel").border_title = \
            f"● CONTAINERS  ({len(cs)})"

        # Rebuild cards
        panel = self.query_one("#containers-panel", ScrollableContainer)
        panel.remove_children()

        if not cs:
            panel.mount(Label(
                "  — no containers deployed yet —",
                classes="empty-msg"
            ))
        else:
            for c in cs:
                panel.mount(ContainerCard(c))

    # ── Actions ───────────────────────────────────────────────
    def action_refresh(self):
        self._refresh()

    def action_quit(self):
        if API_PID:
            try: os.kill(int(API_PID), 15)
            except Exception: pass
        self.exit()

    def action_stop(self):
        cs = self._containers
        if not cs:
            self.notify("No containers to stop.", severity="warning")
            return
        # Stop the first running container (or let user pick via arrow keys in future)
        # For now: if only one, stop it; if multiple, notify user to use number
        running = [c for c in cs if c.get("status") == "running"]
        if not running:
            self.notify("No running containers.", severity="warning")
            return
        c = running[0] if len(running) == 1 else None
        if not c:
            self.notify(
                f"{len(running)} containers running. Click a card then press S.",
                severity="information",
            )
            return

        def after(confirmed):
            if confirmed:
                self._do_stop(c)

        self.push_screen(StopScreen(c), after)

    @work(thread=True)
    def _do_stop(self, c):
        resp = api("DELETE", f"/containers/{c['id']}", {"password": PASS})
        if resp and resp.get("success"):
            self.call_from_thread(
                self.notify,
                f"✔ Removed: {c.get('name')}",
                severity="information",
            )
        else:
            err = resp.get("error", "?") if resp else "No response"
            self.call_from_thread(
                self.notify, f"✘ {err}",
                title="Stop Failed", severity="error",
            )
        self.call_from_thread(self._refresh)

if __name__ == "__main__":
    DocLabTUI().run()
TUIEOF

log_ok "TUI written to $APP_DIR/tui.py"
echo ""

# ───────────────────────────── LAUNCH TUI ───────────────────
log_step "Launching DocLab TUI..."
echo ""
python3 "$APP_DIR/tui.py" "$LAB_PASSWORD" "$APP_PID"

log_ok "Session ended."
