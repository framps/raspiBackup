TARGET=raspiBackupRESTListener
BIN_DIR=bin

default: run-linux

all: 	build-raspi

setup:
	go mod init ${TARGET}
	go mod tidy
build: 
	go build ${TARGET}		

run-linux: build
	go run ${TARGET}.go

build-raspi: build
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go
