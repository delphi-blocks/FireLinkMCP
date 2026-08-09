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

unit FireLink.Form.Console;

interface

uses
  Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.AppEvnts, Vcl.StdCtrls, IdGlobal, Web.HTTPApp,
  IdContext, IdBaseComponent, IdComponent, IdCustomTCPServer,
  IdCustomHTTPServer, IdHTTPServer,

  MCPConnect.JRPC.Server,
  MCPConnect.MCP.Server.Api,
  MCPConnect.Configuration.MCP,
  MCPConnect.Configuration.Session,
  MCPConnect.Configuration.Auth,
  MCPConnect.Content.Writers.RTL,
  MCPConnect.Content.Writers.VCL,
  MCPConnect.Transport.Indy;

type
  TfrmMain = class(TForm)
    ButtonStart: TButton;
    ButtonStop: TButton;
    EditPort: TEdit;
    Label1: TLabel;
    ApplicationEvents1: TApplicationEvents;
    procedure FormCreate(Sender: TObject);
    procedure ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonStopClick(Sender: TObject);
  private
    FHTTPServer: TJRPCIndyServer;

    procedure StartServer;
  public
    { Public declarations }
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  WinApi.Windows, Winapi.ShellApi,
  Logify, Logify.Adapter.Debug,
  FireLink.Config;

procedure TfrmMain.ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
begin
  ButtonStart.Enabled := not FHTTPServer.Active;
  ButtonStop.Enabled := FHTTPServer.Active;
  EditPort.Enabled := not FHTTPServer.Active;
end;

procedure TfrmMain.ButtonStartClick(Sender: TObject);
begin
  StartServer;
end;

procedure TfrmMain.ButtonStopClick(Sender: TObject);
begin
  FHTTPServer.Active := False;
  Logger.Log('MCP Server Stopped', TLogLevel.Debug);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FHTTPServer := TJRPCIndyServer.Create(Self);
  TServerConfigurator.ConfigureServer(FHTTPServer.JRPCServer);

  StartServer;
end;

procedure TfrmMain.StartServer;
begin
  if not FHTTPServer.Active then
  begin
    FHTTPServer.Bindings.Clear;
    FHTTPServer.DefaultPort := StrToInt(EditPort.Text);
    FHTTPServer.Active := True;
    Logger.Log('MCP Server Started', TLogLevel.Debug);
  end;
end;

initialization
  TLoggerAdapterRegistry.Instance.RegisterFactory(
    TLogifyAdapterDebugFactory.CreateAdapterFactory('Debug log', TLogLevel.Info));

end.
