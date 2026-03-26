FROM golang:1.25
ARG TARGETARCH
MAINTAINER The Stripe Observability Team <support@stripe.com>

RUN mkdir -p /build
ENV GOPATH=/go

# 1. Added protobuf-compiler so protoc is installed natively for both AMD64 and ARM64
RUN apt-get update && apt-get install -y zip protobuf-compiler

# 2. Install standard tools using modern module-aware 'go install'
RUN go install github.com/ChimeraCoder/gojson/gojson@latest
RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.2
RUN go install golang.org/x/tools/cmd/stringer@v0.1.8

# 3. Download pre-compiled dep binary based on target architecture (avoids x/sync build errors)
RUN wget https://github.com/golang/dep/releases/download/v0.5.4/dep-linux-${TARGETARCH} -O /go/bin/dep && chmod +x /go/bin/dep

# 4. Disable module mode to support legacy GOPATH operations
ENV GO111MODULE=off

# 5. Manually clone and checkout the pinned gogo/protobuf version using git 
RUN git clone https://github.com/gogo/protobuf.git /go/src/github.com/gogo/protobuf
WORKDIR /go/src/github.com/gogo/protobuf
RUN git checkout v0.5
RUN go install ./protoc-gen-gofast

WORKDIR /go

# 6. Build the main project using legacy GOPATH + dep
WORKDIR /go/src/github.com/stripe/veneur
ADD . /go/src/github.com/stripe/veneur

# If running locally, ignore any changes since the last commit
RUN git reset --hard HEAD && git status

RUN GOOS=linux GOARCH=amd64 go generate ./...
RUN dep ensure -v
RUN gofmt -w .

RUN git add .
RUN git diff --cached
RUN git diff-index --cached --exit-code HEAD

RUN go test -race -v -timeout 60s -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./...
CMD cp -r henson /build/ && env GOBIN=/build go install -a -v -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./cmd/...

