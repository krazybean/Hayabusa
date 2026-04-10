FROM golang:1.25.9-alpine AS build

WORKDIR /src

COPY go.mod go.sum* ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/hayabusa-ingest .

FROM alpine:3.22

RUN adduser -D -H -s /sbin/nologin hayabusa
USER hayabusa

COPY --from=build /out/hayabusa-ingest /usr/local/bin/hayabusa-ingest

ENTRYPOINT ["/usr/local/bin/hayabusa-ingest"]
