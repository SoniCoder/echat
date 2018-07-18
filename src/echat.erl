-module(echat).
-behaviour(gen_server).

-export([connect/2, start_link/0, close_server/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-record(message, {timestamp, name, text, private=false}).
-record(state, {msglist, scribers, clientinfo, maxclients=4}).

%%% Client Utility Functions

current_timestamp() -> io_lib:format("[~2..0b:~2..0b:~2..0b]", tuple_to_list(time())).

create_announcement(Message) ->
    #message{timestamp=current_timestamp(),name="*Server* ", text=Message}.

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
        {_, M} ->
            printMessage(M),            
            keep_receiving()
    after infinity -> erlang:error(timeout)
    end.

printStringList([]) -> ok;
printStringList([H|T]) ->
    printMessage(H),
    printStringList(T).

connect(output, Name) ->
    Pid = whereis(chatsv),
    M = gen_server:call(Pid, {subscribe, Name}),
    printStringList(M),
    keep_receiving();

connect(input, Name) ->
    Pid = whereis(chatsv),
    io:format("Welcome to E-Chat!~n~n"),
    gen_server:call(Pid, {broadcast, create_announcement(lists:concat([Name, " has entered the server.\n"]))}),
    send_to_server(Name, Pid),
    ok.

send_to_server(Name, Pid) ->
    Text = io:get_line("enter message> "),
    {ok, RE_PRV} = re:compile("/w (\\w+) (.+\\n)"),
    case Text of
        "/w" ++ _ -> 
            {match, [ReceiverName | [MainText]]} =  re:run(Text, RE_PRV , [{capture, all_but_first, list}]),
            gen_server:call(Pid, {unicast, #message{timestamp=io_lib:format("[~2..0b:~2..0b:~2..0b]", tuple_to_list(time())), name=Name, text=MainText, private=true}, ReceiverName});
        "/q"++ _ ->
            exit(normal);
        _ ->
            gen_server:call(Pid, {broadcast, #message{timestamp=io_lib:format("[~2..0b:~2..0b:~2..0b]", tuple_to_list(time())), name=Name, text=Text}})
    end,
    send_to_server(Name, Pid).

close_server() ->
    gen_server:call(whereis(chatsv), {terminate}).

start_link() ->
    {ok, _} = gen_server:start_link({local, chatsv}, ?MODULE, [], []).
    %register(chatsv, Pid).

%%% Server functions
init([]) -> {ok,#state{msglist=[], scribers=[], clientinfo=dict:new()}}. %% no treatment of info here!

send_to_clients(_, []) ->
    ok;
send_to_clients(Message, [Scriber | ScriberList]) ->
    gen_server:reply(Scriber, Message),
    send_to_clients(Message, ScriberList).

handle_call({unicast, Message, ReceiverName}, From, S = #state{clientinfo=Dict}) ->
    Receiver = dict:fetch(ReceiverName, Dict),
    send_to_clients(Message, [Receiver]),
    {reply, "Sent", S};

handle_call({broadcast, Message}, From, S = #state{msglist=MList, scribers=ScriberList}) ->
    NewMList = lists:reverse([ Message |lists:reverse(MList)]),
    send_to_clients(Message, ScriberList),
    {reply, "Sent", S#state{msglist=NewMList}};

handle_call({subscribe, Name}, From, S = #state{msglist=MList, scribers=ScriberList, clientinfo=Dict}) ->
    NewScriberList = [From | ScriberList],
    NewDict = dict:store(Name, From, Dict),
    {reply, lists:reverse(lists:sublist(lists:reverse(MList), 3)), S#state{scribers=NewScriberList, clientinfo=NewDict}};

handle_call(terminate, From, _) ->
    gen_server:reply(From, ok),
    terminate().

handle_cast({return}, S) ->
    S.

%%% Private functions
terminate() ->
    exit(normal).
