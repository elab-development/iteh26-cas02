FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm install --no-audit --no-fund
COPY . .
EXPOSE 5000
CMD ["npm", "run", "dev"]
