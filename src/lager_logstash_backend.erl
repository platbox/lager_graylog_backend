%% Copyright (c) 2014 Angelantonio Valente.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

-module(lager_logstash_backend).

-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
         code_change/3]).

%
% Lager backend for graylog
%
% The backend must be configured in the lager's configuration section:
%
% {lager_logstash_backend, [
%    {host, "<host>:<port>"},
%    {level, info},
%    {name, logstash},
%    {format_config, [
%        {facility, "<facility>"}
%    ]}
%  ]}
%

init(Config) -> lager_udp_backend:init(?MODULE, lager_logstash_formatter, Config).

%% @private

handle_call(Request, State) -> lager_udp_backend:handle_call(Request, State).

%% @private

handle_event(Event, State) -> lager_udp_backend:handle_event(Event, State).

%% @private

handle_info(Info, State) -> lager_udp_backend:handle_info(Info, State).

%% @private

terminate(Reason, State) -> lager_udp_backend:terminate(Reason, State).

%% @private

code_change(OldVsn, State, Extra) -> lager_udp_backend:code_change(OldVsn, State, Extra).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-record(state, {name, address, port, socket, level, formatter, format_config}).

udp_server(Caller) ->
    % open a socket on the port zero, this asks the kernel to use a free port
    {ok, Socket} = gen_udp:open(0, [binary, {active, once}]),

    {ok, Port} = inet:port(Socket),

    % send the port to the caller
    Caller ! {port, Port},

    % wait for log
    receive
        {udp, Socket, _Host, _Port, Bin} ->
            Caller ! {data, Bin}
    end,
    gen_udp:close(Socket).

init_test() ->
    Config = [{host, "localhost:12201"}],
    Res = init(Config),

    ?assertMatch({ok, #state{level=64, name={?MODULE, {"localhost", 12201}},
                           address={127,0,0,1}, port=12201,
                           socket=_, format_config=_}}, Res).

handle_call_set_loglevel_test_() ->
    [
        ?_assertEqual({ok, {error, bad_loglevel}, #state{}}, handle_call({set_loglevel, undefined}, #state{})),
        ?_assertEqual({ok, ok, #state{level=lager_util:config_to_mask(info)}}, handle_call({set_loglevel, info}, #state{}))
        ].

handle_call_get_loglevel_test() ->
    ?assertEqual({ok, info, #state{level=info}}, handle_call(get_loglevel, #state{level=info})).

handle_call_cathcall_test() ->
    ?assertEqual({ok, ok, #state{}}, handle_call(test, #state{})).


functional_test() ->
    % start the fake server
    Self = self(),
    F = fun() -> udp_server(Self) end,

    spawn_link(F),

    % wait for the server's port
    Port = receive
        {port, P} ->
            P
    after 500 ->
        {error, not_started}
    end,

    Cfg = [{lager_logstash_backend, [
                    {host, "localhost:"++integer_to_list(Port)},
                    {level, error},
                    {name, logstash},
                    {format_config, [
                        {facility, "lager-test"},
                        {extra_fields, [
                            {'environment', <<"test">>}
                        ]}
                    ]}
                    ]}],

    application:load(lager),
    application:set_env(lager, handlers, Cfg),

    ok = lager:start(),

    % level is "error", so lower-level messages should be dropped
    lager:log(warning, self(), "This should never be received"),
    lager:log(error, self(), "This is a test"),

    {Res} = receive
        {data, Bin} ->
            jiffy:decode(Bin)
    after 500 ->
            {error, message_not_received}
    end,

    ok = application:stop(lager),

    ?assertEqual(<<"1">>, proplists:get_value(<<"@version">>, Res)),
    ?assertEqual(<<"This is a test">>, proplists:get_value(<<"message">>, Res)),
    ?assertEqual(<<"test">>, proplists:get_value(<<"environment">>, Res)),
    ?assertEqual(<<"error">>, proplists:get_value(<<"severity">>, Res)).

-endif.
