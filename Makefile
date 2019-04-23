Literate.html: Literate.md
	bin/lit Literate.md

fullbuild: Literate.html $(sources)
	dmd $(sources) -od=obj -of=bin/lit 
	bin/lit Literate.md

build: $(sources)
	dmd $(sources) -od=obj -of=bin/lit

sources = src/globals.d \
		  src/main.d \
		  src/parser.d \
		  src/tangler.d \
		  src/util.d \
		  src/weaver.d \
		  src/dmarkdown/html.d \
		  src/dmarkdown/markdown.d \
		  src/dmarkdown/package.d \
		  src/dmarkdown/string.d

