# Builds clientdeck-loader (see main.c / claude-blocks/python-qt-startup-splash.claude.md).
# Requires: a C compiler, libx11-dev, libxinerama-dev (or equivalents),
# and `uv` (only for the build-time PNG->header step — see gen_splash_header.py).

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MAKEFILE_DIR)/../..)

BUILD_DIR := $(MAKEFILE_DIR)build
GEN_DIR := $(MAKEFILE_DIR)generated
SPLASH_PNG := $(REPO_ROOT)/resources/splash_screen.png
SPLASH_HEADER := $(GEN_DIR)/splash_image_data.h
TARGET := $(BUILD_DIR)/clientdeck-loader

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11
LDLIBS := -lX11 -lXinerama -lm
UV_RUN := uv run --project $(REPO_ROOT) python

.PHONY: all clean

all: $(TARGET)

$(SPLASH_HEADER): $(SPLASH_PNG) $(MAKEFILE_DIR)gen_splash_header.py
	mkdir -p $(GEN_DIR)
	$(UV_RUN) $(MAKEFILE_DIR)gen_splash_header.py $(SPLASH_PNG) $(SPLASH_HEADER)

$(TARGET): $(MAKEFILE_DIR)main.c $(SPLASH_HEADER)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(GEN_DIR) -o $(TARGET) $(MAKEFILE_DIR)main.c $(LDLIBS)

clean:
	rm -rf $(BUILD_DIR) $(GEN_DIR)
