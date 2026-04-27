# 使用官方 Golang 镜像进行构建
FROM golang:alpine AS builder

# 设置工作目录
WORKDIR /app

# 1. 处理依赖（即使现在没用第三方库，养成这个习惯能避免 90% 的构建报错）
# 如果你没有 go.mod，这一步会报错，请先在本地运行 `go mod init my-service`
COPY go.mod ./
# 如果有 go.sum 也加上
# COPY go.sum ./
RUN go mod download

# 2. 复制源码并编译
COPY . .
# 强制禁用 CGO，确保二进制文件在 alpine 及其它微型镜像中完美运行
RUN CGO_ENABLED=0 GOOS=linux go build -o server main.go

# 3. 使用极小的 alpine 镜像作为运行环境
FROM alpine:latest
RUN apk --no-cache add ca-certificates

WORKDIR /root/
# 从构建阶段把编译好的二进制文件考过来
COPY --from=builder /app/server .

# 启动服务
CMD ["./server"]