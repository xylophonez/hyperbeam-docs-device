%%% @doc Protocol-native documentation payloads for HyperBEAM.
-module(dev_hyperbeam_docs_data).
-export([
    node_info/2,
    node_info_route/3,
    device_info/3,
    device_info_route/4
]).
-export([node_info_data/1, device_info_data/2]).
-export([
    render_node_html/1,
    render_device_html/1,
    render_schema_index_html/1,
    render_schema_key_html/1,
    render_schema_parameter_html/1,
    render_spec_html/1,
    render_spec_section_page_html/1,
    render_recipes_html/1,
    render_recipe_html/1,
    render_implementations_html/1,
    render_node_component_html/3,
    render_node_boilerplate_html/1,
    render_node_boilerplate_page_html/1,
    render_node_concepts_html/1,
    render_node_concept_html/1,
    render_unsupported_device_html/1,
    supported_device/1
]).

-include_lib("hb/include/hb.hrl").


-define(ARWEAVE_DEVICE, <<"arweave@2.9">>).
-define(MESSAGE_DEVICE, <<"message@1.0">>).
-define(CARD_SUMMARY_MAX, 120).
-define(RECIPE_CARD_SUMMARY_MAX, 80).

supported_device(Device) ->
    supported_device(Device, #{}).

supported_device(Device, Opts) ->
    case docs_resolve_spec(Device, Opts) of
        {ok, _SpecID} -> true;
        _ -> false
    end.

node_info(Req, Opts) ->
    Data = node_info_data(Opts),
    {ok, dev_hyperbeam_docs_render:render(node, Data, Req)}.

device_info(Device, Req, Opts) ->
    case supported_device(Device, Opts) of
        true ->
            Data = device_info_data(Device, Opts),
            {ok, dev_hyperbeam_docs_render:render(device, Data, Req)};
        false ->
            {ok, unsupported_device_info_response(Device, Req)}
    end.

node_info_route([], Req, Opts) ->
    node_info(Req, Opts);
node_info_route([<<"assets">> | AssetPath], _Req, _Opts) ->
    docs_asset_response(AssetPath);
node_info_route([<<"schema">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-schema-index">>, <<"schema">>, Data),
    respond_html_or_json(node_schema, Payload, Payload, Req);
node_info_route([<<"spec">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-spec-index">>, <<"spec">>, Data),
    respond_html_or_json(node_spec, Payload, Payload, Req);
node_info_route([<<"recipes">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-recipes-index">>, <<"recipes">>, Data),
    respond_html_or_json(node_recipes, Payload, Payload, Req);
node_info_route([<<"implementations">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = node_component_index(<<"node-implementations-index">>, <<"implementations">>, Data),
    respond_html_or_json(node_implementations, Payload, Payload, Req);
node_info_route([<<"guides">>], Req, _Opts) ->
    Payload = boilerplate_index(),
    respond_html_or_json(node_boilerplate, Payload, Payload, Req);
node_info_route([<<"introduction">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"introduction">> | Parts], Req);
node_info_route([<<"forge">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"forge">> | Parts], Req);
node_info_route([<<"processes">> | Parts], Req, _Opts) ->
    boilerplate_page_response([<<"processes">> | Parts], Req);
node_info_route([<<"boilerplate">> | _Parts], _Req, _Opts) ->
    {ok, not_found_response()};
node_info_route([<<"concepts">>], Req, Opts) ->
    Data = node_info_data(Opts),
    Payload = #{
        <<"kind">> => <<"node-concepts-index">>,
        <<"concepts">> => maps:get(<<"concepts">>, Data, #{})
    },
    respond_html_or_json(node_concepts, Payload, Payload, Req);
node_info_route([<<"concepts">>, Concept], Req, Opts) ->
    Data = node_info_data(Opts),
    Concepts = maps:get(<<"concepts">>, Data, #{}),
    case maps:get(Concept, Concepts, undefined) of
        undefined -> {ok, not_found_response()};
        Description ->
            Payload = #{
                <<"kind">> => <<"node-concept">>,
                <<"concept">> => Concept,
                <<"description">> => Description
            },
            respond_html_or_json(node_concept, Payload, Payload, Req)
    end;
node_info_route(_Tail, _Req, _Opts) ->
    {ok, not_found_response()}.

boilerplate_page_response(Parts, Req) ->
    case boilerplate_page_payload(Parts) of
        {ok, Payload} ->
            respond_html_or_json(node_boilerplate_page, Payload, Payload, Req);
        not_found ->
            {ok, not_found_response()}
    end.

device_info_route(Device, Tail, Req, Opts) ->
    case supported_device(Device, Opts) of
        true -> supported_device_info_route(Device, Tail, Req, Opts);
        false -> {ok, unsupported_device_info_response(Device, Req)}
    end.

supported_device_info_route(Device, [], Req, Opts) ->
    device_info(Device, Req, Opts);
supported_device_info_route(_Device, [<<"assets">> | AssetPath], _Req, _Opts) ->
    docs_asset_response(AssetPath);
supported_device_info_route(Device, [<<"schema">>], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Schema = maps:get(<<"schema">>, Data, #{}),
    respond_html_or_json(schema_index, Data, Schema, Req);
supported_device_info_route(Device, [<<"schema">>, Key], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Schema = maps:get(<<"schema">>, Data, #{}),
    case maps:get(Key, Schema, undefined) of
        undefined -> {ok, not_found_response()};
        KeySchema ->
            Payload = #{
                <<"device">> => maps:get(<<"device">>, Data, #{}),
                <<"device-data">> => Data,
                <<"key">> => Key,
                <<"schema">> => KeySchema
            },
            respond_html_or_json(schema_key, Payload, KeySchema, Req)
    end;
supported_device_info_route(Device, [<<"schema">>, Key, Param], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Schema = maps:get(<<"schema">>, Data, #{}),
    case maps:get(Key, Schema, undefined) of
        undefined ->
            {ok, not_found_response()};
        KeySchema ->
            Params = maps:get(<<"parameters">>, KeySchema, #{}),
            case maps:get(Param, Params, undefined) of
                undefined ->
                    {ok, not_found_response()};
                ParamSchema ->
                    Payload = #{
                        <<"device">> => maps:get(<<"device">>, Data, #{}),
                        <<"device-data">> => Data,
                        <<"key">> => Key,
                        <<"parameter">> => Param,
                        <<"schema">> => ParamSchema
                    },
                    respond_html_or_json(schema_parameter, Payload, ParamSchema, Req)
            end
    end;
supported_device_info_route(Device, [<<"spec">>], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Spec = maps:get(<<"spec">>, Data, #{}),
    respond_html_or_json(spec, Data, Spec, Req);
supported_device_info_route(Device, [<<"spec">>, SectionSlug], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Spec = maps:get(<<"spec">>, Data, #{}),
    case spec_section_lookup(Spec, SectionSlug) of
        undefined ->
            {ok, not_found_response()};
        {SectionSlug, Title} ->
            Payload = #{
                <<"device">> => maps:get(<<"device">>, Data, #{}),
                <<"device-data">> => Data,
                <<"section-id">> => SectionSlug,
                <<"section-title">> => Title,
                <<"spec">> => Spec
            },
            respond_html_or_json(spec_section, Payload, Payload, Req)
    end;
supported_device_info_route(Device, [<<"recipes">>], Req, Opts) ->
    Data = device_recipes_data(Device, Opts),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    respond_html_or_json(recipes, Data, Recipes, Req);
supported_device_info_route(Device, [<<"recipes">>, Slug], Req, Opts) ->
    Data = device_recipes_data(Device, Opts),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    case maps:get(Slug, Recipes, undefined) of
        undefined -> {ok, not_found_response()};
        Recipe ->
            Payload = #{
                <<"device">> => maps:get(<<"device">>, Data, #{}),
                <<"device-data">> => Data,
                <<"recipe">> => Recipe,
                <<"slug">> => Slug
            },
            respond_html_or_json(recipe, Payload, Recipe, Req)
    end;
supported_device_info_route(Device, [<<"implementations">>], Req, Opts) ->
    Data = device_info_data(Device, Opts),
    Implementations = maps:get(<<"implementations">>, Data, []),
    respond_html_or_json(implementations, Data, Implementations, Req);
supported_device_info_route(_Device, _Tail, _Req, _Opts) ->
    {ok, not_found_response()}.

respond_html_or_json(Kind, HtmlData, JsonData, Req) ->
    dev_hyperbeam_docs_render:respond_html_or_json(Kind, HtmlData, JsonData, Req).

not_found_response() ->
    #{
        <<"status">> => 404,
        <<"content-type">> => <<"application/json">>,
        <<"body">> => <<"{\"error\":\"not found\"}">>
    }.

unsupported_device_info_response(Device, Req) ->
    dev_hyperbeam_docs_render:unsupported_device_response(Device, Req).

docs_node_device(DeviceID, Name, Version, Summary) ->
    #{
        <<"name">> => Name,
        <<"version">> => Version,
        <<"href">> => device_info_path(DeviceID),
        <<"summary">> => Summary,
        <<"schema">> => device_schema_path(DeviceID),
        <<"spec">> => device_spec_path(DeviceID),
        <<"recipes">> => device_recipes_path(DeviceID)
    }.

node_device_shortcut_links() ->
    #{}.

node_info_data(Opts) ->
    maps:merge(node_device_shortcut_links(), #{
        <<"kind">> => <<"node-info">>,
        <<"node">> => node_href(Opts),
        <<"summary">> =>
            <<"HyperBEAM documentation for the spec-loaded devices this node "
                "can resolve and run.">>,
        <<"renderer">> => docs_renderer(),
        <<"boilerplate-link">> => <<"/docs/guides">>,
        <<"devices">> => on_weave_node_devices(Opts),
        <<"boilerplate">> => boilerplate_index(),
        <<"concepts">> => #{
            <<"hyperbeam">> =>
                <<"A node runtime for AO-Core messages, devices, and "
                    "path-addressed computation.">>,
            <<"ao-core">> =>
                <<"The message execution model where each path segment applies "
                    "a request message to a base message.">>,
            <<"devices">> =>
                <<"Versioned interpreters that expose computable keys over "
                    "messages.">>,
            <<"messages">> =>
                <<"Typed key/value structures that carry data, commitments, "
                    "device names, and execution history.">>
        }
    }).

device_info_data(Device, Opts) ->
    case docs_resolve_spec(Device, Opts) of
        {ok, SpecID} ->
            on_weave_info_data(Device, SpecID, Opts);
        _ ->
            unsupported_device_info_data(Device)
    end.

device_recipes_data(Device, Opts) ->
    {Name, Version} = split_device_id(Device),
    SpecID =
        case docs_resolve_spec(Device, Opts) of
            {ok, ResolvedSpecID} -> ResolvedSpecID;
            _ -> <<>>
        end,
    Recipes = device_recipe_docs(Device, SpecID, <<>>, Opts),
    maps:merge(device_doc_link_fields(Device), #{
        <<"kind">> => <<"device-info">>,
        <<"device">> => #{
            <<"name">> => Name,
            <<"version">> => Version,
            <<"id">> => Device,
            <<"spec-id">> => SpecID
        },
        <<"device-id">> => Device,
        <<"device-name">> => Name,
        <<"device-version">> => Version,
        <<"renderer">> => docs_renderer(),
        <<"schema">> => #{},
        <<"schema-order">> => [],
        <<"spec">> => #{},
        <<"recipes">> => Recipes,
        <<"recipe-count">> => map_size(Recipes)
    }).

unsupported_device_info_data(Device) ->
    #{
        <<"kind">> => <<"device-info">>,
        <<"device">> => #{ <<"id">> => Device },
        <<"device-id">> => Device,
        <<"status">> => <<"not-implemented">>,
        <<"docs-status">> => <<"not-documented">>,
        <<"summary">> =>
            <<"No on-weave spec-loaded documentation is available for this device.">>
    }.

device_summary(#{ <<"spec-status">> := <<"missing">>, <<"summary">> := Summary }) ->
    Summary;
device_summary(_Spec) ->
    <<>>.

on_weave_node_devices(Opts) ->
    NameResolvers =
        hb_opts:get(
            <<"docs-name-resolvers">>,
            hb_opts:get(<<"name-resolvers">>, [], Opts),
            Opts
        ),
    Pairs0 =
        lists:flatmap(
            fun(Resolver) when is_map(Resolver) -> maps:to_list(Resolver);
               (_Resolver) -> []
            end,
            NameResolvers
        ),
    Pairs =
        lists:usort(
            [
                {DeviceID, SpecID}
            || {DeviceID, SpecID} <- Pairs0,
                is_binary(DeviceID),
                is_binary(SpecID),
                ?IS_ID(SpecID)
            ]
        ),
    [
        on_weave_node_device(DeviceID, SpecID)
    || {DeviceID, SpecID} <- Pairs
    ].

on_weave_node_device(DeviceID, SpecID) ->
    {Name, Version} = split_device_id(DeviceID),
    docs_node_device(
        DeviceID,
        Name,
        Version,
        <<"On-weave device docs discovered from spec ID ", SpecID/binary, ".">>
    ).

on_weave_info_data(Device, SpecID, Opts) ->
    Spec = on_weave_spec_status(Device, SpecID, Opts),
    SpecSigner = maps:get(<<"signer">>, Spec, <<>>),
    SpecSource = maps:get(<<"source">>, Spec, <<"on-weave">>),
    {Schema, SchemaOrder, SchemaSource} =
        docs_schema_for_device(Device, SpecID, Opts),
    Recipes = device_recipe_docs_for_source(
        SpecSource,
        Device,
        SpecID,
        SpecSigner,
        Opts
    ),
    Implementations = implementations_for_source(SpecSource, SpecID, Opts),
    {Name, Version} = split_device_id(Device),
    maps:merge(device_doc_link_fields(Device), #{
        <<"kind">> => <<"device-info">>,
        <<"device">> => #{
            <<"name">> => Name,
            <<"version">> => Version,
            <<"id">> => Device,
            <<"spec-id">> => SpecID
        },
        <<"device-id">> => Device,
        <<"device-name">> => Name,
        <<"device-version">> => Version,
        <<"summary">> => device_summary(Spec),
        <<"renderer">> => docs_renderer(),
        <<"keys">> => on_weave_key_summaries(Device, Schema, SchemaOrder),
        <<"schema">> => Schema,
        <<"schema-order">> => SchemaOrder,
        <<"schema-source">> => SchemaSource,
        <<"spec">> => Spec,
        <<"recipes">> => Recipes,
        <<"recipe-count">> => map_size(Recipes),
        <<"implementations">> => Implementations,
        <<"coverage">> => #{
            <<"spec">> => SpecID,
            <<"schema">> => maps:get(<<"mode">>, SchemaSource, <<"unknown">>),
            <<"schema-status">> => maps:get(<<"status">>, SchemaSource, <<"unknown">>),
            <<"schema-source">> => maps:get(<<"mode">>, SchemaSource, <<"unknown">>),
            <<"recipes">> => recipe_coverage_source(SpecSource),
            <<"source">> => SpecSource
        },
        <<"dependencies">> => [],
        <<"docs-source">> => #{
            <<"mode">> => docs_source_mode(SpecSource),
            <<"spec-id">> => SpecID,
            <<"spec-signer">> => SpecSigner,
            <<"schema-source">> => SchemaSource,
            <<"schema-display-rule">> =>
                <<"implementation-derived schema from the loaded device; "
                    "Device-Schema artifacts are ignored">>,
            <<"recipe-display-rule">> =>
                <<"Device-Recipe messages tagged recipe-for-device, any owner">>
        },
        <<"spec-status">> => maps:get(<<"spec-status">>, Spec, <<"missing">>)
    }).

device_recipe_docs_for_source(<<"on-weave">>, Device, SpecID, SpecSigner, Opts) ->
    device_recipe_docs(Device, SpecID, SpecSigner, Opts);
device_recipe_docs_for_source(_Source, _Device, _SpecID, _SpecSigner, _Opts) ->
    #{}.

implementations_for_source(<<"on-weave">>, SpecID, Opts) ->
    on_weave_implementations(SpecID, Opts);
implementations_for_source(_Source, _SpecID, _Opts) ->
    [].

recipe_coverage_source(<<"on-weave">>) ->
    <<"recipe-for-device graph query">>;
recipe_coverage_source(_Source) ->
    <<"skipped-for-local-spec">>.

docs_source_mode(<<"on-weave">>) ->
    <<"on-weave-by-spec-id">>;
docs_source_mode(Source) ->
    <<Source/binary, "-by-spec-id">>.

split_device_id(DeviceID) ->
    case binary:split(DeviceID, <<"@">>) of
        [Name, Version] when Name =/= <<>>, Version =/= <<>> ->
            {Name, Version};
        _ ->
            {DeviceID, <<>>}
    end.

docs_resolve_spec(Ref, _Opts) when ?IS_ID(Ref) ->
    {ok, Ref};
docs_resolve_spec(Ref, Opts) ->
    case
        hb_ao:raw(
            #{ <<"device">> => <<"name@1.0">> },
            #{ <<"path">> => Ref, <<"load">> => false },
            Opts
        )
    of
        {ok, SpecID} when ?IS_ID(SpecID) -> {ok, SpecID};
        _ -> {error, <<"device-name-not-resolvable">>}
    end.

on_weave_spec_status(Device, SpecID, Opts) ->
    case on_weave_spec_markdown(SpecID, Opts) of
        {ok, Source, Markdown} ->
            Metadata = spec_metadata_for_source(Source, SpecID, Opts),
            maps:merge(on_weave_spec_metadata(Metadata, SpecID, Opts), #{
                <<"kind">> => <<"device-spec">>,
                <<"href">> => <<"/~", Device/binary, "/docs/spec">>,
                <<"spec-status">> => <<"present">>,
                <<"coverage-status">> => <<"present">>,
                <<"source-path">> => <<>>,
                <<"source">> => Source,
                <<"txid">> => SpecID,
                <<"title">> => markdown_title(Markdown, Device),
                <<"summary">> => markdown_summary(Markdown),
                <<"markdown-bytes">> => byte_size(Markdown),
                <<"markdown">> => Markdown
            });
        {error, Reason} ->
            missing_on_weave_spec(
                Device,
                SpecID,
                {markdown, Reason}
            )
    end.

spec_metadata_for_source(<<"on-weave">>, SpecID, Opts) ->
    on_weave_item_by_id(SpecID, Opts);
spec_metadata_for_source(Source, _SpecID, _Opts) ->
    {local, Source}.

on_weave_spec_metadata({ok, Node}, _SpecID, Opts) ->
    (doc_item_metadata(Node, Opts))#{
        <<"metadata-status">> => <<"present">>
    };
on_weave_spec_metadata({local, Source}, SpecID, _Opts) ->
    #{
        <<"txid">> => SpecID,
        <<"signer">> => <<>>,
        <<"block-height">> => <<>>,
        <<"block-timestamp">> => <<>>,
        <<"metadata-status">> => <<"local">>,
        <<"metadata-source">> => Source
    };
on_weave_spec_metadata({error, Reason}, SpecID, _Opts) ->
    #{
        <<"txid">> => SpecID,
        <<"signer">> => <<>>,
        <<"block-height">> => <<>>,
        <<"block-timestamp">> => <<>>,
        <<"metadata-status">> => <<"missing">>,
        <<"metadata-error">> => format_reason(Reason)
    }.

missing_on_weave_spec(Device, SpecID, Reason) ->
            #{
                <<"kind">> => <<"device-spec">>,
                <<"href">> => <<"/~", Device/binary, "/docs/spec">>,
                <<"spec-status">> => <<"missing">>,
                <<"coverage-status">> => <<"missing">>,
                <<"source-path">> => <<>>,
                <<"source">> => <<"on-weave">>,
                <<"txid">> => SpecID,
                <<"summary">> => <<"The on-weave Device-Specification could not be loaded.">>,
                <<"reason">> => format_reason(Reason)
            }.

on_weave_spec_markdown(SpecID, Opts) ->
    case preloaded_spec_markdown(SpecID, Opts) of
        {ok, Markdown} ->
            {ok, <<"preloaded-store">>, Markdown};
        {error, PreloadedReason} ->
            case cached_spec_markdown(SpecID, Opts) of
                {ok, Markdown} ->
                    {ok, <<"cache">>, Markdown};
                {error, CacheReason} ->
                    case gateway_spec_markdown(SpecID, Opts) of
                        {ok, Markdown} ->
                            {ok, <<"on-weave">>, Markdown};
                        {error, GatewayReason} ->
                            {error, {PreloadedReason, CacheReason, GatewayReason}}
                    end
            end
    end.

cached_spec_markdown(SpecID, Opts) ->
    case hb_cache:read(SpecID, Opts) of
        {ok, Item} -> cached_spec_body(Item, Opts);
        {error, Reason} -> {error, {cache_read_failed, Reason}};
        Other -> {error, {cache_read_unexpected, Other}}
    end.

preloaded_spec_markdown(SpecID, Opts) ->
    NodeOpts = maps:without([<<"cache-control">>, <<"only">>, <<"prefer">>], Opts),
    case hb_opts:get(preloaded_store, undefined, NodeOpts) of
        undefined ->
            {error, preloaded_store_missing};
        Store ->
            PreOpts = NodeOpts#{
                <<"store">> => [Store],
                <<"cache-read-mode">> => raw
            },
            case hb_cache:read(SpecID, PreOpts) of
                {ok, Item} -> cached_spec_body(Item, PreOpts);
                {error, Reason} -> {error, {preloaded_cache_read_failed, Reason}};
                Other -> {error, {preloaded_cache_read_unexpected, Other}}
            end
    end.

cached_spec_body(Item, Opts) ->
    case cached_item_body_markdown(Item, Opts) of
        {ok, Markdown} ->
            {ok, Markdown};
        {error, BodyReason} ->
            case raw_ans104_body(Item) of
                {ok, Markdown} -> {ok, Markdown};
                {error, RawReason} ->
                    case safe_structured_ans104_body(Item, Opts) of
                        {ok, Markdown} -> {ok, Markdown};
                        {error, StructuredReason} ->
                            {error,
                                {cache_spec_body_unavailable,
                                    BodyReason,
                                    RawReason,
                                    StructuredReason
                                }}
                    end
            end
    end.

cached_item_body_markdown(Item, Opts) when is_map(Item) ->
    case maps:get(<<"body">>, Item, undefined) of
        undefined ->
            {error, cache_body_missing};
        Body ->
            load_markdown_body(Body, Opts)
    end;
cached_item_body_markdown(_Item, _Opts) ->
    {error, cache_item_not_map}.

load_markdown_body(Body, Opts) ->
    case find_markdown_body(Body) of
        {ok, Markdown} ->
            {ok, Markdown};
        error ->
            case direct_text_body(Body) of
                {ok, Markdown} ->
                    {ok, Markdown};
                error ->
                    case linked_body_value(Body, Opts) of
                        {ok, Loaded} ->
                            loaded_markdown_body(Loaded);
                        error ->
                            try hb_cache:ensure_loaded(Body, Opts) of
                                Loaded ->
                                    loaded_markdown_body(Loaded)
                            catch
                                Class:Reason ->
                                    {error, {cache_body_load_failed, Class, Reason}}
                            end
                    end
            end
    end.

linked_body_value({link, ID, LinkOpts}, Opts) when is_binary(ID), is_map(LinkOpts) ->
    ReadOpts =
        (maps:merge(Opts, maps:without([<<"lazy">>], LinkOpts)))#{
            <<"cache-read-mode">> => raw
        },
    case hb_cache:read(ID, ReadOpts) of
        {ok, Loaded} -> {ok, Loaded};
        _Other -> error
    end;
linked_body_value(_Body, _Opts) ->
    error.

loaded_markdown_body(Loaded) ->
    case find_markdown_body(Loaded) of
        {ok, Markdown} ->
            {ok, Markdown};
        error ->
            case direct_text_body(Loaded) of
                {ok, Markdown} -> {ok, Markdown};
                error -> {error, cache_body_not_markdown}
            end
    end.

direct_text_body(Bin) when is_binary(Bin), byte_size(Bin) > 0 ->
    case text_payload(Bin) of
        true -> {ok, Bin};
        false -> error
    end;
direct_text_body(_Other) ->
    error.

safe_structured_ans104_body(Item, Opts) ->
    try structured_ans104_body(Item, Opts) of
        Result -> Result
    catch
        Class:Reason -> {error, {Class, Reason}}
    end.

gateway_spec_markdown(SpecID, Opts) ->
    case hb_client_gateway:data(SpecID, Opts) of
        {ok, Markdown} when is_binary(Markdown) ->
            case text_payload(Markdown) of
                true -> {ok, Markdown};
                false -> recover_spec_body(Markdown, SpecID, Opts)
            end;
        {ok, Other} ->
            case gateway_item_data(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, Reason} -> {error, {non_binary_spec_body, Other, Reason}}
            end;
        {error, Reason} ->
            case gateway_item_data(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, FallbackReason} -> {error, {Reason, FallbackReason}}
            end
    end.

text_payload(Bin) ->
    binary:match(Bin, <<0>>) =:= nomatch.

recover_spec_body(Raw, SpecID, Opts) ->
    case ans104_body(Raw, Opts) of
        {ok, Markdown} -> {ok, Markdown};
        {error, DecodeReason} ->
            case gateway_item_data(SpecID, Opts) of
                {ok, Markdown} -> {ok, Markdown};
                {error, GatewayReason} -> {error, {DecodeReason, GatewayReason}}
            end
    end.

ans104_body(Raw, Opts) ->
    try
        Item = ar_bundles:deserialize(Raw),
        case structured_ans104_body(Item, Opts) of
            {ok, Body} -> {ok, Body};
            {error, StructuredReason} ->
                case raw_ans104_body(Item) of
                    {ok, Body} -> {ok, Body};
                    {error, RawReason} -> {error, {StructuredReason, RawReason}}
                end
        end
    catch
        Class:Reason:Stack ->
            {error, {Class, Reason, Stack}}
    end.

structured_ans104_body(Item, Opts) ->
    Msg = hb_message:convert(
        Item,
        <<"structured@1.0">>,
        <<"ans104@1.0">>,
        Opts
    ),
    case hb_maps:get(<<"body">>, Msg, not_found, Opts) of
        Body when is_binary(Body), byte_size(Body) > 0 ->
            case text_payload(Body) of
                true -> {ok, Body};
                false -> {error, non_text_ans104_body}
            end;
        Other ->
            {error, {missing_or_empty_ans104_body, Other}}
    end.

raw_ans104_body(Item) ->
    case find_markdown_body(Item) of
        {ok, Body} -> {ok, Body};
        error -> {error, unsupported_ans104_shape}
    end.

find_markdown_body(Term) ->
    find_markdown_body(Term, 0).

find_markdown_body(_Term, Depth) when Depth > 12 ->
    error;
find_markdown_body(#tx{data = Data}, Depth) ->
    find_markdown_body(Data, Depth + 1);
find_markdown_body(Bin, Depth) when is_binary(Bin), byte_size(Bin) > 0 ->
    case markdown_payload(Bin) of
        true -> {ok, Bin};
        false ->
            case embedded_markdown_body(Bin) of
                {ok, _} = Found -> Found;
                error -> nested_ans104_body(Bin, Depth + 1)
            end
    end;
find_markdown_body(Map, Depth) when is_map(Map) ->
    case maps:get(<<"body">>, Map, undefined) of
        undefined ->
            find_markdown_body_in_list(maps:values(Map), Depth + 1);
        Body ->
            case find_markdown_body(Body, Depth + 1) of
                {ok, _} = Found -> Found;
                error ->
                    find_markdown_body_in_list(
                        maps:values(maps:remove(<<"body">>, Map)),
                        Depth + 1
                    )
            end
    end;
find_markdown_body(List, Depth) when is_list(List) ->
    find_markdown_body_in_list(List, Depth + 1);
find_markdown_body(Tuple, Depth) when is_tuple(Tuple) ->
    find_markdown_body_in_list(tuple_to_list(Tuple), Depth + 1);
find_markdown_body(_Other, _Depth) ->
    error.

nested_ans104_body(Bin, Depth) ->
    try ar_bundles:deserialize(Bin) of
        Bin -> error;
        Nested -> find_markdown_body(Nested, Depth)
    catch
        _Class:_Reason -> error
    end.

embedded_markdown_body(Bin) ->
    case embedded_markdown_start(Bin) of
        {ok, Pos} ->
            Candidate0 = binary:part(Bin, Pos, byte_size(Bin) - Pos),
            Candidate = binary_before_nul(Candidate0),
            case markdown_payload(Candidate) of
                true -> {ok, Candidate};
                false -> error
            end;
        error ->
            error
    end.

embedded_markdown_start(Bin) ->
    case binary:match(Bin, <<"# `">>) of
        {Pos, _Len} -> {ok, Pos};
        nomatch ->
            case binary:match(Bin, <<"# ">>) of
                {Pos, _Len} -> {ok, Pos};
                nomatch -> error
            end
    end.

binary_before_nul(Bin) ->
    case binary:match(Bin, <<0>>) of
        {Pos, _Len} -> binary:part(Bin, 0, Pos);
        nomatch -> Bin
    end.

find_markdown_body_in_list([], _Depth) ->
    error;
find_markdown_body_in_list([Term | Rest], Depth) ->
    case find_markdown_body(Term, Depth) of
        {ok, _} = Found -> Found;
        error -> find_markdown_body_in_list(Rest, Depth)
    end.

markdown_payload(Bin) ->
    text_payload(Bin) andalso markdown_prefix(skip_ascii_ws(Bin)).

skip_ascii_ws(<<C, Rest/binary>>) when C =:= 9; C =:= 10; C =:= 13; C =:= 32 ->
    skip_ascii_ws(Rest);
skip_ascii_ws(Bin) ->
    Bin.

markdown_prefix(<<"#", _/binary>>) ->
    true;
markdown_prefix(_Bin) ->
    false.

gateway_item_data(ID, Opts) ->
    Req = #{
        <<"multirequest-accept-status">> => 200,
        <<"multirequest-responses">> => 1,
        <<"path">> => <<"/arweave/", ID/binary>>,
        <<"method">> => <<"GET">>
    },
    case hb_http:request(Req, Opts) of
        {ok, Data} when is_binary(Data) ->
            {ok, Data};
        {ok, Res} ->
            gateway_item_response_body(ID, Res, Opts);
        {error, Reason} ->
            {error, Reason}
    end.

gateway_item_response_body(ID, Res, Opts) when is_map(Res) ->
    Data =
        case hb_maps:find(<<"data">>, Res, Opts) of
            {ok, D} -> D;
            _ -> hb_ao:get(<<"body">>, Res, <<>>, Opts)
        end,
    case Data of
        Bin when is_binary(Bin) -> {ok, Bin};
        Other -> {error, {non_binary_gateway_body, ID, Other}}
    end;
gateway_item_response_body(ID, Other, _Opts) ->
    {error, {unexpected_gateway_item_response, ID, Other}}.

on_weave_key_summaries(Device, Schema, Order) ->
    [
        device_key_summary(
            Device,
            Name,
            maps:get(<<"kind">>, KeySchema, <<"computed">>),
            maps:get(<<"description">>, KeySchema, <<>>)
        )
    || Name <- Order,
        KeySchema <- [maps:get(Name, Schema, #{})],
        map_size(KeySchema) > 0
    ].

device_recipe_docs(_Device, <<>>, _SpecSigner, _Opts) ->
    #{};
device_recipe_docs(Device, SpecID, SpecSigner, Opts) ->
    on_weave_recipe_docs(Device, SpecID, SpecSigner, Opts).

on_weave_recipe_docs(Device, SpecID, SpecSigner, Opts) ->
    case on_weave_doc_items(<<"Device-Recipe">>, <<"recipe-for-device">>, SpecID, [], 20, Opts) of
        {ok, Nodes} ->
            LoadedRecipes = [
                Recipe
            || Node <- Nodes,
                {ok, Recipe} <- [on_weave_recipe_doc(Node, SpecSigner, Opts)]
            ],
            Recipes = apply_recipe_blacklist(Device, SpecID, LoadedRecipes, Opts),
            lists:foldl(
                fun(Recipe, Acc) ->
                    Slug = maps:get(<<"name">>, Recipe),
                    case maps:is_key(Slug, Acc) of
                        true -> Acc;
                        false -> Acc#{Slug => Recipe}
                    end
                end,
                #{},
                Recipes
            );
        {error, _Reason} ->
            #{}
    end.

apply_recipe_blacklist(Device, SpecID, Recipes, Opts) ->
    [
        Recipe
    || Recipe <- Recipes,
        not recipe_blacklisted(Device, SpecID, Recipe, Opts)
    ].

recipe_blacklisted(Device, SpecID, Recipe, Opts) ->
    Entries = docs_recipe_blacklist(Opts),
    lists:any(
        fun(Entry) -> recipe_blacklist_entry_matches(Device, SpecID, Recipe, Entry) end,
        Entries
    ).

docs_recipe_blacklist(Opts) ->
    normalize_recipe_blacklist_entries(
        hb_opts:get(
            <<"docs-recipe-blacklist">>,
            hb_opts:get(docs_recipe_blacklist, [], Opts),
            Opts
        )
    ) ++ docs_recipe_blacklist_file_entries(Opts).

docs_recipe_blacklist_file_entries(Opts) ->
    case hb_opts:get(
        <<"docs-recipe-blacklist-file">>,
        hb_opts:get(docs_recipe_blacklist_file, <<>>, Opts),
        Opts
    ) of
        <<>> ->
            [];
        Path0 ->
            Path = binary_to_list(hb_util:bin(Path0)),
            case file:read_file(Path) of
                {ok, Body} ->
                    try normalize_recipe_blacklist_entries(hb_json:decode(Body))
                    catch _:_ -> []
                    end;
                {error, _Reason} ->
                    []
            end
    end.

normalize_recipe_blacklist_entries(Entries) when is_list(Entries) ->
    [Entry || Entry <- Entries, is_map(Entry)];
normalize_recipe_blacklist_entries(#{ <<"recipes">> := Entries }) ->
    normalize_recipe_blacklist_entries(Entries);
normalize_recipe_blacklist_entries(#{ <<"blacklist">> := Entries }) ->
    normalize_recipe_blacklist_entries(Entries);
normalize_recipe_blacklist_entries(Entry) when is_map(Entry) ->
    [Entry];
normalize_recipe_blacklist_entries(_Entries) ->
    [].

recipe_blacklist_entry_matches(Device, SpecID, Recipe, Entry) when is_map(Entry) ->
    recipe_blacklist_txid_matches(Recipe, Entry) orelse
        recipe_blacklist_slug_matches(Device, SpecID, Recipe, Entry);
recipe_blacklist_entry_matches(_Device, _SpecID, _Recipe, _Entry) ->
    false.

recipe_blacklist_txid_matches(Recipe, Entry) ->
    EntryTXID = trim(hb_util:bin(maps:get(<<"txid">>, Entry, <<>>))),
    EntryTXID =/= <<>> andalso
        lists:member(EntryTXID, recipe_blacklist_txids(Recipe)).

recipe_blacklist_txids(Recipe) ->
    lists:usort([
        TXID
    || Value <- [
            maps:get(<<"txid">>, Recipe, <<>>),
            maps:get(<<"source">>, Recipe, <<>>),
            maps:get(<<"source-relative">>, Recipe, <<>>)
        ],
        TXID <- [strip_weave_prefix(trim(hb_util:bin(Value)))],
        TXID =/= <<>>
    ]).

strip_weave_prefix(<<"weave:", Rest/binary>>) ->
    Rest;
strip_weave_prefix(Value) ->
    Value.

recipe_blacklist_slug_matches(Device, SpecID, Recipe, Entry) ->
    EntrySlug = trim(hb_util:bin(maps:get(<<"slug">>, Entry, <<>>))),
    EntryDevice = trim(hb_util:bin(maps:get(<<"device">>, Entry, <<>>))),
    EntrySpecID = trim(hb_util:bin(maps:get(<<"spec-id">>, Entry, <<>>))),
    Slug = maps:get(<<"name">>, Recipe, <<>>),
    EntrySlug =/= <<>> andalso
        EntrySlug =:= Slug andalso
        (
            (EntryDevice =/= <<>> andalso EntryDevice =:= Device) orelse
            (EntrySpecID =/= <<>> andalso EntrySpecID =:= SpecID)
        ).

on_weave_recipe_doc(Node, SpecSigner, Opts) ->
    ID = maps:get(<<"id">>, Node),
    case hb_client_gateway:data(ID, Opts) of
        {ok, Markdown} ->
            Slug = doc_item_tag(Node, <<"slug">>, ID),
            Title = doc_item_tag(Node, <<"title">>, markdown_title(Markdown, Slug)),
            Blocks = code_blocks(Markdown),
            Runnable = [Block || Block <- Blocks, maps:get(<<"runnable">>, Block, false) =:= true],
            FirstCommand =
                case Runnable of
                    [First|_] -> command_preview(maps:get(<<"text">>, First, <<>>));
                    [] -> <<>>
                end,
            {ok,
                maps:merge(doc_item_metadata(Node, Opts), #{
                    <<"name">> => Slug,
                    <<"title">> => Title,
                    <<"summary">> => markdown_summary(Markdown),
                    <<"source">> => <<"on-weave">>,
                    <<"source-relative">> => <<"weave:", ID/binary>>,
                    <<"recipe-status">> => <<"loaded">>,
                    <<"block-count">> => length(Blocks),
                    <<"runnable-block-count">> => length(Runnable),
                    <<"first-command">> => FirstCommand,
                    <<"blocks">> => Blocks,
                    <<"markdown">> => Markdown,
                    <<"official">> =>
                        SpecSigner =/= <<>> andalso doc_item_owner(Node, Opts) =:= SpecSigner
                })};
        {error, Reason} ->
            {ok,
                maps:merge(doc_item_metadata(Node, Opts), #{
                    <<"name">> => doc_item_tag(Node, <<"slug">>, ID),
                    <<"title">> => doc_item_tag(Node, <<"title">>, ID),
                    <<"summary">> => <<"Recipe body could not be loaded from the weave.">>,
                    <<"source">> => <<"on-weave">>,
                    <<"source-relative">> => <<"weave:", ID/binary>>,
                    <<"recipe-status">> => <<"missing">>,
                    <<"error">> => format_reason(Reason),
                    <<"block-count">> => 0,
                    <<"runnable-block-count">> => 0
                })}
    end.

on_weave_implementations(SpecID, Opts) ->
    TrustedSigners = hb_opts:get(<<"trusted-device-signers">>, [], Opts),
    case TrustedSigners of
        [] ->
            [];
        _ ->
            case hb_client_gateway:device(SpecID, TrustedSigners, Opts) of
                {ok, ImplIDs} ->
                    [
                        #{
                            <<"name">> => SpecID,
                            <<"module">> => <<"on-weave-beam-archive">>,
                            <<"source">> => ImplID,
                            <<"status">> => <<"discovered-by-implements-device">>
                        }
                    || ImplID <- ImplIDs
                    ];
                {error, _Reason} ->
                    []
            end
    end.

on_weave_item_by_id(ID, Opts) ->
    Query =
        <<"query($ids: [ID!]!) { ",
            "transactions(ids: $ids, first: 1){ ",
                "edges { ",
                    "node { ",
                        "id ",
                        "owner { address key } ",
                        "block { height timestamp } ",
                        "tags { name value } ",
                        "data { size } ",
                    "} ",
                    "cursor ",
                "} ",
            "} ",
        "}">>,
    Variables = #{<<"ids">> => [ID]},
    case hb_client_gateway:query(Query, Variables, Opts) of
        {ok, GqlMsg} ->
            case hb_ao:get(<<"data/transactions/edges">>, GqlMsg, Opts) of
                [#{<<"node">> := Node} | _] -> {ok, Node};
                _ -> {error, not_found}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

on_weave_doc_items(Type, TagName, SpecID, Owners, First, Opts) ->
    OwnerVar =
        case Owners of
            [] -> <<>>;
            _ -> <<", $owners: [String!]">>
        end,
    OwnerArg =
        case Owners of
            [] -> <<>>;
            _ -> <<"owners: $owners, ">>
        end,
    FirstBin = integer_to_binary(First),
    Query =
        <<"query($specid: [String!], $type: [String!]", OwnerVar/binary, ") { ",
            "transactions(",
                OwnerArg/binary,
                "tags: [",
                    "{ name: \"type\", values: $type }, ",
                    "{ name: \"", TagName/binary, "\", values: $specid }",
                "], ",
                "sort: HEIGHT_DESC, ",
                "first: ", FirstBin/binary,
            "){ ",
                "edges { ",
                    "node { ",
                        "id ",
                        "owner { address key } ",
                        "block { height timestamp } ",
                        "tags { name value } ",
                        "data { size } ",
                    "} ",
                    "cursor ",
                "} ",
            "} ",
        "}">>,
    Variables0 = #{<<"specid">> => [SpecID], <<"type">> => [Type]},
    Variables =
        case Owners of
            [] -> Variables0;
            _ -> Variables0#{<<"owners">> => Owners}
        end,
    case hb_client_gateway:query(Query, Variables, Opts) of
        {ok, GqlMsg} ->
            case hb_ao:get(<<"data/transactions/edges">>, GqlMsg, Opts) of
                Edges when is_list(Edges) ->
                    {ok, [Node || #{<<"node">> := Node} <- Edges]};
                _ ->
                    {ok, []}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

doc_item_metadata(Node, Opts) ->
    #{
        <<"txid">> => maps:get(<<"id">>, Node, <<>>),
        <<"signer">> => doc_item_owner(Node, Opts),
        <<"block-height">> => hb_ao:get(<<"block/height">>, Node, <<>>, Opts),
        <<"block-timestamp">> => hb_ao:get(<<"block/timestamp">>, Node, <<>>, Opts)
    }.

doc_item_owner(Node, Opts) ->
    hb_ao:get(<<"owner/address">>, Node, <<>>, Opts).

doc_item_tag(Node, Name, Default) ->
    Tags = maps:get(<<"tags">>, Node, []),
    case [Value || #{<<"name">> := TagName, <<"value">> := Value} <- Tags, TagName =:= Name] of
        [Value | _] -> Value;
        [] -> Default
    end.

format_reason(Reason) ->
    hb_util:bin(io_lib:format("~tp", [Reason])).

json_safe(Value) when is_map(Value) ->
    maps:from_list(
        [
            {json_safe_key(Key), json_safe(Inner)}
        || {Key, Inner} <- maps:to_list(Value)
        ]
    );
json_safe(Value) when is_list(Value) ->
    [json_safe(Inner) || Inner <- Value];
json_safe(true) ->
    true;
json_safe(false) ->
    false;
json_safe(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
json_safe(Value) when is_tuple(Value) ->
    [json_safe(Inner) || Inner <- tuple_to_list(Value)];
json_safe(Value) ->
    Value.

json_safe_key(Key) when is_binary(Key) ->
    Key;
json_safe_key(Key) when is_atom(Key) ->
    binary:replace(atom_to_binary(Key, utf8), <<"_">>, <<"-">>, [global]);
json_safe_key(Key) ->
    hb_util:bin(io_lib:format("~tp", [Key])).

node_href(Opts) ->
    Host = hb_opts:get(node_host, <<"localhost">>, Opts),
    Port = hb_opts:get(port, 8734, Opts),
    iolist_to_binary(["http://", hb_util:bin(Host), ":", hb_util:bin(Port)]).

docs_renderer() ->
    dev_hyperbeam_docs_render:renderer_metadata().

node_component_index(Kind, LinkKey, Data) ->
    Devices = maps:get(<<"devices">>, Data, []),
    #{
        <<"kind">> => Kind,
        <<"renderer">> => maps:get(<<"renderer">>, Data, docs_renderer()),
        <<"devices">> =>
            [
                #{
                    <<"device">> => device_card_label(Device),
                    <<"href">> => maps:get(LinkKey, Device, maps:get(<<"href">>, Device, <<>>))
                }
            || Device <- Devices
            ]
    }.

device_key_summary(Device, Name, Kind, Description) ->
    #{
        <<"name">> => Name,
        <<"kind">> => Kind,
        <<"description">> => Description,
        <<"href">> => <<"/~", Device/binary, "/", Name/binary>>
    }.

docs_schema_for_device(Device, SpecID, Opts) ->
    case implementation_derived_schema(Device, Opts) of
        {ok, Schema, SchemaOrder, Source} ->
            {
                Schema,
                SchemaOrder,
                Source#{
                    <<"mode">> => <<"implementation-derived">>,
                    <<"spec-id">> => SpecID
                }
            };
        {error, Reason} ->
            {
                #{},
                [],
                #{
                    <<"mode">> => <<"implementation-derived-unavailable">>,
                    <<"device">> => Device,
                    <<"spec-id">> => SpecID,
                    <<"status">> => <<"unavailable">>,
                    <<"reason">> => format_reason(Reason),
                    <<"display-rule">> =>
                        <<"schema must be derived from the loaded implementation">>
                }
            }
    end.

%% @doc Render the schema retained by the loaded implementation's runtime.
implementation_derived_schema(Device, Opts) ->
    case dev_hyperbeam_docs_schema:extract(Device, Opts) of
        {ok, #{ <<"keys">> := Keys } = Extracted} when map_size(Keys) > 0 ->
            Schema = maps:map(
                fun(Key, KeySchema) ->
                    implementation_schema_key(Device, Key, KeySchema)
                end,
                Keys
            ),
            Count = maps:get(<<"typed-key-count">>, Extracted),
            Status =
                if Count =:= map_size(Keys) -> <<"present">>;
                   Count =:= 0 -> <<"unavailable">>;
                   true -> <<"partial">>
                end,
            {ok, Schema, lists:sort(maps:keys(Schema)),
                (maps:without([<<"keys">>], Extracted))#{
                    <<"status">> => Status,
                    <<"extractor">> => <<"hb_device_load:schema/2">>
                }};
        {ok, _Extracted} -> {error, no_public_keys};
        {error, Reason} -> {error, Reason}
    end.

fallback_schema_key(Device, Key) ->
    (maps:without(
        [<<"description">>],
        schema_key(Device, Key, <<>>, #{})
    ))#{
        <<"source">> => <<"module-info-exports">>,
        <<"description-source">> => <<"none">>,
        <<"derived">> => false,
        <<"schema-status">> => <<"unavailable">>,
        <<"returns">> => <<"not declared">>,
        <<"arguments">> => []
    }.

%% @doc Keep untyped exports visible without presenting them as extracted specs.
implementation_schema_key(Device, Key, #{ <<"status">> := <<"unavailable">> } = Schema) ->
    (fallback_schema_key(Device, Key))#{
        <<"schema-reason">> => maps:get(<<"reason">>, Schema)
    };
implementation_schema_key(Device, Key, KeySchema) ->
    DeviceID =
        case is_binary(Device) of
            true -> Device;
            false -> hb_util:bin(Device)
        end,
    Params = implementation_request_params(maps:get(<<"request">>, KeySchema, #{})),
    Return = implementation_type_label(maps:get(<<"return">>, KeySchema, #{})),
    maps:merge(
        maps:without(
            [<<"description">>],
            schema_key(DeviceID, Key, <<>>, Params)
        ),
        #{
            <<"source">> => <<"hb_device_load:schema/2">>,
            <<"description-source">> => <<"none">>,
            <<"derived">> => true,
            <<"schema-status">> => <<"present">>,
            <<"arguments">> => [
                Argument#{
                    <<"type">> => implementation_type_label(
                        maps:get(<<"type-schema">>, Argument)
                    )
                }
            || Argument <- maps:get(<<"arguments">>, KeySchema)
            ],
            <<"returns">> => Return,
            <<"type-schema">> => json_safe(KeySchema)
        }
    ).

implementation_request_params(#{ <<"kind">> := <<"message">>, <<"keys">> := Keys })
        when is_map(Keys) ->
    maps:from_list(
        [
            {
                Name,
                implementation_param(Name, Presence, Type)
            }
        || {Name, #{ <<"presence">> := Presence, <<"type">> := Type }} <- maps:to_list(Keys)
        ]
    );
implementation_request_params(_Schema) ->
    #{}.

implementation_param(Name, Presence, Type) ->
    (maps:without(
        [<<"description">>, <<"example">>],
        param(
            Name,
            implementation_required(Presence),
            implementation_type_label(Type),
            <<>>,
            <<>>
        )
    ))#{
        <<"description-source">> => <<"none">>,
        <<"type-schema">> => json_safe(Type)
    }.

implementation_required(required) -> true;
implementation_required(<<"required">>) -> true;
implementation_required(_) -> false.

implementation_type_label(#{ <<"kind">> := <<"message">>, <<"keys">> := Keys }) when is_map(Keys) ->
    case maps:keys(Keys) of
        [] -> <<"message">>;
        Names -> iolist_to_binary([<<"message(">>, join_names(Names), <<")">>])
    end;
implementation_type_label(#{ <<"kind">> := <<"list">>, <<"item">> := Item }) ->
    iolist_to_binary([<<"list<">>, implementation_type_label(Item), <<">">>]);
implementation_type_label(#{ <<"kind">> := <<"tuple">>, <<"items">> := Items }) ->
    implementation_join_type(<<"tuple(">>, Items, <<")">>);
implementation_type_label(#{ <<"kind">> := <<"union">>, <<"members">> := Members }) ->
    implementation_join_type(<<"union(">>, Members, <<")">>);
implementation_type_label(#{ <<"kind">> := <<"literal">>, <<"value">> := Value }) ->
    hb_util:bin(io_lib:format("~tp", [Value]));
implementation_type_label(#{ <<"kind">> := <<"range">>, <<"min">> := Min, <<"max">> := Max }) ->
    iolist_to_binary([hb_util:bin(Min), <<"..">>, hb_util:bin(Max)]);
implementation_type_label(#{ <<"kind">> := <<"wildcard">> }) ->
    <<"_ (kept as given)">>;
implementation_type_label(#{ <<"kind">> := Kind }) ->
    hb_util:bin(Kind);
implementation_type_label(_Type) ->
    <<"any">>.

implementation_join_type(Prefix, Items, Suffix) ->
    Labels = [implementation_type_label(Item) || Item <- Items],
    iolist_to_binary([Prefix, lists:join(<<",">>, Labels), Suffix]).

schema_key(Device, Name, Description, Parameters) ->
    Required = [
        ParamName
    ||  {ParamName, ParamSpec} <- maps:to_list(Parameters),
        maps:get(<<"required">>, ParamSpec, false) =:= true
    ],
    maps:merge(Parameters, #{
        <<"name">> => Name,
        <<"kind">> => <<"computed">>,
        <<"description">> => Description,
        <<"href">> => <<"/~", Device/binary, "/", Name/binary>>,
        <<"action-path-template">> => action_path_template(Device, Name),
        <<"parameter-names">> => join_names(maps:keys(Parameters)),
        <<"required-parameters">> => join_names(Required),
        <<"parameters">> => Parameters
    }).

action_path_template(?MESSAGE_DEVICE, <<"field">>) ->
    <<"/~message@1.0/{field}">>;
action_path_template(Device, Name) ->
    <<"/~", Device/binary, "/", Name/binary>>.

join_names([]) ->
    <<"">>;
join_names(Names) ->
    iolist_to_binary(lists:join(<<",">>, lists:sort(Names))).

param(Name, Required, Type, Description, Example) ->
    #{
        <<"name">> => Name,
        <<"required">> => Required,
        <<"type">> => Type,
        <<"description">> => Description,
        <<"example">> => Example
    }.

boilerplate_index() ->
    dev_hyperbeam_docs_ui:boilerplate_index().

boilerplate_page_payload(Parts) ->
    dev_hyperbeam_docs_ui:boilerplate_page_payload(Parts).

docs_asset_response(Parts) ->
    dev_hyperbeam_docs_ui:docs_asset_response(Parts).

render_node_html(Data) ->
    dev_hyperbeam_docs_ui:render_node_html(Data).

render_device_html(Data) ->
    dev_hyperbeam_docs_ui:render_device_html(Data).

render_schema_index_html(Data) ->
    dev_hyperbeam_docs_ui:render_schema_index_html(Data).

render_schema_key_html(Payload) ->
    dev_hyperbeam_docs_ui:render_schema_key_html(Payload).

render_schema_parameter_html(Payload) ->
    dev_hyperbeam_docs_ui:render_schema_parameter_html(Payload).

render_spec_html(Data) ->
    dev_hyperbeam_docs_ui:render_spec_html(Data).

render_spec_section_page_html(Payload) ->
    dev_hyperbeam_docs_ui:render_spec_section_page_html(Payload).

render_recipes_html(Data) ->
    dev_hyperbeam_docs_ui:render_recipes_html(Data).

render_recipe_html(Payload) ->
    dev_hyperbeam_docs_ui:render_recipe_html(Payload).

render_implementations_html(Data) ->
    dev_hyperbeam_docs_ui:render_implementations_html(Data).

render_node_component_html(Title, ActivePath, Data) ->
    dev_hyperbeam_docs_ui:render_node_component_html(Title, ActivePath, Data).

render_node_boilerplate_html(Data) ->
    dev_hyperbeam_docs_ui:render_node_boilerplate_html(Data).

render_node_boilerplate_page_html(Data) ->
    dev_hyperbeam_docs_ui:render_node_boilerplate_page_html(Data).

render_node_concepts_html(Data) ->
    dev_hyperbeam_docs_ui:render_node_concepts_html(Data).

render_node_concept_html(Data) ->
    dev_hyperbeam_docs_ui:render_node_concept_html(Data).

render_unsupported_device_html(Device) ->
    dev_hyperbeam_docs_ui:render_unsupported_device_html(Device).

markdown_title(Markdown, Fallback) ->
    dev_hyperbeam_docs_ui:markdown_title(Markdown, Fallback).

markdown_summary(Markdown) ->
    dev_hyperbeam_docs_ui:markdown_summary(Markdown).

command_preview(Text) ->
    dev_hyperbeam_docs_ui:command_preview(Text).

code_blocks(Markdown) ->
    dev_hyperbeam_docs_ui:code_blocks(Markdown).

trim(Bin) ->
    dev_hyperbeam_docs_ui:trim(Bin).

spec_section_lookup(Spec, SectionSlug) ->
    dev_hyperbeam_docs_ui:spec_section_lookup(Spec, SectionSlug).

device_card_label(Device) ->
    dev_hyperbeam_docs_ui:device_card_label(Device).

device_info_path(DeviceID) ->
    dev_hyperbeam_docs_ui:device_info_path(DeviceID).

device_schema_path(DeviceID) ->
    dev_hyperbeam_docs_ui:device_schema_path(DeviceID).

device_spec_path(DeviceID) ->
    dev_hyperbeam_docs_ui:device_spec_path(DeviceID).

device_recipes_path(DeviceID) ->
    dev_hyperbeam_docs_ui:device_recipes_path(DeviceID).

device_doc_link_fields(Device) ->
    dev_hyperbeam_docs_ui:device_doc_link_fields(Device).
