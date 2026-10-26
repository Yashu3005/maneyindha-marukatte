FROM node:20-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
# Don't run the API as root.
USER node
EXPOSE 5000
CMD ["node", "src/server.js"]
