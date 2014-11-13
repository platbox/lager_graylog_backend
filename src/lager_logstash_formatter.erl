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

-module(lager_logstash_formatter).

-export([format/2, format/3]).

% ignore colors
format(Message, Config, _Colors) ->
    format(Message, Config).

format(Message, Config) ->
    Data = get_raw_data(Message, Config) ++ getvalue(extra_fields, Config, []),
    Msg = jiffy:encode({Data}),
    <<Msg/binary,"\n">>.

utc_iso_datetime(Message) ->
    Ts = {_, _, Micro} = lager_msg:timestamp(Message),

    {UTCDate, {H, M, S}} = calendar:now_to_universal_time(Ts),

    UTCTime = {H, M, S, Micro div 1000 rem 1000},

    {RawDate, RawTime} = lager_util:format_time({UTCDate, UTCTime}),
    iolist_to_binary([RawDate, $T, RawTime, $Z]).

get_raw_data(Message, Config) ->
    LongMessage = unicode:characters_to_binary(lager_msg:message(Message)),

    HostName = get_host(getvalue(host, Config)),

    MetaData = lager_msg:metadata(Message),

    [{'@version', <<"1">>},
     {'@timestamp', utc_iso_datetime(Message)},
     {'severity', binary_severity(lager_msg:severity(Message))},
     {'facility', iolist_to_binary(getvalue(facility, Config, <<"user-level">>))},
     {'message', LongMessage},
     {'host', iolist_to_binary(HostName)} |
       lists:filtermap(fun format_metadata/1, MetaData)
    ].

format_metadata({_, undefined}) -> false;
format_metadata({K, V}) when is_integer(V) -> {true, {K, integer_to_binary(V)}};
format_metadata({K, V}) when is_atom(V)    -> {true, {K, atom_to_binary(V, utf8)}};
format_metadata({K, V}) ->
    {true,
        {K, try iolist_to_binary(V) catch
            _:_ -> unicode:characters_to_binary(lager_trunc_io:fprint(V, 1024))
        end}
    }.

binary_severity(debug) ->
    <<"debug">>;
binary_severity(info) ->
    <<"informational">>;
binary_severity(notice) ->
    <<"notice">>;
binary_severity(warning) ->
    <<"warning">>;
binary_severity(error) ->
    <<"error">>;
binary_severity(critical) ->
    <<"critical">>;
binary_severity(alert) ->
    <<"alert">>;
binary_severity(emergency) ->
    <<"emergency">>;
binary_severity(_) ->
    <<"debug">>.

get_host(undefined) ->
    {ok, HostName} = inet:gethostname(),
    HostName;
get_host(HostName) ->
    HostName.

getvalue(Tag, List, Default) ->
    case lists:keyfind(Tag, 1, List) of
        false ->
            Default;
        {Tag, Value} ->
            Value
    end.
getvalue(Tag, List) ->
    getvalue(Tag, List, undefined).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

get_value_test_() ->
    [
        ?_assertEqual(undefined, getvalue(test, [])),
        ?_assertEqual(undefined, getvalue(test, [{other, "test"}])),
        ?_assertEqual(ok, getvalue(test, [{other, "test"}], ok)),
        ?_assertEqual("test", getvalue(other, [{other, "test"}])),
        ?_assertEqual("test", getvalue(other, [{other, "test"}], "default"))
        ].

get_host_test_() ->
    [
        ?_assertEqual(localhost, get_host(localhost)),
        fun() ->
                    {ok, H} = inet:gethostname(),
                    ?assertEqual(H, get_host(undefined))
            end
        ].

binary_severity_test_() ->
    [
        ?_assertEqual(<<"debug">>, binary_severity(debug)),
        ?_assertEqual(<<"informational">>, binary_severity(info)),
        ?_assertEqual(<<"notice">>, binary_severity(notice)),
        ?_assertEqual(<<"warning">>, binary_severity(warning)),
        ?_assertEqual(<<"error">>, binary_severity(error)),
        ?_assertEqual(<<"critical">>, binary_severity(critical)),
        ?_assertEqual(<<"alert">>, binary_severity(alert)),
        ?_assertEqual(<<"emergency">>, binary_severity(emergency)),
        ?_assertEqual(<<"debug">>, binary_severity(unknown)),
        ?_assertEqual(<<"debug">>, binary_severity("unknown"))
        ].

get_raw_data_test() ->
    Now = os:timestamp(),
    MD = [{application, lager_graylog_backend}],
    Cfg = [{host, "localhost"},
           {inet_family, inet}],

    Message = lager_msg:new("a message", Now, info, MD, []),
    Data = get_raw_data(Message, Cfg),

    Expected = [{'@version', <<"1">>},
                {'@timestamp', utc_iso_datetime(Message)},
                {'severity', <<"informational">>},
                {'facility', <<"user-level">>},
                {'message', <<"a message">>},
                {'host', <<"localhost">>},
                {'application', <<"lager_graylog_backend">>}
               ],

    ?assertEqual(Expected, Data).

format_2_test() ->
    Now = os:timestamp(),
    MD = [{application, lager_graylog_backend}],
    Cfg = [{host, "localhost"},
           {inet_family, inet}],

    Message = lager_msg:new("a message", Now, info, MD, []),
    Data = format(Message, Cfg),

    Expected = jiffy:encode({[{'@version', <<"1">>},
                              {'@timestamp', utc_iso_datetime(Message)},
                              {'severity', <<"informational">>},
                              {'facility', <<"user-level">>},
                              {'message', <<"a message">>},
                              {'host', <<"localhost">>},
                              {'application', <<"lager_graylog_backend">>}
                              ]}),

    ?assertEqual(<<Expected/binary,"\n">>, Data).

format_3_test() ->
    Now = os:timestamp(),
    MD = [{application, lager_graylog_backend}, {module, ?MODULE}, {line, 42}, {pid, self()}],
    Cfg = [{host, "localhost"}],

    Message = lager_msg:new("a message", Now, info, MD, []),
    Data = format(Message, Cfg, []),

    Expected = jiffy:encode({[{'@version', <<"1">>},
                              {'@timestamp', utc_iso_datetime(Message)},
                              {'severity', <<"informational">>},
                              {'facility', <<"user-level">>},
                              {'message', <<"a message">>},
                              {'host', <<"localhost">>},
                              {'application', <<"lager_graylog_backend">>},
                              {'module', <<?MODULE_STRING>>},
                              {'line', <<"42">>},
                              {'pid', iolist_to_binary(pid_to_list(self()))}
                             ]}),

    ?assertEqual(<<Expected/binary,"\n">>, Data).

format_2_with_extra_fields_test() ->
    Now = os:timestamp(),
    MD = [{application, lager_graylog_backend}],
    Cfg = [{host, "localhost"},
           {inet_family, inet},
           {facility, "lager-test"},
           {extra_fields, [
               {'extra', <<"test">>}
        ]}],

    Message = lager_msg:new("a message", Now, info, MD, []),
    Data = format(Message, Cfg),

    Expected = jiffy:encode({[{'@version', <<"1">>},
                              {'@timestamp', utc_iso_datetime(Message)},
                              {'severity', <<"informational">>},
                              {'facility', <<"lager-test">>},
                              {'message', <<"a message">>},
                              {'host', <<"localhost">>},
                              {'application', <<"lager_graylog_backend">>},
                              {'extra', <<"test">>}
                             ]}),

    ?assertEqual(<<Expected/binary,"\n">>, Data).

-endif.
