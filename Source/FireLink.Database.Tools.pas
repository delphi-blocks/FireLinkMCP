{******************************************************************************}
{                                                                              }
{  FireLink MCP Server                                                         }
{                                                                              }
{  Copyright (c) 2026 - present  Delphi Building Blocks                        }
{                                                                              }
{  https://github.com/delphi-blocks/FireLinkMCP                                }
{                                                                              }
{  SPDX-License-Identifier: MIT                                                }
{                                                                              }
{******************************************************************************}

unit FireLink.Database.Tools;

interface

uses
  System.Classes, System.SysUtils,

  MCPConnect.MCP.Attributes,

  FireLink.Database.Intf;

type
  /// <summary>MCP tools for working with the databases configured in
  /// <c>%USERPROFILE%\.FireLink\databases.ini</c>. Depends only on <see cref="IDatabaseManager"/>
  /// and the catalog, never on a specific data-access component.</summary>
  TDatabaseTools = class
  public
    [McpTool('list_databases', 'List the databases configured on this server (from %USERPROFILE%\.FireLink\databases.ini)')]
    function ListDatabases: string;

    [McpTool('execute_query', 'Run a SELECT query on a configured database and return the rows as JSON')]
    function ExecuteQuery(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('sql', 'The SQL SELECT statement to run')] const ASQL: string;
      [McpParam('maxRows', 'Maximum number of rows to return, if you don''t know use 100')] const AMaxRows: string
    ): string;

    [McpTool('execute_command', 'Run a non-query statement (INSERT/UPDATE/DELETE/DDL) on a configured database. Always ask the user for explicit confirmation before running any statement that modifies data or metadata (INSERT, UPDATE, DELETE, ALTER, CREATE, DROP, TRUNCATE, etc.)')]
    function ExecuteCommand(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('sql', 'The SQL statement to run')] const ASQL: string
    ): string;

    [McpTool('list_tables', 'List the tables of a configured database, each with its comment when available')]
    function ListTables(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string
    ): string;

    [McpTool('list_views', 'List the views of a configured database, each with its comment when available')]
    function ListViews(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string
    ): string;

    [McpTool('get_table_metadata', 'Get a table''s columns (type, nullability, comment) plus its primary key and foreign keys')]
    function GetTableMetadata(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('table', 'The table name (use list_tables to discover them)')] const ATable: string
    ): string;

    [McpTool('get_view_metadata', 'Get a view''s columns (type, nullability, comment)')]
    function GetViewMetadata(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('view', 'The view name (use list_views to discover them)')] const AView: string
    ): string;

    [McpTool('list_indexes', 'List the indexes of a table, each with its columns, uniqueness and comment when available')]
    function ListIndexes(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('table', 'The table name (use list_tables to discover them)')] const ATable: string
    ): string;

    [McpTool('list_procedures', 'List the stored procedures/functions of a configured database')]
    function ListProcedures(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string
    ): string;

    [McpTool('list_triggers', 'List the triggers of a configured database, all of them or filtered by table')]
    function ListTriggers(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('table', 'Restrict to triggers of this table; leave empty for all triggers')] const ATable: string
    ): string;

    [McpTool('list_packages', 'List the packages of a configured database (Oracle only)')]
    function ListPackages(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string
    ): string;

    [McpTool('get_source', 'Get the source/DDL of a stored procedure, trigger or package')]
    function GetSource(
      [McpParam('database', 'The configured database name (use list_databases to discover them)')] const ADatabase: string;
      [McpParam('objectType', 'One of: procedure, trigger, package')] const AObjectType: string;
      [McpParam('name', 'The name of the object whose source to retrieve')] const AName: string
    ): string;
  end;

implementation

uses
  FireLink.Database.Catalog;

const
  DEFAULT_MAX_ROWS = 100;

function FormatNameList(const ATitle: string; const ANames: TArray<string>): string;
begin
  if Length(ANames) = 0 then
    Result := ATitle + ': none.'
  else
    Result := Format('%s:'#13#10'- %s', [ATitle, string.Join(#13#10'- ', ANames)]);
end;

function ParseObjectKind(const AValue: string): TDBObjectKind;
begin
  if SameText(AValue, 'procedure') then
    Result := okProcedure
  else if SameText(AValue, 'trigger') then
    Result := okTrigger
  else if SameText(AValue, 'package') then
    Result := okPackage
  else
    raise Exception.CreateFmt(
      'Unknown objectType "%s". Use one of: procedure, trigger, package.', [AValue]);
end;

{ TDatabaseTools }

function TDatabaseTools.ListDatabases: string;
var
  LNames: TArray<string>;
  LInfo: TDatabaseInfo;
  LBuilder: TStringBuilder;
begin
  LNames := TDatabaseCatalog.GetNames();
  if Length(LNames) = 0 then
    Exit(Format('No database configured. Add a section per database to %s.',
      [TDatabaseCatalog.ConfigFileName()]));

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.AppendLine('Configured databases. Pass the exact quoted name as the ' +
      '"database" argument of the other tools (execute_query, get_metadata, ...):');
    LBuilder.AppendLine;
    for var LName in LNames do
    begin
      LInfo := TDatabaseCatalog.GetInfo(LName);
      LBuilder.Append('- name="').Append(LInfo.Name).Append('"');
      LBuilder.Append('  type=').Append(LInfo.DBType);
      if LInfo.Description <> '' then
        LBuilder.Append('  description=').Append(LInfo.Description);
      LBuilder.AppendLine;
    end;
    Result := LBuilder.ToString.TrimRight;
  finally
    LBuilder.Free;
  end;
end;

function TDatabaseTools.ExecuteQuery(const ADatabase, ASQL,
  AMaxRows: string): string;
begin
  try
    var LMaxRows := StrToIntDef(AMaxRows, DEFAULT_MAX_ROWS);
    if LMaxRows <= 0 then
      LMaxRows := DEFAULT_MAX_ROWS;

    var LManager := TDatabaseCatalog.Open(ADatabase);
    Result := LManager.ExecuteQuery(ASQL, LMaxRows);
  except
    on E: Exception do
      Result := Format('Query FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.ExecuteCommand(const ADatabase, ASQL: string): string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    var LRowsAffected := LManager.ExecuteCommand(ASQL);
    Result := Format('Command succeeded on "%s". Rows affected: %d',
      [ADatabase, LRowsAffected]);
  except
    on E: Exception do
      Result := Format('Command FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

/// <summary>Render a table/view list as "- NAME  -- comment" lines.</summary>
function FormatRelationList(const ATitle: string;
  const ARelations: TArray<TDBRelationInfo>): string;
var
  LBuilder: TStringBuilder;
begin
  if Length(ARelations) = 0 then
    Exit(ATitle + ': none.');

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.Append(ATitle).Append(':');
    for var LRelation in ARelations do
    begin
      LBuilder.AppendLine.Append('- ').Append(LRelation.Name);
      if LRelation.Comment <> '' then
        LBuilder.Append('  -- ').Append(LRelation.Comment);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

/// <summary>Render the columns as aligned "- NAME  TYPE  NULL|NOT NULL  -- comment".</summary>
function FormatColumns(const AColumns: TArray<TDBColumnInfo>): string;
var
  LNameWidth: Integer;
  LTypeWidth: Integer;
  LBuilder: TStringBuilder;
  LLine: string;
begin
  LNameWidth := 0;
  LTypeWidth := 0;
  for var LColumn in AColumns do
  begin
    if LColumn.Name.Length > LNameWidth then
      LNameWidth := LColumn.Name.Length;
    if LColumn.DataType.Length > LTypeWidth then
      LTypeWidth := LColumn.DataType.Length;
  end;

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.Append('Columns:');
    for var LColumn in AColumns do
    begin
      LLine := '- ' + LColumn.Name.PadRight(LNameWidth) + '  ' +
        LColumn.DataType.PadRight(LTypeWidth) + '  ';
      if LColumn.Nullable then
        LLine := LLine + 'NULL'
      else
        LLine := LLine + 'NOT NULL';
      if LColumn.Comment <> '' then
        LLine := LLine + '  -- ' + LColumn.Comment;
      LBuilder.AppendLine.Append(LLine);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

/// <summary>Render the indexes as
/// "- NAME  [PRIMARY] UNIQUE|INDEX  (cols) | expression  [WHERE filter]  -- comment".</summary>
function FormatIndexes(const ATitle: string;
  const AIndexes: TArray<TDBIndexInfo>): string;
var
  LBuilder: TStringBuilder;
  LNameWidth: Integer;
  LFlags: string;
  LKey: string;
begin
  if Length(AIndexes) = 0 then
    Exit(ATitle + ': none.');

  LNameWidth := 0;
  for var LIndex in AIndexes do
    if LIndex.Name.Length > LNameWidth then
      LNameWidth := LIndex.Name.Length;

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.Append(ATitle).Append(':');
    for var LIndex in AIndexes do
    begin
      LFlags := '';
      if LIndex.Primary then
        LFlags := 'PRIMARY ';
      if LIndex.Unique then
        LFlags := LFlags + 'UNIQUE'
      else
        LFlags := LFlags + 'INDEX';

      // Plain columns when present, otherwise the functional expression.
      if Length(LIndex.Columns) > 0 then
        LKey := '(' + string.Join(', ', LIndex.Columns) + ')'
      else if LIndex.Expression <> '' then
        LKey := LIndex.Expression
      else
        LKey := '()';

      LBuilder.AppendLine.Append('- ').Append(LIndex.Name.PadRight(LNameWidth))
        .Append('  ').Append(LFlags.PadRight(14))
        .Append('  ').Append(LKey);
      if LIndex.Filter <> '' then
        LBuilder.Append(' WHERE ').Append(LIndex.Filter);
      if LIndex.Comment <> '' then
        LBuilder.Append('  -- ').Append(LIndex.Comment);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

/// <summary>Comment of a specific relation, looked up among the listed ones.</summary>
function RelationComment(const AManager: IDatabaseManager; AKind: TRelationKind;
  const AName: string): string;
begin
  Result := '';
  for var LRelation in AManager.GetRelations(AKind) do
    if SameText(LRelation.Name, AName) then
      Exit(LRelation.Comment);
end;

function TDatabaseTools.ListTables(const ADatabase: string): string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    Result := FormatRelationList(Format('Tables in %s', [ADatabase]),
      LManager.GetRelations(rkTable));
  except
    on E: Exception do
      Result := Format('Listing tables FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.ListViews(const ADatabase: string): string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    Result := FormatRelationList(Format('Views in %s', [ADatabase]),
      LManager.GetRelations(rkView));
  except
    on E: Exception do
      Result := Format('Listing views FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.GetTableMetadata(const ADatabase, ATable: string): string;
var
  LBuilder: TStringBuilder;
  LComment: string;
  LConstraints: TDBTableConstraints;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    var LColumns := LManager.GetColumns(rkTable, ATable);
    if Length(LColumns) = 0 then
      Exit(Format('Table "%s" not found in "%s" (or it has no columns).',
        [ATable, ADatabase]));

    LComment := RelationComment(LManager, rkTable, ATable);
    LConstraints := LManager.GetTableConstraints(ATable);

    LBuilder := TStringBuilder.Create;
    try
      LBuilder.Append('Table ').Append(ATable);
      if LComment <> '' then
        LBuilder.AppendLine.Append('Comment: ').Append(LComment);
      LBuilder.AppendLine.Append(FormatColumns(LColumns));

      if Length(LConstraints.PrimaryKey) > 0 then
        LBuilder.AppendLine.Append('Primary key: ')
          .Append(string.Join(', ', LConstraints.PrimaryKey));

      if Length(LConstraints.ForeignKeys) > 0 then
      begin
        LBuilder.AppendLine.Append('Foreign keys:');
        for var LFK in LConstraints.ForeignKeys do
          LBuilder.AppendLine.Append('- ')
            .Append(string.Join(', ', LFK.Columns))
            .Append(' -> ').Append(LFK.RefTable).Append('(')
            .Append(string.Join(', ', LFK.RefColumns)).Append(')');
      end;
      Result := LBuilder.ToString;
    finally
      LBuilder.Free;
    end;
  except
    on E: Exception do
      Result := Format('Table metadata FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.GetViewMetadata(const ADatabase, AView: string): string;
var
  LBuilder: TStringBuilder;
  LComment: string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    var LColumns := LManager.GetColumns(rkView, AView);
    if Length(LColumns) = 0 then
      Exit(Format('View "%s" not found in "%s" (or it has no columns).',
        [AView, ADatabase]));

    LComment := RelationComment(LManager, rkView, AView);

    LBuilder := TStringBuilder.Create;
    try
      LBuilder.Append('View ').Append(AView);
      if LComment <> '' then
        LBuilder.AppendLine.Append('Comment: ').Append(LComment);
      LBuilder.AppendLine.Append(FormatColumns(LColumns));
      Result := LBuilder.ToString;
    finally
      LBuilder.Free;
    end;
  except
    on E: Exception do
      Result := Format('View metadata FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.ListIndexes(const ADatabase, ATable: string): string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    Result := FormatIndexes(Format('Indexes on %s', [ATable]),
      LManager.GetIndexes(ATable));
  except
    on E: Exception do
      Result := Format('Listing indexes FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.ListProcedures(const ADatabase: string): string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    Result := FormatNameList(Format('Procedures in %s', [ADatabase]),
      LManager.GetObjectNames(okProcedure, ''));
  except
    on E: Exception do
      Result := Format('Listing procedures FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.ListTriggers(const ADatabase, ATable: string): string;
var
  LTitle: string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    if ATable <> '' then
      LTitle := Format('Triggers in %s for table %s', [ADatabase, ATable])
    else
      LTitle := Format('Triggers in %s', [ADatabase]);
    Result := FormatNameList(LTitle, LManager.GetObjectNames(okTrigger, ATable));
  except
    on E: Exception do
      Result := Format('Listing triggers FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.ListPackages(const ADatabase: string): string;
begin
  try
    var LManager := TDatabaseCatalog.Open(ADatabase);
    Result := FormatNameList(Format('Packages in %s', [ADatabase]),
      LManager.GetObjectNames(okPackage, ''));
  except
    on E: Exception do
      Result := Format('Listing packages FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

function TDatabaseTools.GetSource(const ADatabase, AObjectType,
  AName: string): string;
begin
  try
    var LKind := ParseObjectKind(AObjectType);
    var LManager := TDatabaseCatalog.Open(ADatabase);
    var LSource := LManager.GetObjectSource(LKind, AName);
    if LSource.Trim = '' then
      Result := Format('No source found for %s "%s" in "%s".',
        [AObjectType, AName, ADatabase])
    else
      Result := LSource;
  except
    on E: Exception do
      Result := Format('Get source FAILED on "%s": %s', [ADatabase, E.Message]);
  end;
end;

end.
