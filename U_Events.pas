unit U_Events;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ImgList, Vcl.StdCtrls, Vcl.Buttons,
  Vcl.ComCtrls;

type
  TfEvents = class(TForm)
    lvEvents: TListView;
    bbClear: TBitBtn;
    ilEvents: TImageList;
    procedure bbClearClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  fEvents: TfEvents;

implementation

{$R *.dfm}

procedure TfEvents.bbClearClick(Sender: TObject);
begin
    lvEvents.Items.Clear;
end;

end.
