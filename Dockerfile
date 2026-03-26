FROM golang:1.17
LABEL maintainer="The Stripe Observability Team <support@stripe.com>"

ENV GOPATH=/go
ENV GO111MODULE=on

# Install dependencies
RUN apt-get update && apt-get install -y zip curl unzip git

# Install required Go tools
RUN go install github.com/gogo/protobuf/protoc-gen-gogofaster@v1.2.1 && \
    go install golang.org/x/tools/cmd/stringer@v0.1.7 && \
    go install github.com/golang/mock/mockgen@v1.6.0

# Install protoc based on architecture
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v3.5.0/protoc-3.5.0-linux-x86_64.zip"; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        PROTOC_URL="https://github.com/protocolbuffers/protobuf/releases/download/v3.5.0/protoc-3.5.0-linux-aarch_64.zip"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -LO "$PROTOC_URL" && \
    unzip protoc-*.zip -d /usr/local && \
    chmod +x /usr/local/bin/protoc && \
    rm protoc-*.zip

WORKDIR /veneur
ADD . /veneur

# Reset and clean repo state
RUN git reset --hard HEAD && git status

# Generate protobuf
RUN go generate

# Format code (excluding vendor)
RUN mv vendor ../ && gofmt -w . && mv ../vendor .

# Stage any changes caused by generate/gofmt
RUN git add . && git diff --cached

RUN mkdir -p /build

#RUN go test -race -v -timeout 60s -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./...
CMD cp -r henson /build/ && env GOBIN=/build go install -a -v -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./cmd/...

