import express from "express";
import bodyParser from "body-parser";
import { exec } from "child_process";
import cors from "cors";
import os from "os";

const app = express();
const PORT = 3000;
const PASSWORD = Math.random().toString(36).substring(2, 8);

app.use(bodyParser.json());
app.use(cors());

const containers = [];
const log = (...args) => console.log(`[${new Date().toISOString()}]`, ...args);

function getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const iface of Object.values(interfaces)) {
        for (const config of iface) {
            if (config.family === "IPv4" && !config.internal) {
                return config.address;
            }
        }
    }
    return "localhost";
}

app.get("/", (req, res) => {
    res.send(`<h2>CyberLab Agent Running</h2><p>Logged Deployments:</p><pre>${containers.map(c => JSON.stringify(c, null, 2)).join("\n")}</pre>`);
});

app.post("/deploy", (req, res) => {
    const { image, containerPort = 80 } = req.body;

    if (!image) return res.status(400).send("Image is required.");

    const randPort = Math.floor(Math.random() * 1000 + 8000);
    const lastIP = Math.floor(Math.random() * 100 + 10);
    const ip = `192.168.100.${lastIP}`;

    const containerName = `lab_${Date.now()}`;
    const cmd = `docker run -d --name ${containerName} --network lab_net --ip ${ip} ${image}`;

    exec(cmd, (err, stdout, stderr) => {
        if (err) {
            log("❌ Failed:", err.message);
            return res.status(500).send("Deployment failed.");
        }
        const containerId = stdout.trim();
        const accessUrl = `http://${ip}:${containerPort}`;
        containers.push({ containerId, image, ip, containerPort, time: new Date().toISOString() });
        log(`🚀 ${image} container started at ${ip}:${containerPort}`);
        res.send({ success: true, ip, port: containerPort });
    });
});

app.listen(PORT, () => {
    const ip = getLocalIP();
    log(`🎯 Agent ready at ${ip}:${PORT}`);
    log(`🔑 Password: ${PASSWORD}`);

    exec("docker network inspect lab_net", (err) => {
        if (err) {
            exec("docker network create -d macvlan                 --subnet=192.168.100.0/24                 --gateway=192.168.100.1                 -o parent=eth0 lab_net", (e) => {
                if (e) log("❌ Macvlan error:", e.message);
                else log("✅ macvlan network 'lab_net' is ready.");
            });
        } else {
            log("✅ macvlan network already exists.");
        }
    });
});
