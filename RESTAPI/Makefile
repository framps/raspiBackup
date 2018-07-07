.DEFAULT_GOAL := all
TARGET=raspiBackupRESTListener
BIN_DIR=bin
MYFILES=$(shell go list ./... | grep -v /vendor/)
GLIDE := $(shell command -v glide 2> /dev/null)

all: setup vendor build unit-test run

setup:
ifndef GLIDE
	curl -s https://glide.sh/get | sh 2>/dev/null
endif

vendor: setup
	glide install

run:
	go run ${TARGET}.go

build: vendor unit-test
	OOS=linux GOARCH=arm GOARM=7 go build -o ${BIN_DIR}/${TARGET} ${TARGET}.go

unit-test:
	go test . -v
