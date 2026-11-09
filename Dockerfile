# Build the Flutter web app and the Dart server, then ship a small runtime.
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release
RUN dart compile exe bin/server.dart -o server

FROM dart:stable AS runtime
WORKDIR /app
COPY --from=build /app/server ./server
COPY --from=build /app/build/web ./build/web

ENV PORT=8080
EXPOSE 8080

CMD ["./server"]
