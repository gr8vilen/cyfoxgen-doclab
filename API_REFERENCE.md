# 🐳 uneo-HACKLAB API Reference (v6.2)

This document provides a detailed technical reference for the `uneo-HACKLAB` Docker Lab Manager API. 

## 🌐 Base URL
By default, the API service listens on all interfaces at port **62111**:
`http://localhost:62111` or `http://<host-ip>:62111`

---

## 🔐 Authentication
All state-changing operations (Deploy, Delete, Cleanup) require a JSON-based password authentication.
- **Header:** `Content-Type: application/json`
- **Body Requirement:** Include `"password": "YOUR_ACTUAL_PASSWORD"` in the root of your JSON request.

---

## 🚀 Endpoints

### 1. Deploy Container
Starts a new Docker container and assigns it a dedicated IP within the `lab-network`.

- **Method:** `POST`
- **Path:** `/deploy`
- **Request Body:**
  ```json
  {
    "password": "...",
    "image": "httpd:alpine",
    "name": "optional-name",
    "environment": { "KEY": "VALUE" },
    "volumes": { "/host/path": { "bind": "/cont/path", "mode": "rw" } },
    "command": "sh -c 'echo hello'"
  }
  ```
- **Success Response (201):**
  ```json
  {
    "success": true,
    "container": {
      "id": "...",
      "name": "lab-123",
      "image": "httpd:alpine",
      "ip": "172.20.0.x",
      "status": "running",
      "ports": ["80/tcp"],
      "created": 1714668000
    }
  }
  ```

### 2. List Containers
Lists all containers currently managed by the HACKLAB system.

- **Method:** `GET`
- **Path:** `/containers`
- **Response:**
  ```json
  {
    "containers": [
      { "id": "...", "name": "...", "ip": "172.20.0.x", "status": "running" }
    ]
  }
  ```

### 3. Get Container Details
Fetch specific metadata for a single container.

- **Method:** `GET`
- **Path:** `/containers/<cid>`
- **Response:** Container object.

### 4. Delete Container
Forcefully removes a container and releases its IP.

- **Method:** `DELETE`
- **Path:** `/containers/<cid>`
- **Request Body:**
  ```json
  { "password": "..." }
  ```

### 5. Get Container Logs
Fetch the last 100 lines of console output from a container.

- **Method:** `GET`
- **Path:** `/containers/<cid>/logs`
- **Response:**
  ```json
  { "logs": "output text here..." }
  ```

### 6. System Activity Logs
Fetch the internal logs of the Lab Manager (deployment events, errors, cleanups).

- **Method:** `GET`
- **Path:** `/system-logs`
- **Response:**
  ```json
  {
    "logs": [
      { "timestamp": "21:37:46", "message": "...", "type": "info|deployment|error" }
    ]
  }
  ```

### 7. Global Cleanup
Wipes all containers managed by the API.

- **Method:** `POST`
- **Path:** `/cleanup`
- **Request Body:**
  ```json
  { "password": "..." }
  ```

---

## 🍏 macOS Networking (Special Note)
On macOS, Docker runs inside a virtual machine. This means container IPs (like `172.20.0.x`) are not normally reachable from the Mac host.

**HACKLAB Solution:**
The installer automatically sets up `docker-mac-net-connect`. This utility creates a lightweight tunnel (WireGuard) that allows your Mac to talk directly to the `172.20.0.0/16` subnet.
- **Requirement:** You may be prompted for your macOS `sudo` password during installation to start this service.
- **Benefit:** You can access labs directly via their IP (e.g., `http://172.20.0.3`) in your browser, just like you would on Linux.

---

## 🛠️ Troubleshooting
1. **Connection Refused:** Ensure the API server is running (`ps aux | grep app.py`).
2. **Invalid Password:** Check the `KEY` displayed in the terminal dashboard.
3. **Cannot Reach IP (macOS):** Run `sudo brew services restart chipmk/tap/docker-mac-net-connect`.
