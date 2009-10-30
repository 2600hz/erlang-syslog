-module(syslog).

-behaviour(gen_server).

-define(DRV_NAME, "syslog_drv").

% API
-export([
	start/0,
	start_linked/0,
	open/3,
	log/2
]).

% gen_server callbacks
-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3
]).

-record(state, {port}).

start() ->
	gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_linked() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

open(Ident, Logopt, Facility) ->
	gen_server:call(?MODULE, {open, Ident, Logopt, Facility}).

log(Priority, Message) ->
	gen_server:call(?MODULE, {log, Priority, Message}).

%%% API %%%

init([]) ->
	erl_ddll:start(),
	Path = case code:priv_dir(syslog) of
		{error, _} ->
			case load_path(?DRV_NAME++".so") of
				{error, _} ->
					error;
				{ok, P} ->
					P
			end;
		P ->
			P
	end,

	case Path of
		error ->
			{stop, no_driver};
		Path ->
			case erl_ddll:load_driver(Path, ?DRV_NAME) of
				ok ->
					Port = open_port({spawn, ?DRV_NAME}, [binary]),
					{ok, #state{port = Port}};
				{error, Error} ->
					error_logger:format("Error loading driver: " ++ erl_ddll:format_error(Error), []),
					{stop, bad_driver}
			end
	end.

handle_call({log, Priority, Message}, _From, #state{port = Port} = State) ->
	port_command(Port, erlang:term_to_binary({log, Priority, lists:flatten(Message)})),
	Reply = receive
		{Port, {data, Bin}} ->
			Result = binary_to_term(Bin)
	after 1000 -> timeout
	end,
	{reply, Reply, State};
handle_call({open, Ident, Logopt, Facility}, _From, State) ->
	port_command(State#state.port, erlang:term_to_binary({open, Ident, Logopt, Facility})),
	Reply = receive
		{Port, {data, Bin}} ->
			Result = binary_to_term(Bin)
	after 1000 -> timeout
	end,
	{reply, Reply, State};
handle_call(_Msg, _From, State) ->
	{reply, ok, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_, _, _) ->
	ok.

%%% internal functions %%%

load_path(File) ->
	case lists:zf(fun(Ebin) ->
					Priv = Ebin ++ "/../priv/",
					case file:read_file_info(Priv ++ File) of
						{ok, _} -> {true, Priv};
						_ -> false
					end
			end, code:get_path()) of
		[Dir|_] ->
			{ok, Dir};
		[] ->
			error_logger:format("Error: ~s not found in code path\n", [File]),
			{error, enoent}
	end.

