ifneq ($(shell uname),Darwin)
	$(error "Must be run on macOS")
endif

# Make Configs
EXTENSION = Beancount.novaextension
BUILD_DIR ?= build

VERSION ?= $$(git describe --tags --abbrev=0)
VERSION ?= "dev"

# Tools
TS ?= tree-sitter

EXTENSION_FILES = extension.json extension.png \
	README.md LICENSE.md CHANGELOG.md \
	Images/ Scripts/ Queries/ Completions/ \
	de.lproj/ \
	Syntaxes Syntaxes/libtree-sitter-beancount.dylib

.PHONY: $(EXTENSION)
$(EXTENSION): build
	cp -r $(BUILD_DIR)/$(EXTENSION) $@

.PHONY: build
build: $(addprefix $(BUILD_DIR)/$(EXTENSION)/,$(EXTENSION_FILES))

.PHONY: install
install: build
	nova extension activate $(BUILD_DIR)/$(EXTENSION)

.PHONY: validate
validate: build
	nova extension validate $(BUILD_DIR)/$(EXTENSION)

.PHONY: publish
publish:
# TODO: Publish in Nova

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) $(EXTENSION)

# Extension Meta
$(BUILD_DIR)/$(EXTENSION)/extension.json: extension.json
	jq '.version = "abc"' $< > $@

# Static Files
$(BUILD_DIR)/$(EXTENSION)/%: $*
	mkdir -p $(dir $@)
	cp -r $* $@

# Tree Sitter Library
$(BUILD_DIR)/$(EXTENSION)/Syntaxes/libtree-sitter-beancount.dylib: $(BUILD_DIR)/libtree-sitter-beancount.dylib
	mkdir -p $(dir $@)
	cp $< $@
	codesign -s - $@

##### DYLIB Build Process #####

## install directory layout ##
PREFIX ?= /usr/local
INCLUDEDIR ?= $(PREFIX)/include
LIBDIR ?= $(PREFIX)/lib

## Source Files ##
SRC_DIR := $(BUILD_DIR)/src
SRC += $(BUILD_DIR)/src/scanner.c $(BUILD_DIR)/src/parser.c
OBJ := $(addsuffix .o,$(basename $(SRC)))

## Compilation Flags ##
# - Build both arm64 (Apple Silicon) and x86_64 (Intel)
# - Require a minimum of macOS 11.0
CFLAGS ?= -O3 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -I$(SRC_DIR)
CXXFLAGS ?= -O3 -Wall -Wextra -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -I$(SRC_DIR)
override CFLAGS += -std=gnu99 -fPIC
override CXXFLAGS += -fPIC

## Linker Flags ##
# - Include the /src/ directory for headers (for `tree_sitter/parser.h`)
LDFLAGS = -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -I$(SRC_DIR) -F/Applications/Nova.app/Contents/Frameworks/ -framework SyntaxKit -rpath @loader_path/../Frameworks

LINKSHARED := $(LINKSHARED)-dynamiclib -Wl,
ifneq ($(ADDITIONAL_LIBS),)
LINKSHARED := $(LINKSHARED)$(ADDITIONAL_LIBS),
endif
LINKSHARED := $(LINKSHARED)-install_name,$(LIBDIR)/libtree-sitter-beancount.dylib,-rpath,@executable_path/../Frameworks

$(BUILD_DIR)/libtree-sitter-beancount.dylib: $(OBJ)
	$(CC) $(LDFLAGS) $(LINKSHARED) $^ $(LDLIBS) -o $@

$(BUILD_DIR)/src/scanner.c: tree-sitter-beancount/src/scanner.c $(BUILD_DIR)/src/tree_sitter/parser.h
	cp $< $@

$(BUILD_DIR)/src/parser.c: $(BUILD_DIR)/src/tree_sitter/parser.h

$(BUILD_DIR)/src/tree_sitter/parser.h: tree-sitter-beancount/grammar.js
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && $(TS) generate --no-bindings $(realpath $<)