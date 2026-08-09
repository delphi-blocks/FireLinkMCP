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

program FireLinkMCP;

{$APPTYPE CONSOLE}

{$R *.res}

{$R 'FireLink_version.res' '..\FireLink_version.rc'}

uses
  System.SysUtils,
  MCPConnect.JRPC.Server,
  MCPConnect.MCP.Server.Api,
  MCPConnect.Configuration.MCP,
  MCPConnect.Configuration.Session,
  MCPConnect.Configuration.Auth,
  MCPConnect.Content.Writers.RTL,
  MCPConnect.Content.Writers.VCL,
  MCPConnect.Transport.Stdio,
  FireLink.Config in '..\FireLink.Config.pas',
  FireLink.Security.DPAPI in '..\FireLink.Security.DPAPI.pas',
  FireLink.Database.Intf in '..\FireLink.Database.Intf.pas',
  FireLink.Database.FireDAC in '..\FireLink.Database.FireDAC.pas',
  FireLink.Database.Catalog in '..\FireLink.Database.Catalog.pas',
  FireLink.Database.Tools in '..\FireLink.Database.Tools.pas';

procedure StartServer;
var
  LStdioServer: TJRPCStdioServer;
begin

  LStdioServer := TJRPCStdioServer.Create(nil);
  try
    TServerConfigurator.ConfigureServer(LStdioServer.JRPCServer);
    LStdioServer.StartServerAndWait;
  finally
    LStdioServer.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    StartServer;
  except
    on E: Exception do
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
  end;
end.
