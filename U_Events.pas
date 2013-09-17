unit U_Events;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ImgList, Vcl.StdCtrls, Vcl.Buttons,
  Vcl.ComCtrls, Vcl.ExtCtrls,

  U_Classes;

type
  TfEvents = class(TForm)
    lvEvents: TListView;
    bbClear: TBitBtn;
    ilEvents: TImageList;
    tEvents: TTimer;
    procedure bbClearClick(Sender: TObject);
    procedure tEventsTimer(Sender: TObject);
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
    var
          iEvent: TListItem;
    begin
          lvEvents.items.clear;
    end;

    procedure TfEvents.tEventsTimer(Sender: TObject);
    var
          error:  Exception;
          iEvent: TListItem;
    begin
          while not(sErrorHdlr.isErrorListEmpty) do
          begin
              error := sErrorHdlr.pullErrorFromList;
              iEvent := lvEvents.Items.Add;
              iEvent.subItems.add( error.ClassName + ': ' + error.Message );
          end;
    end;

end.
