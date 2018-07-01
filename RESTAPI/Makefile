.DEFAULT_GOAL := run
TARGET=raspiBackupRESTListener
BIN_DIR=bin
MYFILES=$(shell go list ./... | grep -v /vendor/)

setup:
	curl -s https://glide.sh/get | sh 2>/dev/null

vendor: setup
	glide install

run:
	go run ${TARGET}.go

build: vendor unit-test
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go

unit-test:
	go test . -v
