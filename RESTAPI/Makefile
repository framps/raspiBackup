.DEFAULT_GOAL := all
TARGET=raspiBackupRESTListener
BIN_DIR=bin
MYFILES=$(shell go list ./... | grep -v /vendor/)

default: run-linux

all: build-raspi

setup:
	curl -s https://glide.sh/get | sh 2>/dev/null

build: setup
	glide install

run-linux: build
	go run ${TARGET}.go

build-raspi: build 
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go
