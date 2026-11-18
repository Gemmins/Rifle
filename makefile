.PHONY: all debug release rdbg run test test-unit test-e2e c clean docs

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

test: test-unit test-e2e

test-unit:
	mkdir -p bin
	odin test ./test/unit $(COLLECTIONS) -vet -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -out:./bin/unit-tests
	odin test ./bindings/c $(COLLECTIONS) -vet -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -out:./bin/c-binding-unit-tests

test-e2e: c
	mkdir -p bin
	odin test ./test/e2e $(COLLECTIONS) -vet -define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true -define:ODIN_TEST_RANDOM_SEED=123 -define:ODIN_TEST_THREADS=1 -out:./bin/e2e-tests
	cc -std=c11 -Wall -Wextra -Werror -I./bindings/c ./test/e2e/c_api_test.c -L./lib -lrifle -Wl,-rpath,'$$ORIGIN/../lib' -o ./bin/c-api-e2e-test
	./bin/c-api-e2e-test

docs:
	mkdir -p /docs/html
	doxygen Doxyfile

clean:
	rm -rf bin
	rm -rf lib
	rm -rf example/data*
	rm -rf docs/html
