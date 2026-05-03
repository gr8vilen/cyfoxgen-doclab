# How to Convert a Basic React App into a Docker Lab

This guide explains step-by-step how to take a standard React application, containerize it efficiently, and deploy it to GitHub Packages so it can be seamlessly used by the `uneo-HACKLAB` manager across any operating system (like Kali Linux or Windows).

---

## Step 1: Create the `.dockerignore`
Before building anything, we need to stop Docker from copying unnecessary files (like the massive `node_modules` folder). This speeds up the build process significantly.

Create a file named `.dockerignore` in the root of your React app and add:
```text
node_modules
npm-debug.log
build
.dockerignore
**/.git
**/.DS_Store
```

---

## Step 2: Create the `Dockerfile`
We use a **Multi-Stage Build**. This means we use a "fat" Node.js environment to compile the React code, but then copy *only* the finished, compiled static files into a "slim" Nginx web server. This keeps the final image incredibly small and fast to download.

Create a file named `Dockerfile` (no extension) and add exactly this:

```dockerfile
# STAGE 1: Build the React application
FROM node:18-alpine AS build
WORKDIR /app
# Copy package files first to cache dependencies
COPY package*.json ./
RUN npm ci
# Copy the rest of the code and build it
COPY . .
RUN npm run build

# STAGE 2: Serve the application with Nginx
FROM nginx:alpine
# Copy the compiled files from Stage 1 into the Nginx public folder
COPY --from=build /app/build /usr/share/nginx/html
# Expose port 80 for web traffic
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## Step 3: Build the Image (Cross-Platform Warning!)
You must build the Docker image and tag it for the GitHub Container Registry (`ghcr.io`). 

**⚠️ CRITICAL FOR MAC USERS:** If you are building this on an Apple Silicon Mac (M1/M2/M3), Docker will default to building an `arm64` image. If you try to run this on a standard Intel/AMD computer (like a Kali Linux VM), it will fail with a `404 Not Found` error. 

To prevent this, you **must** force Docker to build an `amd64` Linux image using the `--platform` flag:

```bash
docker build --platform linux/amd64 -t ghcr.io/YOUR_USERNAME/hacklab-react:latest .
```
*(Replace `YOUR_USERNAME` and the image name as needed).*

---

## Step 4: Authenticate with GitHub Packages
Before you can push the image to the internet, your terminal must be logged into GitHub. You will need a GitHub Personal Access Token (PAT) with `write:packages` permissions.

```bash
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

---

## Step 5: Push the Image
Once authenticated, push the newly built image up to GitHub:

```bash
docker push ghcr.io/YOUR_USERNAME/hacklab-react:latest
```

---

## Step 6: ⚠️ Make the Package PUBLIC
By default, GitHub makes all uploaded Docker images **Private**. If you don't change this, the `uneo-HACKLAB` deployment script on other computers will get a `404 Not Found` error because it tries to pull anonymously.

1. Open your browser and go to your GitHub Packages: `https://github.com/YOUR_USERNAME?tab=packages`
2. Click on your newly pushed package (e.g., `hacklab-react`).
3. On the right-hand sidebar, click **Package Settings**.
4. Scroll all the way down to the red **Danger Zone**.
5. Click **Change visibility**.
6. Select **Public** and type the package name to confirm.

---

## Step 7: Deploy via the Lab Manager
Your image is now a fully functional Docker Lab! You can deploy it to any student machine or server by sending a request to the `install.sh` API:

```bash
curl -X POST http://localhost:62111/deploy \
  -H "Content-Type: application/json" \
  -d '{"password": "YOUR_DASHBOARD_KEY", "image": "ghcr.io/YOUR_USERNAME/hacklab-react:latest", "name": "my-new-lab"}'
```
