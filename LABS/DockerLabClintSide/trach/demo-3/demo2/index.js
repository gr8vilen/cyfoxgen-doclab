import express from "express";
import cors from "cors";
import { exec } from "child_process";
import os from "os";

const app = express();
app.use(cors());
app.use(express.json());

const logs = [];
const usedIPs = new Set();

function addLog(msg) {
  const timestamp = new Date().toISOString();
  const log = `[${timestamp}] ${msg}`;
  logs.push(log);
  console.log(log);
}

function getInterface() {
  const interfaces = os.networkInterfaces();
  for (let name in interfaces) {
    for (let iface of interfaces[name]) {
      if (!iface.internal && iface.family === 'IPv4') return name;
    }
  }
  return "eth0";
}

function setupMacvlanNetwork() {
  const iface = getInterface();
  const cmd = `docker network inspect lab_net || \
docker network create -d macvlan \
--subnet=192.168.100.0/24 \
--gateway=192.168.100.1 \
-o parent=${iface} lab_net`;

  exec(cmd, (err, stdout, stderr) => {
    if (err) addLog(`❌ Macvlan error: ${stderr}`);
    else addLog("✅ macvlan network 'lab_net' is ready.");
  });
}

app.get("/", (req, res) => {
  res.send(`<h1>🛰️ CyberLab Agent</h1>
<p><strong>IP:</strong> ${getLocalIP()}<br>
<strong>Port:</strong> 3000<br>
<strong>Password:</strong> ${agentPassword}</p>
<pre>${logs.join("\n")}</pre>`);
});

// Function to check if an IP is actually in use by a container
function checkIPInUse(ip) {
  return new Promise((resolve) => {
    exec(`docker ps --filter network=lab_net --format "{{.Networks}}" | grep ${ip}`, (err, stdout) => {
      resolve(stdout.trim().length > 0);
    });
  });
}

// Function to initialize usedIPs by checking running containers
async function initializeUsedIPs() {
  exec('docker ps --filter network=lab_net --format "{{.Networks}}"', async (err, stdout) => {
    if (err) {
      addLog(`❌ Error checking running containers: ${err}`);
      return;
    }
    
    const ips = stdout.split('\n').filter(line => line.includes('lab_net'));
    for (const line of ips) {
      const match = line.match(/192\.168\.100\.\d+/);
      if (match) {
        usedIPs.add(match[0]);
      }
    }
    addLog(`📊 Found ${usedIPs.size} containers using IPs in lab_net`);
  });
}

async function getNextAvailableIP() {
  const base = "192.168.100.";
  for (let i = 10; i <= 254; i++) {
    const ip = base + i;
    if (!usedIPs.has(ip)) {
      const isInUse = await checkIPInUse(ip);
      if (!isInUse) {
        usedIPs.add(ip);
        return ip;
      }
    }
  }
  throw new Error("No available IPs in the range");
}

app.post("/deploy", async (req, res) => {
  const { type, image, port } = req.body;
  if (!port) {
    return res.status(400).json({ error: "Port mapping is required" });
  }

  const containerImage = image || (type === "php" ? "php:8.0-apache" : "httpd");
  const containerName = `container_${Date.now()}`;
  
  try {
    const ip = await getNextAvailableIP();
    const hostPort = parseInt(port);
    const cmd = `docker run -d --name ${containerName} \
--network lab_net --ip ${ip} \
-p ${hostPort}:80 ${containerImage}`;

    exec(cmd, (err, stdout, stderr) => {
      if (err) {
        usedIPs.delete(ip); // Release the IP if container creation fails
        addLog(`❌ Deploy failed: ${stderr}`);
        return res.status(500).json({ error: "Deploy failed" });
      }
      addLog(`🚀 Container ${containerName} started at ${ip}:${hostPort}`);
      res.json({ ip, port: hostPort, containerName });
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (let name in interfaces) {
    for (let iface of interfaces[name]) {
      if (!iface.internal && iface.family === 'IPv4') return iface.address;
    }
  }
  return "localhost";
}

const agentPassword = Math.random().toString(36).substring(2, 8);

app.listen(3000, () => {
  setupMacvlanNetwork();
  initializeUsedIPs(); // Initialize IP tracking when server starts
  addLog(`🎯 Agent ready at ${getLocalIP()}:3000`);
  addLog(`🔑 Password: ${agentPassword}`);
});
