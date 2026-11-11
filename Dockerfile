# Build the Flutter web app and the Dart server, then ship a small runtime.
#
# Pinned to linux/amd64 (Render's architecture) so the build is reproducible:
# the base image supplies the build dependencies (git, clang, etc.), but
# cirruslabs' `stable` tag lags the official releases (its latest is Flutter
# 3.44.0 / Dart 3.12.0) and this project needs Dart >= 3.13.0. Overlay the
# official stable SDK (x64 only) so the toolchain is pinned and current.
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:stable AS build

ARG FLUTTER_VERSION=3.47.9
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl xz-utils ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz; \
    rm -rf /sdks/flutter; \
    tar -xJf /tmp/flutter.tar.xz -C /sdks; \
    rm -f /tmp/flutter.tar.xz; \
    git config --global --add safe.directory /sdks/flutter
ENV PATH="/sdks/flutter/bin:${PATH}"
ENV FLUTTER_VERSION=${FLUTTER_VERSION}

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release
RUN dart compile exe bin/server.dart -o server

FROM --platform=linux/amd64 dart:stable AS runtime
WORKDIR /app
COPY --from=build /app/server ./server
COPY --from=build /app/build/web ./build/web

ENV PORT=8080
EXPOSE 8080

CMD ["./server"]
