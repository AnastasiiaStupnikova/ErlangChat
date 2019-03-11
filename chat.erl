-module(chat).
-compile(export_all).

start_server() ->
    {ok, Listen} = gen_tcp:listen(1208, [binary, {packet, 4}, {active, true}]), 
    Port = 1210,
    spawn(fun() -> connect(self(), Listen, Port) end).
    
connect (Pid, Listen, Port) ->
    {ok, Socket} = gen_tcp:accept(Listen),
    Newport = Port+2,
    Cid = spawn(fun()-> connect(Pid, Listen, Newport) end),
    State = [],
    loop(Socket, State, Port, Cid, Pid).
    
loop (Socket, State, Port, Cid, Pid) ->
    receive
        {add, Name, Addr} ->
            Find = proplists:get_value(Name, State, 0),
            case Find of
                 0 -> 
                    Newstate = [{Name, Addr} | State],
                    Pid ! {add, Name, Addr}, 
                    Cid ! {add, Name, Addr}; 
                 _ -> 
                     Newstate = State
            end,
            loop(Socket, Newstate, Port, Cid, Pid);
        {tcp, Socket, Msg} ->
            Data = binary_to_term(Msg), 
            case Data of
                {send, Receiver, Message} ->
                    case Receiver of 
                        0 ->
                          Portsfind = [Y || {_, Y} <- State],
                          Ports = lists:delete(Port, Portsfind),
                          Sockets =  [gen_tcp:connect("localhost", P, [binary, {packet, 4}]) || P<-Ports],                       
                          [gen_tcp:send(Y, term_to_binary(Message)) || {_, Y} <- Sockets],
                          [gen_tcp:close(Y) || {_, Y} <-Sockets];
                        _ ->    
                          Find = proplists:get_value(Receiver, State, 0),
                          case Find of
                              0 -> 
                                Notfound = "-----Sorry, \""++atom_to_list(Receiver)++"\" can not be found\nProbably you wrote nickname wrong or user left chat-----",
                                
                                spawn(fun()->send(Port, Notfound) end);
                              _ ->
                                spawn(fun()->send(Find, Message) end)
                          end  
                    end,                  
                    loop(Socket, State, Port, Cid, Pid);
                        
                {Nick, gimme} ->       
                    who_is_online_port(Socket, Port, State),
                    Message = "***** "++atom_to_list(Nick)++" has entered chat! *****",  
                    spawn(fun()-> broadcast(State, Message) end),
                    Newstate = [{Nick, Port} | State],
                    Pid ! {add, Nick, Port},
                    Cid ! {add, Nick, Port},
                    loop(Socket, Newstate, Port, Cid, Pid);
                
                {system, Message} ->
                    case Message of 
                        "whoisonline" ->
                            spawn(fun()->who_is_online(Port, State) end),
                            loop(Socket, State, Port, Cid, Pid);
                        {"exit", Name} ->
                            Pid ! {delete, Name},
                            Cid ! {delete, Name},
                            io:format("~p udalil~n",[Port]),
                            Newstate = lists:delete(Name, State),
                            Msgexit = "***** "++atom_to_list(Name)++" has left *****", 
                            spawn(fun()->broadcast(Newstate, Msgexit) end),
                            loop(Socket, Newstate, Port, Cid, Pid)                          
                    end
            end;
           {delete, Name} ->
                 Find = proplists:get_value(Name, State, 0),
                 case Find of
                   0 -> 
                      loop(Socket, State, Port, Cid, Pid); 
                   _ -> 
                     Newstate = proplists:delete(Name, State),
                     Pid ! {delete, Name},
                     Cid ! {delete, Name},
                     io:format("~p udalil~n",[Port]),
                     loop(Socket, Newstate, Port, Cid, Pid)     
                  end      
    end.
    
start_chat(Nick) ->
     case gen_tcp:connect("localhost", 1208, [binary, {packet, 4}]) of
        {ok, Socket} ->
            gen_tcp:send(Socket, term_to_binary({Nick, gimme})),
            receive
                {tcp, Socket, Msg} ->
                    {Port, Online} = binary_to_term(Msg),
                    spawn(fun() -> client_server(Port) end),
                    case Online of
                        [] ->
                            Members = "noone is here yet";
                        _ ->                        
                            Members = clear(Online)  
                    end,
                    io:format("*****~s, you have entered the chat!*****~n*****Now online: ~s*****~n", [Nick, Members]),
                    client(Nick,Socket)
            end;
        {error, Reason} ->
            {error, Reason}
    end.
    
client(Nick,Socket) ->
    Message = io:get_line('You: '),
    spawn(fun()->client_send(Nick, Socket, Message) end),
    case string:strip(Message,both, $\n) of
        "exit" ->
            ok;
        _ ->
            client(Nick, Socket)
    end.
    
client_send(Nick,Socket, Message) ->
    To = string:sub_word(Message,1,126),
    Msg = string:sub_word(Message,2,126),
    case Msg of
        [] ->
            Receiver = 0,
            Messagetosend = string:strip(To,both, $\n),
            Sender = atom_to_list(Nick)++": ",
            case Messagetosend of 
                "whoisonline" ->
                    gen_tcp:send(Socket, term_to_binary({system, Messagetosend}));
                "exit" ->
                    gen_tcp:send(Socket, term_to_binary({system, {Messagetosend, Nick}})),
                    gen_tcp:close(Socket);
                _ ->
                    gen_tcp:send(Socket, term_to_binary({send, Receiver, Sender++Messagetosend}))
            end;
        _ ->
            Receiver = list_to_atom([string:to_lower(T)||T<-To]),
            Messagetosend = string:strip(string:strip(Msg,both, $\n), both, 32),
            Sender = atom_to_list(Nick)++": "++To++", ",
            gen_tcp:send(Socket, term_to_binary({send, Receiver, Sender++Messagetosend}))
    end.  
       
    
client_server(Port) ->
    case gen_tcp:listen(Port, [binary, {packet, 4},
                               {reuseaddr, true},
                               {active, true}]) of
        {ok, Listen} ->
            client_server_connect(Listen);
        {error, Reason} ->
            {error, Reason}
    end.
    
client_server_connect(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Socket} ->
            client_server_loop(Socket),
            client_server_connect(Listen);
        _ ->
            ok
    end.
    
client_server_loop(Socket) ->
    receive
        {tcp, Socket, Msg} ->
            io:format("~s~n", [binary_to_term(Msg)]),
            client_server_loop(Socket);
        {tcp_closed, _Socket} ->
            ok
    end.
    
%%%%%%%%%%%%%%%%% HELP FUNCTIONS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%    

who_is_online(Port, State) ->
    Online = "*****Now online: "++clear([X || {X, _} <- State])++"*****",    
    spawn(fun()->send(Port, Online) end).
    
who_is_online_port(Socket, Port, State) ->
    Online = [X || {X, _} <- State],             
    gen_tcp:send(Socket, term_to_binary({Port, Online})).
    
clear (List) ->
    string:strip(string:strip(lists:flatten(io_lib:format("~w", [lists:sort(List)])),both, 91), both, 93).
    
broadcast (State, Message) ->
    Portsfind = [Y || {_, Y} <- State],
    Sockets =  [gen_tcp:connect("localhost", P, [binary, {packet, 4}]) || P<-Portsfind],                         
    [gen_tcp:send(Y, term_to_binary(Message)) || {_, Y} <- Sockets],
    [gen_tcp:close(Y) || {_, Y} <-Sockets].
    
send (Port, Message) ->
    {ok,Socketsend} = gen_tcp:connect("localhost", Port, [binary, {packet, 4}]),                          
    gen_tcp:send(Socketsend, term_to_binary(Message)),
    gen_tcp:close(Socketsend).