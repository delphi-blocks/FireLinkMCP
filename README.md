# FireLink MCP

An [MCP](https://modelcontextprotocol.io) server, written in Delphi, that exposes your **local databases** to an AI client. Point it at a database and the assistant can query it and explore its structure — without you pasting schemas into a chat window, and without the data ever leaving your machine.

Database access goes through **FireDAC**; the MCP protocol layer is handled by the [MCPConnect](https://github.com/delphi-blocks/MCPConnect) framework.

## What it does

- **Runs SQL** — both read queries (results come back as JSON) and write commands. There is no read-only gate: what the assistant may do is whatever the configured user account may do, so give it a restricted login if that matters to you.
- **Explores schema** — tables and views with their comments, columns with type, nullability and comments, primary and foreign keys, and indexes (including unique/primary flags, functional expressions and partial-index filters).
- **Reads stored code** — lists procedures, triggers and packages, and returns their DDL source.
- **Serves several databases at once** — each one is a named section in a config file, and every request names the database it targets.
- **Keeps passwords out of cleartext** — a password typed into the config file is automatically sealed with the Windows Data Protection API (bound to your user and machine), or can be read from an environment variable instead. No key is stored in the executable.

Two executables ship the same server logic over different transports: a **console app** speaking MCP over stdio (what an MCP client launches as a subprocess) and a **VCL app** serving MCP over HTTP via Indy, useful for browser testing.

## Supported databases

FireDAC can talk to far more engines than this server currently wires up, and being wired up is not the same as having been exercised against a real server. The three levels:

| Database | Status | Notes |
|---|---|---|
| Firebird | ✅ Tested | Reads columns from the system catalog, so a column shows its **domain** name; reconstructs full procedure/trigger DDL headers |
| PostgreSQL | ✅ Tested | Verified against PostgreSQL 15 |
| Oracle | ✅ Tested | The whole connect identifier goes in `Database` (TNS alias or Easy Connect); `Server` is ignored |
| SQLite | ✅ Tested | Linked statically — no `sqlite3.dll` needed |
| MySQL | ⚙️ Implemented | MariaDB should work through the same driver |
| SQL Server | ⚙️ Implemented | Comments (extended properties) not implemented |
| InterBase, DB2, SQL Anywhere, Informix, Sybase ASE, Advantage, Teradata, NexusDB, MS Access, MongoDB, any ODBC source | ○ Possible via FireDAC | No manager yet — see below |

- **✅ Tested** — used against a live database during development.
- **⚙️ Implemented** — a database manager exists and is registered, but it has not been run against a real server. Expect the core to work and the dialect-specific catalog queries to need a look.
- **○ Possible via FireDAC** — FireDAC has a driver, but this server has no manager for it yet.

Adding one is deliberately cheap: the MCP layer depends on an abstraction (`IDatabaseManager`) with no FireDAC types in it. Subclass `TDatabaseManagerBase`, register the new type key in the unit's `initialization`, and reference it from the config file. No MCP or tool code changes.

## Configuration

Connections live in `%USERPROFILE%\.FireLink\databases.ini`, outside the repository. The file is created with fully commented examples on first run — read it, it documents every key. In short: one `[section]` per database (the section name is what requests refer to), a required `Type`, an optional `Password` carrying an explicit scheme (`env:`, `plain:`, `dpapi:`), and every other key passed straight to FireDAC as a connection parameter.

You never write a `dpapi:` value by hand: type the password as `plain:` and the server seals it in place at the next start, or as soon as that database connects if it was added while the server was running. The MCP client never sees it — passwords are read only to open a connection, and no tool returns them.

One key is handled specially: `VendorLib` takes the full path to the DBMS client library (`libpq.dll`, `oci.dll`, `fbclient.dll`, …) for when that DLL is not on the `PATH` nor next to the executable. It must match the server's bitness.

## Building

Requires the RAD Studio IDE toolchain (**BDS 37.0 / Delphi 13**, Win32). The only direct dependency is [MCPConnect](https://github.com/delphi-blocks/MCPConnect), which in turn brings in Neon and Logify. Nothing is vendored: they all resolve from the global IDE library path.

```powershell
$env:BDS = "C:\Program Files (x86)\Embarcadero\Studio\37.0"
msbuild Source\FireLinkMCPGroup.groupproj /t:Build /p:config=Debug /p:platform=Win32
```

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 - present, Delphi Building Blocks.
