FROM node:20-alpine
WORKDIR /app
COPY package.json ./
COPY server.js ./
COPY public/ ./public/
EXPOSE 80
ENV PORT=80
CMD ["node", "server.js"]
