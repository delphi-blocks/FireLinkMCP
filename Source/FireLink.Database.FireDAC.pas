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

unit FireLink.Database.FireDAC;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  FireDAC.Comp.Client,
  FireLink.Database.Intf;

type
  /// <summary>
  ///   FireDAC-based implementation of <see cref="IDatabaseManager"/>. Owns a
  ///   single <c>TFDConnection</c> that is opened lazily on first use. Concrete
  ///   databases are provided by the thin subclasses below, each supplying its
  ///   own <see cref="DefaultDriverID"/>.
  /// </summary>
  TFireDACDatabaseManager = class abstract(TDatabaseManagerBase)
  private
    FConnection: TFDConnection;
    /// <summary>Run a query and return the first column of every row.</summary>
    function RunNameList(const ASQL: string): TArray<string>;
    /// <summary>Run a query and concatenate the first column of every row,
    /// separated by <see cref="SourceSeparator"/>.</summary>
    function RunSourceText(const ASQL: string): string;
    /// <summary>Run a two-column query into a case-insensitive name->value map.</summary>
    function RunKeyValue(const ASQL: string): TDictionary<string, string>;
    /// <summary>True when a qualified relation name belongs to one of the
    /// backend's <see cref="SystemSchemas"/> and must be hidden.</summary>
    function IsSystemRelation(const AName: string): Boolean;
    /// <summary>Point the FireDAC driver definition of <paramref name="ADriverID"/>
    /// at an explicit client library. <c>VendorLib</c> is a driver-level setting,
    /// so it is ignored among the connection parameters and must be applied here.
    /// </summary>
    procedure ApplyVendorLib(const ADriverID, APath: string);
  protected
    /// <summary>Open the connection if needed and return it.</summary>
    function EnsureOpen(): TFDConnection;
    /// <summary>FireDAC DriverID for this database (e.g. <c>FB</c>, <c>PG</c>).
    /// Used unless the configuration provides an explicit <c>DriverID</c>.</summary>
    function DefaultDriverID(): string; virtual; abstract;
    /// <summary>FireDAC <c>CharacterSet</c> applied when the configuration does
    /// not set one. Empty (default) leaves the connection charset untouched.</summary>
    function DefaultCharacterSet(): string; virtual;
    /// <summary>SQL yielding object names in the first column. Return an empty
    /// string when the kind is unsupported for this database.</summary>
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; virtual;
    /// <summary>SQL yielding the object source in the first column (one or more
    /// rows). Return an empty string when the kind is unsupported.</summary>
    function SQLObjectSource(AKind: TDBObjectKind; const AName: string): string; virtual;
    /// <summary>Separator used to join multi-row source results.</summary>
    function SourceSeparator(): string; virtual;
    /// <summary>Schemas holding the backend's own catalog objects, which
    /// <see cref="GetRelations"/> filters out of the relation list. Empty
    /// (default) = the backend exposes no system schema through its metadata.
    /// </summary>
    function SystemSchemas(): TArray<string>; virtual;
    /// <summary>SQL predicate excluding <see cref="SystemSchemas"/> from the
    /// given schema column, e.g. <c>n.nspname NOT IN ('pg_catalog', ...)</c>.
    /// Yields an always-true predicate when the backend declares no system
    /// schema, so it can be concatenated into a WHERE clause unconditionally.
    /// </summary>
    function SystemSchemaFilter(const AColumn: string): string;
    /// <summary>SQL yielding <c>(relation_name, comment)</c> rows for tables or
    /// views. Empty (default) means the backend has no comments.</summary>
    function SQLRelationComments(AKind: TRelationKind): string; virtual;
    /// <summary>SQL yielding <c>(column_name, comment)</c> rows for a relation.
    /// Empty (default) means the backend has no comments.</summary>
    function SQLColumnComments(const ARelation: string): string; virtual;
    /// <summary>SQL yielding <c>(index_name, comment)</c> rows for a table's
    /// indexes. Empty (default) means the backend has no index comments.</summary>
    function SQLIndexComments(const ATable: string): string; virtual;
    /// <summary>SQL yielding <c>(index_name, expression)</c> rows for expression
    /// (functional) indexes. Empty (default) = not exposed by this backend.</summary>
    function SQLIndexExpressions(const ATable: string): string; virtual;
    /// <summary>SQL yielding <c>(index_name, predicate)</c> rows for partial
    /// indexes. Empty (default) = the backend has no partial indexes.</summary>
    function SQLIndexFilters(const ATable: string): string; virtual;
  public
    destructor Destroy(); override;
    procedure Configure(const AName: string; const AParams: TStrings); override;
    procedure Open(); override;
    procedure Close(); override;
    function ExecuteQuery(const ASQL: string; AMaxRows: Integer): string; override;
    function ExecuteCommand(const ASQL: string): Integer; override;
    function GetRelations(AKind: TRelationKind): TArray<TDBRelationInfo>; override;
    function GetColumns(AKind: TRelationKind; const AName: string): TArray<TDBColumnInfo>; override;
    function GetTableConstraints(const ATable: string): TDBTableConstraints; override;
    function GetIndexes(const ATable: string): TArray<TDBIndexInfo>; override;
    function GetObjectNames(AKind: TDBObjectKind; const ATableFilter: string): TArray<string>; override;
    function GetObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
  end;

  /// <summary>
  ///   Firebird manager. Overrides <see cref="GetObjectSource"/> to reconstruct
  ///   the full DDL header (parameters / RETURNS for procedures, FOR / event
  ///   clause for triggers) around the body stored in the system catalog, which
  ///   would otherwise expose only the PSQL block.
  /// </summary>
  TFirebirdDatabaseManager = class(TFireDACDatabaseManager)
  private
    function BuildProcedureSource(const AName: string): string;
    function BuildTriggerSource(const AName: string): string;
  protected
    function DefaultDriverID(): string; override;
    function DefaultCharacterSet(): string; override;
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; override;
    function SQLRelationComments(AKind: TRelationKind): string; override;
    function SQLIndexComments(const ATable: string): string; override;
    function SQLIndexExpressions(const ATable: string): string; override;
  public
    /// <summary>Firebird columns from the system catalog: shows the domain name
    /// when a column uses one (else a base type), with nullability and comment.</summary>
    function GetColumns(AKind: TRelationKind; const AName: string): TArray<TDBColumnInfo>; override;
    function GetObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
  end;

  TPostgresDatabaseManager = class(TFireDACDatabaseManager)
  protected
    function DefaultDriverID(): string; override;
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; override;
    function SQLObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
    function SystemSchemas(): TArray<string>; override;
    function SQLRelationComments(AKind: TRelationKind): string; override;
    function SQLColumnComments(const ARelation: string): string; override;
    function SQLIndexComments(const ATable: string): string; override;
    function SQLIndexExpressions(const ATable: string): string; override;
    function SQLIndexFilters(const ATable: string): string; override;
  end;

  TSQLiteDatabaseManager = class(TFireDACDatabaseManager)
  protected
    function DefaultDriverID(): string; override;
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; override;
    function SQLObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
    function SQLIndexExpressions(const ATable: string): string; override;
    function SQLIndexFilters(const ATable: string): string; override;
  end;

  TMySQLDatabaseManager = class(TFireDACDatabaseManager)
  protected
    function DefaultDriverID(): string; override;
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; override;
    function SQLObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
    function SQLRelationComments(AKind: TRelationKind): string; override;
    function SQLColumnComments(const ARelation: string): string; override;
    function SQLIndexComments(const ATable: string): string; override;
  end;

  TMSSQLDatabaseManager = class(TFireDACDatabaseManager)
  protected
    function DefaultDriverID(): string; override;
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; override;
    function SQLObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
    function SystemSchemas(): TArray<string>; override;
  end;

  TOracleDatabaseManager = class(TFireDACDatabaseManager)
  protected
    function DefaultDriverID(): string; override;
    function SQLObjectNames(AKind: TDBObjectKind; const ATableFilter: string): string; override;
    function SQLObjectSource(AKind: TDBObjectKind; const AName: string): string; override;
    function SourceSeparator(): string; override;
    function SQLRelationComments(AKind: TRelationKind): string; override;
    function SQLColumnComments(const ARelation: string): string; override;
  end;

implementation

uses
  System.JSON, System.Generics.Defaults, System.Character, System.IOUtils,
  Data.DB,
  FireDAC.Stan.Intf, FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.DApt,
  FireDAC.Stan.Consts,
  FireDAC.Phys.Intf,
  // Driver links: linking these units registers the FireDAC drivers.
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Phys.MySQL, FireDAC.Phys.PG, FireDAC.Phys.MSSQL,
  FireDAC.Phys.FB, FireDAC.Phys.Oracle;

const
  PARAM_DRIVER_ID = 'DriverID';
  PARAM_CHARACTER_SET = 'CharacterSet';
  PARAM_VENDOR_LIB = 'VendorLib';
  /// <summary>Neutral predicate used when a filter has nothing to exclude, so
  /// the caller can concatenate it into a WHERE clause unconditionally.</summary>
  SQL_ALWAYS_TRUE = '1 = 1';

// -- Field -> JSON helpers ----------------------------------------------------

function FieldToJSON(const AField: TField): TJSONValue;
begin
  if AField.IsNull then
    Exit(TJSONNull.Create);

  case AField.DataType of
    ftSmallint, ftInteger, ftWord, ftLongWord, ftShortint, ftByte,
    ftLargeint, ftAutoInc:
      Result := TJSONNumber.Create(AField.AsLargeInt);

    ftFloat, ftCurrency, ftBCD, ftFMTBcd, ftSingle, ftExtended:
      Result := TJSONNumber.Create(AField.AsFloat);

    ftBoolean:
      Result := TJSONBool.Create(AField.AsBoolean);
  else
    Result := TJSONString.Create(AField.AsString);
  end;
end;

/// <summary>Build a readable column type from FireDAC metadata: keep the native
/// type name, appending a size the driver did not already embed — <c>(p,s)</c>
/// for scaled numerics, <c>(len)</c> for sized character/binary types.</summary>
function FireDACColumnType(const ATypeName: string;
  APrecision, AScale, ALength: Integer): string;
begin
  Result := ATypeName.Trim;
  if Result.Contains('(') then
    Exit; // the driver already spelled out the size, e.g. VARCHAR(60)

  if (APrecision > 0) and (AScale > 0) then
    Result := Format('%s(%d,%d)', [Result, APrecision, AScale])
  else if ALength > 0 then
    Result := Format('%s(%d)', [Result, ALength]);
end;

function KindPlural(AKind: TDBObjectKind): string;
begin
  case AKind of
    okProcedure: Result := 'procedures';
    okTrigger: Result := 'triggers';
    okPackage: Result := 'packages';
  else
    raise EArgumentException.Create('Unknown TDBObjectKind');
  end;
end;

function KindSingular(AKind: TDBObjectKind): string;
begin
  case AKind of
    okProcedure: Result := 'procedure';
    okTrigger: Result := 'trigger';
    okPackage: Result := 'package';
  else
    raise EArgumentException.Create('Unknown TDBObjectKind');
  end;
end;

// -- Firebird DDL reconstruction helpers --------------------------------------

// RDB$FIELD_TYPE codes in RDB$FIELDS.
const
  FB_TYPE_SMALLINT = 7;
  FB_TYPE_INTEGER = 8;
  FB_TYPE_FLOAT = 10;
  FB_TYPE_DATE = 12;
  FB_TYPE_TIME = 13;
  FB_TYPE_CHAR = 14;
  FB_TYPE_BIGINT = 16;
  FB_TYPE_BOOLEAN = 23;
  FB_TYPE_DOUBLE = 27;
  FB_TYPE_TIMESTAMP = 35;
  FB_TYPE_VARCHAR = 37;
  FB_TYPE_BLOB = 261;

/// <summary>Format a NUMERIC/DECIMAL type from precision and (negative) scale.</summary>
function FirebirdNumeric(APrecision, AScale, ASubType: Integer): string;
var
  LKeyword: string;
  LPrecision: Integer;
begin
  if ASubType = 2 then
    LKeyword := 'DECIMAL'
  else
    LKeyword := 'NUMERIC';
  LPrecision := APrecision;
  if LPrecision <= 0 then
    LPrecision := 18;
  Result := Format('%s(%d,%d)', [LKeyword, LPrecision, -AScale]);
end;

/// <summary>Reconstruct a base SQL type from RDB$FIELDS metadata, used when a
/// procedure parameter is not declared through a named domain.</summary>
function FirebirdBaseType(AFieldType, ASubType, ALength, ACharLength,
  APrecision, AScale: Integer): string;
begin
  case AFieldType of
    FB_TYPE_SMALLINT:
      if AScale < 0 then
        Result := FirebirdNumeric(APrecision, AScale, ASubType)
      else
        Result := 'SMALLINT';
    FB_TYPE_INTEGER:
      if AScale < 0 then
        Result := FirebirdNumeric(APrecision, AScale, ASubType)
      else
        Result := 'INTEGER';
    FB_TYPE_BIGINT:
      if AScale < 0 then
        Result := FirebirdNumeric(APrecision, AScale, ASubType)
      else
        Result := 'BIGINT';
    FB_TYPE_FLOAT:
      Result := 'FLOAT';
    FB_TYPE_DOUBLE:
      Result := 'DOUBLE PRECISION';
    FB_TYPE_DATE:
      Result := 'DATE';
    FB_TYPE_TIME:
      Result := 'TIME';
    FB_TYPE_TIMESTAMP:
      Result := 'TIMESTAMP';
    FB_TYPE_BOOLEAN:
      Result := 'BOOLEAN';
    FB_TYPE_CHAR:
      Result := Format('CHAR(%d)', [ACharLength]);
    FB_TYPE_VARCHAR:
      Result := Format('VARCHAR(%d)', [ACharLength]);
    FB_TYPE_BLOB:
      if ASubType = 1 then
        Result := 'BLOB SUB_TYPE TEXT'
      else
        Result := 'BLOB';
  else
    Result := Format('(type %d)', [AFieldType]);
  end;
end;

/// <summary>Decode a Firebird RDB$TRIGGER_TYPE into its "BEFORE/AFTER e1 [OR e2
/// ...]" clause, supporting single- and multi-action triggers.</summary>
function FirebirdTriggerEvents(ATriggerType: Int64): string;
const
  ACTIONS: array[1..3] of string = ('INSERT', 'UPDATE', 'DELETE');
var
  LSlots: Int64;
  LSlot: Integer;
  LEvents: string;
begin
  if (ATriggerType and 1) = 1 then
    Result := 'BEFORE '
  else
    Result := 'AFTER ';

  // Actions are packed as 2-bit slots in (type + 1) shr 1; a zero slot ends the list.
  LSlots := (ATriggerType + 1) shr 1;
  LEvents := '';
  while LSlots <> 0 do
  begin
    LSlot := LSlots and 3;
    if (LSlot < Low(ACTIONS)) or (LSlot > High(ACTIONS)) then
      Break;
    if LEvents <> '' then
      LEvents := LEvents + ' OR ';
    LEvents := LEvents + ACTIONS[LSlot];
    LSlots := LSlots shr 2;
  end;
  Result := Result + LEvents;
end;

/// <summary>True when <paramref name="AText"/> begins with a standalone <c>AS</c>
/// keyword (case-insensitive), so a header need not add its own.</summary>
function StartsWithAS(const AText: string): Boolean;
var
  LText: string;
  LNext: Char;
begin
  LText := AText.TrimLeft;
  if (LText.Length < 2) or not SameText(LText.Substring(0, 2), 'AS') then
    Exit(False);
  if LText.Length = 2 then
    Exit(True);
  LNext := LText.Chars[2];
  Result := not (LNext.IsLetterOrDigit or (LNext = '_'));
end;

/// <summary>Join a reconstructed header with the stored PSQL body, inserting an
/// <c>AS</c> keyword only when the body does not already carry one.</summary>
function ComposeWithAS(const AHeader, ABody: string): string;
begin
  if StartsWithAS(ABody) then
    Result := AHeader + sLineBreak + ABody.TrimLeft
  else
    Result := AHeader + sLineBreak + 'AS' + sLineBreak + ABody;
end;

{ TFireDACDatabaseManager }

destructor TFireDACDatabaseManager.Destroy();
begin
  FConnection.Free;
  inherited;
end;

procedure TFireDACDatabaseManager.Configure(const AName: string;
  const AParams: TStrings);
var
  LVendorLib: string;
begin
  FConnection := TFDConnection.Create(nil);
  FConnection.ConnectionName := AName;
  FConnection.LoginPrompt := False;
  FConnection.Params.Assign(AParams);
  if FConnection.Params.Values[PARAM_DRIVER_ID] = '' then
    FConnection.Params.Values[PARAM_DRIVER_ID] := DefaultDriverID();
  if (DefaultCharacterSet() <> '') and
     (FConnection.Params.Values[PARAM_CHARACTER_SET] = '') then
    FConnection.Params.Values[PARAM_CHARACTER_SET] := DefaultCharacterSet();

  // VendorLib configures the driver, not the connection: move it off the
  // parameter list and onto the driver definition, where FireDAC reads it.
  LVendorLib := FConnection.Params.Values[PARAM_VENDOR_LIB];
  if LVendorLib <> '' then
  begin
    if not TFile.Exists(LVendorLib) then
      raise Exception.CreateFmt(
        'Database "%s": %s does not exist: %s', [AName, PARAM_VENDOR_LIB, LVendorLib]);

    FConnection.Params.Values[PARAM_VENDOR_LIB] := '';
    ApplyVendorLib(FConnection.Params.Values[PARAM_DRIVER_ID], LVendorLib);
  end;
end;

procedure TFireDACDatabaseManager.ApplyVendorLib(const ADriverID, APath: string);
var
  LDriverDef: IFDStanDefinition;
begin
  LDriverDef := FDManager.DriverDefs.FindDefinition(ADriverID);
  if LDriverDef = nil then
  begin
    LDriverDef := FDManager.DriverDefs.Add;
    LDriverDef.Name := ADriverID;
    LDriverDef.AsString[C_FD_DrvBaseId] := ADriverID;
  end;
  LDriverDef.AsString[S_FD_DrvVendorLib] := APath;
  LDriverDef.Apply();
end;

function TFireDACDatabaseManager.DefaultCharacterSet(): string;
begin
  Result := '';
end;

function TFireDACDatabaseManager.EnsureOpen(): TFDConnection;
begin
  if not FConnection.Connected then
    FConnection.Connected := True;
  Result := FConnection;
end;

procedure TFireDACDatabaseManager.Open();
begin
  EnsureOpen();
end;

procedure TFireDACDatabaseManager.Close();
begin
  if (FConnection <> nil) and FConnection.Connected then
    FConnection.Connected := False;
end;

function TFireDACDatabaseManager.ExecuteQuery(const ASQL: string;
  AMaxRows: Integer): string;
var
  LQuery: TFDQuery;
  LArray: TJSONArray;
  LRow: TJSONObject;
  LCount: Integer;
begin
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := EnsureOpen();
    LQuery.SQL.Text := ASQL;
    LQuery.Open();

    LArray := TJSONArray.Create;
    try
      LCount := 0;
      while not LQuery.Eof and (LCount < AMaxRows) do
      begin
        LRow := TJSONObject.Create;
        for var LField in LQuery.Fields do
          LRow.AddPair(LField.FieldName, FieldToJSON(LField));
        LArray.AddElement(LRow);
        Inc(LCount);
        LQuery.Next();
      end;
      Result := LArray.ToJSON;
    finally
      LArray.Free;
    end;
  finally
    LQuery.Free;
  end;
end;

function TFireDACDatabaseManager.ExecuteCommand(const ASQL: string): Integer;
var
  LQuery: TFDQuery;
begin
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := EnsureOpen();
    LQuery.SQL.Text := ASQL;
    LQuery.ExecSQL();
    Result := LQuery.RowsAffected;
  finally
    LQuery.Free;
  end;
end;

function TFireDACDatabaseManager.GetRelations(
  AKind: TRelationKind): TArray<TDBRelationInfo>;
var
  LNames: TStringList;
  LComments: TDictionary<string, string>;
  LResult: TList<TDBRelationInfo>;
  LInfo: TDBRelationInfo;
  LKinds: TFDPhysTableKinds;
  LCommentSQL: string;
  LComment: string;
begin
  if AKind = rkView then
    LKinds := [tkView]
  else
    LKinds := [tkTable];

  LNames := TStringList.Create;
  LResult := TList<TDBRelationInfo>.Create;
  LComments := nil;
  try
    EnsureOpen().GetTableNames('', '', '', LNames, [osMy], LKinds);

    LCommentSQL := SQLRelationComments(AKind);
    if LCommentSQL <> '' then
      LComments := RunKeyValue(LCommentSQL);

    for var LName in LNames do
    begin
      if IsSystemRelation(LName) then
        Continue;

      LInfo := Default(TDBRelationInfo);
      LInfo.Name := LName;
      if (LComments <> nil) and LComments.TryGetValue(LName, LComment) then
        LInfo.Comment := LComment;
      LResult.Add(LInfo);
    end;
    Result := LResult.ToArray;
  finally
    LComments.Free;
    LResult.Free;
    LNames.Free;
  end;
end;

function TFireDACDatabaseManager.GetColumns(AKind: TRelationKind;
  const AName: string): TArray<TDBColumnInfo>;
var
  LMeta: TFDMetaInfoQuery;
  LComments: TDictionary<string, string>;
  LResult: TList<TDBColumnInfo>;
  LColumn: TDBColumnInfo;
  LAttributes: Integer;
  LCommentSQL: string;
  LComment: string;
begin
  LResult := TList<TDBColumnInfo>.Create;
  LMeta := TFDMetaInfoQuery.Create(nil);
  LComments := nil;
  try
    LCommentSQL := SQLColumnComments(AName);
    if LCommentSQL <> '' then
      LComments := RunKeyValue(LCommentSQL);

    LMeta.Connection := EnsureOpen();
    LMeta.MetaInfoKind := mkTableFields;
    LMeta.ObjectName := AName;
    LMeta.Open();
    while not LMeta.Eof do
    begin
      LColumn := Default(TDBColumnInfo);
      LColumn.Name := LMeta.FieldByName('COLUMN_NAME').AsString.Trim;
      LColumn.DataType := FireDACColumnType(
        LMeta.FieldByName('COLUMN_TYPENAME').AsString.Trim,
        LMeta.FieldByName('COLUMN_PRECISION').AsInteger,
        LMeta.FieldByName('COLUMN_SCALE').AsInteger,
        LMeta.FieldByName('COLUMN_LENGTH').AsInteger);
      LAttributes := LMeta.FieldByName('COLUMN_ATTRIBUTES').AsInteger;
      LColumn.Nullable := (LAttributes and (1 shl Ord(caAllowNull))) <> 0;
      if (LComments <> nil) and LComments.TryGetValue(LColumn.Name, LComment) then
        LColumn.Comment := LComment;
      LResult.Add(LColumn);
      LMeta.Next();
    end;
    Result := LResult.ToArray;
  finally
    LComments.Free;
    LMeta.Free;
    LResult.Free;
  end;
end;

function TFireDACDatabaseManager.GetTableConstraints(
  const ATable: string): TDBTableConstraints;

  function ForeignKeyColumns(const AFKeyName: string;
    out ARefColumns: TArray<string>): TArray<string>;
  var
    LFields: TFDMetaInfoQuery;
    LLocal: TList<string>;
    LRef: TList<string>;
  begin
    LLocal := TList<string>.Create;
    LRef := TList<string>.Create;
    LFields := TFDMetaInfoQuery.Create(nil);
    try
      LFields.Connection := EnsureOpen();
      LFields.MetaInfoKind := mkForeignKeyFields;
      LFields.BaseObjectName := ATable;
      LFields.ObjectName := AFKeyName;
      LFields.Open();
      while not LFields.Eof do
      begin
        LLocal.Add(LFields.FieldByName('COLUMN_NAME').AsString.Trim);
        LRef.Add(LFields.FieldByName('PKEY_COLUMN_NAME').AsString.Trim);
        LFields.Next();
      end;
      ARefColumns := LRef.ToArray;
      Result := LLocal.ToArray;
    finally
      LFields.Free;
      LRef.Free;
      LLocal.Free;
    end;
  end;

var
  LMeta: TFDMetaInfoQuery;
  LPK: TList<string>;
  LFKs: TList<TDBForeignKey>;
  LFK: TDBForeignKey;
  LFKeyNames: TList<string>;
  LRefTables: TList<string>;
  LIndex: Integer;
begin
  Result := Default(TDBTableConstraints);

  // Primary key columns.
  LPK := TList<string>.Create;
  LMeta := TFDMetaInfoQuery.Create(nil);
  try
    LMeta.Connection := EnsureOpen();
    LMeta.MetaInfoKind := mkPrimaryKeyFields;
    LMeta.BaseObjectName := ATable;
    LMeta.Open();
    while not LMeta.Eof do
    begin
      LPK.Add(LMeta.FieldByName('COLUMN_NAME').AsString.Trim);
      LMeta.Next();
    end;
    Result.PrimaryKey := LPK.ToArray;
  finally
    LMeta.Free;
    LPK.Free;
  end;

  // Foreign keys: first the list (name + referenced table), then each one's columns.
  LFKeyNames := TList<string>.Create;
  LRefTables := TList<string>.Create;
  LMeta := TFDMetaInfoQuery.Create(nil);
  try
    LMeta.Connection := EnsureOpen();
    LMeta.MetaInfoKind := mkForeignKeys;
    LMeta.ObjectName := ATable;
    LMeta.Open();
    while not LMeta.Eof do
    begin
      LFKeyNames.Add(LMeta.FieldByName('FKEY_NAME').AsString.Trim);
      LRefTables.Add(LMeta.FieldByName('PKEY_TABLE_NAME').AsString.Trim);
      LMeta.Next();
    end;
  finally
    LMeta.Free;
  end;

  LFKs := TList<TDBForeignKey>.Create;
  try
    for LIndex := 0 to LFKeyNames.Count - 1 do
    begin
      LFK := Default(TDBForeignKey);
      LFK.RefTable := LRefTables[LIndex];
      LFK.Columns := ForeignKeyColumns(LFKeyNames[LIndex], LFK.RefColumns);
      LFKs.Add(LFK);
    end;
    Result.ForeignKeys := LFKs.ToArray;
  finally
    LFKs.Free;
    LRefTables.Free;
    LFKeyNames.Free;
  end;
end;

function TFireDACDatabaseManager.GetIndexes(
  const ATable: string): TArray<TDBIndexInfo>;

  // Columns of one index (via mkIndexFields), suffixing " DESC" on descending
  // columns; ascending is left implicit.
  function IndexColumns(const AIndexName: string): TArray<string>;
  var
    LFields: TFDMetaInfoQuery;
    LCols: TList<string>;
    LColumn: string;
  begin
    LCols := TList<string>.Create;
    LFields := TFDMetaInfoQuery.Create(nil);
    try
      LFields.Connection := EnsureOpen();
      LFields.MetaInfoKind := mkIndexFields;
      LFields.BaseObjectName := ATable;
      LFields.ObjectName := AIndexName;
      LFields.Open();
      while not LFields.Eof do
      begin
        LColumn := LFields.FieldByName('COLUMN_NAME').AsString.Trim;
        // Expression indexes yield a phantom blank column on some backends
        // (e.g. Firebird); skip it so the functional expression is shown instead.
        if LColumn <> '' then
        begin
          if SameText(LFields.FieldByName('SORT_ORDER').AsString.Trim, 'D') then
            LColumn := LColumn + ' DESC';
          LCols.Add(LColumn);
        end;
        LFields.Next();
      end;
      Result := LCols.ToArray;
    finally
      LFields.Free;
      LCols.Free;
    end;
  end;

  // Run a dialect hook (when non-empty) into a name->value map; nil otherwise.
  function OptionalMap(const ASQL: string): TDictionary<string, string>;
  begin
    if ASQL <> '' then
      Result := RunKeyValue(ASQL)
    else
      Result := nil;
  end;

var
  LMeta: TFDMetaInfoQuery;
  LResult: TList<TDBIndexInfo>;
  LIndex: TDBIndexInfo;
  LNames: TList<string>;
  LTypes: TList<Integer>;
  LComments: TDictionary<string, string>;
  LExpressions: TDictionary<string, string>;
  LFilters: TDictionary<string, string>;
  LValue: string;
  LType: Integer;
  I: Integer;
begin
  LComments := nil;
  LExpressions := nil;
  LFilters := nil;
  LNames := TList<string>.Create;
  LTypes := TList<Integer>.Create;
  LResult := TList<TDBIndexInfo>.Create;
  LMeta := TFDMetaInfoQuery.Create(nil);
  try
    LComments := OptionalMap(SQLIndexComments(ATable));
    LExpressions := OptionalMap(SQLIndexExpressions(ATable));
    LFilters := OptionalMap(SQLIndexFilters(ATable));

    // Gather the index list first, then read each one's columns (a second
    // mkIndexFields query would clash with an open mkIndexes cursor).
    LMeta.Connection := EnsureOpen();
    LMeta.MetaInfoKind := mkIndexes;
    LMeta.ObjectName := ATable;
    LMeta.Open();
    while not LMeta.Eof do
    begin
      LNames.Add(LMeta.FieldByName('INDEX_NAME').AsString.Trim);
      LTypes.Add(LMeta.FieldByName('INDEX_TYPE').AsInteger);
      LMeta.Next();
    end;
    LMeta.Close();

    for I := 0 to LNames.Count - 1 do
    begin
      LIndex := Default(TDBIndexInfo);
      LIndex.Name := LNames[I];
      LType := LTypes[I];
      LIndex.Unique := LType >= Ord(ikUnique);   // ikUnique or ikPrimaryKey
      LIndex.Primary := LType = Ord(ikPrimaryKey);
      LIndex.Columns := IndexColumns(LNames[I]);
      if (LComments <> nil) and LComments.TryGetValue(LIndex.Name, LValue) then
        LIndex.Comment := LValue;
      // Expression only matters for indexes with no plain columns (functional).
      if (Length(LIndex.Columns) = 0) and (LExpressions <> nil) and
         LExpressions.TryGetValue(LIndex.Name, LValue) then
        LIndex.Expression := LValue;
      if (LFilters <> nil) and LFilters.TryGetValue(LIndex.Name, LValue) then
        LIndex.Filter := LValue;
      LResult.Add(LIndex);
    end;
    Result := LResult.ToArray;
  finally
    LMeta.Free;
    LComments.Free;
    LExpressions.Free;
    LFilters.Free;
    LResult.Free;
    LTypes.Free;
    LNames.Free;
  end;
end;

function TFireDACDatabaseManager.RunNameList(const ASQL: string): TArray<string>;
var
  LQuery: TFDQuery;
  LNames: TList<string>;
begin
  LNames := TList<string>.Create;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := EnsureOpen();
      LQuery.SQL.Text := ASQL;
      LQuery.Open();
      while not LQuery.Eof do
      begin
        LNames.Add(LQuery.Fields[0].AsString.Trim);
        LQuery.Next();
      end;
    finally
      LQuery.Free;
    end;
    Result := LNames.ToArray;
  finally
    LNames.Free;
  end;
end;

function TFireDACDatabaseManager.RunSourceText(const ASQL: string): string;
var
  LQuery: TFDQuery;
  LBuilder: TStringBuilder;
  LSeparator: string;
  LFirst: Boolean;
begin
  LSeparator := SourceSeparator();
  LBuilder := TStringBuilder.Create;
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := EnsureOpen();
      LQuery.SQL.Text := ASQL;
      LQuery.Open();
      LFirst := True;
      while not LQuery.Eof do
      begin
        if not LFirst then
          LBuilder.Append(LSeparator);
        LBuilder.Append(LQuery.Fields[0].AsString);
        LFirst := False;
        LQuery.Next();
      end;
    finally
      LQuery.Free;
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TFireDACDatabaseManager.RunKeyValue(
  const ASQL: string): TDictionary<string, string>;
var
  LQuery: TFDQuery;
begin
  // Case-insensitive so comment keys match names returned by FireDAC metadata.
  Result := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := EnsureOpen();
      LQuery.SQL.Text := ASQL;
      LQuery.Open();
      while not LQuery.Eof do
      begin
        Result.AddOrSetValue(
          LQuery.Fields[0].AsString.Trim, LQuery.Fields[1].AsString.Trim);
        LQuery.Next();
      end;
    finally
      LQuery.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TFireDACDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  Result := ''; // unsupported unless a subclass overrides
end;

function TFireDACDatabaseManager.SQLObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  Result := ''; // unsupported unless a subclass overrides
end;

function TFireDACDatabaseManager.SourceSeparator(): string;
begin
  Result := sLineBreak;
end;

function TFireDACDatabaseManager.SystemSchemas(): TArray<string>;
begin
  Result := []; // nothing to hide unless a subclass overrides
end;

function TFireDACDatabaseManager.SystemSchemaFilter(const AColumn: string): string;
var
  LList: string;
begin
  LList := '';
  for var LSchema in SystemSchemas() do
  begin
    if LList <> '' then
      LList := LList + ', ';
    LList := LList + QuotedStr(LSchema);
  end;

  if LList = '' then
    Exit(SQL_ALWAYS_TRUE);

  Result := AColumn + ' NOT IN (' + LList + ')';
end;

function TFireDACDatabaseManager.IsSystemRelation(const AName: string): Boolean;
begin
  for var LSchema in SystemSchemas() do
    if AName.StartsWith(LSchema + '.', True) then
      Exit(True);
  Result := False;
end;

function TFireDACDatabaseManager.SQLRelationComments(AKind: TRelationKind): string;
begin
  Result := ''; // no comments unless a subclass overrides
end;

function TFireDACDatabaseManager.SQLColumnComments(const ARelation: string): string;
begin
  Result := ''; // no comments unless a subclass overrides
end;

function TFireDACDatabaseManager.SQLIndexComments(const ATable: string): string;
begin
  Result := ''; // no index comments unless a subclass overrides
end;

function TFireDACDatabaseManager.SQLIndexExpressions(const ATable: string): string;
begin
  Result := ''; // expression indexes not exposed unless a subclass overrides
end;

function TFireDACDatabaseManager.SQLIndexFilters(const ATable: string): string;
begin
  Result := ''; // no partial indexes unless a subclass overrides
end;

function TFireDACDatabaseManager.GetObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): TArray<string>;
var
  LSQL: string;
begin
  LSQL := SQLObjectNames(AKind, ATableFilter);
  if LSQL = '' then
    raise Exception.CreateFmt('Listing %s is not supported for DriverID "%s".',
      [KindPlural(AKind), DefaultDriverID()]);
  Result := RunNameList(LSQL);
end;

function TFireDACDatabaseManager.GetObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
var
  LSQL: string;
begin
  LSQL := SQLObjectSource(AKind, AName);
  if LSQL = '' then
    raise Exception.CreateFmt('%s source is not supported for DriverID "%s".',
      [KindSingular(AKind), DefaultDriverID()]);
  Result := RunSourceText(LSQL);
end;

{ Concrete database managers }

function TFirebirdDatabaseManager.DefaultDriverID(): string;
begin
  Result := 'FB';
end;

function TFirebirdDatabaseManager.DefaultCharacterSet(): string;
begin
  // Read the database in UTF8 so accented text is not mojibaked. The ini can
  // override this (e.g. CharacterSet=ISO8859_1) when the DB uses another charset.
  Result := 'UTF8';
end;

function TPostgresDatabaseManager.DefaultDriverID(): string;
begin
  Result := 'PG';
end;

function TSQLiteDatabaseManager.DefaultDriverID(): string;
begin
  Result := 'SQLite';
end;

function TMySQLDatabaseManager.DefaultDriverID(): string;
begin
  Result := 'MySQL';
end;

function TMSSQLDatabaseManager.DefaultDriverID(): string;
begin
  Result := 'MSSQL';
end;

function TOracleDatabaseManager.DefaultDriverID(): string;
begin
  Result := 'Ora';
end;

{ Firebird catalog queries }

function TFirebirdDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT TRIM(RDB$PROCEDURE_NAME) FROM RDB$PROCEDURES ORDER BY 1';
    okTrigger:
      begin
        Result := 'SELECT TRIM(RDB$TRIGGER_NAME) FROM RDB$TRIGGERS ' +
          'WHERE (RDB$SYSTEM_FLAG = 0 OR RDB$SYSTEM_FLAG IS NULL)';
        if ATableFilter <> '' then
          Result := Result + ' AND RDB$RELATION_NAME = ' + QuotedStr(UpperCase(ATableFilter));
        Result := Result + ' ORDER BY 1';
      end;
  else
    Result := ''; // packages not exposed for Firebird
  end;
end;

function TFirebirdDatabaseManager.SQLRelationComments(AKind: TRelationKind): string;
begin
  // RDB$RELATIONS holds both tables and views; matched by name, so kind-agnostic.
  Result := 'SELECT TRIM(RDB$RELATION_NAME), RDB$DESCRIPTION FROM RDB$RELATIONS ' +
    'WHERE RDB$DESCRIPTION IS NOT NULL';
end;

function TFirebirdDatabaseManager.SQLIndexComments(const ATable: string): string;
begin
  Result := 'SELECT TRIM(RDB$INDEX_NAME), RDB$DESCRIPTION FROM RDB$INDICES ' +
    'WHERE RDB$RELATION_NAME = ' + QuotedStr(UpperCase(ATable)) +
    ' AND RDB$DESCRIPTION IS NOT NULL';
end;

function TFirebirdDatabaseManager.SQLIndexExpressions(const ATable: string): string;
begin
  // Expression (COMPUTED BY) indexes keep their source here; it already carries
  // the surrounding parentheses. Firebird has no partial-index filter.
  Result := 'SELECT TRIM(RDB$INDEX_NAME), RDB$EXPRESSION_SOURCE FROM RDB$INDICES ' +
    'WHERE RDB$RELATION_NAME = ' + QuotedStr(UpperCase(ATable)) +
    ' AND RDB$EXPRESSION_SOURCE IS NOT NULL';
end;

function TFirebirdDatabaseManager.GetColumns(AKind: TRelationKind;
  const AName: string): TArray<TDBColumnInfo>;
var
  LQuery: TFDQuery;
  LResult: TList<TDBColumnInfo>;
  LColumn: TDBColumnInfo;
  LFieldSource: string;
  LBaseType: string;
begin
  // RDB$RELATION_FIELDS covers both tables and views, so AKind is not needed.
  LResult := TList<TDBColumnInfo>.Create;
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := EnsureOpen();
    LQuery.SQL.Text :=
      'SELECT TRIM(rf.RDB$FIELD_NAME) AS FIELD_NAME, ' +
      '  TRIM(rf.RDB$FIELD_SOURCE) AS FIELD_SOURCE, rf.RDB$NULL_FLAG AS NULL_FLAG, ' +
      '  rf.RDB$DESCRIPTION AS DESCRIPTION, ' +
      '  f.RDB$FIELD_TYPE AS FTYPE, f.RDB$FIELD_SUB_TYPE AS FSUBTYPE, ' +
      '  f.RDB$FIELD_LENGTH AS FLEN, f.RDB$CHARACTER_LENGTH AS FCHARLEN, ' +
      '  f.RDB$FIELD_PRECISION AS FPREC, f.RDB$FIELD_SCALE AS FSCALE ' +
      'FROM RDB$RELATION_FIELDS rf ' +
      'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE ' +
      'WHERE rf.RDB$RELATION_NAME = ' + QuotedStr(UpperCase(AName)) + ' ' +
      'ORDER BY rf.RDB$FIELD_POSITION';
    LQuery.Open();
    while not LQuery.Eof do
    begin
      LColumn := Default(TDBColumnInfo);
      LColumn.Name := LQuery.FieldByName('FIELD_NAME').AsString.Trim;
      LFieldSource := LQuery.FieldByName('FIELD_SOURCE').AsString.Trim;
      LBaseType := FirebirdBaseType(
        LQuery.FieldByName('FTYPE').AsInteger,
        LQuery.FieldByName('FSUBTYPE').AsInteger,
        LQuery.FieldByName('FLEN').AsInteger,
        LQuery.FieldByName('FCHARLEN').AsInteger,
        LQuery.FieldByName('FPREC').AsInteger,
        LQuery.FieldByName('FSCALE').AsInteger);
      // Show "DOMAIN (base type)" for a named domain; the bare base type otherwise
      // (auto-generated RDB$ field sources are not real domains).
      if (LFieldSource <> '') and not LFieldSource.StartsWith('RDB$') then
        LColumn.DataType := LFieldSource + ' (' + LBaseType + ')'
      else
        LColumn.DataType := LBaseType;
      // RDB$NULL_FLAG = 1 means NOT NULL; null/0 means the column is nullable.
      LColumn.Nullable := LQuery.FieldByName('NULL_FLAG').AsInteger <> 1;
      LColumn.Comment := LQuery.FieldByName('DESCRIPTION').AsString.Trim;
      LResult.Add(LColumn);
      LQuery.Next();
    end;
    Result := LResult.ToArray;
  finally
    LQuery.Free;
    LResult.Free;
  end;
end;

function TFirebirdDatabaseManager.BuildProcedureSource(const AName: string): string;
var
  LQuery: TFDQuery;
  LBody: string;
  LInputs: TStringList;
  LOutputs: TStringList;
  LFieldSource: string;
  LTypeText: string;
  LDefault: string;
  LLine: string;
  LHeader: string;
begin
  LInputs := TStringList.Create;
  LOutputs := TStringList.Create;
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := EnsureOpen();
    LQuery.SQL.Text :=
      'SELECT p.RDB$PROCEDURE_SOURCE AS BODY, ' +
      '  pp.RDB$PARAMETER_NAME AS PNAME, pp.RDB$PARAMETER_TYPE AS PTYPE, ' +
      '  pp.RDB$FIELD_SOURCE AS FSOURCE, pp.RDB$DEFAULT_SOURCE AS PDEFAULT, ' +
      '  f.RDB$FIELD_TYPE AS FTYPE, f.RDB$FIELD_SUB_TYPE AS FSUBTYPE, ' +
      '  f.RDB$FIELD_LENGTH AS FLEN, f.RDB$CHARACTER_LENGTH AS FCHARLEN, ' +
      '  f.RDB$FIELD_PRECISION AS FPREC, f.RDB$FIELD_SCALE AS FSCALE ' +
      'FROM RDB$PROCEDURES p ' +
      'LEFT JOIN RDB$PROCEDURE_PARAMETERS pp ON pp.RDB$PROCEDURE_NAME = p.RDB$PROCEDURE_NAME ' +
      'LEFT JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = pp.RDB$FIELD_SOURCE ' +
      'WHERE p.RDB$PROCEDURE_NAME = ' + QuotedStr(UpperCase(AName)) + ' ' +
      'ORDER BY pp.RDB$PARAMETER_TYPE, pp.RDB$PARAMETER_NUMBER';
    LQuery.Open();
    if LQuery.Eof then
      Exit('');

    LBody := LQuery.FieldByName('BODY').AsString;
    while not LQuery.Eof do
    begin
      if not LQuery.FieldByName('PNAME').IsNull then
      begin
        LFieldSource := LQuery.FieldByName('FSOURCE').AsString.Trim;
        // A named domain surfaces as-is; auto-generated RDB$ names are expanded.
        if (LFieldSource <> '') and not LFieldSource.StartsWith('RDB$') then
          LTypeText := LFieldSource
        else
          LTypeText := FirebirdBaseType(
            LQuery.FieldByName('FTYPE').AsInteger,
            LQuery.FieldByName('FSUBTYPE').AsInteger,
            LQuery.FieldByName('FLEN').AsInteger,
            LQuery.FieldByName('FCHARLEN').AsInteger,
            LQuery.FieldByName('FPREC').AsInteger,
            LQuery.FieldByName('FSCALE').AsInteger);

        LLine := '    ' + LQuery.FieldByName('PNAME').AsString.Trim + ' ' + LTypeText;
        if LQuery.FieldByName('PTYPE').AsInteger = 0 then
        begin
          LDefault := LQuery.FieldByName('PDEFAULT').AsString.Trim;
          if LDefault <> '' then
            LLine := LLine + ' ' + LDefault;
          LInputs.Add(LLine);
        end
        else
          LOutputs.Add(LLine);
      end;
      LQuery.Next();
    end;

    LHeader := 'PROCEDURE ' + AName;
    if LInputs.Count > 0 then
      LHeader := LHeader + ' (' + sLineBreak +
        string.Join(',' + sLineBreak, LInputs.ToStringArray) + ')';
    if LOutputs.Count > 0 then
      LHeader := LHeader + sLineBreak + 'RETURNS (' + sLineBreak +
        string.Join(',' + sLineBreak, LOutputs.ToStringArray) + ')';

    Result := ComposeWithAS(LHeader, LBody);

  finally
    LQuery.Free;
    LOutputs.Free;
    LInputs.Free;
  end;
end;

function TFirebirdDatabaseManager.BuildTriggerSource(const AName: string): string;
var
  LQuery: TFDQuery;
  LRelation: string;
  LActive: string;
  LEvents: string;
  LSequence: Integer;
  LBody: string;
  LHeader: string;
begin
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := EnsureOpen();
    LQuery.SQL.Text :=
      'SELECT RDB$RELATION_NAME AS RELATION, RDB$TRIGGER_TYPE AS TTYPE, ' +
      '  RDB$TRIGGER_SEQUENCE AS SEQ, RDB$TRIGGER_INACTIVE AS INACTIVE, ' +
      '  RDB$TRIGGER_SOURCE AS BODY ' +
      'FROM RDB$TRIGGERS WHERE RDB$TRIGGER_NAME = ' + QuotedStr(UpperCase(AName));
    LQuery.Open();
    if LQuery.Eof then
      Exit('');

    LRelation := LQuery.FieldByName('RELATION').AsString.Trim;
    if LQuery.FieldByName('INACTIVE').AsInteger = 1 then
      LActive := 'INACTIVE'
    else
      LActive := 'ACTIVE';
    LEvents := FirebirdTriggerEvents(LQuery.FieldByName('TTYPE').AsLargeInt);
    LSequence := LQuery.FieldByName('SEQ').AsInteger;
    LBody := LQuery.FieldByName('BODY').AsString;
  finally
    LQuery.Free;
  end;

  LHeader := Format('TRIGGER %s FOR %s%s%s %s POSITION %d',
    [AName, LRelation, sLineBreak, LActive, LEvents, LSequence]);
  Result := ComposeWithAS(LHeader, LBody);
end;

function TFirebirdDatabaseManager.GetObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  case AKind of
    okProcedure:
      Result := BuildProcedureSource(AName);
    okTrigger:
      Result := BuildTriggerSource(AName);
  else
    // Packages are not a Firebird concept: let the base raise the clear error.
    Result := inherited GetObjectSource(AKind, AName);
  end;
end;

{ PostgreSQL catalog queries }

function TPostgresDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT routine_name FROM information_schema.routines ' +
        'WHERE ' + SystemSchemaFilter('routine_schema') + ' ' +
        'ORDER BY routine_name';
    okTrigger:
      begin
        Result := 'SELECT DISTINCT trigger_name FROM information_schema.triggers ' +
          'WHERE ' + SystemSchemaFilter('trigger_schema');
        if ATableFilter <> '' then
          Result := Result + ' AND event_object_table = ' + QuotedStr(ATableFilter);
        Result := Result + ' ORDER BY trigger_name';
      end;
  else
    Result := ''; // PostgreSQL has no packages
  end;
end;

function TPostgresDatabaseManager.SQLObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT pg_get_functiondef(p.oid) FROM pg_proc p ' +
        'JOIN pg_namespace n ON n.oid = p.pronamespace ' +
        'WHERE p.proname = ' + QuotedStr(AName) +
        ' AND ' + SystemSchemaFilter('n.nspname') + ' LIMIT 1';
    okTrigger:
      Result := 'SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t ' +
        'WHERE NOT t.tgisinternal AND t.tgname = ' + QuotedStr(AName) + ' LIMIT 1';
  else
    Result := '';
  end;
end;

function TPostgresDatabaseManager.SystemSchemas(): TArray<string>;
begin
  Result := ['pg_catalog', 'information_schema', 'pg_toast'];
end;

function TPostgresDatabaseManager.SQLRelationComments(AKind: TRelationKind): string;
begin
  Result := 'SELECT c.relname, obj_description(c.oid) FROM pg_class c ' +
    'JOIN pg_namespace n ON n.oid = c.relnamespace ' +
    'WHERE ' + SystemSchemaFilter('n.nspname') + ' ' +
    'AND obj_description(c.oid) IS NOT NULL';
end;

function TPostgresDatabaseManager.SQLColumnComments(const ARelation: string): string;
begin
  Result := 'SELECT a.attname, col_description(a.attrelid, a.attnum) ' +
    'FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid ' +
    'WHERE c.relname = ' + QuotedStr(ARelation) +
    ' AND a.attnum > 0 AND NOT a.attisdropped ' +
    'AND col_description(a.attrelid, a.attnum) IS NOT NULL';
end;

function TPostgresDatabaseManager.SQLIndexComments(const ATable: string): string;
begin
  Result := 'SELECT ic.relname, obj_description(ic.oid) ' +
    'FROM pg_index i ' +
    'JOIN pg_class ic ON ic.oid = i.indexrelid ' +
    'JOIN pg_class tc ON tc.oid = i.indrelid ' +
    'WHERE tc.relname = ' + QuotedStr(ATable) +
    ' AND obj_description(ic.oid) IS NOT NULL';
end;

function TPostgresDatabaseManager.SQLIndexExpressions(const ATable: string): string;
begin
  Result := 'SELECT ic.relname, ''('' || pg_get_expr(i.indexprs, i.indrelid) || '')'' ' +
    'FROM pg_index i ' +
    'JOIN pg_class ic ON ic.oid = i.indexrelid ' +
    'JOIN pg_class tc ON tc.oid = i.indrelid ' +
    'WHERE tc.relname = ' + QuotedStr(ATable) + ' AND i.indexprs IS NOT NULL';
end;

function TPostgresDatabaseManager.SQLIndexFilters(const ATable: string): string;
begin
  Result := 'SELECT ic.relname, pg_get_expr(i.indpred, i.indrelid) ' +
    'FROM pg_index i ' +
    'JOIN pg_class ic ON ic.oid = i.indexrelid ' +
    'JOIN pg_class tc ON tc.oid = i.indrelid ' +
    'WHERE tc.relname = ' + QuotedStr(ATable) + ' AND i.indpred IS NOT NULL';
end;

{ SQLite catalog queries }

function TSQLiteDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  if AKind = okTrigger then
  begin
    Result := 'SELECT name FROM sqlite_master WHERE type = ''trigger''';
    if ATableFilter <> '' then
      Result := Result + ' AND tbl_name = ' + QuotedStr(ATableFilter);
    Result := Result + ' ORDER BY name';
  end
  else
    Result := ''; // SQLite has no stored procedures or packages
end;

function TSQLiteDatabaseManager.SQLObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  if AKind = okTrigger then
    Result := 'SELECT sql FROM sqlite_master ' +
      'WHERE type = ''trigger'' AND name = ' + QuotedStr(AName)
  else
    Result := '';
end;

function TSQLiteDatabaseManager.SQLIndexExpressions(const ATable: string): string;
begin
  // The parenthesised index spec from the stored DDL; used only for expression
  // indexes (those FireDAC reports with no plain columns).
  Result := 'SELECT name, SUBSTR(sql, INSTR(sql, ''('')) FROM sqlite_master ' +
    'WHERE type = ''index'' AND tbl_name = ' + QuotedStr(ATable) +
    ' AND sql IS NOT NULL';
end;

function TSQLiteDatabaseManager.SQLIndexFilters(const ATable: string): string;
begin
  // Partial-index predicate: the DDL text after WHERE (INSTR is case-sensitive,
  // so search the upper-cased copy; positions line up with the original).
  Result := 'SELECT name, TRIM(SUBSTR(sql, INSTR(UPPER(sql), '' WHERE '') + 7)) ' +
    'FROM sqlite_master WHERE type = ''index'' AND tbl_name = ' + QuotedStr(ATable) +
    ' AND sql IS NOT NULL AND INSTR(UPPER(sql), '' WHERE '') > 0';
end;

{ MySQL / MariaDB catalog queries }

function TMySQLDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT routine_name FROM information_schema.routines ' +
        'WHERE routine_schema = DATABASE() ORDER BY routine_name';
    okTrigger:
      begin
        Result := 'SELECT trigger_name FROM information_schema.triggers ' +
          'WHERE trigger_schema = DATABASE()';
        if ATableFilter <> '' then
          Result := Result + ' AND event_object_table = ' + QuotedStr(ATableFilter);
        Result := Result + ' ORDER BY trigger_name';
      end;
  else
    Result := ''; // MySQL has no packages
  end;
end;

function TMySQLDatabaseManager.SQLObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT routine_definition FROM information_schema.routines ' +
        'WHERE routine_schema = DATABASE() AND routine_name = ' + QuotedStr(AName) + ' LIMIT 1';
    okTrigger:
      Result := 'SELECT action_statement FROM information_schema.triggers ' +
        'WHERE trigger_schema = DATABASE() AND trigger_name = ' + QuotedStr(AName) + ' LIMIT 1';
  else
    Result := '';
  end;
end;

function TMySQLDatabaseManager.SQLRelationComments(AKind: TRelationKind): string;
begin
  Result := 'SELECT table_name, table_comment FROM information_schema.tables ' +
    'WHERE table_schema = DATABASE() AND table_comment <> ''''';
end;

function TMySQLDatabaseManager.SQLColumnComments(const ARelation: string): string;
begin
  Result := 'SELECT column_name, column_comment FROM information_schema.columns ' +
    'WHERE table_schema = DATABASE() AND table_name = ' + QuotedStr(ARelation) +
    ' AND column_comment <> ''''';
end;

function TMySQLDatabaseManager.SQLIndexComments(const ATable: string): string;
begin
  Result := 'SELECT DISTINCT index_name, index_comment ' +
    'FROM information_schema.statistics ' +
    'WHERE table_schema = DATABASE() AND table_name = ' + QuotedStr(ATable) +
    ' AND index_comment <> ''''';
end;

{ Microsoft SQL Server catalog queries }

function TMSSQLDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT name FROM sys.procedures ORDER BY name';
    okTrigger:
      begin
        Result := 'SELECT name FROM sys.triggers WHERE is_ms_shipped = 0';
        if ATableFilter <> '' then
          Result := Result + ' AND parent_id = OBJECT_ID(' + QuotedStr(ATableFilter) + ')';
        Result := Result + ' ORDER BY name';
      end;
  else
    Result := ''; // SQL Server has no packages
  end;
end;

function TMSSQLDatabaseManager.SQLObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  case AKind of
    okProcedure, okTrigger:
      Result := 'SELECT OBJECT_DEFINITION(OBJECT_ID(' + QuotedStr(AName) + '))';
  else
    Result := '';
  end;
end;

function TMSSQLDatabaseManager.SystemSchemas(): TArray<string>;
begin
  Result := ['sys', 'INFORMATION_SCHEMA'];
end;

{ Oracle catalog queries }

function TOracleDatabaseManager.SQLObjectNames(AKind: TDBObjectKind;
  const ATableFilter: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT object_name FROM user_objects ' +
        'WHERE object_type IN (''PROCEDURE'', ''FUNCTION'') ORDER BY object_name';
    okTrigger:
      begin
        Result := 'SELECT trigger_name FROM user_triggers';
        if ATableFilter <> '' then
          Result := Result + ' WHERE table_name = ' + QuotedStr(UpperCase(ATableFilter));
        Result := Result + ' ORDER BY trigger_name';
      end;
    okPackage:
      Result := 'SELECT object_name FROM user_objects ' +
        'WHERE object_type = ''PACKAGE'' ORDER BY object_name';
  else
    Result := '';
  end;
end;

function TOracleDatabaseManager.SQLObjectSource(AKind: TDBObjectKind;
  const AName: string): string;
begin
  case AKind of
    okProcedure:
      Result := 'SELECT text FROM user_source ' +
        'WHERE name = ' + QuotedStr(UpperCase(AName)) +
        ' AND type IN (''PROCEDURE'', ''FUNCTION'') ORDER BY line';
    okTrigger:
      Result := 'SELECT DBMS_METADATA.GET_DDL(''TRIGGER'', ' +
        QuotedStr(UpperCase(AName)) + ') FROM dual';
    okPackage:
      Result := 'SELECT text FROM user_source ' +
        'WHERE name = ' + QuotedStr(UpperCase(AName)) +
        ' AND type IN (''PACKAGE'', ''PACKAGE BODY'') ' +
        'ORDER BY DECODE(type, ''PACKAGE'', 1, 2), line';
  else
    Result := '';
  end;
end;

function TOracleDatabaseManager.SourceSeparator(): string;
begin
  Result := ''; // user_source rows already carry their line terminator
end;

function TOracleDatabaseManager.SQLRelationComments(AKind: TRelationKind): string;
begin
  Result := 'SELECT table_name, comments FROM user_tab_comments ' +
    'WHERE comments IS NOT NULL';
end;

function TOracleDatabaseManager.SQLColumnComments(const ARelation: string): string;
begin
  Result := 'SELECT column_name, comments FROM user_col_comments ' +
    'WHERE table_name = ' + QuotedStr(UpperCase(ARelation)) +
    ' AND comments IS NOT NULL';
end;

initialization
  TDatabaseFactory.Register('firebird', TFirebirdDatabaseManager);
  TDatabaseFactory.Register('postgres', TPostgresDatabaseManager);
  TDatabaseFactory.Register('sqlite', TSQLiteDatabaseManager);
  TDatabaseFactory.Register('mysql', TMySQLDatabaseManager);
  TDatabaseFactory.Register('mssql', TMSSQLDatabaseManager);
  TDatabaseFactory.Register('oracle', TOracleDatabaseManager);

end.
