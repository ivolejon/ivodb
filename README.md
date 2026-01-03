# IvoDB - Document Database Engine

A lightweight, document-oriented database engine written in Zig, featuring a custom storage engine with a Slotted Page architecture and LRU caching.

## Project Status & Checklist

### 🛠 Core Engine
- [x] **Disk I/O Layer**: Offset-based reading/writing to file.
- [x] **Slotted Page System**: Variable-length data storage in 4KB blocks.
- [x] **LRU Cache (Pager)**: Memory management and block eviction.
- [x] **Database Catalog**: Mapping table names to page IDs in Block 0.
- [x] **Table Logic**: Page-aware document insertion and isolation.
- [x] **Iterators**: Cell-level and Table-level data traversal.

---

### 🚀 Roadmap: REPL / CLI (Local Interaction)
- [x] **Lexer**: Tokenize input strings (e.g., "INSERT", "FROM", "{").
- [x] **Parser**: Convert tokens into executable Command structures.
- [x] **REPL Loop**: Standard Input (stdin) handler.
- [ ] **Result Formatter**: Pretty-print query results in the terminal.

---

### 🌐 Roadmap: Networking & Server (TCP)
- [ ] **Protocol Definition**: Design the binary or text format for TCP packets.
- [ ] **TCP Server**: Basic listener using `std.net`.
- [ ] **Connection Handler**: Route incoming network commands to the engine.
- [ ] **Concurrency**: Support for multiple simultaneous client connections.

---

### 🔍 Roadmap: Query Features
- [ ] **Filtering**: Add `WHERE` clause support to the iterators.
- [ ] **Selection**: Support for returning specific fields instead of full documents.
- [ ] **Basic Indexing**: Initial implementation of B-Tree or Hash indexes.