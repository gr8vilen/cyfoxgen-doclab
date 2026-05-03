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
