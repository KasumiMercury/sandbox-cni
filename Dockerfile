FROM --platform=$BUILDPLATFORM golang:1.26.3 AS build
ARG TARGETOS TARGETARCH

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" \
    -o /out/sandbox-cni .

FROM alpine:3.22
LABEL org.opencontainers.image.source="https://github.com/KasumiMercury/sandbox-cni"
LABEL org.opencontainers.image.description="A learning-purpose CNI plugin"

RUN apk add --no-cache curl jq

COPY --from=build /out/sandbox-cni /sandbox-cni
COPY --chmod=0755 install.sh /install.sh

ENTRYPOINT ["/install.sh"]
