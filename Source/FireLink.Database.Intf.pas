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

unit FireLink.Database.Intf;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections;

type
  /// <summary>Kind of schema object whose list/source can be retrieved.</summary>
  TDBObjectKind = (okProcedure, okTrigger, okPackage);

  /// <summary>Kind of relation whose list/metadata can be retrieved.</summary>
  TRelationKind = (rkTable, rkView);

  /// <summary>A table or view with its optional comment (remarks).</summary>
  TDBRelationInfo = record
    Name: string;
    Comment: string;
  end;

  /// <summary>A single column: name, DB type text, nullability and comment.</summary>
  TDBColumnInfo = record
    Name: string;
    DataType: string;
    Nullable: Boolean;
    Comment: string;
  end;

  /// <summary>A foreign key: local columns mapped to the referenced table's columns.</summary>
  TDBForeignKey = record
    Columns: TArray<string>;
    RefTable: string;
    RefColumns: TArray<string>;
  end;

  /// <summary>The constraints of a table relevant to a reader: PK columns and FKs.</summary>
  TDBTableConstraints = record
    PrimaryKey: TArray<string>;
    ForeignKeys: TArray<TDBForeignKey>;
  end;

  /// <summary>An index on a table: its columns (each optionally suffixed
  /// <c> DESC</c>), uniqueness/primary flags, and — when the backend exposes
  /// them — the functional <c>Expression</c> (for expression indexes that have
  /// no plain columns), the partial-index <c>Filter</c> predicate, and a
  /// comment.</summary>
  TDBIndexInfo = record
    Name: string;
    Columns: TArray<string>;
    Unique: Boolean;
    Primary: Boolean;
    Expression: string;
    Filter: string;
    Comment: string;
  end;

  /// <summary>
  ///   Abstraction the MCP layer depends on to work with a database, independent
  ///   of the underlying data-access component (FireDAC today, UniDAC or others
  ///   tomorrow). Concrete implementations are registered in
  ///   <see cref="TDatabaseFactory"/> and created by database-type key.
  /// </summary>
  IDatabaseManager = interface
    ['{4A1E0D2C-2E8B-4C7E-9F0B-2A6C1B3D5E70}']
    /// <summary>Configure the connection from key/value parameters (using the
    /// data-access component's own parameter names). Does not open it.</summary>
    procedure Configure(const AName: string; const AParams: TStrings);
    /// <summary>Open the connection (no-op if already open).</summary>
    procedure Open();
    /// <summary>Close the connection (no-op if already closed).</summary>
    procedure Close();
    /// <summary>Run a SELECT and return the rows as a JSON array of objects,
    /// capped to <paramref name="AMaxRows"/>.</summary>
    function ExecuteQuery(const ASQL: string; AMaxRows: Integer): string;
    /// <summary>Run a non-query statement and return the number of affected rows.</summary>
    function ExecuteCommand(const ASQL: string): Integer;
    /// <summary>List the tables or the views of the database, each with its
    /// comment when the backend exposes one.</summary>
    function GetRelations(AKind: TRelationKind): TArray<TDBRelationInfo>;
    /// <summary>Return the columns of the given table or view.</summary>
    function GetColumns(AKind: TRelationKind; const AName: string): TArray<TDBColumnInfo>;
    /// <summary>Return the primary key and foreign keys of a table.</summary>
    function GetTableConstraints(const ATable: string): TDBTableConstraints;
    /// <summary>Return the indexes defined on a table, each with its columns,
    /// uniqueness and (when the backend exposes one) comment.</summary>
    function GetIndexes(const ATable: string): TArray<TDBIndexInfo>;
    /// <summary>List the names of objects of the given kind. For
    /// <c>okTrigger</c>, <paramref name="ATableFilter"/> (when not empty)
    /// restricts the result to triggers of that table.</summary>
    function GetObjectNames(AKind: TDBObjectKind; const ATableFilter: string): TArray<string>;
    /// <summary>Return the source/DDL text of the named object of the given kind.</summary>
    function GetObjectSource(AKind: TDBObjectKind; const AName: string): string;
  end;

  /// <summary>
  ///   Base for concrete <see cref="IDatabaseManager"/> implementations. Reference
  ///   counted (via <c>TInterfacedObject</c>): the instance is freed automatically
  ///   when the last interface reference goes out of scope.
  /// </summary>
  TDatabaseManagerBase = class abstract(TInterfacedObject, IDatabaseManager)
  public
    procedure Configure(const AName: string; const AParams: TStrings); virtual; abstract;
    procedure Open(); virtual; abstract;
    procedure Close(); virtual; abstract;
    function ExecuteQuery(const ASQL: string; AMaxRows: Integer): string; virtual; abstract;
    function ExecuteCommand(const ASQL: string): Integer; virtual; abstract;
    function GetRelations(AKind: TRelationKind): TArray<TDBRelationInfo>; virtual; abstract;
    function GetColumns(AKind: TRelationKind; const AName: string): TArray<TDBColumnInfo>; virtual; abstract;
    function GetTableConstraints(const ATable: string): TDBTableConstraints; virtual; abstract;
    function GetIndexes(const ATable: string): TArray<TDBIndexInfo>; virtual; abstract;
    function GetObjectNames(AKind: TDBObjectKind; const ATableFilter: string): TArray<string>; virtual; abstract;
    function GetObjectSource(AKind: TDBObjectKind; const AName: string): string; virtual; abstract;
  end;

  TDatabaseManagerClass = class of TDatabaseManagerBase;

  /// <summary>
  ///   Registry mapping a database-type key (e.g. <c>firebird</c>) to the concrete
  ///   class implementing <see cref="IDatabaseManager"/> for it. Keys are matched
  ///   case-insensitively. Implementations self-register in their unit's
  ///   <c>initialization</c> section.
  /// </summary>
  TDatabaseFactory = class
  private
    class var FRegistry: TDictionary<string, TDatabaseManagerClass>;
    class constructor Create;
    class destructor Destroy;
  public
    /// <summary>Register (or replace) the implementation for a database-type key.</summary>
    class procedure Register(const AKey: string; AClass: TDatabaseManagerClass); static;
    /// <summary>Create an instance for the given database-type key.</summary>
    /// <exception cref="Exception">Raised when no implementation is registered.</exception>
    class function CreateFor(const AKey: string): IDatabaseManager; static;
    /// <summary>True when an implementation is registered for the key.</summary>
    class function IsRegistered(const AKey: string): Boolean; static;
    /// <summary>All registered database-type keys.</summary>
    class function Keys(): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Defaults;

{ TDatabaseFactory }

class constructor TDatabaseFactory.Create;
begin
  // Ordinal case-insensitive comparer so 'Firebird' and 'firebird' match.
  FRegistry := TDictionary<string, TDatabaseManagerClass>.Create(
    TIStringComparer.Ordinal);
end;

class destructor TDatabaseFactory.Destroy;
begin
  FRegistry.Free;
end;

class procedure TDatabaseFactory.Register(const AKey: string;
  AClass: TDatabaseManagerClass);
begin
  FRegistry.AddOrSetValue(AKey, AClass);
end;

class function TDatabaseFactory.CreateFor(const AKey: string): IDatabaseManager;
var
  LClass: TDatabaseManagerClass;
begin
  if not FRegistry.TryGetValue(AKey, LClass) then
    raise Exception.CreateFmt(
      'No database manager registered for type "%s". Registered types: %s.',
      [AKey, string.Join(', ', Keys())]);
  Result := LClass.Create;
end;

class function TDatabaseFactory.IsRegistered(const AKey: string): Boolean;
begin
  Result := FRegistry.ContainsKey(AKey);
end;

class function TDatabaseFactory.Keys(): TArray<string>;
begin
  Result := FRegistry.Keys.ToArray;
end;

end.
