-module(echat).
-behaviour(gen_server).

-export([connect/2, start_link/0, close_server/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-record(message, {timestamp, name, text, private=false}).
-record(state, {msglist, scribers, clientinfo, maxclients=2}).

%%% Client Utility Functions

current_timestamp() -> io_lib:format("[~2..0b:~2..0b:~2..0b]", tuple_to_list(time())).

create_message(Message, Sender) -> create_message(Message, Sender, false).

create_message(Message, Sender, Private) ->
    #message{timestamp=current_timestamp(),name=Sender, text=Message, private=Private}.

printStringList([]) -> ok;
printStringList([H|T]) ->
    printMessage(H),
    printStringList(T).

printList([]) -> ok;
printList([H|T]) ->
    io:format("~p~n", [H]),
    printList(T).

%%% Client API
printMessage(M) ->
        if
            M#message.private == false ->
                    io:format("~-12s ~-10s : ~s", [M#message.timestamp, M#message.name, M#message.text]);
            M#message.private == true ->
                    io:format("~-12s ~-10s : ~s", [M#message.timestamp, "[" ++ M#message.name ++ "]", M#message.text])
        end.


keep_receiving() ->
    receive
        {_, quit} ->
            ok;
        {_, M} ->
            printMessage(M),            
            keep_receiving()
    after infinity -> erlang:error(timeout)
    end.

connect(output, Name) ->
    Pid = whereis(chatsv),
    M = gen_server:call(Pid, {subscribe, Name}),
    case M of
        {ok, MList} -> 
            printStringList(MList),
            keep_receiving();
        {error, ErrMsg} ->
            io:format(ErrMsg)
    end;


connect(input, Name) ->
    Pid = whereis(chatsv),
    io:format("Welcome to E-Chat!~n~n"),
    gen_server:call(Pid, {broadcast, create_message(lists:concat([Name, " has entered the server.\n"]), "*Server*")}),
    send_to_server(Name, Pid),
    ok.

send_to_server(Name, Pid) ->
    Text = io:get_line("enter message> "),
    {ok, RE_PRV} = re:compile("/w (\\w+) (.+\\n)"),
    case Text of
        "/l" ++ _ ->
            ClientList = gen_server:call(Pid, {getclist}),
            printList(ClientList);
        "/w" ++ _ -> 
            {match, [ReceiverName | [MainText]]} =  re:run(Text, RE_PRV , [{capture, all_but_first, list}]),
            gen_server:call(Pid, {unicast, create_message(MainText, Name, true), ReceiverName});
        "/q"++ _ ->
            gen_server:call(Pid, {disconnect, Name}),
            gen_server:call(Pid, {broadcast, create_message(lists:concat([Name, " has left the server.\n"]), "*Server*")}),
            exit(normal);
        _ ->
            gen_server:call(Pid, {broadcast, create_message(Text, Name)})
    end,
    send_to_server(Name, Pid).

close_server() ->
    gen_server:call(whereis(chatsv), {terminate}).

start_link() ->
    gen_server:start_link({local, chatsv}, ?MODULE, [], []).

%%% Server functions
init([]) -> {ok,#state{msglist=[], scribers=[], clientinfo=dict:new()}}. %% no treatment of info here!

send_to_clients(_, []) ->
    ok;
send_to_clients(Message, [Scriber | ScriberList]) ->
    gen_server:reply(Scriber, Message),
    send_to_clients(Message, ScriberList).

handle_call({unicast, Message, ReceiverName}, _, S = #state{clientinfo=Dict}) ->
    Receiver = dict:fetch(ReceiverName, Dict),
    send_to_clients(Message, [Receiver]),
    {reply, "Sent", S};

handle_call({broadcast, Message}, _, S = #state{msglist=MList, scribers=ScriberList}) ->
    NewMList = lists:reverse([ Message |lists:reverse(MList)]),
    send_to_clients(Message, ScriberList),
    {reply, "Sent", S#state{msglist=NewMList}};

handle_call({getclist}, _, S = #state{clientinfo=Dict}) ->
    {reply, dict:fetch_keys(Dict), S};

handle_call({disconnect, Name}, _, S = #state{scribers=ScriberList, clientinfo=Dict}) ->
    Receiver = dict:fetch(Name, Dict),
    NewScriberList = lists:delete(Receiver, ScriberList),
    NewDict = dict:erase(Name, Dict),
    send_to_clients(quit, [Receiver]),
    {reply, "Sent", S#state{scribers=NewScriberList, clientinfo=NewDict}};

handle_call({subscribe, Name}, From, S = #state{msglist=MList, scribers=ScriberList, clientinfo=Dict}) ->
    if
        length(ScriberList) == S#state.maxclients ->
                {reply, {error, "Error: Room is full!"} , S};
            
        true ->
                NewScriberList = [From | ScriberList],
                NewDict = dict:store(Name, From, Dict),
                {reply, {ok, lists:reverse(lists:sublist(lists:reverse(MList), 3))}, S#state{scribers=NewScriberList, clientinfo=NewDict}}
    end;
    

handle_call(terminate, From, _) ->
    gen_server:reply(From, ok),
    terminate().

handle_cast({return}, S) ->
    S.

%%% Private functions
terminate() ->
    exit(normal).
