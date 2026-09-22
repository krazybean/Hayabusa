FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/hayabusa-detection .

FROM alpine:3.22
RUN addgroup -S hayabusa && adduser -S -G hayabusa hayabusa
COPY --from=build /out/hayabusa-detection /usr/local/bin/hayabusa-detection
USER hayabusa
ENTRYPOINT ["/usr/local/bin/hayabusa-detection"]
