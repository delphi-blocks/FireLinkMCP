# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**FireLink MCP** — an MCP (Model Context Protocol) server, written in Delphi, that exposes **local databases** as MCP tools, so an AI client can run SQL and inspect schema (tables, views, columns, keys, indexes, procedures, triggers, packages, DDL) on this machine. Database access goes through **FireDAC**; the MCP plumbing is the **MCPConnect** framework. The server ships as two transports of the same server logic.

## Layout

```
FireLinkMCP/
  CLAUDE.md
  Source/
    FireLink.Config.pas              single point of server configuration
    FireLink.Database.Intf.pas       DB abstraction (no FireDAC)
    FireLink.Database.FireDAC.pas    FireDAC implementation + per-dialect subclasses
    FireLink.Database.Catalog.pas    databases.ini → opened IDatabaseManager
    FireLink.Database.Tools.pas      the [McpTool] surface
    FireLink.Security.DPAPI.pas      Windows DPAPI protect/unprotect
    FireLinkMCPGroup.groupproj       project group (both transports)
    Stdio/FireLinkMCP.dpr            console transport
    Indy/FireLinkMCPIndy.dpr         VCL/HTTP transport + FireLink.Form.Console
```

Shared units live in `Source\`; each transport is a thin `.dpr` in its own subfolder referencing them via `..\`.

## Two transports, one shared core

- **`Source\Stdio\FireLinkMCP.dpr`** — console app, MCP over stdio (`TJRPCStdioServer`). This is what an MCP client launches as a subprocess.
- **`Source\Indy\FireLinkMCPIndy.dpr`** — VCL GUI app, MCP over HTTP via Indy (`TJRPCIndyServer`); `FireLink.Form.Console.pas` is the form that starts/stops the listener and picks a port. Useful for browser/HTTP testing.

Both call the **single point of configuration**: `TServerConfigurator.ConfigureServer` in `FireLink.Config.pas` — server metadata, `[Tools, Resources]` capabilities, icon folder (`<exe dir>\data\icons`), CORS, content writers, and `RegisterClass(TDatabaseTools)`. It also calls `TDatabaseCatalog.EnsureConfigFile` at startup. Any change there applies to both transports automatically; adding a transport = new `.dpr` that calls `ConfigureServer`. An auth-token plugin block is present but commented out.

### Note on the rename / de-scoping

The Delphi-compilation tools (`list_products`, `compile`) and the `TProduct` unit behind them were **removed** — this server is database-only. One trace is intentionally left: the DPAPI entropy string in `FireLink.Security.DPAPI.pas` is still `'DelphiMCP'`. **Do not change it** — it would invalidate every password already sealed as `dpapi:` in a user's `databases.ini`.

## Database access

Tools: `list_databases`, `execute_query`, `execute_command`, `list_tables` /
`list_views` (each with its comment), `get_table_metadata` (columns: type / nullability / comment,
plus primary key and foreign keys), `get_view_metadata` (columns), `list_indexes` (a table's
indexes: columns with sort, `UNIQUE`/`PRIMARY` flags, functional expression, partial-index filter,
comment), `list_procedures`, `list_triggers` (all or by table), `list_packages` (Oracle),
`get_source` (DDL of a procedure/trigger/package). The design is deliberately decoupled from FireDAC
so a different component (e.g. UniDAC) can be added later:

- `FireLink.Database.Intf.pas` — the abstraction the MCP layer depends on: `IDatabaseManager`
  (`Configure`/`Open`/`Close`/`ExecuteQuery`/`ExecuteCommand`/`GetRelations`/`GetColumns`/
  `GetTableConstraints`/`GetIndexes`/`GetObjectNames`/`GetObjectSource`), the enums `TDBObjectKind`
  (`okProcedure`/`okTrigger`/`okPackage`) and `TRelationKind` (`rkTable`/`rkView`), the structured
  records `TDBRelationInfo` / `TDBColumnInfo` / `TDBForeignKey` / `TDBTableConstraints` /
  `TDBIndexInfo` (the manager
  returns **data**, the tool layer formats the readable text), `TDatabaseManagerBase` (ref-counted),
  and `TDatabaseFactory`, a registry keyed by database-type string → concrete class. **No FireDAC
  dependency.**
- `FireLink.Database.FireDAC.pas` — `TFireDACDatabaseManager` + thin per-DB subclasses
  (`TFirebirdDatabaseManager`, `TPostgresDatabaseManager`, `TSQLiteDatabaseManager`,
  `TMySQLDatabaseManager`, `TMSSQLDatabaseManager`, `TOracleDatabaseManager`). Each fixes its FireDAC
  `DriverID` and overrides the `SQLObjectNames`/`SQLObjectSource` hooks to supply the dialect's
  system-catalog queries for procedures/triggers/packages (base runs them via `RunNameList` /
  `RunSourceText`; an empty hook result means "unsupported for this DB" → a clear error).
  `TFirebirdDatabaseManager` instead **overrides `GetObjectSource`**: the Firebird catalog stores
  only the PSQL body, so it reconstructs the full DDL header — procedure `(params)` / `RETURNS`
  (domain name when the parameter uses one, else a base type rebuilt from `RDB$FIELDS`), and the
  trigger `FOR <table>` / `ACTIVE|INACTIVE BEFORE|AFTER <events> POSITION n` clause (trigger-type
  bitmask decoded, multi-action supported) — then joins it to the body via `ComposeWithAS`.
  Table/view **structure** (relation lists, columns + type + nullability, PK, FK) is read
  **DB-agnostically** from FireDAC metadata: `TFDConnection.GetTableNames` with `tkTable`/`tkView`,
  and `TFDMetaInfoQuery` with `mkTableFields` (via `ObjectName`), `mkPrimaryKeyFields` (via
  `BaseObjectName`), `mkForeignKeys` (via `ObjectName`) + `mkForeignKeyFields` (via
  `BaseObjectName` + `ObjectName`=FK). **Indexes** (`GetIndexes`) are DB-agnostic for the core:
  `mkIndexes` (via `ObjectName`; `INDEX_TYPE` decoded against `TFDPhysIndexKind` =
  `ikNonUnique`/`ikUnique`/`ikPrimaryKey`) + `mkIndexFields` (via `BaseObjectName` + `ObjectName`=index,
  `SORT_ORDER='D'`→`DESC`). FireDAC metadata does **not** expose a functional index's **expression**
  (`mkIndexFields` returns no rows) nor a partial index's **filter**, so those come from dialect
  hooks `SQLIndexExpressions`/`SQLIndexFilters` (default empty): expression via Firebird
  `RDB$EXPRESSION_SOURCE` / PostgreSQL `pg_get_expr(indexprs)` / SQLite `sqlite_master.sql`, filter
  via PostgreSQL `pg_get_expr(indpred)` / SQLite `sqlite_master.sql` (Firebird has no partial
  indexes). The expression is shown only when the index has no plain columns. Column **comments** are a dialect-specific part, added by
  optional `SQLRelationComments`/`SQLColumnComments`/`SQLIndexComments` hooks (default empty = no
  comments); relation/column comments overridden for PostgreSQL/Oracle/MySQL and **index comments**
  for Firebird (`RDB$INDICES`)/PostgreSQL (`obj_description`)/MySQL (`statistics.INDEX_COMMENT`);
  **MSSQL comments** (extended properties) are deferred. **Firebird
  overrides `GetColumns`** to read `RDB$RELATION_FIELDS`+`RDB$FIELDS` directly, so a column shows its
  **domain name** when it uses one (else a base type via `FirebirdBaseType`), with nullability from
  `RDB$NULL_FLAG` and comment from `RDB$DESCRIPTION` in the same query. Its
  `initialization` calls `TDatabaseFactory.Register('firebird', ...)` etc., and its `uses` links all
  the `FireDAC.Phys.*` driver units (SQLite is linked **statically** via
  `FireDAC.Phys.SQLiteWrapper.Stat`, so SQLite needs no `sqlite3.dll`). **This unit must stay in both
  `.dpr` uses clauses** even though nothing references it directly — its `initialization` is what
  populates the factory; drop it and the linker strips the registrations.
- `FireLink.Database.Catalog.pas` — reads `%USERPROFILE%\.FireLink\databases.ini` and turns
  a section into an opened `IDatabaseManager`. Depends only on the Intf unit + `TIniFile`.
  `EnsureConfigFile` (called once from `ConfigureServer` at startup) creates the folder and a
  fully-commented example ini on first run; the `CONFIG_TEMPLATE` const there is the single source of
  truth for that template.
- `FireLink.Database.Tools.pas` — `TDatabaseTools`, the `[McpTool]` surface. Talks only to
  the catalog + `IDatabaseManager`. `execute_query` results are returned as **JSON**; the metadata
  tools (`list_tables`/`list_views`/`get_table_metadata`/`get_view_metadata`/`list_indexes`) return
  **readable text** formatted here from the manager's records (aligned columns, `-- comment`,
  `Primary key:` / `Foreign keys:` sections, index `UNIQUE`/`PRIMARY` flags + columns). Errors are
  returned as a readable `'... FAILED: <msg>'` string, not raised.

**To add a new database backend:** implement `IDatabaseManager` (subclass `TDatabaseManagerBase`),
`TDatabaseFactory.Register('<key>', ...)` it in that unit's `initialization`, add the unit to both
`.dpr` uses clauses, then reference it from an ini section via `Type=<key>`. No MCP/tool code changes.

### Connection config (`%USERPROFILE%\.FireLink\databases.ini`)

Lives in the user's home (outside the repo), located via `GetEnvironmentVariable('USERPROFILE')` +
`CONFIG_FOLDER = '.FireLink'`. Auto-created with commented examples on first server start (see
`EnsureConfigFile` above); existing files are never overwritten. One `[section]` per database (the
section name is the `database` tool argument). Meta keys consumed by the catalog: `Type` (factory key,
required), `Password` (optional), `Description` (optional). Every other key is passed verbatim as a
FireDAC connection parameter.

**Password** is an optional directive whose value **must** carry a scheme prefix, resolved at connect
time by `ResolvePassword` in the catalog and injected into `Params.Password`. `ResolvePassword` also
returns an `out AIsCleartext: Boolean` — True only for `plain:` — which drives the auto-hardening
below:
- `env:VAR_NAME` — password taken from that environment variable (keeps secrets off disk).
- `plain:secret` — literal password in the ini. **On Windows it does not stay plain:** the private
  `SealPassword` rewrites that section's value in place as `dpapi:` (comments/other keys preserved via
  `TIniFile`), and **two paths** call it, so nothing stays in cleartext for long:
  - `TDatabaseCatalog.HardenPasswords` — called from `ConfigureServer` right after `EnsureConfigFile`,
    sweeps **every** section at startup. Idempotent, no-op off Windows or without the file.
  - `TDatabaseCatalog.Open` — at the end, **only after the connection succeeded**, seals that one
    section when `ResolvePassword` flagged the value as cleartext. This is what covers a password
    added to the ini while the server is already running.
- `dpapi:base64` — password sealed with the Windows Data Protection API (`CryptProtectData`, **user
  scope**), Base64-encoded. Implemented in `FireLink.Security.DPAPI.pas`
  (`DPAPIProtect`/`DPAPIUnprotect`/`DPAPIAvailable`, all under `{$IFDEF MSWINDOWS}`; no key lives in
  the exe). The blob is bound to **this Windows user + machine**, so it is not portable to another
  account/PC — copying the ini elsewhere makes `CryptUnprotectData` fail with a clear error. You
  normally never write `dpapi:` by hand: type `plain:` and let the auto-hardening convert it.
- future schemes plug into `ResolvePassword`. A value with no prefix is rejected.

`list_databases` never reads the `Password` directive, so it never exposes secrets.

No gating between read and write: `execute_query` and `execute_command` both work on any configured
connection.

## Building

Requires the RAD Studio IDE toolchain (**BDS 37.0 / Delphi 13**, Win32). The only direct dependency
is **MCPConnect** (`C:\Progetti\MCPConnect\Source`); it in turn pulls in `Neon` (JSON serialization,
`C:\Progetti\MCPConnect\Libs\neon\Source`) and `Logify` (logging, `C:\Progetti\Logify\Source`). None
of them are vendored or on project-relative paths — they all resolve from the global IDE library
path.

Build the whole group or a single project with MSBuild:

```powershell
# set BDS to the IDE root first, e.g. Delphi 13:
$env:BDS = "C:\Program Files (x86)\Embarcadero\Studio\37.0"
msbuild Source\FireLinkMCPGroup.groupproj  /t:Build /p:config=Debug /p:platform=Win32
msbuild Source\Indy\FireLinkMCPIndy.dproj  /t:Build /p:config=Debug /p:platform=Win32
msbuild Source\Stdio\FireLinkMCP.dproj     /t:Build /p:config=Debug /p:platform=Win32
```

There are **no automated tests** in this repo.

### Dogfooding

A Delphi MCP server is registered with this Claude Code session as the `delphi-server` plugin — an **older build** that still exposes `compile` / `list_products` / `goto_definition` alongside the database tools. You can use it to compile this project instead of shelling out to MSBuild; just don't take its tool list as the current shape of this codebase.

## Conventions

Every `.pas`/`.dpr` starts with the standard 80-column comment box: project name, `Copyright (c) 2026 - present  Delphi Building Blocks`, the repo URL, and `SPDX-License-Identifier: MIT`. Copy it verbatim from any existing unit when adding a file. The licence is **MIT** — `LICENSE` in the root is the authoritative text, and no source file carries an `All rights reserved.` line.

Delphi/Object Pascal code must follow the team style guide — **invoke the `delphi-basic:delphi-conventions` skill** before writing or reviewing any `.pas`/`.dpr`/`.dpk`/`.inc` code. Existing code already reflects it: `T`-prefixed types, `F`-prefixed fields, `A`-prefixed params, `L`-prefixed locals, inline `var` declarations, XML-doc `///` comments on public APIs. Commit messages: use `delphi-basic:write-commit-message-it` (Italian) or `-en` (English).
