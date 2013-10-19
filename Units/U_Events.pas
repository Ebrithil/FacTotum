unit U_Events;

interface

uses
    System.UITypes, System.Classes, System.SyncObjs, System.SysUtils, System.Types, vcl.comCtrls,

    U_OutputTasks;

type
    tTabImage   = (tiNoImg = -1, tiInstall, tiConfig, tiUpdate, tiEvents, tiUpdateNotif, tiEvtErr);
    tEventImage = (eiNoImg = -1, eiInfo, eiAlert, eiError, eiDotGreen, eiDotYellow, eiDotRed);

    tTaskEvent = class(tTaskOutput)
        public
            eventDesc,
            eventTime:  string;
            eventType:  tImageIndex;
            constructor create(description: string; eventType: tImageIndex);
            procedure   exec; override;
    end;

    eventHandler = class
        public
            function  createEvent(description: string; eventType: tImageIndex): tTaskEvent;
            function  prepare(event: tTaskEvent): boolean;
            procedure initialize(errorList: tListView; errorTab: tTabSheet);
        protected
            m_errorList: tListView;
            m_errorTab:  tTabSheet;
    end;

var
    sEventHdlr: eventHandler;

implementation
    procedure eventHandler.initialize(errorList: tListView; errorTab: tTabSheet);
    begin
        self.m_errorList := errorList;
        self.m_errorTab  := errorTab;
    end;

    function eventHandler.prepare(event: tTaskEvent): boolean;
    begin
        if (not assigned(self.m_errorList)) or
           (not assigned(self.m_errorTab)) then
        begin
            result := false;
            exit;
        end;

        event.dummyTargets[0] := self.m_errorList;
        event.dummyTargets[1] := self.m_errorTab;
        result := true;
    end;

    function eventHandler.createEvent(description: string; eventType: TImageIndex): tTaskEvent;
    begin
        result := tTaskEvent.create(description, eventType);
        setLength(result.dummyTargets, 2);
        result.dummyTargets[0] := self.m_errorList;
        result.dummyTargets[1] := Self.m_errorTab;
    end;

    constructor tTaskEvent.create(description: string; eventType: tImageIndex);
    begin
        self.eventTime := formatDateTime('hh:nn:ss', now);
        self.eventDesc := description;
        self.eventType := eventType;
    end;

    procedure tTaskEvent.exec;
    var
        lvEvents: tListView;
        tLog:     tTabSheet;
    begin
        if not (self.dummyTargets[0] is tListView) or
           not (self.dummyTargets[1] is tTabSheet) then
            if not sEventHdlr.prepare(self) then
                exit;

        lvEvents := self.dummyTargets[0] as tListView;
        tLog     := self.dummyTargets[1] as tTabSheet;

        if self.eventType = tImageIndex(eiError) then
            tLog.ImageIndex := tImageIndex(tiEvtErr);

        with(lvEvents.items.add) do
        begin
            stateIndex := self.eventType;
            subItems.add(self.eventTime);
            subItems.add(self.eventDesc);
        end;
    end;
end.
