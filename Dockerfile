FROM node:20-alpine
WORKDIR /app
COPY workers/cobalt-gateway/package.json ./
RUN npm install --omit=dev
COPY workers/cobalt-gateway/server.mjs ./
EXPOSE 8080
CMD ["npm","start"]
