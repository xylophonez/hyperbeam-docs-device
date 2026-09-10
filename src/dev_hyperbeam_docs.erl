%%% @doc Renderer device for HyperBEAM `/docs' documentation payloads.
%%%
%%% `dev_hyperbeam_docs_data' discovers and assembles documentation data. This
%%% device owns the renderer-facing contract, mounted through a request hook.
-module(dev_hyperbeam_docs).
-implements(<<"hyperbeam-docs@1.0">>).
-export([info/1, info/3]).
-export([request/3, route/3, index/3, node/3, device/3, spec/3, recipes/3]).

-define(DEFAULT_DEVICE, <<"message@1.0">>).

-spec info(#{ _ => _ }) -> #{ exports := [binary()] }.
info(_Opts) ->
    #{
        exports => [
            <<"info">>,
            <<"request">>,
            <<"route">>,
            <<"index">>,
            <<"node">>,
            <<"device">>,
            <<"spec">>,
            <<"recipes">>
        ]
    }.

%% @doc Return docs for the HyperBEAM docs renderer itself.
-spec info(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
info(_Base, Req, Opts) ->
    dev_hyperbeam_docs_data:device_info(<<"hyperbeam-docs@1.0">>, Req, Opts).

%% @doc Request-hook entrypoint for mounting `/docs' without changing core.
-spec request(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, map()}.
request(_Base, HookReq, Opts) ->
    Msgs = hb_maps:get(<<"body">>, HookReq, [], Opts),
    RawReq = hb_maps:get(<<"request">>, HookReq, #{}, Opts),
    Body =
        case docs_route(Msgs) of
            {node, Tail} ->
                docs_route_request(<<"node">>, <<>>, Tail, RawReq);
            {device, Device, Tail} ->
                docs_route_request(<<"device">>, Device, Tail, RawReq);
            false ->
                Msgs
        end,
    {ok, #{ <<"body">> => Body }}.

%% @doc Dispatch a docs route produced by the request hook.
-spec route(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
route(_Base, Req, Opts) ->
    RenderReq = render_request(Req, Opts),
    case hb_maps:get(<<"docs-kind">>, Req, <<"node">>, Opts) of
        <<"device">> ->
            dev_hyperbeam_docs_data:device_info_route(
                hb_maps:get(<<"docs-device">>, Req, ?DEFAULT_DEVICE, Opts),
                hb_maps:get(<<"docs-tail">>, Req, [], Opts),
                RenderReq,
                Opts
            );
        _ ->
            dev_hyperbeam_docs_data:node_info_route(
                hb_maps:get(<<"docs-tail">>, Req, [], Opts),
                RenderReq,
                Opts
            )
    end.

%% @doc Render the node documentation index.
-spec index(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
index(_Base, Req, Opts) ->
    {ok, dev_hyperbeam_docs_render:render(node, dev_hyperbeam_docs_data:node_info_data(Opts), Req)}.

%% @doc Alias for `index/3'.
-spec node(#{ _ => _ }, #{ _ => _ }, #{ _ => _ }) -> {ok, _} | {error, _}.
node(Base, Req, Opts) ->
    index(Base, Req, Opts).

%% @doc Render documentation for the device named in the `for' parameter.
-spec device(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
device(_Base, Req, Opts) ->
    dev_hyperbeam_docs_data:device_info(requested_device(Req, Opts), Req, Opts).

%% @doc Render spec for the device named in the `for' parameter.
-spec spec(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
spec(_Base, Req, Opts) ->
    dev_hyperbeam_docs_data:device_info_route(requested_device(Req, Opts), [<<"spec">>], Req, Opts).

%% @doc Render recipes for the device named in the `for' parameter.
-spec recipes(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
recipes(_Base, Req, Opts) ->
    dev_hyperbeam_docs_data:device_info_route(requested_device(Req, Opts), [<<"recipes">>], Req, Opts).

requested_device(Req, Opts) ->
    strip_device_prefix(
        hb_maps:get(
            <<"for">>,
            Req,
            hb_maps:get(<<"device-id">>, Req, ?DEFAULT_DEVICE, Opts),
            Opts
        )
    ).

strip_device_prefix(<<"~", Device/binary>>) ->
    Device;
strip_device_prefix(Device) ->
    Device.

render_request(Req, Opts) ->
    case hb_maps:get(<<"request">>, Req, #{}, Opts) of
        Request when is_map(Request) -> Request;
        _ -> Req
    end.

docs_route_request(Kind, Device, Tail, RawReq) ->
    [
        #{ <<"device">> => <<"hyperbeam-docs@1.0">> },
        #{
            <<"path">> => <<"route">>,
            <<"docs-kind">> => Kind,
            <<"docs-device">> => Device,
            <<"docs-tail">> => Tail,
            <<"request">> => RawReq
        }
    ].

docs_route([Base, Info | Tail]) when is_map(Base), is_map(Info) ->
    case {maps:is_key(<<"device">>, Base), docs_tail(path_key(Info), Tail)} of
        {false, {ok, RouteTail}} -> {node, RouteTail};
        _ -> false
    end;
docs_route([{as, Device, _Base}, Info | Tail]) when is_map(Info) ->
    case docs_tail(path_key(Info), Tail) of
        {ok, RouteTail} -> {device, Device, RouteTail};
        false -> false
    end;
docs_route(_) ->
    false.

docs_tail(<<"docs">>, Tail) ->
    {ok, path_tail_keys(Tail)};
docs_tail(_, _Tail) ->
    false.

path_key(Msg) ->
    hb_maps:get(<<"path">>, Msg, <<>>, #{}).

path_tail_key(Msg) when is_map(Msg) ->
    path_key(Msg);
path_tail_key(Msg) when is_binary(Msg) ->
    Msg;
path_tail_key(_) ->
    <<>>.

path_tail_keys(Tail) ->
    [Key || Msg <- Tail, (Key = path_tail_key(Msg)) =/= <<>>].

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%% @doc The docs device inherits its own schema and preserves non-docs requests.
schema_and_hook_test() ->
    Opts = #{ <<"store">> => hb_test_utils:test_store() },
    Base = #{ <<"device">> => <<"hyperbeam-docs@1.0">> },
    ?assertMatch(
        {ok, #{ <<"args">> := _, <<"return">> := _ }},
        hb_ao:resolve(Base, <<"schema/request/3">>, Opts)
    ),
    lists:foreach(
        fun(Key) ->
            Msgs = [{as, <<"json@1.0">>, #{}}, #{ <<"path">> => Key }],
            {ok, Result} = hb_ao:resolve(
                Base, #{ <<"path">> => <<"request">>, <<"body">> => Msgs }, Opts
            ),
            ?assertEqual(Msgs, hb_maps:get(<<"body">>, Result))
        end,
        [<<"info">>, <<"schema">>, <<"serialize">>]
    ).

%% @doc Exercise packaged docs, schema adaptation and assets over real HTTP.
http_docs_test_() ->
    {timeout, 60, fun() ->
        Wallet = ar_wallet:new(),
        Store = hb_test_utils:test_store(),
        {ok, SpecID} = hb_cache:write(
            #{ <<"body">> => <<"# JSON specification\n\nCanonical test spec.\n">> },
            #{ <<"store">> => Store }
        ),
        Opts = #{
            <<"priv-wallet">> => Wallet,
            <<"port">> => 0,
            <<"store">> => Store,
            <<"docs-name-resolvers">> => [#{ <<"json@1.0">> => SpecID }],
            <<"cache-control">> => [<<"no-cache">>, <<"no-store">>],
            <<"on">> => #{ <<"request">> => #{
                <<"device">> => <<"hyperbeam-docs@1.0">>,
                <<"path">> => <<"request">>
            }}
        },
        Node = hb_http_server:start_node(Opts),
        try
            {Headers, HTML} = test_get(Node, <<"docs">>, "text/html"),
            ?assertMatch({_, _}, binary:match(HTML, <<"<!doctype html>">>)),
            ?assert(lists:prefix("text/html", proplists:get_value("content-type", Headers))),
            {_, JSON} = test_get(Node, <<"~json@1.0/docs">>, "application/json"),
            Data = hb_json:decode(JSON),
            ?assertEqual(SpecID, maps:get(<<"txid">>, maps:get(<<"spec">>, Data))),
            ?assertMatch(
                #{ <<"status">> := <<"present">>, <<"extractor">> := <<"schema">> },
                maps:get(<<"schema-source">>, Data)
            ),
            ?assertMatch(
                #{ <<"type-schema">> := #{ <<"args">> := [_, _, _], <<"arity">> := 3 } },
                maps:get(<<"serialize">>, maps:get(<<"schema">>, Data))
            ),
            {_, Raw} = test_get(Node, <<"~json@1.0/schema/serialize/3">>, "application/json"),
            ?assert(byte_size(Raw) > 0),
            {_, CSS} = test_get(Node, <<"docs/assets/site.css">>, "text/css"),
            ?assert(byte_size(CSS) > 100)
        after
            cowboy:stop_listener(hb_util:human_id(ar_wallet:to_address(Wallet)))
        end
    end}.

%% @doc Fetch from a disposable HyperBEAM node without decoding its HTTP body.
test_get(Node, Path, Accept) ->
    {ok, {{_, 200, _}, Headers, Body}} = httpc:request(
        get,
        {binary_to_list(<<Node/binary, Path/binary>>), [{"accept", Accept}]},
        [{timeout, 10000}],
        [{body_format, binary}]
    ),
    {Headers, Body}.
-endif.
