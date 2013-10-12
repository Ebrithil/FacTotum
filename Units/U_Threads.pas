unit U_Threads;

interface

uses
    System.SyncObjs, System.Types, System.Classes, System.SysUtils, Windows,

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

    taskManager = class // Wrapper di funzioni ed oggetti relativi alla gestione dei task
        public
            constructor create; overload;
            constructor create(const threadsCount: byte); overload;
            destructor  Destroy(forced: boolean = false); overload;

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

const
    defaultThreadPoolSleepTime = 50;

var
    sTaskMgr: taskManager;

implementation

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

    constructor taskManager.create;
    begin
        self.create(CPUCount)
    end;

    destructor taskManager.Destroy(forced: boolean);
    var
        i: integer;
    begin
        if forced then
            for i := 0 to pred( length(m_threadPool) ) do
                terminateThread(m_threadPool[i].threadID, 0)
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

    constructor taskManager.create(const threadsCount: byte);
    var
        i: byte;
    begin
        m_inputMutex  := tMutex.create;
        m_outputMutex := tMutex.create;
        m_inputTasks  := tList.create;
        m_outputTasks := tList.create;

        setLength(m_threadPool, threadsCount);

        for i := 0 to threadsCount - 1 do
            m_threadPool[i] := thread.create;

        sEventHdlr.pushEventToList('ThreadPool inizializzata a ' + IntToStr(threadsCount) + ' threads.', eiInfo);
    end;

    function taskManager.getBusyThreadsCount: byte;
    var
        i: byte;
    begin
        result := 0;
        for i := 0 to pred( length(self.m_threadPool) ) do
            if self.m_threadPool[i].isWorking then
                inc(result);
    end;

    function taskManager.getThreadsCount: byte;
    begin
        result := length(m_threadPool);
    end;

    procedure taskManager.pushTaskToInput(taskToAdd: tTask);
    begin
        self.pushTaskToQueue(taskToAdd, m_inputTasks, m_inputMutex)
    end;

    function taskManager.pullTaskFromInput: tTask;
    begin
        result := self.pullTaskFromQueue(m_inputTasks, m_inputMutex)
    end;

    procedure taskManager.pushTaskToOutput(taskToAdd: tTaskOutput);
    begin
        self.pushTaskToQueue(taskToAdd, m_outputTasks, m_outputMutex)
    end;

    function taskManager.isTaskOutputEmpty: boolean;
    begin
        result := (m_outputTasks.count = 0);
    end;

    function taskManager.pullTaskFromOutput: tTaskOutput;
    begin
        result := self.pullTaskFromQueue(m_outputTasks, m_outputMutex) as tTaskOutput
    end;

    procedure taskManager.pushTaskToQueue(taskToAdd: tTask; taskQueue: tList; queueMutex: tMutex);
    begin
        queueMutex.acquire;
        taskQueue.add(taskToAdd);
        queueMutex.release;
    end;

    function taskManager.pullTaskFromQueue(taskQueue: tList; queueMutex: tMutex): tTask;
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
