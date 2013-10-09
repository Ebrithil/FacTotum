unit U_Events;

interface

uses
    System.UITypes, System.Classes, System.SyncObjs, System.SysUtils, System.Types;

type
    tEventImage = (eiNoImg = -1, eiInfo, eiAlert, eiError, eiDotGreen, eiDotYellow, eiDotRed);

    tEvent = class
        eventDesc,
        eventTime:  string;
        eventType:  tImageIndex;
        constructor create(eDesc: string; eType: tEventImage);
    end;

    eventHandler = class
        public
            constructor create;
            procedure   pushEventToList(event: string; eType: tEventImage); overload;
            function    pullEventFromList: tEvent;
            function    isEventListEmpty:  boolean;
            function    getErrorCache:     boolean;
            procedure   clearErrorCache;
        protected
            m_eventMutex:     tMutex;
            m_eventList:      tList;
            m_containsErrors: boolean;
            procedure   pushEventToList(event: tEvent); overload;
    end;

var
    sEventHdlr: eventHandler;

implementation

    constructor tEvent.create(eDesc: string; eType: tEventImage);
    begin
        self.eventType := tImageIndex(eType);
        self.eventTime := formatDateTime('hh:nn:ss', now);
        self.eventDesc := eDesc;
    end;

    constructor eventHandler.create;
    begin
        m_eventMutex := tMutex.create;
        m_eventList := tList.create;
    end;

    procedure eventHandler.pushEventToList(event: tEvent);
    begin
        m_eventMutex.acquire;
        m_eventList.add(event);
        m_eventMutex.release;

        if event.eventType = tImageIndex(eiError) then
            m_containsErrors := true;
    end;

    procedure eventHandler.pushEventToList(event: string; eType: tEventImage);
    begin
        self.pushEventToList( tEvent.create(event, eType) );
    end;

    function eventHandler.pullEventFromList: tEvent;
    begin
        m_eventMutex.acquire;

        if m_eventList.count = 0 then
        begin
            m_eventMutex.release;
            result := nil;
            exit;
        end;

        result := tEvent(m_eventList.first);
        m_eventList.remove(m_eventList.first);
        m_eventMutex.release;
    end;

    function eventHandler.isEventListEmpty: boolean;
    begin
        m_eventMutex.acquire;
        result := (m_eventList.count = 0);
        m_eventMutex.release;
    end;

    function eventHandler.getErrorCache: boolean;
    begin
        result := m_containsErrors;
    end;

    procedure eventHandler.clearErrorCache;
    begin
        m_containsErrors := false;
    end;

end.
