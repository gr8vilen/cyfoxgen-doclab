import express from "express";
import bodyParser from "body-parser";
import cors from "cors";
import { exec } from "child_process";
import os from "os";
import crypto from "crypto";

const app = express();
const PORT = 3000;
const LOGS = [];
const PASSWORD = crypto.randomBytes(3).toString("hex");

app.use(cors());
app.use(bodyParser.json());

const network = "lab_net";
const subnet = "192.168.100";
let usedIPs = new Set();

function getAvailableIP() {
  for (let i = 2; i < 254; i++) {
    const ip = `${subnet}.${i}`;
    if (!usedIPs.has(ip)) {
      usedIPs.add(ip);
      return ip;
    }
  }
  return null;
}

function getRandomPort() {
  return Math.floor(Math.random() * 1000) + 8000;
}

app.get("/", (_, res) => {
  const ip = Object.values(os.networkInterfaces())
    .flat()
    .find(i => i.family === "IPv4" && !i.internal).address;

  res.send(`
    <pre>
🎯 Agent ready at ${ip}:${PORT}
🔑 Password: ${PASSWORD}

Logs:
${LOGS.slice(-10).join('\n')}
    </pre>
  `);
});

app.post("/deploy", (req, res) => {
  const { image } = req.body;

  const ip = getAvailableIP();
  const port = getRandomPort();

  if (!ip) return res.status(500).json({ error: "No available IPs" });

  const cmd = `docker run -dit --rm \
    --network=${network} --ip=${ip} \
    -p ${port}:80 ${image}`;

  exec(cmd, (err, stdout) => {
    if (err) {
      console.error(err);
      LOGS.push(`❌ Failed to deploy ${image}`);
      return res.status(500).json({ error: "Docker error" });
    }

    LOGS.push(`🚀 ${image} container started at ${ip}:${port}`);
    res.json({ ip, port });
  });
});

app.listen(PORT, () => {
  const ip = Object.values(os.networkInterfaces())
    .flat()
    .find(i => i.family === "IPv4" && !i.internal).address;

  console.log(`[${new Date().toISOString()}] 🎯 Agent ready at ${ip}:${PORT}`);
  console.log(`[${new Date().toISOString()}] 🔑 Password: ${PASSWORD}`);
});
