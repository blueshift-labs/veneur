FROM golang:1.25
MAINTAINER The Stripe Observability Team <support@stripe.com>

RUN mkdir -p /build
ENV GOPATH=/go
RUN apt-get update && apt-get install -y zip

# 1. Install standard tools using Go 1.17's module-aware 'go install'
RUN go install github.com/ChimeraCoder/gojson/gojson@latest
RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.2
RUN go install github.com/golang/dep/cmd/dep@latest
RUN go install golang.org/x/tools/cmd/stringer@latest

# 2. Disable module mode to support legacy GOPATH operations (dep and gogo/protobuf)
ENV GO111MODULE=off

# 3. Manually clone and checkout the pinned gogo/protobuf version using git 
#    instead of the deprecated 'go get -d'
RUN git clone https://github.com/gogo/protobuf.git /go/src/github.com/gogo/protobuf
WORKDIR /go/src/github.com/gogo/protobuf
RUN git checkout v0.5
RUN go install ./protoc-gen-gofast

WORKDIR /go

# 4. Install protoc binary
RUN wget https://github.com/google/protobuf/releases/download/v3.1.0/protoc-3.1.0-linux-x86_64.zip
RUN unzip protoc-3.1.0-linux-x86_64.zip
RUN cp bin/protoc /usr/bin/protoc
RUN chmod 777 /usr/bin/protoc

# 5. Build the main project using legacy GOPATH + dep
WORKDIR /go/src/github.com/stripe/veneur
ADD . /go/src/github.com/stripe/veneur

# If running locally, ignore any changes since the last commit
RUN git reset --hard HEAD && git status

RUN go generate
RUN dep ensure -v
RUN gofmt -w .

RUN git add .
RUN git diff --cached
RUN git diff-index --cached --exit-code HEAD

RUN go test -race -v -timeout 60s -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./...
CMD cp -r henson /build/ && env GOBIN=/build go install -a -v -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./cmd/...

