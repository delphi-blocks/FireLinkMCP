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

program FireLinkMCPIndy;
{$APPTYPE GUI}

{$R 'FireLink_version.res' '..\FireLink_version.rc'}

uses
  Vcl.Forms,
  FireLink.Config in '..\FireLink.Config.pas',
  FireLink.Security.DPAPI in '..\FireLink.Security.DPAPI.pas',
  FireLink.Database.Intf in '..\FireLink.Database.Intf.pas',
  FireLink.Database.FireDAC in '..\FireLink.Database.FireDAC.pas',
  FireLink.Database.Catalog in '..\FireLink.Database.Catalog.pas',
  FireLink.Database.Tools in '..\FireLink.Database.Tools.pas',
  FireLink.Form.Console in 'FireLink.Form.Console.pas' {frmMain};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
