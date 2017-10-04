.DEFAULT_GOAL := all
TARGET=raspiBackupRESTListener
BIN_DIR=bin
MYFILES=$(shell go list ./... | grep -v /vendor/)

default: run-linux

all: build-raspi

setup:
	curl -s https://glide.sh/get | sh 2>/dev/null
	go get github.com/go-swagger/go-swagger/cmd/swagger

build: setup
	glide install

swagger:
	swagger generate spec -o ./swagger/swagger.json
	swagger validate ./swagger/swagger.json

run-linux: build
	go run ${TARGET}.go

build-raspi: build swagger
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go
