# Build static assets, then serve with nginx — no Node.js needed at runtime,
# and employees just open a browser URL instead of running npm locally.
FROM node:20-slim AS build
WORKDIR /build
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /build/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
