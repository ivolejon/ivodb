# IvoDB - Document Database Engine

A lightweight, document-oriented database engine written in Zig, featuring a custom storage engine with a Slotted Page architecture and LRU caching.

## Prerequisites
* **Zig 0.15.0** (or later). Check your version with `zig version`.

## Build and Run
To start the database in interactive mode (REPL):

```bash
zig build run
```

## Project Status & Checklist
- [x] Offset-based reading/writing to file.
- [x] Variable-length data storage in 4KB blocks.
- [x] LRU Cache and block eviction.
- [x] Mapping table names to page IDs in Block 0.
- [x]  Page-aware document insertion and isolation.
- [x] Cell-level and Table-level data traversal.
- [x] Lexer, tokenize input strings.
- [x] Convert tokens into executable Command structures.
- [x] repl, standard Input (stdin) handler.
- [x] Pretty-print query results in the terminal.
- [x] Table scans.
- [ ] Use uuidV7 to generate _id instad of random bytes
- [ ] Design the binary or text format for TCP packets.
- [ ] Basic listener using `std.net`.
- [ ] Route incoming network commands to the engine.
- [ ] Support for multiple simultaneous client connections.
- [ ] Basic filter (`GET key*`)
- [ ] Support for returning specific fields instead of full documents.
- [ ] Initial implementation indexes.

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| CREATE  | Creates a new table in the database. | CREATE users |
| USE     | Sets the active table for subsequent commands. | USE users |
| SET     | Inserts or updates a Key-Value pair (assigns an _id). | SET ivo developer |
| GET     | Retrieves a value by key and prints the hidden _id. | GET ivo |
| DELETE  | Removes a document by key. | DELETE ivo |