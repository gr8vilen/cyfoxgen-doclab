FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
  curl iproute2 net-tools ipcalc docker.io nodejs npm

WORKDIR /app
COPY . .

RUN npm install

EXPOSE 3000
CMD ["node", "index.js"]
