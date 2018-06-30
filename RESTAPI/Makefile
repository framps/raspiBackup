.DEFAULT_GOAL := all
TARGET=raspiBackupRESTListener
BIN_DIR=bin
MYFILES=$(shell go list ./... | grep -v /vendor/)

default: run-linux

all: build-raspi

setup:
	curl -s https://glide.sh/get | sh 2>/dev/null

vendor: setup
	glide install

run-linux: vendor unit-test
	go run ${TARGET}.go

build-raspi: vendor unit-test
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go

unit-test:
	go test . -v
