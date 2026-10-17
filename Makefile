.PHONY: all build test clean
all: build
build:
	./scripts/build.sh
test:
	./scripts/test.sh
clean:
	rm -rf build
