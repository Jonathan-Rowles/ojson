.PHONY: test clean generate build-generator

DEV_FLAGS := -vet -strict-style -debug

test:
	@mkdir -p bin
	@odin test ./jsonimpl -out:bin/test $(DEV_FLAGS) -define:ODIN_TEST_SHORT_LOGS=true -define:ODIN_TEST_LOG_LEVEL=warning
	@odin test ./generate -out:bin/test-gen $(DEV_FLAGS) -define:ODIN_TEST_SHORT_LOGS=true -define:ODIN_TEST_LOG_LEVEL=warning

build-generator:
	@mkdir -p bin
	@odin build ./generate -out:bin/generate $(DEV_FLAGS)

generate: build-generator
ifndef SRC
	$(error SRC is required. Usage: make generate SRC=. or make generate SRC=./models)
endif
	@./bin/generate -r $(SRC) -o unmarshal.gen.odin

clean:
	@rm -rf bin/
	@rm -f unmarshal.gen.odin
	@echo "cleaned"
