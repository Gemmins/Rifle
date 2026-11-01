.PHONY: all debug release rdbg run old-debug old-release old-rdbg old-run test clean

COLLECTIONS := -collection:rifle=./src

all: debug

old-debug:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle-old -vet -debug -o:none -show-timings

old-release:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle-old -vet -no-bounds-check -disable-assert -o:speed -show-timings

old-rdbg:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle-old -vet -no-bounds-check -disable-assert -debug -o:speed -show-timings

old-run: old-debug
	./bin/rifle-old

debug:
	mkdir -p bin
	odin build ./example_new $(COLLECTIONS) -out:./bin/rifle -vet -debug -o:none

release:
	mkdir -p bin
	odin build ./example_new $(COLLECTIONS) -out:./bin/rifle -vet -o:speed

rdbg:
	mkdir -p bin
	odin build ./example_new $(COLLECTIONS) -out:./bin/rifle -vet -debug -o:speed

run: debug
	./bin/rifle

test:
	mkdir -p bin
	odin test ./test $(COLLECTIONS) -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -out:./bin/test

clean:
	rm -rf bin
	rm -rf example/idk
