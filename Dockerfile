FROM golang:1.9.4
LABEL maintainer="The Stripe Observability Team <support@stripe.com>"

RUN mkdir -p /build
ENV GOPATH=/go
RUN printf "deb [trusted=yes] http://archive.debian.org/debian buster main contrib non-free\n" > /etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=true update && \
    apt-get install -y --allow-unauthenticated zip curl unzip git wget

RUN rm -rf /go/src/github.com/golang/protobuf && \
    mkdir -p /go/src/github.com/golang && \
    git clone https://github.com/golang/protobuf /go/src/github.com/golang/protobuf && \
    cd /go/src/github.com/golang/protobuf && \
    git checkout v1.3.5 && \
    go install github.com/golang/protobuf/protoc-gen-go

RUN rm -rf /go/src/github.com/gogo/protobuf && \
    mkdir -p /go/src/github.com/gogo && \
    git clone https://github.com/gogo/protobuf /go/src/github.com/gogo/protobuf && \
    cd /go/src/github.com/gogo/protobuf && \
    git checkout v0.5 && \
    go install github.com/gogo/protobuf/protoc-gen-gofast

RUN go get -u -v github.com/ChimeraCoder/gojson/gojson
WORKDIR /go/src/github.com/gogo/protobuf
RUN git fetch
RUN git checkout v0.5
RUN go install github.com/gogo/protobuf/protoc-gen-gofast
WORKDIR /go
RUN go get -u github.com/golang/dep/cmd/dep
RUN rm -rf /go/src/golang.org/x/tools && \
    mkdir -p /go/src/golang.org/x && \
    git clone https://github.com/golang/tools /go/src/golang.org/x/tools && \
    cd /go/src/golang.org/x/tools && \
    git checkout release-branch.go1.9 && \
    go install golang.org/x/tools/cmd/stringer
RUN ARCH="$(uname -m)" && \
    if [ "$ARCH" = "x86_64" ]; then \
      PROTOC_VERSION="3.1.0"; \
      PROTOC_ZIP="protoc-3.1.0-linux-x86_64.zip"; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
      PROTOC_VERSION="3.6.0"; \
      PROTOC_ZIP="protoc-3.6.0-linux-aarch_64.zip"; \
    else \
      echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    wget "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ZIP}" && \
    unzip "${PROTOC_ZIP}" && \
    cp bin/protoc /usr/bin/protoc && \
    chmod 755 /usr/bin/protoc

WORKDIR /go/src/github.com/stripe/veneur
ADD . /go/src/github.com/stripe/veneur

# If running locally, ignore any changes since
# the last commit
RUN git reset --hard HEAD && git status

# Unlike the travis build file, we do NOT need to
# ignore changes to protobuf-generated output
# because we are guaranteed only one version of Go
# used to build protoc-gen-go
RUN go generate
RUN dep ensure -v
RUN gofmt -w .

# Stage any changes caused by go generate and gofmt,
# then confirm that there are no staged changes.
#
# If `go generate` or `gofmt` yielded any changes,
# this will fail with an error message like "too many arguments"
# or "M: binary operator expected"
# Due to overlayfs peculiarities, running git diff-index without --cached
# won't work, because it'll compare the mtimes (which have changed), and
# therefore reports that the file may have changed (ie, a series of 0s)
# See https://github.com/stripe/veneur/pull/110#discussion_r92843581
RUN git add .
# The output will be empty unless the build fails, in which case this
# information is helpful in debugging
RUN git diff --cached
RUN git diff-index --cached --exit-code HEAD


RUN go test -race -v -timeout 60s -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./...
CMD cp -r henson /build/ && env GOBIN=/build go install -a -v -ldflags "-X github.com/stripe/veneur.VERSION=$(git rev-parse HEAD) -X github.com/stripe/veneur.BUILD_DATE=$(date +%s)" ./cmd/...
