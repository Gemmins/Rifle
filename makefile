.PHONY: all debug release rdbg run test c test-c clean docs

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

c:
	mkdir -p lib
	odin build ./bindings/c $(COLLECTIONS) -out:./lib/librifle.so -vet -build-mode:shared -o:speed -no-entry-point -no-bounds-check

test:
	mkdir -p bin
	odin test ./test $(COLLECTIONS) -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -out:./bin/test

docs:
	mkdir -p /docs/html
	doxygen Doxyfile

clean:
	rm -rf bin
	rm -rf lib
	rm -rf example/data*
	rm -rf docs/html
