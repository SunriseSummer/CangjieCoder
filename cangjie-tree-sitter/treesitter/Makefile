# Build libtree_sitter_cangjie.so — bundles tree-sitter runtime + Cangjie grammar
CC      ?= gcc
CFLAGS  := -std=c11 -fPIC -D_DEFAULT_SOURCE -I. -I./tree_sitter \
           -Wno-unused-but-set-variable -Wno-unused-parameter -Wno-format-security
TARGET  := libtree_sitter_cangjie.so

OBJS := ts_runtime.o cangjie_parser.o cangjie_scanner.o

all: $(TARGET)

ts_runtime.o: ts_lib.c
	$(CC) $(CFLAGS) -c $< -o $@

cangjie_parser.o: cangjie_parser.c
	$(CC) $(CFLAGS) -c $< -o $@

cangjie_scanner.o: cangjie_scanner.c
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) -shared -fPIC $(OBJS) -o $@

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean
