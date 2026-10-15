.PHONY: all debug release run test clean

COLLECTIONS := -collection:rifle=./src

all: debug

debug:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle -vet -debug -o:none -show-timings

release:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle -vet -no-bounds-check -disable-assert -o:speed -show-timings

rdbg: 
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle -vet -no-bounds-check -disable-assert -debug -o:speed -show-timings

run: debug
	./bin/rifle

test:
	mkdir -p bin
	odin test ./test $(COLLECTIONS) -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -out:./bin/test

clean:
	rm -rf bin
	rm -rf example/idk
