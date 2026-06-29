%%% @doc HyperBEAM docs renderer implementation for HyperBEAM docs payloads.
%%%
%%% This module is packaged with the `~hyperbeam-docs@1.0' Forge device so it
%%% can expose the same renderer over direct device calls and the `/docs' hook.
-module(dev_hyperbeam_docs_render).
-export([render/3, respond_html_or_json/4, unsupported_device_response/2]).
-export([renderer_metadata/0]).

%% @doc Render a docs payload for the caller's preferred response format.
render(Kind, Data, Req) ->
    case wants_html(Req) of
        true -> html_response(Kind, Data);
        false -> json_response(Data)
    end.

respond_html_or_json(Kind, HtmlData, JsonData, Req) ->
    {ok,
        case wants_html(Req) of
            true -> html_response(Kind, HtmlData);
            false -> json_response(JsonData)
        end}.

unsupported_device_response(Device, Req) ->
    case wants_html(Req) of
        true ->
            (html_doc_response(dev_hyperbeam_docs_data:render_unsupported_device_html(Device)))#{
                <<"status">> => 404
            };
        false ->
            json_response(
                404,
                #{
                    <<"kind">> => <<"device-info">>,
                    <<"device">> => #{ <<"id">> => Device },
                    <<"device-id">> => Device,
                    <<"docs-status">> => <<"not-documented">>,
                    <<"status">> => <<"not-implemented">>,
                    <<"summary">> =>
                        <<"No on-weave spec-loaded documentation is available for this device.">>
                }
            )
    end.

renderer_metadata() ->
    #{
        <<"device">> => <<"hyperbeam-docs@1.0">>,
        <<"node-renderer">> => <<"/~hyperbeam-docs@1.0/index">>,
        <<"device-renderer">> => <<"/~hyperbeam-docs@1.0/device?for=<device@version>">>,
        <<"source">> => <<"hyperbeam_docs/src/dev_hyperbeam_docs.erl">>,
        <<"status">> => <<"renderer-device">>
    }.

wants_html(Req) ->
    Accept = hb_util:to_lower(hb_maps:get(<<"accept">>, Req, <<"">>, #{})),
    binary:match(Accept, <<"text/html">>) =/= nomatch andalso
        binary:match(Accept, <<"application/json">>) =:= nomatch.

html_response(node, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_html(Data));
html_response(device, Data) ->
    Links = maps:get(<<"links">>, Data, #{}),
    maps:merge(
        html_doc_response(dev_hyperbeam_docs_data:render_device_html(Data)),
        #{
            <<"schema+link">> => maps:get(<<"schema">>, Links, <<>>),
            <<"specification+link">> => maps:get(<<"spec">>, Links, <<>>),
            <<"recipes+link">> => maps:get(<<"recipes">>, Links, <<>>)
        }
    );
html_response(schema_index, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_schema_index_html(Data));
html_response(schema_key, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_schema_key_html(Data));
html_response(schema_parameter, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_schema_parameter_html(Data));
html_response(spec, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_spec_html(Data));
html_response(spec_section, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_spec_section_page_html(Data));
html_response(recipes, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_recipes_html(Data));
html_response(recipe, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_recipe_html(Data));
html_response(implementations, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_implementations_html(Data));
html_response(node_schema, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_component_html(<<"Schema">>, <<"/docs/schema">>, Data));
html_response(node_spec, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_component_html(<<"Spec">>, <<"/docs/spec">>, Data));
html_response(node_recipes, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_component_html(<<"Recipes">>, <<"/docs/recipes">>, Data));
html_response(node_implementations, Data) ->
    html_doc_response(
        dev_hyperbeam_docs_data:render_node_component_html(<<"Implementations">>, <<"/docs/implementations">>, Data)
    );
html_response(node_boilerplate, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_boilerplate_html(Data));
html_response(node_boilerplate_page, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_boilerplate_page_html(Data));
html_response(node_concepts, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_concepts_html(Data));
html_response(node_concept, Data) ->
    html_doc_response(dev_hyperbeam_docs_data:render_node_concept_html(Data)).

html_doc_response(Body) ->
    #{
        <<"status">> => 200,
        <<"content-type">> => <<"text/html; charset=utf-8">>,
        <<"body">> => Body
    }.

json_response(Data) ->
    json_response(200, Data).

json_response(Status, Data) ->
    #{
        <<"status">> => Status,
        <<"content-type">> => <<"application/json">>,
        <<"body">> => hb_json:encode(json_safe(Data))
    }.

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
