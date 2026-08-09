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

unit FireLink.Config;

interface

uses
  System.SysUtils, System.Classes,
  IdGlobal, IdContext, IdBaseComponent, IdComponent,
  IdCustomTCPServer, IdCustomHTTPServer, IdHTTPServer,

  MCPConnect.JRPC.Server,
  MCPConnect.Transport.Indy,

  MCPConnect.MCP.Server.Api,

  MCPConnect.Configuration.MCP,
  MCPConnect.Configuration.Session,
  MCPConnect.Configuration.Auth,

  MCPConnect.Content.Writers.RTL,
  MCPConnect.Content.Writers.VCL;

type
  TServerConfigurator = class
    class procedure ConfigureServer(AServer: TJRPCServer);
  end;

implementation

uses
  System.IOUtils,
  FireLink.Database.Catalog,
  FireLink.Database.Tools;

{ TServerConfigurator }

class procedure TServerConfigurator.ConfigureServer(AServer: TJRPCServer);
var
  LDataPath: string;
begin
  // Create the database config file with commented examples on first run.
  TDatabaseCatalog.EnsureConfigFile();
  // Seal any plaintext password (plain:) into a DPAPI blob (Windows only). The
  // ones added while the server is running are sealed by TDatabaseCatalog.Open.
  TDatabaseCatalog.HardenPasswords();

  LDataPath := TPath.Combine(TPath.GetAppPath, 'data');

  AServer

    .Plugin.Configure<IMCPConfig>
      .Server
        .SetName('firelink-mcp-server')
        .SetVersion('2.0.0')
        .SetCapabilities([Tools])

        .RegisterWriter(TMCPImageWriter)
        .RegisterWriter(TMCPPictureWriter)
        .RegisterWriter(TMCPStreamWriter)
        .RegisterWriter(TMCPStringListWriter)
      .BackToMCP

      .Security
        .SetCORS(True)
        .SetAllowedMethods(['POST'])
        .SetAllowedOrigins(['*'])
      .BackToMCP

      .Tools
        .RegisterClass(TDatabaseTools)
      .BackToMCP
  ;
end;

end.
