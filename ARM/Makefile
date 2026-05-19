SHELL := /bin/sh

ARM_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
UPSTREAM_ROOT ?= $(abspath $(ARM_ROOT)/../upstream-lapee)
BUILD_DIR ?= $(ARM_ROOT)/build
INSTALL_PREFIX ?= /opt/lapee-arm
CONFIG_DIR ?= /etc/lapee-arm

export ARM_ROOT UPSTREAM_ROOT BUILD_DIR INSTALL_PREFIX CONFIG_DIR

.PHONY: help deps build run install service start stop status display clean

help:
	@printf '%s\n' \
	  'LapEE ARM/Raspberry Pi 4 targets:' \
	  '  make deps       Install Raspberry Pi OS build dependencies' \
	  '  make build      Build HyperBEAM with the LapEE overlay for ARM64' \
	  '  make run        Run the built node in the foreground' \
	  '  sudo make install   Install runtime and systemd unit' \
	  '  sudo make start     Start HyperBEAM for this boot only' \
	  '  sudo make display   Start the local display on tty2' \
	  '  sudo make stop      Stop the display and node' \
	  '  make status     Show service status' \
	  '  make clean      Remove ARM/build only'

deps:
	sh ./scripts/install-deps.sh

build:
	bash ./scripts/build-hyperbeam.sh

run:
	bash ./scripts/run-hyperbeam.sh

install:
	bash ./scripts/install-service.sh

service:
	$(MAKE) start

start:
	systemctl daemon-reload
	systemctl start lapee-hyperbeam.service

display:
	systemctl start lapee-splash.service
	-command -v chvt >/dev/null 2>&1 && chvt 2

stop:
	-systemctl stop lapee-splash.service
	-systemctl stop lapee-hyperbeam.service

status:
	systemctl status lapee-hyperbeam.service --no-pager
	-systemctl status lapee-splash.service --no-pager

clean:
	rm -rf "$(BUILD_DIR)"
