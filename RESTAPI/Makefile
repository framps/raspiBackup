TARGET=raspiBackupRESTListener
BIN_DIR=.

default: build 

setup:
	go mod init ${TARGET}
	go mod tidy

run: build
	go run ${TARGET}.go

build: 
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go
