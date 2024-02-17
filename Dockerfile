FROM dart:stable as build

WORKDIR /build
COPY pubspec.* .
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/main.dart -o bebtrk_server

FROM debian:bookworm-slim

RUN useradd -ms /bin/bash app
RUN apt-get update && apt-get install -y \
    ca-certificates \
    qrencode \
    tini

USER app
WORKDIR /opt/bebtrk
COPY --from=build /build/bebtrk_server .

EXPOSE 8900
ENTRYPOINT ["tini", "--"]
CMD ["/opt/bebtrk/bebtrk_server"]
