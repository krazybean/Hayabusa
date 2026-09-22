const net = require("net");

function parseNatsEndpoint(value) {
  const parsed = new URL(value);
  if (parsed.protocol !== "nats:") {
    throw new Error(`Unsupported NATS_URL protocol: ${parsed.protocol}`);
  }

  const port = Number(parsed.port || 4222);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("Invalid NATS_URL port");
  }

  return {
    host: parsed.hostname || "localhost",
    port,
  };
}

function createNatsClient(natsUrl) {
  const endpoint = parseNatsEndpoint(natsUrl);

  return {
    async publish(subject, payload) {
      if (!/^[A-Za-z0-9_.-]+$/.test(subject)) {
        throw new Error("Invalid NATS subject");
      }

      const body = Buffer.from(JSON.stringify(payload));
      const command = Buffer.concat([
        Buffer.from('CONNECT {"verbose":false,"pedantic":false,"lang":"node","version":"hayabusa-demo"}\r\n'),
        Buffer.from(`PUB ${subject} ${body.length}\r\n`),
        body,
        Buffer.from("\r\nPING\r\n"),
      ]);

      return new Promise((resolve, reject) => {
        const socket = net.createConnection(endpoint);
        let buffer = "";
        let sent = false;
        const timeout = setTimeout(() => {
          socket.destroy();
          reject(new Error(`NATS publish timed out for ${endpoint.host}:${endpoint.port}`));
        }, 4000);

        const finish = (fn, value) => {
          clearTimeout(timeout);
          socket.destroy();
          fn(value);
        };

        socket.on("connect", () => socket.setEncoding("utf8"));
        socket.on("data", (chunk) => {
          buffer += chunk;
          if (!sent && buffer.includes("INFO")) {
            sent = true;
            socket.write(command);
          }
          if (buffer.includes("-ERR")) {
            return finish(reject, new Error(buffer.trim()));
          }
          if (buffer.includes("PONG")) {
            clearTimeout(timeout);
            socket.end();
            resolve();
          }
        });
        socket.on("error", (err) => finish(reject, err));
      });
    },

    async check() {
      return new Promise((resolve) => {
        const socket = net.createConnection(endpoint);
        const timeout = setTimeout(() => {
          socket.destroy();
          resolve(false);
        }, 1500);

        socket.on("connect", () => {
          clearTimeout(timeout);
          socket.end();
          resolve(true);
        });
        socket.on("error", () => {
          clearTimeout(timeout);
          resolve(false);
        });
      });
    },
  };
}

module.exports = {
  createNatsClient,
  parseNatsEndpoint,
};
