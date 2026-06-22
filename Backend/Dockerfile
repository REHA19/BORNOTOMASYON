# Multi-stage build: compile with the full Swift toolchain, ship a slim runtime image.
# This lets a VM run the backend with only Docker installed — no manual Swift setup
# needed (Plan §0/§6: avoids the Windows Swift-toolchain dead end entirely).
FROM swift:6.1-jammy AS build
WORKDIR /build

COPY Package.swift Package.resolved* ./
RUN swift package resolve

COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product App --static-swift-stdlib -Xswiftc -j1

FROM swift:6.1-jammy-slim
WORKDIR /app
COPY --from=build /build/.build/release/App ./App

EXPOSE 8080
ENV PORT=8080
CMD ["./App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
