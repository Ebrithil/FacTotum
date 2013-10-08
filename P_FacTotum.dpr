program P_FacTotum;

uses
  Vcl.Forms,
  U_Main in 'U_Main.pas' {fFacTotum},
  Vcl.Themes,
  Vcl.Styles,
  U_Functions in 'Units\U_Functions.pas',
  U_DataBase in 'Units\U_DataBase.pas',
  U_Threads in 'Units\U_Threads.pas',
  U_InputTasks in 'Units\U_InputTasks.pas',
  U_Download in 'Units\U_Download.pas',
  U_Events in 'Units\U_Events.pas',
  U_OutputTasks in 'Units\U_OutputTasks.pas',
  U_Parser in 'Units\U_Parser.pas',
  U_Files in 'Units\U_Files.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Metropolis UI Dark');
  Application.CreateForm(TfFacTotum, fFacTotum);
  Application.Run;
end.
