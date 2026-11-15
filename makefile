.PHONY: all debug release rdbg run test clean

COLLECTIONS := -collection:rifle=./src

all: debug

debug:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle -vet -debug -o:none  -show-timings

release:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle -vet -o:speed -show-timings -no-bounds-check -disable-assert

rdbg:
	mkdir -p bin
	odin build ./example $(COLLECTIONS) -out:./bin/rifle -vet -debug -o:speed -show-timings  -no-bounds-check -disable-assert

run: debug
	./bin/rifle

vtab:
	mkdir -p lib
	odin build ./src/vtab $(COLLECTIONS) -out:./lib/rifle_vtab -vet -build-mode:shared -o:none -no-entry-point -show-timings

test:
	mkdir -p bin
	odin test ./test $(COLLECTIONS) -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -out:./bin/test

clean:
	rm -rf bin
	rm -rf lib
	rm -rf example/data*
