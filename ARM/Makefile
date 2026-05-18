SHELL := /bin/sh

ARM_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
UPSTREAM_ROOT ?= $(abspath $(ARM_ROOT)/../upstream-lapee)
BUILD_DIR ?= $(ARM_ROOT)/build
INSTALL_PREFIX ?= /opt/lapee-arm
CONFIG_DIR ?= /etc/lapee-arm

export ARM_ROOT UPSTREAM_ROOT BUILD_DIR INSTALL_PREFIX CONFIG_DIR

.PHONY: help deps build run install service clean

help:
	@printf '%s\n' \
	  'LapEE ARM/Raspberry Pi 4 targets:' \
	  '  make deps       Install Raspberry Pi OS build dependencies' \
	  '  make build      Build HyperBEAM with the LapEE overlay for ARM64' \
	  '  make run        Run the built node in the foreground' \
	  '  sudo make install   Install runtime and systemd unit' \
	  '  sudo make service   Enable and start lapee-hyperbeam.service' \
	  '  make clean      Remove ARM/build only'

deps:
	./scripts/install-deps.sh

build:
	./scripts/build-hyperbeam.sh

run:
	./scripts/run-hyperbeam.sh

install:
	./scripts/install-service.sh

service:
	systemctl daemon-reload
	systemctl enable --now lapee-hyperbeam.service

clean:
	rm -rf "$(BUILD_DIR)"
