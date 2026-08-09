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

unit FireLink.Security.DPAPI;

{
  Thin wrapper around the Windows Data Protection API (DPAPI). Passwords are
  sealed with a key Windows derives from the current user's credentials (user
  scope), so the resulting blob is only decryptable by the same Windows account
  on the same machine and no key ever lives in this executable.

  The whole crypto is Windows-only: on other platforms the functions raise a
  clear error and DPAPIAvailable returns False.
}

interface

uses
  System.SysUtils;

type
  /// <summary>Raised when a DPAPI operation fails or is unavailable.</summary>
  EDPAPIError = class(Exception);

/// <summary>True only on Windows, where DPAPI is available.</summary>
function DPAPIAvailable(): Boolean;

/// <summary>Encrypt <paramref name="APlainText"/> (user scope) and return the
/// resulting blob as a Base64 string suitable for storing in a text file.</summary>
function DPAPIProtect(const APlainText: string): string;

/// <summary>Decrypt a Base64 blob previously produced by <see cref="DPAPIProtect"/>.
/// Succeeds only for the same Windows user on the same machine.</summary>
function DPAPIUnprotect(const ABase64Blob: string): string;

implementation

uses
  System.NetEncoding
{$IFDEF MSWINDOWS}
  , Winapi.Windows
{$ENDIF}
  ;

{$IFDEF MSWINDOWS}

type
  DATA_BLOB = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDATA_BLOB = ^DATA_BLOB;

const
  CRYPT32 = 'crypt32.dll';
  CRYPTPROTECT_UI_FORBIDDEN = $1;

function CryptProtectData(pDataIn: PDATA_BLOB; szDataDescr: LPCWSTR;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer; pPromptStruct: Pointer;
  dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall; external CRYPT32 name 'CryptProtectData';

function CryptUnprotectData(pDataIn: PDATA_BLOB; ppszDataDescr: PPWideChar;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer; pPromptStruct: Pointer;
  dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall; external CRYPT32 name 'CryptUnprotectData';

function DPAPIAvailable(): Boolean;
begin
  Result := True;
end;

/// <summary>Copy a DATA_BLOB produced by DPAPI into managed bytes and free it.</summary>
function BlobToBytes(const ABlob: DATA_BLOB): TBytes;
begin
  SetLength(Result, ABlob.cbData);
  if ABlob.cbData > 0 then
    Move(ABlob.pbData^, Result[0], ABlob.cbData);
end;

function DPAPIProtect(const APlainText: string): string;
var
  LInput: TBytes;
  LIn: DATA_BLOB;
  LOut: DATA_BLOB;
  LResult: TBytes;
begin
  LInput := TEncoding.UTF8.GetBytes(APlainText);
  LIn.cbData := Length(LInput);
  if Length(LInput) > 0 then
    LIn.pbData := @LInput[0]
  else
    LIn.pbData := nil;

  if not CryptProtectData(@LIn, 'DelphiMCP', nil, nil, nil,
    CRYPTPROTECT_UI_FORBIDDEN, @LOut) then
    raise EDPAPIError.CreateFmt('CryptProtectData failed (error %d).', [GetLastError]);
  try
    LResult := BlobToBytes(LOut);
  finally
    LocalFree(HLOCAL(LOut.pbData));
  end;
  // Strip the MIME line breaks TNetEncoding inserts every 76 chars, so the blob
  // is a single line and survives an ini round-trip (TIniFile reads one line).
  Result := TNetEncoding.Base64.EncodeBytesToString(LResult)
    .Replace(#13, '', [rfReplaceAll]).Replace(#10, '', [rfReplaceAll]);
end;

function DPAPIUnprotect(const ABase64Blob: string): string;
var
  LInput: TBytes;
  LIn: DATA_BLOB;
  LOut: DATA_BLOB;
  LResult: TBytes;
begin
  LInput := TNetEncoding.Base64.DecodeStringToBytes(ABase64Blob);
  LIn.cbData := Length(LInput);
  if Length(LInput) > 0 then
    LIn.pbData := @LInput[0]
  else
    LIn.pbData := nil;

  if not CryptUnprotectData(@LIn, nil, nil, nil, nil,
    CRYPTPROTECT_UI_FORBIDDEN, @LOut) then
    raise EDPAPIError.CreateFmt('CryptUnprotectData failed (error %d).', [GetLastError]);
  try
    LResult := BlobToBytes(LOut);
  finally
    LocalFree(HLOCAL(LOut.pbData));
  end;
  Result := TEncoding.UTF8.GetString(LResult);
end;

{$ELSE}

function DPAPIAvailable(): Boolean;
begin
  Result := False;
end;

function DPAPIProtect(const APlainText: string): string;
begin
  raise EDPAPIError.Create('DPAPI is only supported on Windows.');
end;

function DPAPIUnprotect(const ABase64Blob: string): string;
begin
  raise EDPAPIError.Create('DPAPI is only supported on Windows.');
end;

{$ENDIF}

end.
