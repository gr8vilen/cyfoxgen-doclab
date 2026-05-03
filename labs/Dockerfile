# Stage 1: Build the React application
FROM node:18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Serve the application with Nginx
FROM nginx:alpine
# Copy the build output to replace the default nginx contents.
COPY --from=build /app/build /usr/share/nginx/html
# Expose port 80
EXPOSE 80
# Run nginx
CMD ["nginx", "-g", "daemon off;"]
