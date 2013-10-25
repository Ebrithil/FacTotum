unit U_Threads;

interface

uses
    System.SyncObjs, System.Types, System.Classes, System.SysUtils, System.UITypes, Windows,

    U_InputTasks, U_OutputTasks, U_Events;

type
    thread = class(tThread)
        protected
            working:  boolean;
            procedure Execute; override;

        public
            constructor create; reintroduce;
            property    isWorking: boolean read working;
    end;

    tThreads = Array of thread;

    tTaskManager = class // Wrapper di funzioni ed oggetti relativi alla gestione dei task
        public
            constructor create; overload;
            constructor create(const threadsCount: byte); overload;
            destructor  Destroy(forced: boolean = false); reintroduce; overload;

            function  getBusyThreadsCount: byte;
            function  getThreadsCount: byte;
            function  pullTaskFromInput: tTask;
            procedure pushTaskToInput(taskToAdd: tTask);
            function  pullTaskFromOutput: tTaskOutput;
            procedure pushTaskToOutput(taskToAdd: tTaskOutput);
            function  isTaskOutputEmpty: boolean;

        protected
            m_threadPool: tThreads;
            m_inputMutex, m_outputMutex: tMutex;
            m_inputTasks, m_outputTasks: tList;
            procedure pushTaskToQueue(taskToAdd: tTask; taskQueue: tList; queueMutex: tMutex);
            function  pullTaskFromQueue(taskQueue: tList; queueMutex: tMutex): tTask;
    end;

    procedure createEvent(description: string; eventType: tEventImage); inline;

const
    defaultThreadPoolSleepTime = 50;

var
    sTaskMgr: tTaskManager;

implementation
    procedure createEvent(description: string; eventType: tEventImage); inline;
    begin
        sTaskMgr.pushTaskToOutput( sEventHdlr.createEvent(description, tImageIndex(eventType)) );
    end;

    constructor thread.create;
    begin
        self.working := false;
        inherited create(false);
    end;

    procedure thread.execute;
    var
        task: tTask;
    begin
        while not(self.terminated) do
        begin
            self.working := false;

            if not( assigned(sTaskMgr) ) then
            begin
                sleep(defaultThreadPoolSleepTime);
                continue;
            end;

            task := sTaskMgr.pullTaskFromInput;

            if not( assigned(task) ) then
            begin
                sleep(defaultThreadPoolSleepTime);
                continue;
            end;

            self.working := true;

            task.exec;
            task.free;
        end;
    end;

    constructor tTaskManager.create;
    begin
        self.create(CPUCount)
    end;

    destructor tTaskManager.Destroy(forced: boolean = false);
    var
        i: integer;
    begin
        if forced then
            for i := 0 to pred( length(m_threadPool) ) do
                m_threadPool[i].free
        else
        begin
            for i := 0 to pred( length(m_threadPool) ) do
                m_threadPool[i].terminate;

            for i := 0 to pred( length(m_threadPool) ) do
            begin
                m_threadPool[i].waitFor;
                m_threadPool[i].free;
            end;
        end;

        inherited Destroy;
    end;

    constructor tTaskManager.create(const threadsCount: byte);
    var
        i: byte;
    begin
        m_inputMutex  := tMutex.create;
        m_outputMutex := tMutex.create;
        m_inputTasks  := tList.create;
        m_outputTasks := tList.create;

        m_outputTasks.add(
            sEventHdlr.createEvent( 'ThreadPool: inizializzazione di '
                                  + intToStr(threadsCount) + ' threads.',
                                    tImageIndex(eiInfo) )
        );

        setLength(m_threadPool, threadsCount);
        for i := 0 to threadsCount - 1 do
            m_threadPool[i] := thread.create;
    end;

    function tTaskManager.getBusyThreadsCount: byte;
    var
        i: byte;
    begin
        result := 0;
        for i := 0 to pred( length(self.m_threadPool) ) do
            if self.m_threadPool[i].isWorking then
                inc(result);
    end;

    function tTaskManager.getThreadsCount: byte;
    begin
        result := length(m_threadPool);
    end;

    procedure tTaskManager.pushTaskToInput(taskToAdd: tTask);
    begin
        self.pushTaskToQueue(taskToAdd, m_inputTasks, m_inputMutex)
    end;

    function tTaskManager.pullTaskFromInput: tTask;
    begin
        result := self.pullTaskFromQueue(m_inputTasks, m_inputMutex)
    end;

    procedure tTaskManager.pushTaskToOutput(taskToAdd: tTaskOutput);
    begin
        self.pushTaskToQueue(taskToAdd, m_outputTasks, m_outputMutex)
    end;

    function tTaskManager.isTaskOutputEmpty: boolean;
    begin
        result := (m_outputTasks.count = 0);
    end;

    function tTaskManager.pullTaskFromOutput: tTaskOutput;
    begin
        result := self.pullTaskFromQueue(m_outputTasks, m_outputMutex) as tTaskOutput
    end;

    procedure tTaskManager.pushTaskToQueue(taskToAdd: tTask; taskQueue: tList; queueMutex: tMutex);
    begin
        queueMutex.acquire;
        taskQueue.add(taskToAdd);
        queueMutex.release;
    end;

    function tTaskManager.pullTaskFromQueue(taskQueue: tList; queueMutex: tMutex): tTask;
    begin
        queueMutex.acquire;

        if taskQueue.count > 0 then
        begin
            result := tTask(taskQueue.first);
            taskQueue.remove(taskQueue.first);
        end
        else
            result := nil;


        queueMutex.release;
    end;

end.
