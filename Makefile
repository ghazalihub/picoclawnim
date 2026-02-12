# Makefile for PicoClaw Nim reimplementation

NIM_FLAGS = --mm:arc -d:release -d:danger --opt:size --passL:-s

all: build

build:
	nim c $(NIM_FLAGS) src/picoclaw.nim

debug:
	nim c src/picoclaw.nim

test:
	@echo "Running tests..."
	nim c -r src/logger.nim
	nim c -r src/config.nim
	nim c -r src/bus.nim
	nim c -r src/utils.nim
	nim c -r src/agent/session.nim
	nim c -r src/agent/memory.nim
	nim c -r src/agent/context.nim
	nim c -r src/tools/filesystem.nim
	nim c -r src/tools/shell.nim

clean:
	rm -f src/picoclaw
	rm -rf nimcache
