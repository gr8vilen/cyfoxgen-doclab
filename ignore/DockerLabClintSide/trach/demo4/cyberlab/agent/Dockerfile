FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
  docker.io nodejs npm iproute2 net-tools ipcalc curl

WORKDIR /app

COPY . .

RUN npm install

RUN chmod +x network.sh && ./network.sh

CMD ["node", "index.js"]
