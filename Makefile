all:
	rm -rf bin && iced -I inline -cb -o . src && echo "#!/usr/bin/env node" | cat - bin/portmanteau.js > bin/portmanteau && rm bin/portmanteau.js

test:
	./node_modules/.bin/mocha --reporter spec

.PHONY: test

	{exec} = require 'child_process'