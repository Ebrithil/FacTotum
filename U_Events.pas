unit U_Events;

interface

uses
    winapi.windows, winapi.messages, system.sysUtils, system.variants, system.classes, vcl.graphics,
    vcl.controls, vcl.forms, vcl.dialogs, vcl.imgList, vcl.stdCtrls, vcl.buttons,
    vcl.comCtrls, vcl.extCtrls,

    U_Classes;

type
    tFEvents = class(tForm)
        lvEvents:  tListView;
        bbClear:   tBitBtn;
        ilEvents:  tImageList;
        tEvents:   tTimer;
        procedure  bbClearClick(sender: tObject);
        procedure  tEventsTimer(sender: tObject);
    private
        { Private declarations }
    public
        { Public declarations }
    end;

var
    fEvents: tFEvents;

implementation

{$R *.dfm}

    procedure tFEvents.bbClearClick(sender: tObject);
    begin
          lvEvents.items.clear;
    end;

    procedure TfEvents.tEventsTimer(Sender: tObject);
    var
          error:  exception;
          iEvent: tListItem;
    begin
          while not(sErrorHdlr.isErrorListEmpty) do
          begin
              error := sErrorHdlr.pullErrorFromList;
              iEvent := lvEvents.items.add;
              iEvent.subItems.add( error.className + ': ' + error.message );
          end;
    end;

end.
