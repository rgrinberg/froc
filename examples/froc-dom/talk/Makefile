JS=talk.js

all: myocamlbuild.ml
	ocamlbuild $(JS); ln -s _build/$(JS) .

clean:
	ocamlbuild -clean
	rm -f myocamlbuild.ml $(JS)

myocamlbuild.ml:
	ln -s ../../../tools/myocamlbuild.ml
