FROM swift:6.1.3-noble AS build
WORKDIR /build
COPY Packages/CatanEngine Packages/CatanEngine
COPY Packages/CatanAI Packages/CatanAI
COPY Packages/EmpiresOnline Packages/EmpiresOnline
COPY Packages/EmpiresOnlineServer Packages/EmpiresOnlineServer
RUN swift build --package-path Packages/EmpiresOnlineServer -c release --jobs 2 \
    --force-resolved-versions --product empires-online-server --static-swift-stdlib \
    && install -D "$(swift build --package-path Packages/EmpiresOnlineServer -c release --show-bin-path)/empires-online-server" /staging/empires-online-server

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4t64 libxml2 tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0700 -o 10001 -g 10001 /var/lib/empires-online
WORKDIR /srv/empires
COPY --from=build /staging/empires-online-server ./empires-online-server
ENV EMPIRES_ONLINE_BIND_ADDRESS=0.0.0.0
ENV EMPIRES_ONLINE_DATA_DIRECTORY=/var/lib/empires-online
ENV PORT=8080
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/srv/empires/empires-online-server"]
