%%% @doc Renderer device for HyperBEAM `/docs' documentation payloads.
%%%
%%% `dev_hyperbeam_docs_data' discovers and assembles documentation data. This
%%% device owns the renderer-facing contract. Nodes can reach it through a
%%% request hook with no core changes, or through `message@1.0/docs' if a core
%%% build exposes that key.
-module(dev_hyperbeam_docs).
-implements(<<"hyperbeam-docs@1.0">>).
-export([info/1, info/3]).
-export([request/3, route/3, index/3, node/3, device/3, schema/3, spec/3, recipes/3]).
-export([render/3, respond_html_or_json/4, unsupported_device_response/2]).
-export([renderer_metadata/0]).

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
            <<"schema">>,
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

%% @doc Dispatch a docs route produced by the request hook or `message@1.0/docs'.
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

%% @doc Render schema for the device named in the `for' parameter.
-spec schema(#{ _ => _ }, #{ 'for' => binary(), _ => _ }, #{ _ => _ }) ->
    {ok, _} | {error, _}.
schema(_Base, Req, Opts) ->
    dev_hyperbeam_docs_data:device_info_route(requested_device(Req, Opts), [<<"schema">>], Req, Opts).

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

%% @doc Render a docs payload for the caller's preferred response format.
-spec render(atom(), map(), map()) -> map().
render(Kind, Data, Req) ->
    dev_hyperbeam_docs_render:render(Kind, Data, Req).

-spec respond_html_or_json(atom(), map(), map(), map()) -> {ok, map()}.
respond_html_or_json(Kind, HtmlData, JsonData, Req) ->
    dev_hyperbeam_docs_render:respond_html_or_json(Kind, HtmlData, JsonData, Req).

-spec unsupported_device_response(binary(), map()) -> map().
unsupported_device_response(Device, Req) ->
    dev_hyperbeam_docs_render:unsupported_device_response(Device, Req).

-spec renderer_metadata() -> map().
renderer_metadata() ->
    dev_hyperbeam_docs_render:renderer_metadata().

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
-include_lib("hb/include/hb.hrl").

%% @doc Packaged BEAMs yield real types even without code-server object code.
archive_schema_test() ->
    Device = <<"message@1.0">>,
    Opts = schema_test_opts(Device),
    {ok, Module} = hb_device_load:reference(Device, Opts),
    ?assertEqual(error, code:get_object_code(Module)),
    Data = schema_test_json(Device, [], Opts),
    Source = maps:get(<<"schema-source">>, Data),
    ?assertEqual(<<"hb_device_load:schema/2">>, maps:get(<<"extractor">>, Source)),
    ?assert(maps:get(<<"typed-key-count">>, Source) > 0),
    ID = maps:get(<<"id">>, maps:get(<<"schema">>, Data)),
    Params = maps:get(<<"parameters">>, ID),
    ?assertMatch(
        #{ <<"required">> := false, <<"type">> := <<"binary">> },
        maps:get(<<"id-device">>, Params)
    ),
    ?assertMatch(
        #{ <<"kind">> := <<"tuple">>, <<"items">> := [_, #{ <<"kind">> := <<"binary">> }] },
        maps:get(<<"return">>, maps:get(<<"type-schema">>, ID))
    ).

%% @doc Required request fields and nested base fields survive normalization.
schema_fields_test() ->
    Device = <<"test-device@1.0">>,
    Opts = schema_test_opts(Device),
    Compute = schema_test_json(Device, [<<"schema">>, <<"compute">>], Opts),
    ?assertMatch(
        #{ <<"required">> := true, <<"type">> := <<"integer">> },
        maps:get(<<"slot">>, maps:get(<<"parameters">>, Compute))
    ),
    Projection = schema_test_json(Device, [<<"schema">>, <<"vary-projection">>], Opts),
    Base = maps:get(<<"base">>, maps:get(<<"type-schema">>, Projection)),
    Fields = maps:get(<<"keys">>, Base),
    ?assertMatch(#{ <<"presence">> := <<"optional">> }, maps:get(<<"optional">>, Fields)),
    Deep = maps:get(<<"type">>, maps:get(<<"deep">>, Fields)),
    ?assertMatch(
        #{ <<"type">> := #{ <<"kind">> := <<"integer">> } },
        maps:get(<<"slot">>, maps:get(<<"keys">>, Deep))
    ).

%% @doc A private catch-all handler's request is its third argument.
handler_schema_test() ->
    Device = <<"name@1.0">>,
    Schema = schema_test_json(Device, [<<"schema">>, <<"resolve">>], schema_test_opts(Device)),
    ?assertEqual(
        [<<"key">>, <<"base">>, <<"request">>, <<"opts">>],
        [maps:get(<<"name">>, Argument) || Argument <- maps:get(<<"arguments">>, Schema)]
    ),
    ?assertMatch(
        #{ <<"required">> := false, <<"type-schema">> := #{ <<"kind">> := <<"union">> } },
        maps:get(<<"load">>, maps:get(<<"parameters">>, Schema))
    ).

%% @doc Excluded helpers and metadata info/1 must not replace public info/3.
public_schema_test() ->
    Device = <<"router@1.0">>,
    Schema = schema_test_json(Device, [<<"schema">>], schema_test_opts(Device)),
    ?assertNot(maps:is_key(<<"field-distance">>, Schema)),
    ?assertEqual(
        3,
        maps:get(<<"arity">>, maps:get(<<"type-schema">>, maps:get(<<"info">>, Schema)))
    ).

%% @doc An export without a spec is visible without a fabricated return type.
untyped_schema_test() ->
    Device = <<"test-device@1.0">>,
    Schema = schema_test_json(
        Device, [<<"schema">>, <<"vary-unspecified">>], schema_test_opts(Device)
    ),
    ?assertEqual(<<"unavailable">>, maps:get(<<"schema-status">>, Schema)),
    ?assertEqual(<<"not declared">>, maps:get(<<"returns">>, Schema)),
    ?assertNot(maps:is_key(<<"type-schema">>, Schema)).

%% @doc The rendered docs expose types in the index, key, and parameter views.
schema_html_test() ->
    Device = <<"test-device@1.0">>,
    Opts = schema_test_opts(Device),
    Index = schema_test_request(Device, [<<"schema">>], <<"text/html">>, Opts),
    ?assertNotEqual(nomatch, binary:match(Index, <<"<th>Returns</th>">>)),
    Page = schema_test_request(Device, [<<"schema">>, <<"compute">>], <<"text/html">>, Opts),
    [?assertNotEqual(nomatch, binary:match(Page, Text)) || Text <- [
        <<"<h2>Arguments</h2>">>, <<"<h2>Returns</h2>">>,
        <<"Full extracted schema">>, <<"integer">>, <<"required">>
    ]],
    Param = schema_test_request(
        Device, [<<"schema">>, <<"compute">>, <<"slot">>], <<"text/html">>, Opts
    ),
    ?assertNotEqual(nomatch, binary:match(Param, <<"integer">>)).

%% @doc Resolve a fixture's spec through the same preload index as the launcher.
schema_test_opts(Device) ->
    Store = hb_opts:get(preloaded_store, undefined, #{}),
    {ok, SpecID} = hb_store:read(Store, [?PRELOADED_INDEX_KEY, Device], #{}),
    #{
        <<"name-resolvers">> => [#{ Device => SpecID }],
        <<"cache-control">> => [<<"no-cache">>, <<"no-store">>]
    }.

%% @doc Decode the docs contract returned through an AO-Core resolution.
schema_test_json(Device, Tail, Opts) ->
    hb_json:decode(schema_test_request(Device, Tail, <<"application/json">>, Opts)).

%% @doc Exercise the packaged renderer rather than calling its modules directly.
schema_test_request(Device, Tail, Accept, Opts) ->
    {ok, Response} = hb_ao:resolve(
        #{ <<"device">> => <<"hyperbeam-docs@1.0">> },
        #{
            <<"path">> => <<"route">>,
            <<"docs-kind">> => <<"device">>,
            <<"docs-device">> => Device,
            <<"docs-tail">> => Tail,
            <<"request">> => #{ <<"accept">> => Accept }
        },
        Opts
    ),
    ?assertEqual(200, hb_maps:get(<<"status">>, Response, undefined, Opts)),
    hb_maps:get(<<"body">>, Response, undefined, Opts).
-endif.
