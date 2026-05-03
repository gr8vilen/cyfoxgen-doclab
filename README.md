# Dockerization & Deployment Guide

This guide walks you through the complete process of containerizing the React application and pushing it to GitHub Packages (GitHub Container Registry).

## Prerequisites

- **Docker:** Ensure Docker Desktop or the Docker Engine is installed and running on your machine.
- **GitHub Account:** You need a GitHub account to publish the package.
- **Personal Access Token (PAT):** A GitHub PAT with `write:packages` and `read:packages` scopes.

---

## 1. Project Docker Files

We have created three critical files in the root of the `/labs` directory to handle the Docker environment:

### `Dockerfile`
We use a **multi-stage build** to keep the final image size as small as possible.
- **Stage 1 (Build):** Uses a Node.js image to install dependencies and compile the production build (`npm run build`).
- **Stage 2 (Serve):** Uses a lightweight Nginx web server to serve the static compiled files.

### `.dockerignore`
This file behaves like `.gitignore` but for Docker. It prevents large directories like `node_modules` and the local `build` folder from being sent to the Docker daemon, significantly speeding up the build process.

### `docker-compose.yml`
A simple compose file that allows you to quickly spin up the environment locally for testing without writing long Docker commands.

---

## 2. Building the Image

To build the image and tag it for the GitHub Container Registry (`ghcr.io`), ensure you are inside the `/labs` directory and run:

```bash
docker build -t ghcr.io/gr8vilen/cyfoxgen-doclab-labs:latest .
```

*Note: The `.` at the end is crucial as it tells Docker to look for the `Dockerfile` in the current directory.*

---

## 3. Testing Locally

Before pushing your image to the cloud, it's always a good idea to verify that it works on your local machine.

### Run via Docker CLI
You can spin up the container and map it to port `8080` on your machine:

```bash
docker run -p 8080:80 ghcr.io/gr8vilen/cyfoxgen-doclab-labs:latest
```
Open your browser and navigate to [http://localhost:8080](http://localhost:8080) to view the app.

*(Press `Ctrl + C` in your terminal to stop the container).*

### Check Image Size
To verify how large the built image is:
```bash
docker images ghcr.io/gr8vilen/cyfoxgen-doclab-labs:latest
```
Look under the **SIZE** column.

---

## 4. Pushing to GitHub Packages

Once you are satisfied with the local build, you can push it to the GitHub Container Registry.

### Step 4a: Authenticate with GitHub
You must log in to the GitHub registry via the Docker CLI. You will need your Personal Access Token (PAT) for this step.

Run the following command, replacing `YOUR_GITHUB_PAT` with your actual token:

```bash
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u gr8vilen --password-stdin
```

If successful, you will see a `Login Succeeded` message.

### Step 4b: Push the Image
Since we already tagged the image correctly during the build step, you only need to run the push command:

```bash
docker push ghcr.io/gr8vilen/cyfoxgen-doclab-labs:latest
```

Docker will begin pushing the individual layers of the image to your GitHub account. 

---

## 5. Verifying the Deployment

1. Navigate to your GitHub profile or the `cyfoxgen-doclab` repository page.
2. Click on the **Packages** tab on the right sidebar.
3. You should see `cyfoxgen-doclab-labs` listed as a Docker container package.
4. From here, anyone with access (or publicly, if you change the package visibility) can pull the image using:

```bash
docker pull ghcr.io/gr8vilen/cyfoxgen-doclab-labs:latest
```



# API ref

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
