# syntax=docker/dockerfile:1
# Build go-crond from scratch
FROM golang:1.25-alpine AS go-builder

ARG VERSION=23.12.0

ADD https://github.com/webdevops/go-crond.git#${VERSION} /build

WORKDIR /build

RUN go mod download -json \
    && go test ./... \
    && GOOS=${GOOS} GOARCH=${GOARCH} CGO_ENABLED=0 go build -ldflags "-X main.gitTag=${VERSION} -X main.gitCommit=github.com/amazeeio/go-crond -extldflags '-static' -s -w" -o go-crond .

FROM alpine:3.22

LABEL org.opencontainers.image.title="go-crond" \
    org.opencontainers.image.description="A simple cron daemon written in Go" \
    org.opencontainers.image.url="https://github.com/amazeeio/go-crond" \
    org.opencontainers.image.source="https://github.com/amazeeio/go-crond.git" \
    org.opencontainers.image.authors="packaged by amazee.io, original work by WebDevOps Team <hello@webdevops.io>" \
    org.opencontainers.image.licenses="GPL-2.0"

# Install go-crond from build stage
COPY --from=go-builder /build/go-crond /usr/local/bin/go-crond

ENTRYPOINT ["/usr/local/bin/go-crond", "--version"]
