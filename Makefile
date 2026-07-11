.PHONY: lint test check clean

# Luacheck with project config
lint:
	luacheck . --config .luacheckrc

# Run all tests
test:
	busted tests/

# Full quality gate
check: lint test

# Clean build artifacts (if any)
clean:
	find . -name "*.luac" -delete
