#include "./alloc.c"
#include "./get_changed_ranges.c"
#include "./language.c"
#include "./lexer.c"
#include "./node.c"
#include "./parser.c"
#include "./query.c"
#include "./stack.c"
#include "./subtree.c"
#include "./tree_cursor.c"
#include "./tree.c"
#include "./wasm_store.c"

// Utility: write raw bytes directly to stdout fd (bypasses all buffering).
// Cangjie's ConsoleWriter.flush() may not flush to the OS pipe, so we
// provide a direct-write path for MCP stdio transport.
#include <unistd.h>

int cj_write_stdout(const char *data, int len) {
    int written = 0;
    while (written < len) {
        int n = write(STDOUT_FILENO, data + written, len - written);
        if (n <= 0) return -1;
        written += n;
    }
    return written;
}

