.PHONY: test benchmark

test:
	@nvim --headless -u spec/init.lua -i NONE -c "PlenaryBustedDirectory spec/ { minimal_init = 'spec/init.lua' }"

benchmark:
	@nvim --headless -u NONE -i NONE -l scripts/benchmark.lua
