# syntax=docker/dockerfile:1
# Build docker-gen from scratch
FROM golang:1.25-alpine AS go-builder

ARG VERSION=23.12.0

ADD https://github.com/webdevops/go-crond.git#${VERSION} /build

WORKDIR /build

RUN go mod download -json \
    && go test ./... \
    && GOOS=${GOOS} GOARCH=${GOARCH} CGO_ENABLED=0 go build -ldflags "-X main.gitTag=${VERSION} -X main.gitCommit=github.com/amazeeio/go-crond -extldflags '-static' -s -w" -o go-crond .

FROM alpine:3.22

# Install docker-gen from build stage
COPY --from=go-builder /build/go-crond /usr/local/bin/go-crond

ENTRYPOINT ["/usr/local/bin/go-crond", "--version"]
