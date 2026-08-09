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

unit FireLink.Database.Catalog;

interface

uses
  System.Classes, System.SysUtils,
  FireLink.Database.Intf;

type
  /// <summary>Non-secret summary of a configured database, for listing.</summary>
  TDatabaseInfo = record
    Name: string;
    DBType: string;
    Description: string;
  end;

  /// <summary>
  ///   Reads the connection catalog from <c>%USERPROFILE%\.FireLink\databases.ini</c>
  ///   (one section per database) and turns a section into a ready, opened
  ///   <see cref="IDatabaseManager"/> via <see cref="TDatabaseFactory"/>.
  ///   The optional <c>Password</c> directive carries a scheme prefix
  ///   (<c>env:</c>, <c>plain:</c>, ...) resolved at connect time. A password
  ///   still stored in cleartext is sealed by <see cref="HardenPasswords"/> at
  ///   startup, or by <see cref="Open"/> right after a successful connection for
  ///   the ones added while the server is already running.
  /// </summary>
  TDatabaseCatalog = class
  private
    class function IniFileName(): string; static;
    /// <summary>Replace the section's <c>Password=plain:...</c> directive with
    /// <c>Password=dpapi:...</c> in place (comments and other keys preserved).
    /// A no-op when DPAPI is unavailable (non-Windows) or the password is empty.</summary>
    class procedure SealPassword(const ASection, APassword: string); static;
  public
    /// <summary>Create the config folder and a commented example ini on first run,
    /// if it does not exist yet. Existing files are never overwritten.</summary>
    class procedure EnsureConfigFile(); static;
    /// <summary>On Windows, seal every <c>Password=plain:...</c> directive in the
    /// file into <c>Password=dpapi:...</c> in place (comments preserved). Meant to
    /// run once at startup; <see cref="Open"/> covers the passwords added later.
    /// Idempotent; a no-op on other platforms or when the file is missing.</summary>
    class procedure HardenPasswords(); static;
    /// <summary>Full path of the configuration file.</summary>
    class function ConfigFileName(): string; static;
    /// <summary>Names of all configured databases (ini section names).</summary>
    class function GetNames(): TArray<string>; static;
    /// <summary>Non-secret info for a configured database.</summary>
    class function GetInfo(const AName: string): TDatabaseInfo; static;
    /// <summary>Create, configure and open the manager for a configured database.</summary>
    /// <exception cref="Exception">Raised when the file, section or type is missing.</exception>
    class function Open(const AName: string): IDatabaseManager; static;
  end;

implementation

uses
  System.IOUtils, System.IniFiles,
  FireLink.Security.DPAPI;

const
  // Config lives in the user's home: %USERPROFILE%\.FireLink\databases.ini
  CONFIG_FOLDER = '.FireLink';
  INI_FILE = 'databases.ini';

  // Meta keys consumed by the catalog and NOT passed verbatim to the connection.
  META_TYPE = 'Type';
  META_PASSWORD = 'Password';
  META_DESCRIPTION = 'Description';

  // Password handling. The Password directive value always carries a scheme
  // prefix: "<scheme>:<arg>". Add new schemes in ResolvePassword.
  PARAM_PASSWORD = 'Password';
  SCHEME_SEP = ':';
  SCHEME_ENV = 'env';     // env:VAR_NAME    -> value of the environment variable
  SCHEME_PLAIN = 'plain'; // plain:secret    -> the literal password
  SCHEME_DPAPI = 'dpapi'; // dpapi:base64    -> Windows DPAPI-sealed password

  // Written verbatim on first run when the config file does not exist. Every
  // directive is commented out, so no database is active until the user edits it.
  CONFIG_TEMPLATE: TArray<string> = [
    '; Database catalog for the FireLink MCP Server.',
    '; This file was created automatically on first run. Edit it to add your',
    '; databases. It may hold host/db names but NEVER passwords.',
    ';',
    '; One [section] per database. The section name is the "database" argument used',
    '; by the MCP tools (list_databases / execute_query / execute_command /',
    '; get_metadata).',
    ';',
    '; Meta keys (consumed by the server, NOT passed to the connection):',
    ';   Type         required. Registered database-type key: sqlite | firebird |',
    ';                postgres | mysql | mssql | oracle',
    ';   Password     optional. Value carries a mandatory scheme prefix:',
    ';                  env:VAR_NAME   password taken from that environment variable',
    ';                  plain:secret   the literal password. On Windows it is sealed',
    ';                                 automatically into dpapi: on the next startup,',
    ';                                 or as soon as this database connects when it is',
    ';                                 added while the server is already running.',
    ';                  dpapi:base64   Windows DPAPI-sealed password (user scope). You',
    ';                                 normally do not write this by hand: type a',
    ';                                 plain: value and let the server convert it. The',
    ';                                 blob is bound to THIS Windows user and machine,',
    ';                                 so it is not portable to another account/PC.',
    ';   Description  optional. Free text shown by list_databases.',
    ';',
    '; Every other key is passed verbatim to the connection as a FireDAC parameter',
    '; (Server, Database, Port, User_Name, Protocol, ...), with one exception:',
    ';   VendorLib    optional. Full path to the DBMS client library to load',
    ';                (libpq.dll, oci.dll, fbclient.dll, libmysql.dll, ...). Use it',
    ';                when that DLL is not on the PATH nor next to the server exe.',
    ';                It must match the server bitness (Win32). Note it configures',
    ';                the FireDAC driver, not the single connection, so it applies',
    ';                to every database sharing the same Type.',
    ';',
    '; ---------------------------------------------------------------------------',
    '; Example databases (remove the leading '';'' to enable one):',
    ';',
    '; [localdb]',
    '; Type=sqlite',
    '; Database=C:\data\app.db',
    '; Description=Local SQLite database (no server, no password)',
    ';',
    '; [northwind]',
    '; Type=postgres',
    '; Server=localhost',
    '; Port=5432',
    '; Database=northwind',
    '; User_Name=postgres',
    '; Password=env:PG_MAIN_PWD',
    '; Description=Demo Northwind database',
    ';',
    '; [employees]',
    '; Type=firebird',
    '; Server=localhost',
    '; Database=C:\db\EMPLOYEE.FDB',
    '; User_Name=SYSDBA',
    '; Protocol=TCPIP',
    ';   (Firebird defaults to CharacterSet=UTF8; set it below if the DB differs)',
    '; CharacterSet=UTF8',
    '; Password=env:MCPDB_EMPLOYEES_PWD',
    '; Description=Firebird sample database',
    ';',
    '; [hr]',
    '; Type=oracle',
    ';   (Oracle takes the WHOLE connect identifier in Database and ignores Server:',
    ';    either a TNS alias declared in tnsnames.ora, e.g. Database=ORCLTNS, or an',
    ';    Easy Connect string as below. Do NOT split host and service across',
    ';    Server/Database, it will not connect.)',
    '; Database=//dbhost:1521/ORCLPDB1',
    '; User_Name=HR',
    '; Password=env:ORA_HR_PWD',
    '; VendorLib=C:\instantclient_21_3\oci.dll',
    '; Description=Oracle sample schema'
  ];

function IsMetaKey(const AKey: string): Boolean;
begin
  Result := SameText(AKey, META_TYPE) or
            SameText(AKey, META_PASSWORD) or
            SameText(AKey, META_DESCRIPTION);
end;

/// <summary>Resolve a Password directive value of the form "&lt;scheme&gt;:&lt;arg&gt;".
/// A scheme prefix is mandatory. Add new schemes (e.g. aes) here.</summary>
/// <param name="AIsCleartext">True when the directive still holds the secret in
/// cleartext (<c>plain:</c>), i.e. the caller should seal it on disk.</param>
function ResolvePassword(const AValue: string; out AIsCleartext: Boolean): string;
var
  LSepPos: Integer;
  LScheme: string;
  LArg: string;
begin
  AIsCleartext := False;
  LSepPos := AValue.IndexOf(SCHEME_SEP);
  if LSepPos < 0 then
    raise Exception.CreateFmt(
      'Invalid Password "%s": a scheme prefix is required (e.g. env:VAR_NAME or plain:secret).',
      [AValue]);

  LScheme := AValue.Substring(0, LSepPos);
  LArg := AValue.Substring(LSepPos + 1);

  if SameText(LScheme, SCHEME_ENV) then
    Result := GetEnvironmentVariable(LArg)
  else if SameText(LScheme, SCHEME_PLAIN) then
  begin
    Result := LArg;
    AIsCleartext := True;
  end
  else if SameText(LScheme, SCHEME_DPAPI) then
    Result := DPAPIUnprotect(LArg)
  else
    raise Exception.CreateFmt(
      'Unsupported Password scheme "%s". Supported schemes: %s, %s, %s.',
      [LScheme, SCHEME_ENV, SCHEME_PLAIN, SCHEME_DPAPI]);
end;

{ TDatabaseCatalog }

class function TDatabaseCatalog.IniFileName(): string;
begin
  Result := TPath.Combine(
    TPath.Combine(GetEnvironmentVariable('USERPROFILE'), CONFIG_FOLDER), INI_FILE);
end;

class function TDatabaseCatalog.ConfigFileName(): string;
begin
  Result := IniFileName();
end;

class procedure TDatabaseCatalog.EnsureConfigFile();
var
  LFolder: string;
begin
  if TFile.Exists(IniFileName()) then
    Exit;

  LFolder := TPath.GetDirectoryName(IniFileName());
  if not TDirectory.Exists(LFolder) then
    TDirectory.CreateDirectory(LFolder);

  TFile.WriteAllText(IniFileName(), string.Join(sLineBreak, CONFIG_TEMPLATE));
end;

class procedure TDatabaseCatalog.SealPassword(const ASection, APassword: string);
var
  LIni: TIniFile;
  LSealed: string;
begin
  // Nothing to seal without DPAPI (non-Windows) or for an empty password: in
  // both cases the directive is left exactly as the user wrote it.
  if not DPAPIAvailable() then
    Exit;
  if APassword = '' then
    Exit;

  LSealed := SCHEME_DPAPI + SCHEME_SEP + DPAPIProtect(APassword);
  LIni := TIniFile.Create(IniFileName());
  try
    // TIniFile writes via WritePrivateProfileString, so comments and the other
    // keys in the section are preserved; only this value is replaced in place.
    LIni.WriteString(ASection, META_PASSWORD, LSealed);
  finally
    LIni.Free;
  end;
end;

class procedure TDatabaseCatalog.HardenPasswords();
var
  LIni: TIniFile;
  LSections: TStringList;
  LPlainPrefix: string;
  LDirective: string;
begin
  if not DPAPIAvailable() then
    Exit;
  if not TFile.Exists(IniFileName()) then
    Exit;

  LPlainPrefix := SCHEME_PLAIN + SCHEME_SEP; // 'plain:'
  LIni := TIniFile.Create(IniFileName());
  LSections := TStringList.Create;
  try
    LIni.ReadSections(LSections);
    for var LSection in LSections do
    begin
      LDirective := LIni.ReadString(LSection, META_PASSWORD, '');
      if LDirective.StartsWith(LPlainPrefix, True) then
        SealPassword(LSection, LDirective.Substring(LPlainPrefix.Length));
    end;
  finally
    LSections.Free;
    LIni.Free;
  end;
end;

class function TDatabaseCatalog.GetNames(): TArray<string>;
var
  LIni: TIniFile;
  LSections: TStringList;
begin
  if not TFile.Exists(IniFileName()) then
    Exit(nil);

  LIni := TIniFile.Create(IniFileName());
  LSections := TStringList.Create;
  try
    LIni.ReadSections(LSections);
    Result := LSections.ToStringArray;
  finally
    LSections.Free;
    LIni.Free;
  end;
end;

class function TDatabaseCatalog.GetInfo(const AName: string): TDatabaseInfo;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(IniFileName());
  try
    Result.Name := AName;
    Result.DBType := LIni.ReadString(AName, META_TYPE, '');
    Result.Description := LIni.ReadString(AName, META_DESCRIPTION, '');
  finally
    LIni.Free;
  end;
end;

class function TDatabaseCatalog.Open(const AName: string): IDatabaseManager;
var
  LIni: TIniFile;
  LKeys: TStringList;
  LParams: TStringList;
  LDBType: string;
  LPasswordDirective: string;
  LPassword: string;
  LIsCleartext: Boolean;
begin
  if not TFile.Exists(IniFileName()) then
    raise Exception.CreateFmt(
      'Database configuration file not found: %s', [IniFileName()]);

  LIni := TIniFile.Create(IniFileName());
  LKeys := TStringList.Create;
  LParams := TStringList.Create;
  try
    if not LIni.SectionExists(AName) then
      raise Exception.CreateFmt(
        'Database "%s" is not configured in %s.', [AName, INI_FILE]);

    LDBType := LIni.ReadString(AName, META_TYPE, '');
    if LDBType = '' then
      raise Exception.CreateFmt(
        'Database "%s" has no "%s" key in %s.', [AName, META_TYPE, INI_FILE]);

    // Every non-meta key becomes a connection parameter, verbatim.
    LIni.ReadSection(AName, LKeys);
    for var LKey in LKeys do
      if not IsMetaKey(LKey) then
        LParams.Values[LKey] := LIni.ReadString(AName, LKey, '');

    // Password directive (optional): "<scheme>:<arg>", e.g. env:VAR or plain:secret.
    LIsCleartext := False;
    LPasswordDirective := LIni.ReadString(AName, META_PASSWORD, '');
    if LPasswordDirective <> '' then
    begin
      LPassword := ResolvePassword(LPasswordDirective, LIsCleartext);
      LParams.Values[PARAM_PASSWORD] := LPassword;
    end;

    Result := TDatabaseFactory.CreateFor(LDBType);
    Result.Configure(AName, LParams);
    Result.Open();

    // The connection worked, so the secret is known to be good: get it off the
    // disk in cleartext. Only reached on success, so a wrong password stays
    // readable (and fixable) in the ini.
    if LIsCleartext then
      SealPassword(AName, LPassword);
  finally
    LParams.Free;
    LKeys.Free;
    LIni.Free;
  end;
end;

end.
