FROM golang:1.13
LABEL maintainer="The Stripe Observability Team <support@stripe.com>"

ENV GOPATH=/go
ENV GO111MODULE=off
ENV PATH=$GOPATH/bin:$PATH
RUN printf "deb http://archive.debian.org/debian buster main contrib non-free\n" > /etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update && \
    apt-get install -y zip curl unzip git

RUN GO111MODULE=on go install github.com/gogo/protobuf/protoc-gen-gofast@v1.2.1 && \
    GO111MODULE=on go install golang.org/x/tools/cmd/stringer@v0.1.7 && \
    GO111MODULE=on go install github.com/golang/mock/mockgen@v1.6.0 && \
    GO111MODULE=on go install github.com/ChimeraCoder/gojson/gojson@latest

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

WORKDIR /go/src/github.com/stripe/veneur
ADD . /go/src/github.com/stripe/veneur

RUN git reset --hard HEAD && git status
RUN go generate
RUN mv vendor ../vendor && gofmt -w . && mv ../vendor vendor
RUN git add . && git diff --cached

RUN mkdir -p /build

CMD cp -r henson /build/ && \
    env GOBIN=/build go install -a -v \
    -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" \
    ./cmd/...

