%%% @doc HTML, Markdown, asset, and boilerplate-page rendering for HyperBEAM docs.
-module(dev_hyperbeam_docs_ui).
-export([
    boilerplate_index/0,
    boilerplate_page_payload/1,
    docs_asset_response/1,
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
    render_markdown/1,
    render_markdown/2,
    render_markdown_with_heading_ids/2,
    markdown_title/2,
    markdown_summary/1,
    card_summary/1,
    recipe_card_summary/1,
    code_blocks/1,
    command_preview/1,
    spec_sections/1,
    spec_section_lookup/2,
    spec_section_markdown/2,
    spec_section_nav_label/1,
    spec_tx_link/2,
    render_spec_body/1,
    device_card_label/1,
    device_doc_link_fields/1,
    device_info_path/1,
    device_marked_id/1,
    device_recipes_path/1,
    device_schema_path/1,
    device_spec_path/1,
    device_summary_paragraph/1,
    schema_table/3,
    recipe_icon_name/2,
    recipe_icon_paths/0,
    recipe_nav/2,
    on_chain_link_paragraph/2,
    on_chain_txid/1,
    implementation_source_cell/1,
    boilerplate_pages_for_section/2,
    sidebar_device_context/2,
    packaged_device_docs_root/0,
    trim/1
]).

-define(DEVICE_DOCS_PRIV_ROOT, ["src", "priv", "dev_hyperbeam_docs", "device-docs"]).

docs_renderer() ->
    dev_hyperbeam_docs_render:renderer_metadata().

boilerplate_index() ->
    Pages = [boilerplate_page_entry(Page) || Page <- boilerplate_pages()],
    #{
        <<"kind">> => <<"node-boilerplate-index">>,
        <<"href">> => <<"/docs/guides">>,
        <<"summary">> =>
            <<"Conceptual HyperBEAM, AO-Core, process, and Device Forge guides.">>,
        <<"source-root">> => hb_util:bin(device_docs_root()),
        <<"ui-source">> => <<"src/priv/dev_hyperbeam_docs/device-docs/site">>,
        <<"build-script">> => <<"src/priv/dev_hyperbeam_docs/device-docs/scripts/build-docs-site.mjs">>,
        <<"pages">> => Pages
    }.

boilerplate_page_payload(Parts) ->
    case boilerplate_relpath_from_parts(Parts) of
        undefined ->
            not_found;
        RelPath ->
            case lists:keyfind(RelPath, 2, boilerplate_pages()) of
                false ->
                    not_found;
                Page ->
                    Entry = boilerplate_page_entry(Page),
                    Source = device_docs_path(RelPath),
                    case file:read_file(binary_to_list(Source)) of
                        {ok, RawMarkdown} ->
                            Markdown = sanitize_boilerplate_markdown(RawMarkdown),
                            {ok, Entry#{
                                <<"kind">> => <<"node-boilerplate-page">>,
                                <<"markdown">> => Markdown,
                                <<"markdown-bytes">> => byte_size(Markdown)
                            }};
                        {error, Reason} ->
                            {ok, Entry#{
                                <<"kind">> => <<"node-boilerplate-page">>,
                                <<"markdown">> => <<>>,
                                <<"error">> => hb_util:bin(io_lib:format("~tp", [Reason]))
                            }}
                    end
            end
    end.

boilerplate_relpath_from_parts([]) ->
    undefined;
boilerplate_relpath_from_parts([Section])
    when Section =:= <<"introduction">>; Section =:= <<"forge">> ->
    boilerplate_relpath_from_parts([Section, <<"index">>]);
boilerplate_relpath_from_parts([<<"processes">>]) ->
    boilerplate_relpath_from_parts([<<"processes">>, <<"overview">>]);
boilerplate_relpath_from_parts([<<"processes">>, Slug]) ->
    boilerplate_process_route(Slug);
boilerplate_relpath_from_parts(Parts) ->
    case lists:all(fun safe_route_part/1, Parts) of
        true ->
            iolist_to_binary([<<"docs/">>, lists:join(<<"/">>, Parts), <<".md">>]);
        false ->
            undefined
    end.

safe_route_part(Part) when is_binary(Part) ->
    Part =/= <<>> andalso
        binary:match(Part, <<"/">>) =:= nomatch andalso
        binary:match(Part, <<"..">>) =:= nomatch;
safe_route_part(_) ->
    false.

boilerplate_page_entry({Section, RelPath, FallbackTitle}) ->
    Source = device_docs_path(RelPath),
    Markdown =
        case file:read_file(binary_to_list(Source)) of
            {ok, Body} -> sanitize_boilerplate_markdown(Body);
            {error, _Reason} -> <<>>
        end,
    Title =
        case boilerplate_title_override(RelPath) of
            undefined -> markdown_title(Markdown, FallbackTitle);
            OverrideTitle -> OverrideTitle
        end,
    #{
        <<"section">> => Section,
        <<"title">> => Title,
        <<"summary">> => boilerplate_card_summary(RelPath, Markdown),
        <<"href">> => boilerplate_href(RelPath),
        <<"source">> => Source,
        <<"source-relative">> => RelPath
    }.

boilerplate_title_override(RelPath) ->
    case lists:keyfind(RelPath, 2, boilerplate_process_pages()) of
        {_, RelPath, Title} -> Title;
        false -> undefined
    end.

boilerplate_href(<<"docs/", Rest/binary>>) ->
    case boilerplate_href_override(<<"docs/", Rest/binary>>) of
        undefined ->
            WithoutExt = strip_suffix(Rest, <<".md">>),
            boilerplate_href_from_doc_path(WithoutExt);
        Href ->
            Href
    end;
boilerplate_href(RelPath) ->
    case boilerplate_href_override(RelPath) of
        undefined ->
            WithoutExt = strip_suffix(RelPath, <<".md">>),
            boilerplate_href_from_doc_path(WithoutExt);
        Href ->
            Href
    end.

boilerplate_href_override(RelPath) ->
    case lists:keyfind(RelPath, 2, boilerplate_process_pages()) of
        {Slug, RelPath, _Title} -> <<"/docs/processes/", Slug/binary>>;
        false -> undefined
    end.

boilerplate_href_from_doc_path(<<"introduction/", Rest/binary>>) ->
    <<"/docs/introduction/", Rest/binary>>;
boilerplate_href_from_doc_path(<<"forge/", Rest/binary>>) ->
    <<"/docs/forge/", Rest/binary>>;
boilerplate_href_from_doc_path(Path) ->
    <<"/docs/", Path/binary>>.

boilerplate_card_summary(RelPath, Markdown) ->
    case boilerplate_card_summary_override(RelPath) of
        undefined ->
            markdown_summary(Markdown);
        Summary ->
            Summary
    end.

boilerplate_card_summary_override(<<"docs/introduction/index.md">>) ->
    <<"The conceptual start for this corpus: HyperBEAM, AO-Core, devices, and pathing.">>;
boilerplate_card_summary_override(<<"docs/introduction/what-is-hyperbeam.md">>) ->
    <<"The production-ready AO-Core runtime that powers decentralized compute on Erlang/OTP.">>;
boilerplate_card_summary_override(<<"docs/introduction/what-is-ao-core.md">>) ->
    <<"The HTTP-native protocol for decentralized computation on the Arweave permaweb.">>;
boilerplate_card_summary_override(<<"docs/introduction/ao-devices.md">>) ->
    <<"How AO devices modularize compute, codecs, storage, and node services.">>;
boilerplate_card_summary_override(<<"docs/introduction/pathing-in-ao-core.md">>) ->
    <<"How HyperPATH URLs address messages, devices, and computation results.">>;
boilerplate_card_summary_override(<<"docs/processes/overview.md">>) ->
    <<"Create and understand HyperBEAM process@1.0 processes, messages, and authorities.">>;
boilerplate_card_summary_override(<<"docs/processes/state-and-reads.md">>) ->
    <<"Expose process state through patch@1.0 and read it over HTTP.">>;
boilerplate_card_summary_override(<<"docs/processes/builder-templates.md">>) ->
    <<"Copy practical Lua process templates for tokens, chats, and public state.">>;
boilerplate_card_summary_override(<<"docs/processes/ao-connect-mainnet.md">>) ->
    <<"Spawn, message, and read HyperBEAM processes from JavaScript clients.">>;
boilerplate_card_summary_override(<<"docs/processes/aos-lua-reference.md">>) ->
    <<"Keep the AOS Lua commands, globals, handlers, and replies close at hand.">>;
boilerplate_card_summary_override(<<"docs/processes/migration-to-hyperbeam.md">>) ->
    <<"Move legacy AO process patterns to HyperBEAM HTTP reads and patch updates.">>;
boilerplate_card_summary_override(<<"docs/processes/legacynet-appendix.md">>) ->
    <<"Reference old Legacynet AO patterns only when supporting existing processes.">>;
boilerplate_card_summary_override(_) ->
    undefined.

sanitize_boilerplate_markdown(Markdown) ->
    lists:foldl(
        fun(Needle, Acc) ->
            binary:replace(Acc, Needle, <<>>, [global])
        end,
        Markdown,
        [
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n\n">>,
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "`c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`. Local links have been "
                "adjusted for this combined docs corpus.\n\n">>,
            <<"> Merged from the HyperBEAM edge documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n\n">>,
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n">>,
            <<"> Merged from the HyperBEAM `edge` documentation at commit "
                "`c6a16a26dc4ddca55c57db2fd7be6b898d105bb3`. Local links have been "
                "adjusted for this combined docs corpus.\n">>,
            <<"> Merged from the HyperBEAM edge documentation at commit "
                "c6a16a26dc4ddca55c57db2fd7be6b898d105bb3. Local links have been "
                "adjusted for this combined docs corpus.\n">>
        ]
    ).

strip_suffix(Bin, Suffix) ->
    case ends_with(Bin, Suffix) of
        true -> binary:part(Bin, 0, byte_size(Bin) - byte_size(Suffix));
        false -> Bin
    end.

boilerplate_pages() ->
    [
        {<<"Introduction">>, <<"docs/introduction/index.md">>, <<"Introduction">>},
        {<<"Introduction">>, <<"docs/introduction/what-is-hyperbeam.md">>, <<"What Is HyperBEAM?">>},
        {<<"Introduction">>, <<"docs/introduction/what-is-ao-core.md">>, <<"What Is AO-Core?">>},
        {<<"Introduction">>, <<"docs/introduction/ao-devices.md">>, <<"AO Devices">>},
        {<<"Introduction">>, <<"docs/introduction/pathing-in-ao-core.md">>, <<"Pathing In AO-Core">>}
    ] ++ [
        {<<"Processes">>, RelPath, Title}
    || {_Slug, RelPath, Title} <- boilerplate_process_pages()
    ] ++ [
        {<<"Device Forge">>, <<"docs/forge/index.md">>, <<"Device Forge">>},
        {<<"Device Forge">>, <<"docs/forge/create-a-device.md">>, <<"Create A Device">>},
        {<<"Device Forge">>, <<"docs/forge/install-template.md">>, <<"Install Template">>},
        {<<"Device Forge">>, <<"docs/forge/operator-configuration.md">>, <<"Operator Configuration">>},
        {<<"Device Forge">>, <<"docs/forge/publish-and-load.md">>, <<"Publish And Load">>},
        {<<"Device Forge">>, <<"docs/forge/run-local.md">>, <<"Run Local">>},
        {<<"Device Forge">>, <<"docs/forge/runbook.md">>, <<"Runbook">>},
        {<<"Device Forge">>, <<"docs/forge/test-package-verify.md">>, <<"Test Package Verify">>},
        {<<"Device Forge">>, <<"docs/forge/trusted-signers-and-pins.md">>, <<"Trusted Signers And Pins">>}
    ].

boilerplate_process_route(Slug) ->
    case lists:keyfind(Slug, 1, boilerplate_process_pages()) of
        {Slug, RelPath, _Title} -> RelPath;
        false -> undefined
    end.

boilerplate_process_pages() ->
    [
        {<<"overview">>, <<"docs/processes/overview.md">>, <<"Process Overview">>},
        {<<"state-and-reads">>, <<"docs/processes/state-and-reads.md">>, <<"State And Reads">>},
        {<<"builder-templates">>, <<"docs/processes/builder-templates.md">>, <<"Builder Templates">>},
        {<<"ao-connect-mainnet">>, <<"docs/processes/ao-connect-mainnet.md">>, <<"AO Connect Mainnet">>},
        {<<"aos-lua-reference">>, <<"docs/processes/aos-lua-reference.md">>, <<"AOS Lua Reference">>},
        {<<"migration-to-hyperbeam">>, <<"docs/processes/migration-to-hyperbeam.md">>, <<"Migration To HyperBEAM">>},
        {<<"legacynet-appendix">>, <<"docs/processes/legacynet-appendix.md">>, <<"Legacynet Appendix">>}
    ].

extract_markdown_section(Markdown, SectionTitle) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    extract_markdown_section_lines(Lines, SectionTitle).

extract_markdown_section_lines([], _SectionTitle) ->
    false;
extract_markdown_section_lines([Line | Rest], SectionTitle) ->
    case heading(trim(Line)) of
        {Level, Text} when Text =:= SectionTitle ->
            {SectionLines, _After} = take_section_body(Rest, Level, []),
            {ok,
                iolist_to_binary(
                    lists:join(<<"\n">>, [<<"# ", SectionTitle/binary>> | SectionLines])
                )};
        _ ->
            extract_markdown_section_lines(Rest, SectionTitle)
    end.

take_section_body([Line | Rest] = All, Level, Acc) ->
    case heading(trim(Line)) of
        {NextLevel, _Text} when NextLevel =< Level ->
            {lists:reverse(Acc), All};
        _ ->
            take_section_body(Rest, Level, [Line | Acc])
    end;
take_section_body([], _Level, Acc) ->
    {lists:reverse(Acc), []}.

device_docs_path(RelPath) ->
    hb_util:bin(filename:join([device_docs_root(), binary_to_list(RelPath)])).

device_docs_root() ->
    case os:getenv("HB_DEVICE_DOCS_ROOT") of
        false -> packaged_device_docs_root();
        "" -> packaged_device_docs_root();
        Root -> Root
    end.

packaged_device_docs_root() ->
    Candidate = filename:join(hb_device_archive:implementation_dir(?MODULE), "device-docs"),
    case filelib:is_dir(Candidate) of
        true -> Candidate;
        false -> filename:join(?DEVICE_DOCS_PRIV_ROOT)
    end.

command_preview(Text) ->
    OneLine0 = binary:replace(Text, <<"\r">>, <<" ">>, [global]),
    OneLine = binary:replace(OneLine0, <<"\n">>, <<" ">>, [global]),
    case byte_size(OneLine) > 1200 of
        true -> <<(binary:part(OneLine, 0, 1200))/binary, "...">>;
        false -> OneLine
    end.

render_node_html(Data) ->
    Devices = maps:get(<<"devices">>, Data),
    Renderer = maps:get(<<"renderer">>, Data, docs_renderer()),
    Boilerplate = maps:get(<<"boilerplate">>, Data, boilerplate_index()),
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>HyperBEAM Docs</h1><p>">>,
            esc(maps:get(<<"summary">>, Data)),
            <<"</p><p class=\"hb-docs-renderer-note\">Rendered by <a href=\"">>,
            esc(maps:get(<<"node-renderer">>, Renderer)),
            <<"\">~">>, esc(maps:get(<<"device">>, Renderer)), <<"</a>.</p>">>,
            <<"<h2>Guides</h2>">>,
            boilerplate_structured_index(Boilerplate),
            <<"<h2 id=\"devices\">Devices</h2><div class=\"hb-docs-card-grid\">">>,
            [device_row(Device) || Device <- Devices],
            <<"</div><h2>Concepts</h2>">>,
            concept_rows(maps:get(<<"concepts">>, Data))
        ],
    docs_page_html(<<"HyperBEAM Node Info">>, <<"/docs">>, node_sidebar(Devices, <<"/docs">>), Content).

render_device_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Schema = maps:get(<<"schema">>, Data),
    SchemaOrder = maps:get(<<"schema-order">>, Data, []),
    Recipes = maps:get(<<"recipes">>, Data),
    Spec = maps:get(<<"spec">>, Data),
    Content =
        [
            <<"<p class=\"eyebrow\">Device</p><h1>~">>,
            esc(maps:get(<<"id">>, Device)),
            <<"</h1>">>,
            device_summary_paragraph(Data),
            schema_source_note(Data),
            <<"<h2 id=\"schema\">Schema</h2>">>,
            schema_table(DeviceID, Schema, SchemaOrder),
            schema_handlers(Data),
            render_spec_section(DeviceID, Spec),
            <<"<h2 id=\"recipes\">Recipes</h2><div class=\"hb-docs-card-grid\">">>,
            recipe_nav(DeviceID, Recipes),
            <<"</div>">>
        ],
    docs_page_html(
        <<"HyperBEAM Device Info">>,
        device_info_path(DeviceID),
        device_sidebar(Data, device_info_path(DeviceID)),
        Content
    ).

render_schema_index_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Schema = maps:get(<<"schema">>, Data, #{}),
    SchemaOrder = maps:get(<<"schema-order">>, Data, []),
    Content =
        [
            <<"<p class=\"eyebrow\">Schema</p><h1>~">>, esc(DeviceID),
            <<" schema</h1>">>,
            schema_source_note(Data),
            schema_table(DeviceID, Schema, SchemaOrder),
            schema_handlers(Data)
        ],
    docs_page_html(
        <<"HyperBEAM Schema">>,
        device_schema_path(DeviceID),
        device_sidebar(Data, device_schema_path(DeviceID)),
        Content
    ).

device_summary_paragraph(Data) ->
    case trim(maps:get(<<"summary">>, Data, <<>>)) of
        <<>> -> [];
        Summary -> [<<"<p>">>, esc(Summary), <<"</p>">>]
    end.

render_schema_key_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    Key = maps:get(<<"key">>, Payload),
    KeySchema = maps:get(<<"schema">>, Payload),
    Params = maps:get(<<"parameters">>, KeySchema, #{}),
    Content =
        [
            <<"<p class=\"eyebrow\">Schema Key</p><h1>~">>, esc(DeviceID),
            <<" / ">>, esc(Key), <<"</h1><p>">>,
            esc(maps:get(<<"description">>, KeySchema, <<>>)),
            <<"</p>">>,
            schema_arguments(KeySchema),
            <<"<h2>Request parameters</h2>">>,
            case maps:get(<<"schema-status">>, KeySchema, <<>>) of
                <<"unavailable">> -> <<"<p>Request parameters are not declared.</p>">>;
                _ -> params_table(DeviceID, Key, Params)
            end,
            schema_result(KeySchema)
        ],
    docs_page_html(
        <<"HyperBEAM Schema Key">>,
        device_schema_key_path(DeviceID, Key),
        device_sidebar(Data, device_schema_key_path(DeviceID, Key)),
        Content
    ).

%% @doc Show the function's argument roles and declared types.
schema_arguments(KeySchema) ->
    case maps:get(<<"arguments">>, KeySchema, []) of
        [] ->
            [<<"<p>">>, esc(maps:get(<<"schema-reason">>, KeySchema,
                <<"No extractable type specification is available for this key.">>)), <<"</p>">>];
        Arguments ->
            [
                <<"<h2>Arguments</h2><table><thead><tr><th>Argument</th>"
                    "<th>Type</th></tr></thead><tbody>">>,
                [
                    [<<"<tr><td>">>, esc(maps:get(<<"name">>, Argument)),
                        <<"</td><td><code>">>, esc(maps:get(<<"type">>, Argument)),
                        <<"</code></td></tr>">>]
                || Argument <- Arguments
                ],
                <<"</tbody></table>">>
            ]
    end.

%% @doc Keep return types and nested schemas inspectable in the HTML docs.
schema_result(KeySchema) ->
    [
        <<"<h2>Returns</h2>">>,
        schema_returns(KeySchema, detailed),
        case maps:find(<<"type-schema">>, KeySchema) of
            {ok, Schema} ->
                [
                    <<"<details><summary>Full extracted schema</summary>">>,
                    render_code_block(<<"json">>, [json:format(Schema, #{indent => 2})]),
                    <<"</details>">>
                ];
            error -> []
        end
    ].

%% @doc Render each possible result without exposing the compact schema grammar.
schema_returns(#{ <<"type-schema">> := #{ <<"return">> := Return } }, Mode) ->
    Cases = case Return of
        #{ <<"kind">> := <<"union">>, <<"members">> := Members } -> Members;
        _ -> [Return]
    end,
    [
        case {Mode, length(Cases)} of
            {detailed, Count} when Count > 1 ->
                <<"<p class=\"hb-schema-result-note\">Returns one of the following:</p>">>;
            _ -> []
        end,
        <<"<div class=\"hb-schema-results ">>, atom_to_binary(Mode), <<"\">">>,
        [schema_return_case(Case, Mode) || Case <- Cases],
        <<"</div>">>
    ];
schema_returns(_KeySchema, _Mode) ->
    <<"<span class=\"hb-schema-result-note\">Not declared</span>">>.

%% @doc Recognize tagged result tuples while preserving their extracted tag.
schema_return_case(#{ <<"kind">> := <<"tuple">>, <<"items">> := [
        #{ <<"kind">> := <<"literal">>, <<"value">> := Tag }, Payload
    ] }, Mode) ->
    {Tone, Title} = case Tag of
        <<"ok">> -> {<<"success">>, <<"Success">>};
        <<"error">> -> {<<"error">>, <<"Error">>};
        _ -> {<<"neutral">>, <<"Tagged result">>}
    end,
    [
        <<"<div class=\"hb-schema-result ">>, Tone, <<"\">">>,
        <<"<div class=\"hb-schema-result-heading\"><strong>">>, Title, <<"</strong>">>,
        case {Mode, Tone} of
            {compact, Known} when Known =/= <<"neutral">> -> [];
            _ -> [<<"<code class=\"hb-schema-result-tag\">">>,
                esc(json:encode(Tag)), <<"</code>">>]
        end,
        <<"</div>">>, schema_return_payload(Payload, Mode), <<"</div>">>
    ];
schema_return_case(Type, Mode) ->
    [<<"<div class=\"hb-schema-result neutral\">">>,
        schema_return_payload(Type, Mode), <<"</div>">>].

schema_return_payload(Type, detailed) -> schema_type_tree(Type);
schema_return_payload(Type, compact) ->
    [<<"<span class=\"hb-schema-result-type\">">>, esc(schema_type_text(Type)), <<"</span>">>].

%% @doc Expand message fields and nested containers into readable type trees.
schema_type_tree(#{ <<"kind">> := <<"message">>, <<"keys">> := Fields } = Type) ->
    [
        <<"<span class=\"hb-schema-type-label\">Message</span><dl class=\"hb-schema-fields\">">>,
        [
            [<<"<div><dt><code>">>, esc(Name), <<"</code><span>">>,
                esc(maps:get(<<"presence">>, Field, <<"optional">>)),
                <<"</span></dt><dd>">>, schema_type_tree(maps:get(<<"type">>, Field)),
                <<"</dd></div>">>]
        || {Name, Field} <- lists:sort(maps:to_list(Fields))
        ],
        case maps:get(<<"wildcard">>, Type, <<"none">>) of
            #{ <<"type">> := Other } ->
                [<<"<div><dt>Other fields</dt><dd>">>, schema_type_tree(Other), <<"</dd></div>">>];
            _ -> []
        end,
        <<"</dl>">>
    ];
schema_type_tree(#{ <<"kind">> := <<"union">>, <<"members">> := Members }) ->
    [<<"<span class=\"hb-schema-type-label\">One of</span><ul class=\"hb-schema-type-list\">">>,
        [[<<"<li>">>, schema_type_tree(Member), <<"</li>">>] || Member <- Members], <<"</ul>">>];
schema_type_tree(#{ <<"kind">> := <<"tuple">>, <<"items">> := Items }) ->
    [<<"<span class=\"hb-schema-type-label\">Tuple, in this order</span><ol class=\"hb-schema-type-list\">">>,
        [[<<"<li>">>, schema_type_tree(Item), <<"</li>">>] || Item <- Items], <<"</ol>">>];
schema_type_tree(#{ <<"kind">> := <<"list">>, <<"item">> := Item }) ->
    [<<"<span class=\"hb-schema-type-label\">List of</span><div class=\"hb-schema-type-item\">">>,
        schema_type_tree(Item), <<"</div>">>];
schema_type_tree(Type) ->
    [<<"<span class=\"hb-schema-type-label\">">>, esc(schema_type_text(Type)), <<"</span>">>].

%% @doc Short labels for result summaries; the full schema retains exact types.
schema_type_text(#{ <<"kind">> := <<"message">> }) -> <<"Message">>;
schema_type_text(#{ <<"kind">> := <<"wildcard">> }) -> <<"Unspecified (_)">>;
schema_type_text(#{ <<"kind">> := <<"any">> }) -> <<"Any value">>;
schema_type_text(#{ <<"kind">> := <<"literal">>, <<"value">> := Value }) -> json:encode(Value);
schema_type_text(#{ <<"kind">> := <<"union">>, <<"members">> := Members }) ->
    lists:join(<<" or ">>, [schema_type_text(Member) || Member <- Members]);
schema_type_text(#{ <<"kind">> := <<"tuple">>, <<"items">> := Items }) ->
    [<<"{">>, lists:join(<<", ">>, [schema_type_text(Item) || Item <- Items]), <<"}">>];
schema_type_text(#{ <<"kind">> := <<"list">>, <<"item">> := Item }) ->
    [<<"List of ">>, schema_type_text(Item)];
schema_type_text(#{ <<"kind">> := <<"range">>, <<"min">> := Min, <<"max">> := Max }) ->
    [hb_util:bin(Min), <<" to ">>, hb_util:bin(Max)];
schema_type_text(#{ <<"kind">> := <<"remote">>, <<"module">> := Module, <<"name">> := Name }) ->
    [Module, <<":">>, Name];
schema_type_text(#{ <<"name">> := Name }) -> Name;
schema_type_text(#{ <<"kind">> := Kind }) ->
    binary:replace(Kind, <<"_">>, <<" ">>, [global]);
schema_type_text(_) -> <<"Unspecified">>.

%% @doc Document catch-all functions without presenting their names as API keys.
schema_handlers(Data) ->
    case maps:get(<<"schema-handlers">>, Data, #{}) of
        Handlers when map_size(Handlers) =:= 0 -> [];
        Handlers ->
            [
                <<"<h2 id=\"handlers\">Handlers</h2><p>These functions handle keys "
                    "selected by device dispatch. Their function names are not "
                    "a list of callable API keys.</p>">>,
                [
                    [
                        <<"<details><summary>">>, esc(Kind), <<" handler: ">>,
                        esc(maps:get(<<"function">>, Handler)), <<"/">>,
                        hb_util:bin(maps:get(<<"arity">>, Handler)), <<"</summary>">>,
                        schema_arguments(Handler),
                        <<"<h3>Request parameters</h3>">>,
                        handler_parameters(Handler),
                        schema_result(Handler),
                        <<"</details>">>
                    ]
                || {Kind, Handler} <- lists:sort(maps:to_list(Handlers))
                ]
            ]
    end.

%% @doc Handler parameters have no invented callable-key URLs.
handler_parameters(#{ <<"schema-status">> := <<"unavailable">> }) ->
    <<"<p>Request parameters are not declared.</p>">>;
handler_parameters(Handler) ->
    [
        <<"<dl>">>,
        [
            [<<"<dt><code>">>, esc(Name), <<"</code></dt><dd><code>">>,
                esc(maps:get(<<"type">>, Param)), <<"</code> — ">>,
                case maps:get(<<"required">>, Param) of
                    true -> <<"required">>;
                    false -> <<"optional">>
                end,
                <<"</dd>">>]
        || {Name, Param} <- lists:sort(maps:to_list(maps:get(<<"parameters">>, Handler)))
        ],
        <<"</dl>">>
    ].

render_schema_parameter_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    Key = maps:get(<<"key">>, Payload),
    Param = maps:get(<<"parameter">>, Payload),
    ParamSchema = maps:get(<<"schema">>, Payload),
    Content =
        [
            <<"<p class=\"eyebrow\">Schema Parameter</p><h1>~">>, esc(DeviceID),
            <<" / ">>, esc(Key), <<" / ">>, esc(Param), <<"</h1>">>,
            <<"<table><tbody>">>,
            <<"<tr><th>Name</th><td><code>">>, esc(Param), <<"</code></td></tr>">>,
            <<"<tr><th>Required</th><td>">>,
            case maps:get(<<"required">>, ParamSchema, false) of
                true -> <<"yes">>;
                false -> <<"no">>
            end,
            <<"</td></tr><tr><th>Type</th><td>">>,
            esc(maps:get(<<"type">>, ParamSchema, <<>>)),
            <<"</td></tr>">>,
            [
                [
                    <<"<tr><th>">>, Label, <<"</th><td>">>,
                    param_metadata_value(Field, ParamSchema),
                    <<"</td></tr>">>
                ]
            || {Field, Label} <- param_metadata_fields([ParamSchema])
            ],
            <<"</tbody></table>">>
        ],
    docs_page_html(
        <<"HyperBEAM Schema Parameter">>,
        device_schema_key_path(DeviceID, Key),
        device_sidebar(Data, device_schema_key_path(DeviceID, Key)),
        Content
    ).

render_spec_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Content =
        [
            <<"<p class=\"eyebrow\">Specification</p><h1>~">>, esc(DeviceID),
            <<" spec</h1>">>,
            render_spec_body(maps:get(<<"spec">>, Data, #{}))
        ],
    docs_page_html(
        <<"HyperBEAM Spec">>,
        device_spec_path(DeviceID),
        device_sidebar(Data, device_spec_path(DeviceID)),
        Content
    ).

render_spec_section_page_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    SectionId = maps:get(<<"section-id">>, Payload),
    Title = maps:get(<<"section-title">>, Payload),
    Spec = maps:get(<<"spec">>, Payload),
    ActivePath = device_spec_section_path(DeviceID, SectionId),
    Content =
        [
            <<"<p class=\"eyebrow\">Specification</p><h1>">>, esc(DeviceID),
            <<" / ">>, esc(spec_section_nav_label(Title)), <<"</h1>">>,
            spec_tx_link_paragraph(Spec),
            render_markdown_with_heading_ids(spec_section_markdown(Spec, SectionId), #{
                <<"strip-numbered-headings">> => true
            })
        ],
    docs_page_html(<<"HyperBEAM Spec">>, ActivePath, device_sidebar(Data, ActivePath), Content).

render_recipes_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    Content =
        [
            <<"<p class=\"eyebrow\">Recipes</p><h1>~">>, esc(DeviceID),
            <<" recipes</h1><div class=\"hb-docs-card-grid\">">>,
            recipe_nav(DeviceID, Recipes),
            <<"</div>">>
        ],
    docs_page_html(
        <<"HyperBEAM Recipes">>,
        device_recipes_path(DeviceID),
        device_sidebar(Data, device_recipes_path(DeviceID)),
        Content
    ).

render_recipe_html(Payload) ->
    Data = maps:get(<<"device-data">>, Payload),
    Device = maps:get(<<"device">>, Payload),
    DeviceID = maps:get(<<"id">>, Device),
    Slug = maps:get(<<"slug">>, Payload),
    Recipe = maps:get(<<"recipe">>, Payload),
    ActivePath = device_recipe_path(DeviceID, Slug),
    Content =
        [
            <<"<p class=\"eyebrow\">Recipe</p><h1>">>, esc(DeviceID),
            <<" / ">>, esc(maps:get(<<"title">>, Recipe, Slug)), <<"</h1>">>,
            on_chain_link_paragraph(Recipe, <<"View recipe transaction">>),
            render_markdown(
                drop_first_h1(recipe_markdown(Recipe)),
                #{ <<"source-relative">> => maps:get(<<"source-relative">>, Recipe, undefined) }
            )
        ],
    docs_page_html(<<"HyperBEAM Recipe">>, ActivePath, device_sidebar(Data, ActivePath), Content).

render_implementations_html(Data) ->
    Device = maps:get(<<"device">>, Data),
    DeviceID = maps:get(<<"id">>, Device),
    Implementations = maps:get(<<"implementations">>, Data, []),
    Content =
        [
            <<"<p class=\"eyebrow\">Implementations</p><h1>~">>, esc(DeviceID),
            <<" implementations</h1><table><thead><tr><th>Name</th><th>Module</th>"
                "<th>Source</th><th>Status</th></tr></thead><tbody>">>,
            [
                [
                    <<"<tr><td>">>, esc(maps:get(<<"name">>, Impl, <<>>)),
                    <<"</td><td><code>">>, esc(maps:get(<<"module">>, Impl, <<>>)),
                    <<"</code></td><td>">>, implementation_source_cell(Impl),
                    <<"</td><td>">>, esc(maps:get(<<"status">>, Impl, <<>>)),
                    <<"</td></tr>">>
                ]
            || Impl <- Implementations
            ],
            <<"</tbody></table>">>
        ],
    docs_page_html(
        <<"HyperBEAM Implementations">>,
        device_implementations_path(DeviceID),
        device_sidebar(Data, device_implementations_path(DeviceID)),
        Content
    ).

render_node_component_html(Title, ActivePath, Data) ->
    Devices = maps:get(<<"devices">>, Data, []),
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>">>, esc(Title),
            <<" index</h1><div class=\"hb-docs-device-grid\">">>,
            [device_row(Device) || Device <- Devices],
            <<"</div>">>
        ],
    docs_page_html(
        <<"HyperBEAM Node Index">>, ActivePath, node_sidebar_from_component(Devices, ActivePath), Content
    ).

render_node_boilerplate_html(Data) ->
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>Guides</h1><p>">>,
            esc(maps:get(<<"summary">>, Data, <<>>)),
            <<"</p>">>,
            boilerplate_section_cards(Data, h2)
        ],
    docs_page_html(
        <<"HyperBEAM Guides">>, <<"/docs/guides">>, node_sidebar([], <<"/docs/guides">>), Content
    ).

render_node_boilerplate_page_html(Data) ->
    Markdown = maps:get(<<"markdown">>, Data, <<>>),
    ActivePath = maps:get(<<"href">>, Data, <<"/docs/guides">>),
    Content =
        [
            <<"<p class=\"eyebrow\">Guide</p><h1>">>,
            esc(maps:get(<<"title">>, Data, <<>>)),
            <<"</h1>">>,
            render_markdown(
                drop_first_h1(Markdown),
                #{ <<"source-relative">> => maps:get(<<"source-relative">>, Data, undefined) }
            )
        ],
    docs_page_html(<<"HyperBEAM Guide">>, ActivePath, node_sidebar([], ActivePath), Content).

render_node_concepts_html(Data) ->
    Concepts = maps:get(<<"concepts">>, Data, #{}),
    Content =
        [
            <<"<p class=\"eyebrow\">Node</p><h1>Concepts</h1>">>,
            concept_rows(Concepts)
        ],
    docs_page_html(
        <<"HyperBEAM Concepts">>, <<"/docs/concepts">>, node_sidebar([], <<"/docs/concepts">>), Content
    ).

render_node_concept_html(Data) ->
    Concept = maps:get(<<"concept">>, Data, <<>>),
    ActivePath = <<"/docs/concepts/", Concept/binary>>,
    Content =
        [
            <<"<p class=\"eyebrow\">Concept</p><h1>">>, esc(Concept),
            <<"</h1><p>">>, esc(maps:get(<<"description">>, Data, <<>>)), <<"</p>">>
        ],
    docs_page_html(<<"HyperBEAM Concept">>, ActivePath, node_sidebar([], ActivePath), Content).

render_unsupported_device_html(Device) ->
    ActivePath = device_info_path(Device),
    Content =
        [
            <<"<p class=\"eyebrow\">Device</p><h1>">>,
            esc(device_marked_id(Device)),
            <<" docs not available</h1><p>No on-weave spec-loaded documentation is "
                "available for this device.</p><p><a href=\"/docs\">View All Node Info</a></p>">>
        ],
    docs_page_html(<<"HyperBEAM Device Docs Not Available">>, ActivePath, node_sidebar([], ActivePath), Content).

docs_page_html(Title, ActivePath, Sidebar, Content) ->
    iolist_to_binary([
        html_head(Title),
        <<"<body class=\"ready sticky hb-docs-protocol close\" data-active-path=\"">>,
        esc(ActivePath),
        <<"\">">>,
        docs_site_header(),
        docs_mobile_nav_drawer(),
        <<"<main>">>,
        docs_sidebar(Sidebar),
        <<"<section class=\"content\"><article class=\"markdown-section\" id=\"main\">">>,
        Content,
        <<"</article></section></main>">>,
        docs_shell_assets(),
        <<"</body></html>">>
    ]).

docs_site_header() ->
    <<
        "<header class=\"site-header\" id=\"site-header\">"
        "<div class=\"site-header-top\">"
        "<div class=\"site-header-start\">"
        "<a class=\"site-brand site-header-home\" href=\"/docs\">View All Node Info</a>"
        "</div>"
        "<div class=\"site-header-actions\">"
        "<button type=\"button\" class=\"mobile-menu-toggle\" id=\"mobile-menu-toggle\" "
        "aria-label=\"Open sections menu\" aria-expanded=\"false\" aria-controls=\"mobile-nav-panel\">"
        "<svg viewBox=\"0 0 256 256\" fill=\"currentColor\" aria-hidden=\"true\">"
        "<path d=\"M40,88a8,8,0,0,1,8-8H208a8,8,0,0,1,0,16H48A8,8,0,0,1,40,88Zm0,80a8,8,0,0,1,8-8H168a8,8,0,0,1,0,16H48A8,8,0,0,1,40,168Z\"/>"
        "</svg>"
        "</button>"
        "</div>"
        "</div>"
        "</header>"
    >>.

docs_mobile_nav_drawer() ->
    <<
        "<div class=\"mobile-nav-drawer\" id=\"mobile-nav-drawer\" aria-hidden=\"true\">"
        "<div class=\"mobile-nav-backdrop\" data-mobile-nav-close></div>"
        "<nav class=\"mobile-nav-panel\" id=\"mobile-nav-panel\" aria-label=\"Documentation sections\">"
        "<div class=\"mobile-nav-panel-header\">"
        "<span class=\"mobile-nav-panel-title\">Sections</span>"
        "<button type=\"button\" class=\"mobile-nav-close\" data-mobile-nav-close "
        "aria-label=\"Close menu\">"
        "<svg viewBox=\"0 0 256 256\" fill=\"currentColor\" aria-hidden=\"true\">"
        "<path d=\"M205.66,194.34a8,8,0,0,1-11.32,11.32L128,139.31,61.66,205.66a8,8,0,0,1-11.32-11.32L116.69,128,50.34,61.66A8,8,0,0,1,61.66,50.34L128,116.69l66.34-66.35a8,8,0,0,1,11.32,11.32L139.31,128Z\"/>"
        "</svg>"
        "</button>"
        "</div>"
        "<div class=\"mobile-nav-panel-body\" id=\"mobile-nav-body\">"
        "<div class=\"mobile-nav-tabs\" id=\"mobile-nav-tabs\">"
        "<a class=\"mobile-nav-home\" href=\"/docs\">View All Node Info</a>"
        "</div>"
        "<div class=\"mobile-nav-search\" id=\"mobile-nav-search\">"
        "<div class=\"mobile-nav-search-wrap\">"
        "<span class=\"mobile-nav-search-icon\" aria-hidden=\"true\">"
        "<svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" "
        "stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"
        "<path d=\"m21 21-4.34-4.34\"/>"
        "<circle cx=\"11\" cy=\"11\" r=\"8\"/>"
        "</svg>"
        "</span>"
        "<input type=\"search\" id=\"mobile-nav-search-input\" class=\"mobile-nav-search-input\" "
        "placeholder=\"Search docs...\" autocomplete=\"off\" aria-label=\"Search documentation\">"
        "</div>"
        "</div>"
        "<div class=\"mobile-nav-list\" id=\"mobile-nav-list\"></div>"
        "</div>"
        "</nav>"
        "</div>"
    >>.

html_head(Title) ->
    [
        <<"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            "<title>">>,
        esc(Title),
        <<"</title>"
            "<link rel=\"preload\" href=\"/docs/assets/fonts/dm-sans-400.woff2\" "
            "as=\"font\" type=\"font/woff2\" crossorigin>"
            "<link rel=\"preload\" href=\"/docs/assets/fonts/dm-sans-500.woff2\" "
            "as=\"font\" type=\"font/woff2\" crossorigin>"
            "<link rel=\"preload\" href=\"/docs/assets/fonts/dm-sans-600.woff2\" "
            "as=\"font\" type=\"font/woff2\" crossorigin>"
            "<link rel=\"stylesheet\" href=\"/docs/assets/fonts.css\">"
            "<link rel=\"stylesheet\" href=\"/docs/assets/docsify-vue.css\">"
            "<link rel=\"stylesheet\" href=\"/docs/assets/prism.css\">"
            "<link rel=\"stylesheet\" href=\"/docs/assets/site.css\">"
            "<style>">>,
        dev_hyperbeam_docs_data_overrides_css(),
        <<"</style></head>">>
    ].

dev_hyperbeam_docs_data_overrides_css() ->
    <<"
body.hb-docs-protocol {
  background: var(--bg);
  color: var(--text);
  --text-page-title: clamp(1.28125rem, 0.7rem + 2.3vw, 1.875rem);
  --text-section-title: clamp(1.046875rem, 0.605rem + 1.65vw, 1.3125rem);
  --text-subheading: clamp(0.9375rem, 1.2vw, 1.0625rem);
  --text-lead: clamp(0.90625rem, 1.05vw, 1rem);
  --text-body: clamp(0.8125rem, 0.925vw, 0.875rem);
  --text-ui: clamp(0.75rem, 0.875vw, 0.8125rem);
  --text-caption: clamp(0.6875rem, 0.8vw, 0.75rem);
}
body.hb-docs-protocol .site-header { display: none; }
body.hb-docs-protocol .sidebar { top: 0 !important; }
body.hb-docs-protocol .sidebar > h1 { display: none; }
body.hb-docs-protocol .content {
  padding-top: 0 !important;
}
@media (max-width: 1200px) {
  body.hb-docs-protocol .content {
    right: 0 !important;
  }
}
@media (min-width: 1201px) {
  body.hb-docs-protocol .content {
    right: 0 !important;
  }
  body.hb-docs-protocol.page-toc-active .content {
    right: calc(var(--toc-width) + var(--layout-inline-padding)) !important;
  }
  body.hb-docs-protocol.page-toc-active .page-toc {
    top: 28px;
    max-height: calc(100vh - 40px);
  }
}
body.hb-docs-protocol .content .markdown-section,
body.hb-docs-protocol .markdown-section {
  max-width: var(--content-max) !important;
  margin: 0 auto !important;
  width: auto !important;
  box-sizing: border-box;
}
body.hb-docs-protocol .content .markdown-section { padding-top: 36px !important; }
body.hb-docs-protocol .markdown-section table {
  width: 100%;
  max-width: 100%;
}
body.hb-docs-protocol .markdown-section h3 {
  font-size: 1.025rem !important;
}
body.hb-docs-protocol .page-toc-links a[data-level='h2'] {
  font-size: var(--text-body);
}
body.hb-docs-protocol .page-toc-links a[data-level='h3'] {
  font-size: var(--text-caption);
}
body.hb-docs-protocol .site-header-nav-zone { display: none; }
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child > a {
  padding-left: var(--sidebar-link-pad-x) !important;
  padding-right: var(--sidebar-link-pad-x) !important;
  color: var(--sidebar-link-color) !important;
  opacity: 1;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li > a:hover,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child > a:hover {
  color: var(--sidebar-link-hover-color) !important;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li.active > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li.active > a:hover,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child.active > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:first-child.active > a:hover {
  color: var(--sidebar-link-active-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 600 !important;
  opacity: 1;
  padding-left: var(--sidebar-link-pad-x) !important;
  padding-right: var(--sidebar-link-pad-x) !important;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child) > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child) > a:hover,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a:hover {
  padding-left: var(--sidebar-link-pad-x) !important;
  padding-right: var(--sidebar-link-pad-x) !important;
  color: var(--sidebar-link-color) !important;
  opacity: 1;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a,
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-flat-links > ul > li:not(:first-child).active > a:hover {
  color: var(--sidebar-link-active-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 600 !important;
  opacity: 1;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child) > a {
  color: var(--sidebar-nested-link-color) !important;
  opacity: 0.72;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child) > a:hover {
  color: var(--sidebar-link-hover-color) !important;
  opacity: 0.88;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child).active > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li:not(:first-child).active > a:hover {
  color: var(--sidebar-nested-link-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 500 !important;
  opacity: 0.9;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li > ul a {
  color: var(--sidebar-nested-link-color) !important;
  opacity: 0.58;
}
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li > ul li.active > a,
body.hb-docs-protocol .sidebar-nav > ul > li > ul > li > ul li.active > a:hover {
  color: var(--sidebar-nested-link-color) !important;
  background: var(--sidebar-link-active-bg) !important;
  font-weight: 500 !important;
  opacity: 0.78;
}
body.hb-docs-protocol .sidebar-nav > ul > li.sidebar-viewing-context {
  margin: 0 0 10px !important;
}
body.hb-docs-protocol .sidebar-viewing-context {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 2px 0 14px;
  border-bottom: 1px solid var(--border);
}
body.hb-docs-protocol .sidebar-viewing-context .eyebrow {
  margin: 0 !important;
  padding: 0 !important;
  color: var(--text-tertiary) !important;
  font-size: var(--text-caption) !important;
  font-weight: 400 !important;
  line-height: 1.15;
  letter-spacing: 0 !important;
  text-transform: none !important;
}
body.hb-docs-protocol .sidebar-viewing-context > a {
  padding: 0 !important;
  text-transform: none !important;
}
body.hb-docs-protocol .sidebar-viewing-device {
  display: block;
  padding: 0 !important;
  color: var(--text) !important;
  font-size: var(--text-body) !important;
  font-weight: 600 !important;
  line-height: 1.25;
  letter-spacing: -0.02em;
  text-decoration: none !important;
  transition: opacity 100ms ease;
}
body.hb-docs-protocol .sidebar-viewing-context > a,
body.hb-docs-protocol .sidebar-viewing-context.active > a,
body.hb-docs-protocol li.sidebar-viewing-context.active > a,
body.hb-docs-protocol .sidebar-viewing-context > a.is-active,
body.hb-docs-protocol .sidebar-viewing-context > a.is-active:hover,
body.hb-docs-protocol li.sidebar-viewing-context.active > a:hover {
  background: transparent !important;
  border: none !important;
}
body.hb-docs-protocol .sidebar-viewing-device:hover {
  opacity: 0.72;
}
body.hb-docs-protocol .sidebar-viewing-device.is-active {
  color: var(--text) !important;
}
body.hb-docs-protocol .sidebar-viewing-back {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 0;
  padding: 0 !important;
  color: var(--sidebar-link-color) !important;
  font-size: var(--text-ui) !important;
  font-weight: 400 !important;
  line-height: 1.25;
  letter-spacing: -0.02em;
  text-decoration: none !important;
  transition: opacity 100ms ease, color 100ms ease;
}
body.hb-docs-protocol .sidebar-viewing-back-icon {
  flex: 0 0 auto;
  width: 13px;
  height: 13px;
  opacity: 0.62;
}
body.hb-docs-protocol .sidebar-viewing-back-icon svg {
  display: block;
  width: 100%;
  height: 100%;
}
body.hb-docs-protocol .sidebar-viewing-back:hover {
  color: var(--sidebar-link-hover-color) !important;
  opacity: 0.72;
}
body.hb-docs-protocol .sidebar-viewing-device + .sidebar-viewing-back {
  margin-top: 16px;
}
body.hb-docs-protocol .sidebar-viewing-back + .sidebar-viewing-back {
  margin-top: 6px;
}
body.hb-docs-protocol .sidebar-viewing-back.is-active {
  color: var(--sidebar-link-active-color) !important;
}
.hb-docs-guide-section {
  margin: 0 0 2rem;
}
.hb-docs-guide-section:last-child {
  margin-bottom: 0;
}
.hb-docs-guide-section > h2,
.hb-docs-guide-section > h3 {
  margin: 0 0 0.75rem;
}
.hb-docs-guide-section .hb-docs-card-grid {
  margin-top: 0;
}
.hb-docs-section-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin: 0 0 0.75rem;
}
.hb-docs-section-header h2 {
  margin: 0;
}
.hb-docs-section-link {
  flex: 0 0 auto;
  font-size: var(--text-caption);
  font-weight: 500;
  color: var(--text-secondary) !important;
  text-decoration: none !important;
}
.hb-docs-section-link:hover {
  color: var(--text) !important;
}
.markdown-section .theme-invert-video {
  width: 100%;
  height: auto;
  display: block;
  margin: 0 0 1.5rem;
  background: var(--bg-muted);
}
@media (prefers-color-scheme: dark) {
  .markdown-section .theme-invert-video {
    filter: invert(1) hue-rotate(180deg);
    background: #000;
  }
}
.markdown-section .core-concepts-flex {
  display: flex;
  align-items: flex-start;
  gap: 2rem;
  width: 100%;
  margin: 1.75rem 0 2rem;
}
.markdown-section .core-concepts-fig {
  flex: 1 0 100px;
  width: 100px;
  max-width: 160px !important;
  height: auto;
  margin: 0.25rem 0 0;
}
.markdown-section .core-concepts-column {
  display: flex;
  flex: 1 1 auto;
  min-width: 0;
  flex-direction: column;
}
.markdown-section .core-concepts-column p {
  margin: 0 0 1rem;
}
.markdown-section .core-concept-header-messages,
.markdown-section .core-concept-header-devices,
.markdown-section .core-concept-header-paths {
  margin: 0 0 0.25rem;
  line-height: 1.25;
}
.markdown-section .core-concept-subtitle {
  margin: 0 0 1rem;
  color: var(--text-tertiary);
  font-size: var(--text-caption);
  line-height: 1.3;
}
.markdown-section .core-concept-copy {
  line-height: 1.65;
}
.hb-docs-device-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 260px), 1fr));
  gap: 20px;
  margin: 0 0 2rem;
}
.markdown-section a.hb-docs-device-card,
.markdown-section a.hb-docs-device-card:hover,
.markdown-section a.hb-docs-device-card strong,
.markdown-section a.hb-docs-device-card span {
  text-decoration: none !important;
}
.hb-docs-device-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 0;
  border: none;
  border-radius: 0;
  background: transparent;
  color: var(--text) !important;
  text-decoration: none !important;
}
.hb-docs-device-card:hover {
  background: transparent;
}
.hb-docs-device-tint-0 {
  --device-card-accent: #c45c68;
}
.hb-docs-device-tint-1 {
  --device-card-accent: #2a7db5;
}
.hb-docs-device-tint-2 {
  --device-card-accent: #d46a42;
}
.hb-docs-device-tint-3 {
  --device-card-accent: #4a56b8;
}
.hb-docs-device-tint-4 {
  --device-card-accent: #2d8a5c;
}
.hb-docs-device-tint-5 {
  --device-card-accent: #6b8f1a;
}
.hb-docs-device-tint-6 {
  --device-card-accent: #0072c8;
}
.hb-docs-device-tint-7 {
  --device-card-accent: #c75a38;
}
.hb-docs-device-card-body {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-height: 168px;
}
.hb-docs-device-card-title-row {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 8px;
}
.hb-docs-device-card-title {
  font-size: var(--text-ui);
  font-weight: 700;
  color: var(--text);
}
.hb-docs-device-card-id {
  font-size: var(--text-ui);
  font-weight: 600;
  color: var(--device-card-accent, var(--text-secondary));
  letter-spacing: -0.02em;
}
.hb-docs-device-card-desc {
  font-size: var(--text-caption);
  line-height: 1.45;
  color: var(--text-secondary);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.hb-docs-reference-list {
  margin: 0;
}
.hb-docs-reference-section > h2 {
  margin: 0 0 0.75rem;
}
.markdown-section .hb-docs-reference-item {
  margin: 0 0 1rem;
  font-size: inherit;
  line-height: inherit;
}
.markdown-section .hb-docs-reference-item:last-child {
  margin-bottom: 0;
}
.markdown-section .hb-docs-reference-item a,
.markdown-section .hb-docs-reference-item a:hover,
.markdown-section .hb-docs-reference-item a strong {
  text-decoration: none !important;
  color: var(--text);
  font-size: inherit;
}
.markdown-section .hb-docs-reference-item a:hover {
  opacity: 0.72;
}
.hb-docs-guide-list-desc {
  font-size: inherit;
  line-height: inherit;
  color: var(--text-secondary);
  font-weight: 400;
  opacity: 0.8;
}
.hb-docs-card-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  margin: 1rem 0 1.5rem;
}
@media (max-width: 640px) {
  .hb-docs-card-grid {
    grid-template-columns: 1fr;
  }
}
.markdown-section a.hb-docs-card,
.markdown-section a.hb-docs-card:hover,
.markdown-section a.hb-docs-card strong,
.markdown-section a.hb-docs-card span,
.markdown-section a.hb-docs-card small,
.markdown-section a.hb-docs-recipe-card .hb-docs-recipe-card-cta {
  text-decoration: none !important;
}
.hb-docs-card {
  display: flex;
  flex-direction: column;
  gap: 0;
  min-height: 168px;
  height: 100%;
  padding: 14px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg);
  color: var(--text) !important;
  text-decoration: none !important;
}
.hb-docs-card:hover { background: var(--bg-hover); }
.hb-docs-card span,
.hb-docs-card small { color: var(--text-secondary); }
.hb-docs-recipe-card {
  gap: 8px;
}
.hb-docs-recipe-card-header {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.hb-docs-recipe-card-icon {
  flex: 0 0 20px;
  width: 20px;
  height: 20px;
  color: var(--text-secondary);
  line-height: 0;
}
.hb-docs-recipe-card-icon svg {
  display: block;
  width: 100%;
  height: 100%;
}
.hb-docs-recipe-card-title {
  min-width: 0;
  line-height: 1.3;
}
.hb-docs-recipe-card-body {
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  gap: 8px;
  min-height: 0;
}
.hb-docs-recipe-card-desc {
  flex: 0 1 auto;
  font-size: var(--text-caption);
  line-height: 1.45;
  color: var(--text-secondary);
}
.hb-docs-recipe-card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: auto;
  width: 100%;
}
.hb-docs-recipe-card-cta {
  flex: 0 0 auto;
  font-size: var(--text-caption);
  font-weight: 500;
  color: var(--text-secondary);
}
.hb-docs-recipe-card-meta {
  flex: 0 0 auto;
  margin-left: auto;
  font-size: var(--text-caption);
  color: var(--text-tertiary);
  text-align: right;
  white-space: nowrap;
}
.hb-docs-chain-link-row {
  margin: 0.5rem 0 1rem;
}
.markdown-section a.hb-docs-chain-link,
.markdown-section a.hb-docs-chain-link:hover,
.markdown-section a.hb-docs-chain-link span {
  text-decoration: none !important;
}
.hb-docs-chain-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 24px;
  padding: 3px 9px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--bg-muted);
  color: var(--text-secondary) !important;
  font-size: var(--text-caption);
  font-weight: 600;
  line-height: 1.2;
}
.hb-docs-chain-link:hover {
  background: var(--bg-hover);
  color: var(--text) !important;
}
.hb-docs-chain-link-icon {
  flex: 0 0 14px;
  width: 14px;
  height: 14px;
  line-height: 0;
}
.hb-docs-chain-link-icon svg {
  display: block;
  width: 100%;
  height: 100%;
}
.hb-docs-guide-index {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr));
  column-gap: 28px;
  row-gap: 22px;
  margin: 1rem 0 2rem;
}
.hb-docs-guide-group {
  min-width: 0;
  padding-top: 12px;
  border-top: 1px solid var(--border);
}
.hb-docs-guide-group h3 {
  margin: 0 0 8px;
  font-size: 1rem;
  line-height: 1.3;
}
.hb-docs-guide-group ul {
  display: grid;
  gap: 6px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.hb-docs-guide-group li { margin: 0; }
.hb-docs-guide-group a {
  color: var(--text) !important;
  font-weight: 500;
  text-decoration: none !important;
}
.hb-docs-guide-group a:hover { text-decoration: underline !important; }
.hb-schema-results { display: grid; gap: 12px; margin: 12px 0 24px; }
.hb-schema-result {
  --result-accent: var(--border-strong);
  min-width: 0;
  padding: 18px 20px;
  border: 1px solid var(--border);
  border-left: 3px solid var(--result-accent);
  border-radius: 8px;
  background: var(--bg);
  overflow-wrap: anywhere;
}
.hb-schema-result.success { --result-accent: var(--positive); }
.hb-schema-result.error { --result-accent: var(--negative); }
.hb-schema-result-heading {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 10px;
}
.hb-schema-result-heading strong { font-size: 0.95rem; }
.hb-schema-result-tag { font-size: 0.8rem !important; }
.hb-schema-result-note { color: var(--text-secondary); font-size: 0.9rem; }
.hb-schema-type-label { font-size: 0.9rem; }
.markdown-section .hb-schema-fields { margin: 10px 0 0; }
.hb-schema-fields > div {
  display: grid;
  grid-template-columns: minmax(110px, 1fr) minmax(0, 2fr);
  gap: 12px;
  padding: 10px 0;
  border-top: 1px solid var(--border);
}
.hb-schema-fields dt { display: flex; align-items: baseline; flex-wrap: wrap; gap: 8px; }
.hb-schema-fields dt > span { color: var(--text-tertiary); font-size: 0.75rem; font-weight: 400; }
.markdown-section .hb-schema-fields dd { margin: 0; }
.markdown-section .hb-schema-type-list { margin: 6px 0 0; padding-left: 20px; }
.hb-schema-type-item { margin: 6px 0 0 12px; }
.hb-schema-results.compact { gap: 8px; margin: 0; }
.compact .hb-schema-result { padding: 0; border: 0; background: none; }
.compact .hb-schema-result-heading { margin-bottom: 2px; }
.compact .hb-schema-result-heading strong { font-size: 0.8rem; }
.hb-schema-result-type { color: var(--text-secondary); font-size: 0.85rem; }
@media (max-width: 600px) {
  .hb-schema-result { padding: 14px; }
  .hb-schema-fields > div { grid-template-columns: 1fr; gap: 5px; }
}
		.hb-docs-renderer-note {
		  color: var(--text-secondary);
		  font-size: var(--text-small);
	}
	.spec-meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin: 0.75rem 0 1rem;
}
.status {
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 0 8px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--bg-muted);
  color: var(--text-secondary);
  font-size: var(--text-caption);
  font-weight: 600;
  text-transform: uppercase;
}
.pill {
  display: inline-flex;
  align-items: center;
  min-height: 22px;
  padding: 0 8px;
  margin: 0 4px 4px 0;
  border: 1px solid transparent;
  border-radius: 999px;
  font-size: var(--text-caption);
  font-weight: 400;
  line-height: 1.3;
}
.pill-required {
  border-color: transparent;
  background: var(--tag-required-bg) !important;
  color: var(--tag-required-fg) !important;
}
.pill-optional {
  border-color: transparent;
  background: var(--tag-optional-bg) !important;
  color: var(--tag-optional-fg) !important;
}
.pill-tone-0 {
  background: var(--brand-pink-soft);
  color: var(--pill-tone-0-fg);
}
.pill-tone-1 {
  background: var(--brand-coral-soft);
  color: var(--pill-tone-1-fg);
}
.pill-tone-2 {
  background: var(--brand-sky-soft);
  color: var(--pill-tone-2-fg);
}
.pill-tone-3 {
  background: var(--brand-lime-soft);
  color: var(--pill-tone-3-fg);
}
.pill-tone-4 {
  background: var(--brand-mint-soft);
  color: var(--pill-tone-4-fg);
}
.pill-tone-5 {
  background: var(--brand-lavender-soft);
  color: var(--pill-tone-5-fg);
}
.pill-tone-6 {
  background: var(--brand-coral-soft);
  color: var(--pill-tone-6-fg);
}
.pill-tone-7 {
  background: var(--brand-sky-soft);
  color: var(--pill-tone-7-fg);
}
.param-pills-none {
  color: var(--text-tertiary);
  font-size: var(--text-caption);
  font-style: italic;
}
@media (max-width: 1000px) {
  body.hb-docs-protocol .site-header { display: block; }
  body.hb-docs-protocol.mobile-nav-open .site-header { z-index: 280; }
  body.hb-docs-protocol .site-header-home {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 500;
  }
  body.hb-docs-protocol .sidebar { top: var(--header-height) !important; }
  body.hb-docs-protocol .content { padding-top: var(--header-height) !important; }
}
">>.
docs_sidebar(Items) ->
    [
        <<"<aside class=\"sidebar\" id=\"sidebar\"><h1>HyperBEAM</h1>"
            "<div class=\"sidebar-nav\"><ul>">>,
        Items,
        <<"</ul></div></aside>">>
    ].

device_info_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs">>.
device_docs_route_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs">>.
device_schema_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/schema">>.
device_direct_schema_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/schema">>.
device_schema_key_path(DeviceID, Key) ->
    <<"/~", DeviceID/binary, "/docs/schema/", Key/binary>>.
device_spec_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/spec">>.
device_spec_section_path(DeviceID, SectionId) ->
    <<"/~", DeviceID/binary, "/docs/spec/", SectionId/binary>>.
device_recipes_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/recipes">>.
device_recipe_path(DeviceID, Slug) ->
    <<"/~", DeviceID/binary, "/docs/recipes/", Slug/binary>>.
device_implementations_path(DeviceID) ->
    <<"/~", DeviceID/binary, "/docs/implementations">>.
device_schema_param_path(DeviceID, Key, Param) ->
    <<(device_schema_key_path(DeviceID, Key))/binary, "/", Param/binary>>.

device_doc_links(DeviceID) ->
    #{
        <<"self">> => device_info_path(DeviceID),
        <<"docs">> => device_docs_route_path(DeviceID),
        <<"schema">> => device_schema_path(DeviceID),
        <<"schema-direct">> => device_direct_schema_path(DeviceID),
        <<"spec">> => device_spec_path(DeviceID),
        <<"recipes">> => device_recipes_path(DeviceID),
        <<"implementations">> => device_implementations_path(DeviceID)
    }.

device_doc_link_fields(DeviceID) ->
    Links = device_doc_links(DeviceID),
    #{
        <<"links">> => Links,
        <<"schema-link">> => maps:get(<<"schema">>, Links),
        <<"specification-link">> => maps:get(<<"spec">>, Links),
        <<"recipes-link">> => maps:get(<<"recipes">>, Links)
    }.

devices_index_path() ->
    <<"/docs#devices">>.

active_path_match(ActivePath, Href) when is_binary(ActivePath), is_binary(Href) ->
    ActivePath =:= Href.

sidebar_li(ActivePath, Href, Content) ->
    ActiveClass =
        case active_path_match(ActivePath, Href) of
            true -> <<" class=\"active\"">>;
            false -> <<>>
        end,
    [
        <<"<li">>, ActiveClass, <<"><a href=\"">>, esc(Href), <<"\">">>,
        Content,
        <<"</a></li>">>
    ].

node_sidebar_index_items() ->
    [
        {<<"/docs/schema">>, <<"Schema">>},
        {<<"/docs/spec">>, <<"Spec">>},
        {<<"/docs/recipes">>, <<"Recipes">>},
        {<<"/docs/implementations">>, <<"Implementations">>}
    ].

sidebar_nav_section(ActivePath, SectionLabel, AllLabel, AllHref, ItemLis) ->
    [
        <<"<li><p>">>, SectionLabel, <<"</p><ul>">>,
        sidebar_li(ActivePath, AllHref, AllLabel),
        ItemLis,
        <<"</ul></li>">>
    ].

phosphor_icon_path_svg(Icon) ->
    Path = maps:get(Icon, recipe_icon_paths()),
    [
        <<"<svg viewBox=\"0 0 256 256\" fill=\"currentColor\" focusable=\"false\">">>,
        <<"<path d=\"">>, Path, <<"\"></path></svg>">>
    ].

sidebar_context_link_class(ActivePath, Href, Base) ->
    case active_path_match(ActivePath, Href) of
        true -> <<Base/binary, " is-active">>;
        false -> Base
    end.

sidebar_viewing_icon_markup(Icon) ->
    [
        <<"<span class=\"sidebar-viewing-back-icon\" aria-hidden=\"true\">">>,
        phosphor_icon_path_svg(Icon),
        <<"</span>">>
    ].

sidebar_viewing_back_link(ActivePath, Href, Label, Icon) ->
    [
        <<"<a class=\"">>,
        sidebar_context_link_class(ActivePath, Href, <<"sidebar-viewing-back">>),
        <<"\" href=\"">>, esc(Href), <<"\">">>,
        sidebar_viewing_icon_markup(Icon),
        esc(Label),
        <<"</a>">>
    ].

sidebar_node_context(ActivePath) ->
    [
        <<"<li class=\"sidebar-viewing-context\">">>,
        <<"<p class=\"eyebrow\">You are viewing</p>">>,
        <<"<a class=\"">>,
        sidebar_context_link_class(ActivePath, <<"/docs">>, <<"sidebar-viewing-device">>),
        <<"\" href=\"/docs\">Node</a>">>,
        <<"</li>">>
    ].

sidebar_device_context(ActivePath, DeviceID) ->
    DeviceHref = device_info_path(DeviceID),
    DevicesHref = devices_index_path(),
    [
        <<"<li class=\"sidebar-viewing-context\">">>,
        <<"<p class=\"eyebrow\">You are viewing</p>">>,
        <<"<a class=\"">>,
        sidebar_context_link_class(ActivePath, DeviceHref, <<"sidebar-viewing-device">>),
        <<"\" href=\"">>, esc(DeviceHref), <<"\">">>,
        esc(device_marked_id(DeviceID)),
        <<"</a>">>,
        sidebar_viewing_back_link(ActivePath, DevicesHref, <<"View All Devices">>, <<"stack">>),
        sidebar_viewing_back_link(ActivePath, <<"/docs">>, <<"View All Node Info">>, <<"database">>),
        <<"</li>">>
    ].

node_sidebar(Devices, ActivePath) ->
    Boilerplate = boilerplate_index(),
    [
        sidebar_node_context(ActivePath),
        node_sidebar_devices_section(Devices, ActivePath),
        [
            <<"<li class=\"sidebar-flat-links\"><p>Indexes</p><ul>">>,
            [sidebar_li(ActivePath, Href, Label) || {Href, Label} <- node_sidebar_index_items()],
            <<"</ul></li>">>
        ],
        [
            <<"<li><p>Guides</p><ul>">>,
            boilerplate_sidebar_rows(Boilerplate),
            <<"</ul></li>">>
        ]
    ].

node_sidebar_devices_section(Devices, ActivePath) ->
    [
        <<"<li class=\"sidebar-flat-links\"><p>Devices</p><ul>">>,
        [
            sidebar_li(
                ActivePath,
                maps:get(<<"href">>, Device),
                esc(device_marked_id(device_card_label(Device)))
            )
        || Device <- Devices
        ],
        <<"</ul></li>">>
    ].

boilerplate_sidebar_rows(Index) ->
    Pages = maps:get(<<"pages">>, Index, []),
    [
        <<"<li><a href=\"/docs/guides\">All guides</a></li>">>,
        [
            boilerplate_sidebar_section(Section, Pages)
        || Section <- boilerplate_section_order()
        ]
    ].

boilerplate_sidebar_section(<<"Overview">>, Pages) ->
    case boilerplate_pages_for_section(<<"Overview">>, Pages) of
        [] ->
            [];
        [Page | _Rest] ->
            [
                <<"<li><a href=\"">>, esc(maps:get(<<"href">>, Page, <<>>)),
                <<"\">Overview</a></li>">>
            ]
    end;
boilerplate_sidebar_section(Section, Pages) ->
    case boilerplate_pages_for_section(Section, Pages) of
        [] ->
            [];
        SectionPages ->
            [
                <<"<li><p>">>, esc(Section), <<"</p><ul>">>,
                [
                    [
                        <<"<li><a href=\"">>, esc(maps:get(<<"href">>, Page, <<>>)),
                        <<"\">">>, esc(maps:get(<<"title">>, Page, <<>>)), <<"</a></li>">>
                    ]
                || Page <- SectionPages
                ],
                <<"</ul></li>">>
            ]
    end.

boilerplate_pages_for_section(Section, Pages) ->
    [
        Page
    || Page <- Pages,
       maps:get(<<"section">>, Page, <<>>) =:= Section
    ].

boilerplate_section_order() ->
    [
        <<"Introduction">>,
        <<"Processes">>,
        <<"Device Forge">>
    ].

index_section_li_open(ActivePath) ->
    NodeIndexPaths = [Href || {Href, _} <- node_sidebar_index_items()],
    case lists:member(ActivePath, NodeIndexPaths) of
        true -> <<"<li class=\"sidebar-flat-links active\">">>;
        false -> <<"<li class=\"sidebar-flat-links\">">>
    end.

node_sidebar_from_component(Devices, ActivePath) ->
    [
        sidebar_node_context(ActivePath),
        [
            index_section_li_open(ActivePath),
            <<"<p>Index</p><ul>">>,
            [
                sidebar_li(
                    ActivePath,
                    maps:get(<<"href">>, Device, <<>>),
                    esc(device_marked_id(maps:get(<<"device">>, Device, <<>>)))
                )
            || Device <- Devices
            ],
            <<"</ul></li>">>
        ]
    ].

device_sidebar(Data, ActivePath) ->
    Device = maps:get(<<"device">>, Data, #{}),
    DeviceID = maps:get(<<"id">>, Device, <<>>),
    SchemaOrder = maps:get(<<"schema-order">>, Data, []),
    Spec = maps:get(<<"spec">>, Data, #{}),
    SpecSections = spec_sections(Spec),
    Recipes = maps:get(<<"recipes">>, Data, #{}),
    [
        sidebar_device_context(ActivePath, DeviceID),
        sidebar_nav_section(
            ActivePath, <<"Schema">>, <<"All keys">>, device_schema_path(DeviceID),
            [sidebar_li(ActivePath, device_schema_key_path(DeviceID, Key), esc(Key)) || Key <- SchemaOrder]
        ),
        sidebar_nav_section(
            ActivePath, <<"Spec">>, <<"All spec">>, device_spec_path(DeviceID),
            [
                sidebar_li(
                    ActivePath,
                    device_spec_section_path(DeviceID, SectionId),
                    esc(spec_section_nav_label(Title))
                )
            || {SectionId, Title} <- SpecSections
            ]
        ),
        sidebar_nav_section(
            ActivePath, <<"Recipes">>, <<"All recipes">>, device_recipes_path(DeviceID),
            [
                sidebar_li(
                    ActivePath,
                    device_recipe_path(DeviceID, Slug),
                    esc(maps:get(<<"title">>, Recipe, Slug))
                )
            || {Slug, Recipe} <- lists:sort(maps:to_list(Recipes))
            ]
        )
    ].

device_row(Device) ->
    Label = device_card_label(Device),
    Title = device_card_title(Device),
    Summary = device_card_summary_text(Device),
    TintClass = device_tint_class(Label),
    [
        <<"<a class=\"hb-docs-device-card\" href=\"">>,
        esc(device_card_href(Device)),
        <<"\">">>,
        <<"<div class=\"hb-docs-device-card-body\">">>,
        <<"<div class=\"hb-docs-device-card-title-row ">>,
        TintClass,
        <<"\">">>,
        <<"<strong class=\"hb-docs-device-card-title\">">>,
        esc(Title),
        <<"</strong>">>,
        <<"<span class=\"hb-docs-device-card-id\">">>,
        esc(device_marked_id(Label)),
        <<"</span>">>,
        <<"</div>">>,
        <<"<span class=\"hb-docs-device-card-desc\">">>,
        esc(card_summary(Summary)),
        <<"</span></div></a>">>
    ].

device_card_label(#{<<"device">> := Id}) ->
    Id;
device_card_label(Device) ->
    <<(maps:get(<<"name">>, Device))/binary, "@",
        (maps:get(<<"version">>, Device))/binary>>.

device_marked_id(Label) when is_binary(Label) ->
    case Label of
        <<$~, _/binary>> -> Label;
        _ -> <<$~, Label/binary>>
    end.

device_card_href(Device) ->
    maps:get(<<"href">>, Device, <<>>).

device_card_title(#{<<"device">> := Id}) ->
    device_display_title(Id);
device_card_title(Device) ->
    device_display_title(maps:get(<<"name">>, Device, device_card_label(Device))).

device_card_summary_text(Device) ->
    maps:get(<<"summary">>, Device,
        maps:get(<<"schema">>, Device, maps:get(<<"href">>, Device, <<>>))).

device_display_names() ->
    #{
        <<"arweave">> => <<"Arweave">>,
        <<"message">> => <<"Message">>,
        <<"cookbook">> => <<"Cookbook">>
    }.

device_display_title(Id) when is_binary(Id) ->
    case maps:get(Id, device_display_names(), undefined) of
        undefined ->
            case binary:split(Id, <<"@">>) of
                [Name, _Version] -> device_display_title(Name);
                _ ->
                    case Id of
                        <<C, Rest/binary>> ->
                            <<(string:uppercase(<<C>>))/binary, Rest/binary>>;
                        _ ->
                            Id
                    end
            end;
        Title ->
            Title
    end.

device_tint_class(Label) ->
    Index = erlang:phash2(Label) rem 8,
    <<"hb-docs-device-tint-", (integer_to_binary(Index))/binary>>.

boilerplate_section_cards(Index, Heading) ->
    [
        boilerplate_section_block(Section, Pages, Heading)
    || {Section, Pages} <- boilerplate_grouped_pages(Index)
    ].

boilerplate_section_block(Section, Pages, Heading) ->
    Tag =
        case Section of
            <<"Reference">> -> <<"h2">>;
            _ -> boilerplate_section_heading_tag(Heading)
        end,
    SectionClass =
        case Section of
            <<"Reference">> -> <<" hb-docs-reference-section">>;
            _ -> <<>>
        end,
    {ContainerOpen, ContainerClose, RowFun} = boilerplate_section_layout(Section),
    [
        <<"<section class=\"hb-docs-guide-section">>, SectionClass, <<"\">">>,
        ["<", Tag, ">", esc(Section), "</", Tag, ">"],
        ContainerOpen,
        [RowFun(Page, Section) || Page <- Pages],
        ContainerClose,
        <<"</section>">>
    ].

boilerplate_section_layout(<<"Reference">>) ->
    {<<"<div class=\"hb-docs-reference-list\">">>, <<"</div>">>, fun boilerplate_list_row/2};
boilerplate_section_layout(_) ->
    {<<"<div class=\"hb-docs-card-grid\">">>, <<"</div>">>, fun boilerplate_card_row/2}.

boilerplate_section_heading_tag(h2) -> <<"h2">>;
boilerplate_section_heading_tag(h3) -> <<"h3">>;
boilerplate_section_heading_tag(_) -> <<"h2">>.

boilerplate_grouped_pages(Index) ->
    boilerplate_group_pages_by_section(maps:get(<<"pages">>, Index, []), []).

boilerplate_group_pages_by_section([], Acc) ->
    [{Section, lists:reverse(Pages)} || {Section, Pages} <- lists:reverse(Acc)];
boilerplate_group_pages_by_section([Page | Rest], Acc) ->
    Section = maps:get(<<"section">>, Page, <<>>),
    case Acc of
        [{Section, Pages} | Tail] ->
            boilerplate_group_pages_by_section(Rest, [{Section, [Page | Pages]} | Tail]);
        _ ->
            boilerplate_group_pages_by_section(Rest, [{Section, [Page]} | Acc])
    end.

boilerplate_card_row(Page, Section)
        when Section =:= <<"Device Forge">>; Section =:= <<"Processes">> ->
    boilerplate_recipe_card_row(Page);
boilerplate_card_row(Page, _Section) ->
    [
        <<"<a class=\"hb-docs-card\" href=\"">>,
        esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\"><strong>">>, esc(maps:get(<<"title">>, Page, <<>>)),
        <<"</strong><span>">>, esc(card_summary(maps:get(<<"summary">>, Page, <<>>))),
        <<"</span></a>">>
    ].

boilerplate_list_row(Page, _Section) ->
    [
        <<"<p class=\"hb-docs-reference-item\"><a href=\"">>,
        esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\"><strong>">>, esc(maps:get(<<"title">>, Page, <<>>)),
        <<"</strong></a><br><span class=\"hb-docs-guide-list-desc\">">>,
        esc(card_summary(maps:get(<<"summary">>, Page, <<>>))),
        <<"</span></p>">>
    ].

boilerplate_recipe_card_row(Page) ->
    Title = maps:get(<<"title">>, Page, <<>>),
    Slug = boilerplate_page_slug(Page),
    Summary = card_summary(maps:get(<<"summary">>, Page, <<>>)),
    [
        <<"<a class=\"hb-docs-card hb-docs-recipe-card\" href=\"">>,
        esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\">">>,
        <<"<div class=\"hb-docs-recipe-card-header\">">>,
        recipe_icon_markup(Slug, #{<<"title">> => Title}),
        <<"<strong class=\"hb-docs-recipe-card-title\">">>,
        esc(Title),
        <<"</strong></div>">>,
        <<"<div class=\"hb-docs-recipe-card-body\">">>,
        <<"<span class=\"hb-docs-recipe-card-desc\">">>,
        esc(Summary),
        <<"</span><div class=\"hb-docs-recipe-card-footer\">">>,
        <<"<span class=\"hb-docs-recipe-card-cta\">Open &rarr;</span>">>,
        <<"</div></div></a>">>
    ].

boilerplate_structured_index(Index) ->
    Pages = maps:get(<<"pages">>, Index, []),
    [
        <<"<nav class=\"hb-docs-guide-index\" aria-label=\"Guides\">">>,
        [
            boilerplate_guide_group(Section, Pages)
        || Section <- boilerplate_section_order()
        ],
        <<"</nav>">>
    ].

boilerplate_guide_group(Section, Pages) ->
    case boilerplate_pages_for_section(Section, Pages) of
        [] ->
            [];
        SectionPages ->
            [
                <<"<section class=\"hb-docs-guide-group\"><h3>">>, esc(Section),
                <<"</h3><ul>">>,
                [
                    boilerplate_guide_link(Page)
                || Page <- SectionPages
                ],
                <<"</ul></section>">>
            ]
    end.

boilerplate_guide_link(Page) ->
    [
        <<"<li><a href=\"">>, esc(maps:get(<<"href">>, Page, <<>>)),
        <<"\">">>, esc(maps:get(<<"title">>, Page, <<>>)), <<"</a></li>">>
    ].

boilerplate_page_slug(Page) ->
    Href = maps:get(<<"href">>, Page, <<>>),
    case binary:split(Href, <<"/">>, [global]) of
        Parts ->
            case lists:reverse(Parts) of
                [Slug | _] when Slug =/= <<>> -> Slug;
                _ -> <<"guide">>
            end
    end.

concept_rows(Concepts) ->
    [
        [
            <<"<p><strong>">>, esc(Key), <<"</strong><br>">>, esc(Value), <<"</p>">>
        ]
    || {Key, Value} <- lists:sort(maps:to_list(Concepts))
    ].

schema_table(_DeviceID, _Schema, []) ->
    <<"<p>No directly callable keys are documented.</p>">>;
schema_table(DeviceID, Schema, Order) ->
    IncludeDescriptions = schema_has_descriptions(Schema, Order),
    [
        <<"<table><thead><tr><th>Key</th>">>,
        case IncludeDescriptions of
            true -> <<"<th>Description</th>">>;
            false -> []
        end,
        <<"<th>Parameters</th><th>Returns</th><th>Schema</th></tr></thead><tbody>">>,
        schema_rows(DeviceID, Schema, Order, IncludeDescriptions),
        <<"</tbody></table>">>
    ].

schema_has_descriptions(Schema, Order) ->
    lists:any(
        fun(Name) ->
            case maps:get(Name, Schema, undefined) of
                undefined -> false;
                KeySchema -> trim(maps:get(<<"description">>, KeySchema, <<>>)) =/= <<>>
            end
        end,
        Order
    ).

schema_rows(DeviceID, Schema, Order, IncludeDescriptions) ->
    [
        case maps:get(Name, Schema, undefined) of
            undefined -> [];
            KeySchema ->
                [
                    <<"<tr><td><a href=\"">>,
                    esc(device_schema_key_path(DeviceID, Name)),
                    <<"\">">>, esc(Name), <<"</a></td>">>,
                    schema_description_cell(KeySchema, IncludeDescriptions),
                    <<"<td>">>,
                    case maps:get(<<"schema-status">>, KeySchema, <<>>) of
                        <<"unavailable">> -> <<"not declared">>;
                        _ -> param_pills(DeviceID, Name, maps:get(<<"parameters">>, KeySchema, #{}))
                    end,
                    <<"</td><td>">>, schema_returns(KeySchema, compact),
                    <<"</td><td>">>, esc(maps:get(<<"schema-status">>, KeySchema, <<>>)),
                    <<"</td></tr>">>
                ]
        end
    || Name <- Order
    ].

schema_description_cell(KeySchema, true) ->
    [<<"<td>">>, esc(maps:get(<<"description">>, KeySchema, <<>>)), <<"</td>">>];
schema_description_cell(_KeySchema, false) ->
    [].

param_pills(_DeviceID, _Key, Params) when map_size(Params) =:= 0 ->
    <<"<span class=\"param-pills-none\">none</span>">>;
param_pills(_DeviceID, _Key, Params) ->
    [
        [
            <<"<span class=\"">>, pill_class_for_label(param_required_label(Param)), <<"\">">>,
            esc(Name),
            <<" ">>, param_required_label(Param),
            <<"</span>">>
        ]
    || {Name, Param} <- lists:sort(maps:to_list(Params))
    ].

param_required_label(Param) ->
    case maps:get(<<"required">>, Param, false) of
        true -> <<"required">>;
        false -> <<"optional">>
    end.

pill_class_for_label(<<"required">>) ->
    <<"pill pill-required">>;
pill_class_for_label(<<"optional">>) ->
    <<"pill pill-optional">>;
pill_class_for_label(Label) when is_binary(Label) ->
    Tone = erlang:phash2(Label) rem 8,
    <<"pill pill-tone-", (integer_to_binary(Tone))/binary>>.

param_required_cell(_DeviceID, _Key, _Name, Param) ->
    Label = param_required_label(Param),
    [<<"<span class=\"">>, pill_class_for_label(Label), <<"\">">>, esc(Label), <<"</span>">>].

recipe_icon_keywords() ->
    [
        {<<"bundle">>, <<"package">>},
        {<<"reassembl">>, <<"puzzle-piece">>},
        {<<"inspect">>, <<"magnifying-glass">>},
        {<<"post">>, <<"upload">>},
        {<<"upload">>, <<"upload">>},
        {<<"chunk">>, <<"stack">>},
        {<<"offset">>, <<"crosshair">>},
        {<<"resolve">>, <<"crosshair">>},
        {<<"verify">>, <<"seal-check">>},
        {<<"commitment">>, <<"seal-check">>},
        {<<"serialize">>, <<"export">>},
        {<<"typed">>, <<"book-open">>},
        {<<"key">>, <<"key">>},
        {<<"list">>, <<"list-bullets">>},
        {<<"message">>, <<"chat-dots">>},
        {<<"transaction">>, <<"chat-dots">>},
        {<<"raw">>, <<"database">>},
        {<<"range">>, <<"database">>},
        {<<"read">>, <<"book-open">>}
    ].

recipe_icon_paths() ->
    #{
        <<"package">> =>
            <<"M223.68,66.15,135.68,18a15.88,15.88,0,0,0-15.36,0l-88,48.17a16,16,0,0,0-8.32,14v95.64a16,16,0,0,0,8.32,14l88,48.17a15.88,15.88,0,0,0,15.36,0l88-48.17a16,16,0,0,0,8.32-14V80.18A16,16,0,0,0,223.68,66.15ZM128,32l80.34,44-29.77,16.3-80.35-44ZM128,120,47.66,76l33.9-18.56,80.34,44ZM40,90l80,43.78v85.79L40,175.82Zm176,85.78h0l-80,43.79V133.82l32-17.51V152a8,8,0,0,0,16,0V107.55L216,90v85.77Z">>,
        <<"upload">> =>
            <<"M240,136v64a16,16,0,0,1-16,16H32a16,16,0,0,1-16-16V136a16,16,0,0,1,16-16H80a8,8,0,0,1,0,16H32v64H224V136H176a8,8,0,0,1,0-16h48A16,16,0,0,1,240,136ZM85.66,77.66,120,43.31V128a8,8,0,0,0,16,0V43.31l34.34,34.35a8,8,0,0,0,11.32-11.32l-48-48a8,8,0,0,0-11.32,0l-48,48A8,8,0,0,0,85.66,77.66ZM200,168a12,12,0,1,0-12,12A12,12,0,0,0,200,168Z">>,
        <<"book-open">> =>
            <<"M232,48H160a40,40,0,0,0-32,16A40,40,0,0,0,96,48H24a8,8,0,0,0-8,8V200a8,8,0,0,0,8,8H96a24,24,0,0,1,24,24,8,8,0,0,0,16,0,24,24,0,0,1,24-24h72a8,8,0,0,0,8-8V56A8,8,0,0,0,232,48ZM96,192H32V64H96a24,24,0,0,1,24,24V200A39.81,39.81,0,0,0,96,192Zm128,0H160a39.81,39.81,0,0,0-24,8V88a24,24,0,0,1,24-24h64Z">>,
        <<"stack">> =>
            <<"M230.91,172A8,8,0,0,1,228,182.91l-96,56a8,8,0,0,1-8.06,0l-96-56A8,8,0,0,1,36,169.09l92,53.65,92-53.65A8,8,0,0,1,230.91,172ZM220,121.09l-92,53.65L36,121.09A8,8,0,0,0,28,134.91l96,56a8,8,0,0,0,8.06,0l96-56A8,8,0,1,0,220,121.09ZM24,80a8,8,0,0,1,4-6.91l96-56a8,8,0,0,1,8.06,0l96,56a8,8,0,0,1,0,13.82l-96,56a8,8,0,0,1-8.06,0l-96-56A8,8,0,0,1,24,80Zm23.88,0L128,126.74,208.12,80,128,33.26Z">>,
        <<"crosshair">> =>
            <<"M232,120h-8.34A96.14,96.14,0,0,0,136,32.34V24a8,8,0,0,0-16,0v8.34A96.14,96.14,0,0,0,32.34,120H24a8,8,0,0,0,0,16h8.34A96.14,96.14,0,0,0,120,223.66V232a8,8,0,0,0,16,0v-8.34A96.14,96.14,0,0,0,223.66,136H232a8,8,0,0,0,0-16Zm-96,87.6V200a8,8,0,0,0-16,0v7.6A80.15,80.15,0,0,1,48.4,136H56a8,8,0,0,0,0-16H48.4A80.15,80.15,0,0,1,120,48.4V56a8,8,0,0,0,16,0V48.4A80.15,80.15,0,0,1,207.6,120H200a8,8,0,0,0,0,16h7.6A80.15,80.15,0,0,1,136,207.6ZM128,88a40,40,0,1,0,40,40A40,40,0,0,0,128,88Zm0,64a24,24,0,1,1,24-24A24,24,0,0,1,128,152Z">>,
        <<"magnifying-glass">> =>
            <<"M229.66,218.34l-50.07-50.06a88.11,88.11,0,1,0-11.31,11.31l50.06,50.07a8,8,0,0,0,11.32-11.32ZM40,112a72,72,0,1,1,72,72A72.08,72.08,0,0,1,40,112Z">>,
        <<"export">> =>
            <<"M216,112v96a16,16,0,0,1-16,16H56a16,16,0,0,1-16-16V112A16,16,0,0,1,56,96H80a8,8,0,0,1,0,16H56v96H200V112H176a8,8,0,0,1,0-16h24A16,16,0,0,1,216,112ZM93.66,69.66,120,43.31V136a8,8,0,0,0,16,0V43.31l26.34,26.35a8,8,0,0,0,11.32-11.32l-40-40a8,8,0,0,0-11.32,0l-40,40A8,8,0,0,0,93.66,69.66Z">>,
        <<"key">> =>
            <<"M216.57,39.43A80,80,0,0,0,83.91,120.78L28.69,176A15.86,15.86,0,0,0,24,187.31V216a16,16,0,0,0,16,16H72a8,8,0,0,0,8-8V208H96a8,8,0,0,0,8-8V184h16a8,8,0,0,0,5.66-2.34l9.56-9.57A79.73,79.73,0,0,0,160,176h.1A80,80,0,0,0,216.57,39.43ZM224,98.1c-1.09,34.09-29.75,61.86-63.89,61.9H160a63.7,63.7,0,0,1-23.65-4.51,8,8,0,0,0-8.84,1.68L116.69,168H96a8,8,0,0,0-8,8v16H72a8,8,0,0,0-8,8v16H40V187.31l58.83-58.82a8,8,0,0,0,1.68-8.84A63.72,63.72,0,0,1,96,95.92c0-34.14,27.81-62.8,61.9-63.89A64,64,0,0,1,224,98.1ZM192,76a12,12,0,1,1-12-12A12,12,0,0,1,192,76Z">>,
        <<"seal-check">> =>
            <<"M225.86,102.82c-3.77-3.94-7.67-8-9.14-11.57-1.36-3.27-1.44-8.69-1.52-13.94-.15-9.76-.31-20.82-8-28.51s-18.75-7.85-28.51-8c-5.25-.08-10.67-.16-13.94-1.52-3.56-1.47-7.63-5.37-11.57-9.14C146.28,23.51,138.44,16,128,16s-18.27,7.51-25.18,14.14c-3.94,3.77-8,7.67-11.57,9.14C88,40.64,82.56,40.72,77.31,40.8c-9.76.15-20.82.31-28.51,8S41,67.55,40.8,77.31c-.08,5.25-.16,10.67-1.52,13.94-1.47,3.56-5.37,7.63-9.14,11.57C23.51,109.72,16,117.56,16,128s7.51,18.27,14.14,25.18c3.77,3.94,7.67,8,9.14,11.57,1.36,3.27,1.44,8.69,1.52,13.94.15,9.76.31,20.82,8,28.51s18.75,7.85,28.51,8c5.25.08,10.67.16,13.94,1.52,3.56,1.47,7.63,5.37,11.57,9.14C109.72,232.49,117.56,240,128,240s18.27-7.51,25.18-14.14c3.94-3.77,8-7.67,11.57-9.14,3.27-1.36,8.69-1.44,13.94-1.52,9.76-.15,20.82-.31,28.51-8s7.85-18.75,8-28.51c.08-5.25.16-10.67,1.52-13.94,1.47-3.56,5.37-7.63,9.14-11.57C232.49,146.28,240,138.44,240,128S232.49,109.73,225.86,102.82Zm-11.55,39.29c-4.79,5-9.75,10.17-12.38,16.52-2.52,6.1-2.63,13.07-2.73,19.82-.1,7-.21,14.33-3.32,17.43s-10.39,3.22-17.43,3.32c-6.75.1-13.72.21-19.82,2.73-6.35,2.63-11.52,7.59-16.52,12.38S132,224,128,224s-9.15-4.92-14.11-9.69-10.17-9.75-16.52-12.38c-6.1-2.52-13.07-2.63-19.82-2.73-7-.1-14.33-.21-17.43-3.32s-3.22-10.39-3.32-17.43c-.1-6.75-.21-13.72-2.73-19.82-2.63-6.35-7.59-11.52-12.38-16.52S32,132,32,128s4.92-9.15,9.69-14.11,9.75-10.17,12.38-16.52c2.52-6.1,2.63-13.07,2.73-19.82.1-7,.21-14.33,3.32-17.43S70.51,56.9,77.55,56.8c6.75-.1,13.72-.21,19.82-2.73,6.35-2.63,11.52-7.59,16.52-12.38S124,32,128,32s9.15,4.92,14.11,9.69,10.17,9.75,16.52,12.38c6.1,2.52,13.07,2.63,19.82,2.73,7,.1,14.33.21,17.43,3.32s3.22,10.39,3.32,17.43c.1,6.75.21,13.72,2.73,19.82,2.63,6.35,7.59,11.52,12.38,16.52S224,124,224,128,219.08,137.15,214.31,142.11ZM173.66,98.34a8,8,0,0,1,0,11.32l-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35A8,8,0,0,1,173.66,98.34Z">>,
        <<"list-bullets">> =>
            <<"M80,64a8,8,0,0,1,8-8H216a8,8,0,0,1,0,16H88A8,8,0,0,1,80,64Zm136,56H88a8,8,0,0,0,0,16H216a8,8,0,0,0,0-16Zm0,64H88a8,8,0,0,0,0,16H216a8,8,0,0,0,0-16ZM44,52A12,12,0,1,0,56,64,12,12,0,0,0,44,52Zm0,64a12,12,0,1,0,12,12A12,12,0,0,0,44,116Zm0,64a12,12,0,1,0,12,12A12,12,0,0,0,44,180Z">>,
        <<"database">> =>
            <<"M128,24C74.17,24,32,48.6,32,80v96c0,31.4,42.17,56,96,56s96-24.6,96-56V80C224,48.6,181.83,24,128,24Zm80,104c0,9.62-7.88,19.43-21.61,26.92C170.93,163.35,150.19,168,128,168s-42.93-4.65-58.39-13.08C55.88,147.43,48,137.62,48,128V111.36c17.06,15,46.23,24.64,80,24.64s62.94-9.68,80-24.64ZM69.61,53.08C85.07,44.65,105.81,40,128,40s42.93,4.65,58.39,13.08C200.12,60.57,208,70.38,208,80s-7.88,19.43-21.61,26.92C170.93,115.35,150.19,120,128,120s-42.93-4.65-58.39-13.08C55.88,99.43,48,89.62,48,80S55.88,60.57,69.61,53.08ZM186.39,202.92C170.93,211.35,150.19,216,128,216s-42.93-4.65-58.39-13.08C55.88,195.43,48,185.62,48,176V159.36c17.06,15,46.23,24.64,80,24.64s62.94-9.68,80-24.64V176C208,185.62,200.12,195.43,186.39,202.92Z">>,
        <<"chat-dots">> =>
            <<"M116,128a12,12,0,1,1,12,12A12,12,0,0,1,116,128ZM84,140a12,12,0,1,0-12-12A12,12,0,0,0,84,140Zm88,0a12,12,0,1,0-12-12A12,12,0,0,0,172,140Zm60-76V192a16,16,0,0,1-16,16H83l-32.6,28.16-.09.07A15.89,15.89,0,0,1,40,240a16.13,16.13,0,0,1-6.8-1.52A15.85,15.85,0,0,1,24,224V64A16,16,0,0,1,40,48H216A16,16,0,0,1,232,64ZM40,224h0ZM216,64H40V224l34.77-30A8,8,0,0,1,80,192H216Z">>,
        <<"link">> =>
            <<"M165.66,90.34a8,8,0,0,1,0,11.32l-64,64a8,8,0,0,1-11.32-11.32l64-64A8,8,0,0,1,165.66,90.34ZM215.6,40.4a56.08,56.08,0,0,0-79.2,0L112,64.8a8,8,0,0,0,11.31,11.31l24.4-24.4a40,40,0,1,1,56.57,56.57l-24.4,24.4A8,8,0,0,0,191.2,144l24.4-24.4A56.08,56.08,0,0,0,215.6,40.4ZM132.69,179.89l-24.4,24.4a40,40,0,1,1-56.57-56.57l24.4-24.4A8,8,0,0,0,64.8,112l-24.4,24.4a56,56,0,0,0,79.2,79.2L144,191.2a8,8,0,0,0-11.31-11.31Z">>,
        <<"puzzle-piece">> =>
            <<"M220.27,158.54a8,8,0,0,0-7.7-.46,20,20,0,1,1,0-36.16A8,8,0,0,0,224,114.69V72a16,16,0,0,0-16-16H171.78a35.36,35.36,0,0,0,.22-4,36.11,36.11,0,0,0-11.36-26.24,36,36,0,0,0-60.55,23.62,36.56,36.56,0,0,0,.14,6.62H64A16,16,0,0,0,48,72v32.22a35.36,35.36,0,0,0-4-.22,36.12,36.12,0,0,0-26.24,11.36,35.7,35.7,0,0,0-9.69,27,36.08,36.08,0,0,0,33.31,33.6,35.68,35.68,0,0,0,6.62-.14V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V165.31A8,8,0,0,0,220.27,158.54ZM208,208H64V165.31a8,8,0,0,0-11.43-7.23,20,20,0,1,1,0-36.16A8,8,0,0,0,64,114.69V72h46.69a8,8,0,0,0,7.23-11.43,20,20,0,1,1,36.16,0A8,8,0,0,0,161.31,72H208v32.23a35.68,35.68,0,0,0-6.62-.14A36,36,0,0,0,204,176a35.36,35.36,0,0,0,4-.22Z">>,
        <<"cooking-pot">> =>
            <<"M88,48V16a8,8,0,0,1,16,0V48a8,8,0,0,1-16,0Zm40,8a8,8,0,0,0,8-8V16a8,8,0,0,0-16,0V48A8,8,0,0,0,128,56Zm32,0a8,8,0,0,0,8-8V16a8,8,0,0,0-16,0V48A8,8,0,0,0,160,56Zm92.8,46.4L224,124v60a32,32,0,0,1-32,32H64a32,32,0,0,1-32-32V124L3.2,102.4a8,8,0,0,1,9.6-12.8L32,104V80a8,8,0,0,1,8-8H216a8,8,0,0,1,8,8v24l19.2-14.4a8,8,0,0,1,9.6,12.8ZM208,88H48v96a16,16,0,0,0,16,16H192a16,16,0,0,0,16-16Z">>
    }.

recipe_icon_name(Slug, Title) ->
    Text =
        iolist_to_binary([
            hb_util:to_lower(hb_util:bin(Slug)),
            <<" ">>,
            hb_util:to_lower(hb_util:bin(Title))
        ]),
    case first_recipe_icon_match(recipe_icon_keywords(), Text) of
        undefined -> <<"cooking-pot">>;
        Icon -> Icon
    end.

first_recipe_icon_match([], _Text) ->
    undefined;
first_recipe_icon_match([{Keyword, Icon} | Rest], Text) ->
    case binary:match(Text, Keyword) of
        nomatch -> first_recipe_icon_match(Rest, Text);
        _ -> Icon
    end.

recipe_icon_markup(Slug, Recipe) ->
    Icon = recipe_icon_name(Slug, maps:get(<<"title">>, Recipe, Slug)),
    [
        <<"<div class=\"hb-docs-recipe-card-icon\" aria-hidden=\"true\">">>,
        phosphor_icon_path_svg(Icon),
        <<"</div>">>
    ].

recipe_nav(DeviceID, Recipes) ->
    [
        [
            <<"<a class=\"hb-docs-card hb-docs-recipe-card\" href=\"">>,
            esc(device_recipe_path(DeviceID, Name)),
            <<"\">">>,
            <<"<div class=\"hb-docs-recipe-card-header\">">>,
            recipe_icon_markup(Name, Recipe),
            <<"<strong class=\"hb-docs-recipe-card-title\">">>,
            esc(maps:get(<<"title">>, Recipe, Name)),
            <<"</strong></div>">>,
            <<"<div class=\"hb-docs-recipe-card-body\">">>,
            <<"<span class=\"hb-docs-recipe-card-desc\">">>,
            esc(recipe_card_summary(Recipe)),
            <<"</span><div class=\"hb-docs-recipe-card-footer\">">>,
            <<"<span class=\"hb-docs-recipe-card-cta\">Open &rarr;</span>">>,
            recipe_card_meta(Recipe),
            <<"</div></div></a>">>
        ]
    || {Name, Recipe} <- lists:sort(maps:to_list(Recipes))
    ].

schema_source_note(Data) ->
    case maps:get(<<"schema-source">>, Data, undefined) of
        Source when is_map(Source) ->
            [
                <<"<p class=\"hb-docs-renderer-note\"><strong>Schema source:</strong> ">>,
                esc(schema_source_label(Source)),
                <<"</p>">>
            ];
        _ ->
            []
    end.

schema_source_label(Source) ->
    Mode = maps:get(<<"mode">>, Source, <<"unknown">>),
    case Mode of
        <<"implementation-derived">> ->
            iolist_to_binary([
                <<"implementation-derived via ">>,
                maps:get(<<"extractor">>, Source, <<"schema">>),
                <<" (">>,
                hb_util:bin(maps:get(<<"typed-key-count">>, Source, 0)),
                <<" typed / ">>,
                hb_util:bin(maps:get(<<"key-count">>, Source, 0)),
                <<" keys; ">>,
                hb_util:bin(maps:get(<<"typed-handler-count">>, Source, 0)),
                <<" typed / ">>,
                hb_util:bin(maps:get(<<"handler-count">>, Source, 0)),
                <<" handlers)">>,
                schema_source_status_suffix(Source)
            ]);
        <<"implementation-derived-unavailable">> ->
            iolist_to_binary([
                <<"implementation-derived unavailable">>,
                schema_source_status_suffix(Source)
            ]);
        _ ->
            Mode
    end.

schema_source_status_suffix(Source) ->
    case maps:get(<<"status">>, Source, <<>>) of
        <<>> -> <<>>;
        Status -> iolist_to_binary([<<" (">>, Status, <<")">>])
    end.

render_spec_section(_DeviceID, Spec) ->
    [
        <<"<h2 id=\"spec\">Spec</h2>">>,
        render_spec_body(Spec)
    ].

render_spec_body(Spec) ->
    Status = maps:get(<<"spec-status">>, Spec, <<"missing">>),
    [
        spec_tx_link_paragraph(Spec),
        case {Status, spec_markdown(Spec)} of
            {<<"present">>, Markdown} when byte_size(Markdown) > 0 ->
                render_markdown_with_heading_ids(drop_first_h1(Markdown), #{
                    <<"strip-numbered-headings">> => true
                });
            _ ->
                [<<"<p>">>, esc(maps:get(<<"summary">>, Spec, <<>>)), <<"</p>">>]
        end
    ].

%% @doc Strip leading "N. " numbering from spec section titles for nav display.
spec_section_nav_label(Title) ->
    case spec_section_nav_skip_digits(Title, 0) of
        {Count, <<".", Rest/binary>>} when Count > 0 ->
            trim(Rest);
        _ ->
            Title
    end.

spec_section_nav_skip_digits(<<C, Rest/binary>>, Count) when C >= $0, C =< $9 ->
    spec_section_nav_skip_digits(Rest, Count + 1);
spec_section_nav_skip_digits(Bin, Count) ->
    {Count, Bin}.

spec_sections(Spec) ->
    case maps:get(<<"spec-status">>, Spec, <<"missing">>) of
        <<"present">> ->
            case spec_markdown(Spec) of
                Markdown when byte_size(Markdown) > 0 ->
                    spec_sections_from_markdown(drop_first_h1(Markdown));
                _ ->
                    []
            end;
        _ ->
            []
    end.

spec_sections_from_markdown(Markdown) ->
    spec_sections_from_lines(binary:split(Markdown, <<"\n">>, [global]), [], #{}).

spec_sections_from_lines([], Acc, _UsedIds) ->
    lists:reverse(Acc);
spec_sections_from_lines([Line | Rest], Acc, UsedIds) ->
    case heading(trim(Line)) of
        {2, Text} ->
            Plain = strip_inline_markdown(Text),
            {SectionId, NewUsedIds} = unique_heading_slug(Plain, UsedIds),
            spec_sections_from_lines(Rest, [{SectionId, Plain} | Acc], NewUsedIds);
        _ ->
            spec_sections_from_lines(Rest, Acc, UsedIds)
    end.

spec_section_lookup(Spec, SectionSlug) ->
    case lists:keyfind(SectionSlug, 1, spec_sections(Spec)) of
        false -> undefined;
        {SectionSlug, Title} -> {SectionSlug, Title}
    end.

spec_section_markdown(Spec, SectionSlug) ->
    case spec_markdown(Spec) of
        Markdown when byte_size(Markdown) > 0 ->
            case spec_section_lookup(Spec, SectionSlug) of
                undefined ->
                    <<>>;
                {_Id, Title} ->
                    case extract_markdown_section(drop_first_h1(Markdown), Title) of
                        {ok, SectionMarkdown} -> SectionMarkdown;
                        false -> <<>>
                    end
            end;
        _ ->
            <<>>
    end.

spec_tx_link_paragraph(Spec) ->
    on_chain_link_paragraph(Spec, <<"View spec transaction">>).

spec_tx_link(Spec, Prefix) ->
    case on_chain_txid(Spec) of
        <<>> -> [];
        TXID ->
            [
                Prefix,
                arweave_tx_link(TXID, <<"View spec transaction">>)
            ]
    end.

on_chain_link_paragraph(Item, Label) ->
    case on_chain_txid(Item) of
        <<>> -> [];
        TXID ->
            [
                <<"<p class=\"hb-docs-chain-link-row\">">>,
                arweave_tx_link(TXID, Label),
                <<"</p>">>
            ]
    end.

arweave_tx_link(TXID, Label) ->
    [
        <<"<a class=\"hb-docs-chain-link\" href=\"">>,
        esc(arweave_tx_href(TXID)),
        <<"\" target=\"_blank\" rel=\"noopener\" title=\"">>,
        esc(TXID),
        <<"\">">>,
        <<"<span class=\"hb-docs-chain-link-icon\" aria-hidden=\"true\">">>,
        phosphor_icon_path_svg(<<"link">>),
        <<"</span><span>">>,
        esc(Label),
        <<"</span></a>">>
    ].

arweave_tx_href(TXID) ->
    <<"https://viewblock.io/arweave/tx/", TXID/binary>>.

on_chain_txid(Item) when is_map(Item) ->
    case on_chain_txid_value(maps:get(<<"txid">>, Item, <<>>)) of
        <<>> ->
            case on_chain_txid_value(maps:get(<<"source">>, Item, <<>>)) of
                <<>> -> on_chain_txid_value(maps:get(<<"source-relative">>, Item, <<>>));
                TXID -> TXID
            end;
        TXID ->
            TXID
    end;
on_chain_txid(Item) ->
    on_chain_txid_value(Item).

on_chain_txid_value(Value) ->
    Bin = trim(hb_util:bin(Value)),
    TXID =
        case Bin of
            <<"weave:", Rest/binary>> -> Rest;
            _ -> Bin
        end,
    case is_arweave_txid(TXID) of
        true -> TXID;
        false -> <<>>
    end.

implementation_source_cell(Impl) ->
    Source = maps:get(<<"source">>, Impl, <<>>),
    case on_chain_txid(Source) of
        <<>> ->
            [<<"<code>">>, esc(Source), <<"</code>">>];
        TXID ->
            arweave_tx_link(TXID, <<"View implementation transaction">>)
    end.

spec_markdown(Spec) ->
    case maps:get(<<"markdown">>, Spec, undefined) of
        Markdown when is_binary(Markdown) ->
            Markdown;
        _ ->
            Source = maps:get(<<"source-path">>, Spec, <<>>),
            case file:read_file(binary_to_list(Source)) of
                {ok, Markdown} -> Markdown;
                {error, _Reason} -> <<>>
            end
    end.

params_table(_DeviceID, _Key, Params) when map_size(Params) =:= 0 ->
    <<"<p>No parameters.</p>">>;
params_table(DeviceID, Key, Params) ->
    Fields = param_metadata_fields(maps:values(Params)),
    [
        <<"<table><thead><tr><th>Name</th><th>Required</th><th>Type</th>">>,
        [[<<"<th>">>, Label, <<"</th>">>] || {_, Label} <- Fields],
        <<"</tr></thead><tbody>">>,
        [
            [
                <<"<tr><td><a href=\"">>,
                esc(device_schema_param_path(DeviceID, Key, Name)),
                <<"\"><code>">>, esc(Name),
                <<"</code></a></td><td>">>,
                param_required_cell(DeviceID, Key, Name, Param),
                <<"</td><td>">>, esc(maps:get(<<"type">>, Param, <<>>)),
                <<"</td>">>,
                [
                    [<<"<td>">>, param_metadata_value(Field, Param), <<"</td>">>]
                || {Field, _} <- Fields
                ],
                <<"</tr>">>
            ]
        || {Name, Param} <- lists:sort(maps:to_list(Params))
        ],
        <<"</tbody></table>">>
    ].

%% @doc Include optional metadata only when at least one parameter supplies it.
param_metadata_fields(Params) ->
    [
        {Field, Label}
    || {Field, Label} <- [
        {<<"description">>, <<"Description">>},
        {<<"example">>, <<"Example">>}
    ],
        lists:any(
            fun(Param) ->
                trim(hb_util:bin(maps:get(Field, Param, <<>>))) =/= <<>>
            end,
            Params
        )
    ].

%% @doc Escape parameter metadata and retain code formatting for examples.
param_metadata_value(<<"example">>, Param) ->
    [<<"<code>">>, esc(maps:get(<<"example">>, Param, <<>>)), <<"</code>">>];
param_metadata_value(Field, Param) ->
    esc(maps:get(Field, Param, <<>>)).

recipe_markdown(Recipe) ->
    case maps:get(<<"markdown">>, Recipe, undefined) of
        Markdown when is_binary(Markdown) ->
            Markdown;
        _ ->
            <<>>
    end.

docs_shell_assets() ->
    [
        <<"<script src=\"/docs/assets/prism-core.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-bash.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-json.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-http.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-erlang.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-lua.min.js\"></script>">>,
        <<"<script src=\"/docs/assets/prism-markdown.min.js\"></script>">>,
        <<"<script>">>, docs_page_enhancer_js(), <<"</script>">>,
        <<"<script>">>, docs_page_toc_js(), <<"</script>">>,
        <<"<script>">>, docs_footer_nav_js(), <<"</script>">>,
        <<"<script>">>, docs_mobile_nav_js(), <<"</script>">>,
        <<"<script src=\"/docs/assets/example-runner.js\"></script>">>,
        <<"<script>">>,
        <<"window.addEventListener('DOMContentLoaded',function(){">>,
        <<"if(window.Prism){window.Prism.highlightAll();}">>,
        <<"if(window.HBDocsCodeChrome){window.HBDocsCodeChrome.refresh();}">>,
        <<"if(window.HBExampleRunner){window.HBExampleRunner.refresh();}">>,
        <<"if(window.HBDocsMobileNav){window.HBDocsMobileNav.init();}">>,
        <<"if(window.HBDocsPageToc){window.HBDocsPageToc.init();}">>,
        <<"if(window.HBDocsFooterNav){window.HBDocsFooterNav.init();}">>,
        <<"});">>,
        <<"</script>">>
    ].

docs_page_enhancer_js() ->
    <<"
(function(){
  function addLineNumbers(pre, code) {
    if (pre.dataset.lineNumbers) return;
    var lines = (code.textContent || '').split('\\n');
    if (lines.length && lines[lines.length - 1] === '') lines.pop();
    if (!lines.length) return;
    var gutter = document.createElement('div');
    gutter.className = 'code-line-numbers';
    gutter.setAttribute('aria-hidden', 'true');
    lines.forEach(function (_, i) {
      var span = document.createElement('span');
      span.textContent = String(i + 1);
      gutter.appendChild(span);
    });
    pre.classList.add('has-line-numbers');
    pre.insertBefore(gutter, code);
    pre.dataset.lineNumbers = '1';
  }

	  function addCopyButtons() {
	    document.querySelectorAll('.markdown-section pre').forEach(function (pre) {
      var code = pre.querySelector('code');
      if (!code || pre.dataset.codeChrome) return;
      addLineNumbers(pre, code);
      var lang = (pre.getAttribute('data-lang') || '').trim();
      var header = document.createElement('div');
      header.className = 'code-header';
      var langLabel = document.createElement('span');
      langLabel.className = 'code-header-lang';
      langLabel.textContent = lang || 'code';
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-code-btn';
      btn.setAttribute('aria-label', 'Copy code');
      btn.innerHTML =
        '<span class=\"copy-code-btn-stage\" aria-hidden=\"true\">' +
        '<span class=\"copy-code-btn-icon copy-code-btn-icon-copy\">' +
        '<svg viewBox=\"0 0 256 256\" fill=\"currentColor\"><path d=\"M216,32H88a8,8,0,0,0-8,8V80H40a8,8,0,0,0-8,8V216a8,8,0,0,0,8,8H168a8,8,0,0,0,8-8V176h40a8,8,0,0,0,8-8V40A8,8,0,0,0,216,32ZM160,208H48V96H160Zm48-48H176V88a8,8,0,0,0-8-8H96V48H208Z\"/></svg>' +
        '</span><span class=\"copy-code-btn-icon copy-code-btn-icon-check\">' +
        '<svg viewBox=\"0 0 256 256\" fill=\"currentColor\"><path d=\"M232.49,80.49l-128,128a12,12,0,0,1-17,0l-56-56a12,12,0,1,1,17-17L96,183,215.51,63.51a12,12,0,0,1,17,17Z\"/></svg>' +
        '</span></span>';
      btn.addEventListener('click', function () {
        var text = code.textContent || '';
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () {
            btn.classList.add('copied');
            btn.setAttribute('aria-label', 'Copied');
            setTimeout(function () {
              btn.classList.remove('copied');
              btn.setAttribute('aria-label', 'Copy code');
            }, 1800);
          });
        }
      });
      header.appendChild(langLabel);
      header.appendChild(btn);
      pre.insertBefore(header, pre.firstChild);
      pre.classList.add('has-code-header');
      pre.dataset.codeChrome = '1';
	    });
	  }

	  window.HBDocsCodeChrome = {
	    refresh: function () {
	      addCopyButtons();
	    }
	  };
	})();
">>.

docs_page_toc_js() ->
    <<"
(function () {
  var tocScrollRoot = null;
  var tocScrollHandler = null;
  var tocScrollEndHandler = null;
  var tocResizeHandler = null;
  var tocObserver = null;
  var tocScrollRaf = null;

  function teardownPageTocScroll() {
    if (tocObserver) {
      tocObserver.disconnect();
      tocObserver = null;
    }
    if (tocScrollRaf) {
      window.cancelAnimationFrame(tocScrollRaf);
      tocScrollRaf = null;
    }
    if (tocScrollRoot && tocScrollHandler) {
      tocScrollRoot.removeEventListener('scroll', tocScrollHandler);
    }
    if (tocScrollRoot && tocScrollEndHandler) {
      tocScrollRoot.removeEventListener('scrollend', tocScrollEndHandler);
    }
    if (tocResizeHandler) {
      window.removeEventListener('resize', tocResizeHandler);
    }
    tocScrollRoot = null;
    tocScrollHandler = null;
    tocScrollEndHandler = null;
    tocResizeHandler = null;
  }

  function getScrollEl() {
    var content = document.querySelector('.content');
    if (content) {
      var overflowY = window.getComputedStyle(content).overflowY;
      if (/(auto|scroll|overlay)/.test(overflowY) && content.scrollHeight > content.clientHeight + 1) {
        return content;
      }
    }
    return window;
  }

  function getHeaderHeight() {
    var header = document.getElementById('site-header');
    if (!header || window.getComputedStyle(header).display === 'none') return 0;
    return header.getBoundingClientRect().height;
  }

  function getHeaderScrollOffset() {
    return getHeaderHeight() + 12;
  }

  function getAnchorIdFromHref(href) {
    if (!href) return '';
    var idMatch = href.match(/[?&]id=([^&]+)/);
    if (idMatch) return decodeURIComponent(idMatch[1]);
    var hash = href.split('#').pop() || '';
    return hash.replace(/^\\//, '');
  }

  function slugify(text) {
    return String(text || '')
      .trim()
      .toLowerCase()
      .replace(/[^\\w\\s-]/g, '')
      .replace(/\\s+/g, '-')
      .replace(/-+/g, '-');
  }

  function resolveHeadingLink(heading, usedIds) {
    var anchor = heading.querySelector('a.anchor');
    if (anchor) {
      var anchorId = getAnchorIdFromHref(anchor.getAttribute('href') || '');
      if (anchorId && !heading.id) heading.id = anchorId;
      if (heading.id) {
        usedIds[heading.id] = true;
        return { href: anchor.getAttribute('href') || ('#' + heading.id), id: heading.id };
      }
    }
    if (heading.id) {
      usedIds[heading.id] = true;
      return { href: '#' + heading.id, id: heading.id };
    }
    var base = slugify(heading.textContent || '');
    if (!base) return null;
    var id = base;
    var suffix = 2;
    while (usedIds[id]) {
      id = base + '-' + suffix;
      suffix += 1;
    }
    heading.id = id;
    usedIds[id] = true;
    return { href: '#' + id, id: id };
  }

  function addPageToc() {
    if (!document.body.classList.contains('hb-docs-protocol')) return;
    teardownPageTocScroll();
    document.body.classList.remove('page-toc-active');
    document.querySelector('.page-toc')?.remove();

    var markdownSection = document.querySelector('#main.markdown-section') ||
      document.querySelector('.markdown-section');
    var headings = markdownSection
      ? markdownSection.querySelectorAll('h2, h3')
      : document.querySelectorAll('.markdown-section h2, .markdown-section h3');
    if (!headings.length) return;

    var toc = document.createElement('aside');
    toc.className = 'page-toc';
    toc.setAttribute('aria-label', 'On this page');

    var tocNav = document.createElement('nav');
    tocNav.className = 'page-toc-nav';
    tocNav.setAttribute('aria-label', 'On this page sections');

    var tocProgress = document.createElement('div');
    tocProgress.className = 'page-toc-progress';
    tocProgress.setAttribute('aria-hidden', 'true');
    tocProgress.innerHTML =
      '<span class=\"page-toc-progress-rail\"></span>' +
      '<span class=\"page-toc-progress-indicator\"></span>';

    var tocLinksWrap = document.createElement('div');
    tocLinksWrap.className = 'page-toc-links';

    tocNav.appendChild(tocProgress);
    tocNav.appendChild(tocLinksWrap);
    toc.appendChild(tocNav);

    var tocLinks = [];
    var usedIds = {};
    headings.forEach(function (heading) {
      var linkInfo = resolveHeadingLink(heading, usedIds);
      if (!linkInfo) return;
      var link = document.createElement('a');
      link.href = linkInfo.href;
      link.textContent = (heading.textContent || '').trim();
      link.dataset.level = heading.tagName.toLowerCase();
      tocLinksWrap.appendChild(link);
      tocLinks.push({ link: link, heading: heading });
    });

    if (tocLinks.length <= 1) {
      return;
    }

    document.body.classList.add('page-toc-active');
    document.body.appendChild(toc);

    var scrollRoot = getScrollEl();
    var tocSpySuppressUntil = 0;

    function getScrollTop() {
      return scrollRoot === window ? window.pageYOffset : scrollRoot.scrollTop;
    }

    function getScrollHeight() {
      return scrollRoot === window
        ? Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)
        : scrollRoot.scrollHeight;
    }

    function getViewportHeight() {
      return scrollRoot === window ? window.innerHeight : scrollRoot.clientHeight;
    }

    function getHeadingDocumentY(heading) {
      if (scrollRoot === window) {
        return heading.getBoundingClientRect().top + window.pageYOffset;
      }
      var rootRect = scrollRoot.getBoundingClientRect();
      return heading.getBoundingClientRect().top - rootRect.top + scrollRoot.scrollTop;
    }

    function scrollToY(targetY) {
      var top = Math.max(0, targetY);
      if (scrollRoot === window) {
        window.scrollTo({ top: top, behavior: 'smooth' });
      } else {
        scrollRoot.scrollTo({ top: top, behavior: 'smooth' });
      }
    }

    function scrollToHeading(heading, linkHref) {
      var offset = getHeaderScrollOffset();
      scrollToY(getHeadingDocumentY(heading) - offset);
      tocSpySuppressUntil = Date.now() + 900;
      if (linkHref) {
        history.replaceState(null, '', linkHref);
      }
      window.setTimeout(function () {
        setActiveTocLink(heading.id);
      }, 0);
    }

    function updatePageTocProgress() {
      var indicator = toc.querySelector('.page-toc-progress-indicator');
      var progress = toc.querySelector('.page-toc-progress');
      var active = tocLinksWrap.querySelector('a.active');
      if (!indicator || !progress || !active) {
        if (indicator) indicator.style.opacity = '0';
        return;
      }

      var progressRect = progress.getBoundingClientRect();
      var activeRect = active.getBoundingClientRect();
      var top = activeRect.top - progressRect.top;

      indicator.style.opacity = '1';
      indicator.style.height = activeRect.height + 'px';
      indicator.style.transform = 'translateY(' + top + 'px)';
    }

    function setActiveTocLink(targetId) {
      tocLinks.forEach(function (item) {
        var active = item.heading.id === targetId;
        item.link.classList.toggle('active', active);
      });
      updatePageTocProgress();
    }

    function resolveActiveTocIndex() {
      if (!tocLinks.length) return 0;

      var offset = getHeaderScrollOffset();
      var scrollTop = getScrollTop();
      var maxScroll = Math.max(0, getScrollHeight() - getViewportHeight());

      if (scrollTop <= 1) {
        return 0;
      }
      if (maxScroll > 0 && scrollTop >= maxScroll - 1) {
        return tocLinks.length - 1;
      }

      var anchorY = scrollTop + offset;
      var activeIndex = 0;
      for (var i = 0; i < tocLinks.length; i++) {
        if (getHeadingDocumentY(tocLinks[i].heading) <= anchorY + 1) {
          activeIndex = i;
        }
      }
      return activeIndex;
    }

    function syncActiveTocFromScroll() {
      if (!markdownSection || !tocLinks.length) return;
      if (Date.now() < tocSpySuppressUntil) return;
      var activeIndex = resolveActiveTocIndex();
      setActiveTocLink(tocLinks[activeIndex].heading.id);
    }

    function scheduleTocSync() {
      if (tocScrollRaf) return;
      tocScrollRaf = window.requestAnimationFrame(function () {
        tocScrollRaf = null;
        syncActiveTocFromScroll();
      });
    }

    tocLinksWrap.addEventListener('click', function (event) {
      var link = event.target.closest('a');
      if (!link || !tocLinksWrap.contains(link)) return;
      var linkHref = link.getAttribute('href') || '';
      var targetId = getAnchorIdFromHref(linkHref);
      var item = tocLinks.find(function (entry) {
        return entry.heading.id === targetId;
      });
      if (!item) return;
      event.preventDefault();
      scrollToHeading(item.heading, linkHref);
    });

    tocScrollHandler = scheduleTocSync;
    tocScrollEndHandler = syncActiveTocFromScroll;
    tocScrollRoot = scrollRoot === window ? window : scrollRoot;
    tocScrollRoot.addEventListener('scroll', tocScrollHandler, { passive: true });
    if ('onscrollend' in tocScrollRoot) {
      tocScrollRoot.addEventListener('scrollend', tocScrollEndHandler, { passive: true });
    }
    tocResizeHandler = scheduleTocSync;
    window.addEventListener('resize', tocResizeHandler, { passive: true });

    tocObserver = new IntersectionObserver(
      function () {
        scheduleTocSync();
      },
      {
        root: scrollRoot === window ? null : scrollRoot,
        rootMargin: '-' + getHeaderScrollOffset() + 'px 0px -70% 0px',
        threshold: [0, 1]
      }
    );
    tocLinks.forEach(function (item) {
      tocObserver.observe(item.heading);
    });

    window.requestAnimationFrame(function () {
      window.requestAnimationFrame(syncActiveTocFromScroll);
    });

    toc.__updatePageTocProgress = updatePageTocProgress;
    toc.__syncActiveTocFromScroll = syncActiveTocFromScroll;
  }

  if (!window.__pageTocProgressResizeBound) {
    window.__pageTocProgressResizeBound = true;
    window.addEventListener('resize', function () {
      var tocEl = document.querySelector('.page-toc');
      if (!tocEl) return;
      if (typeof tocEl.__syncActiveTocFromScroll === 'function') {
        tocEl.__syncActiveTocFromScroll();
      } else if (typeof tocEl.__updatePageTocProgress === 'function') {
        tocEl.__updatePageTocProgress();
      }
    }, { passive: true });
  }

  window.HBDocsPageToc = {
    init: addPageToc,
    refresh: addPageToc
  };
})();
">>.

docs_footer_nav_js() ->
    <<"
(function () {
  function normalizePath(path) {
    return String(path || '/')
      .split('?')[0]
      .split('#')[0]
      .replace(/\\/$/, '') || '/';
  }

  function getSidebarLinks() {
    return Array.from(document.querySelectorAll('.sidebar-nav a'))
      .map(function (a) {
        return {
          href: a.getAttribute('href') || '',
          text: (a.textContent || '').trim()
        };
      })
      .filter(function (item) {
        return item.href.charAt(0) === '/' && item.text;
      });
  }

  function getCurrentLinkIndex(links) {
    var current = normalizePath(
      document.body.getAttribute('data-active-path') || window.location.pathname
    );
    return links.findIndex(function (item) {
      return normalizePath(item.href) === current;
    });
  }

  function addFooterNav() {
    var section = document.querySelector('.markdown-section');
    if (!section) return;
    section.querySelector('.docs-footer-nav')?.remove();

    var links = getSidebarLinks();
    var index = getCurrentLinkIndex(links);
    if (index < 0) return;

    var nav = document.createElement('nav');
    nav.className = 'docs-footer-nav';
    nav.setAttribute('aria-label', 'Page navigation');

    if (index > 0) {
      var prev = links[index - 1];
      var prevLink = document.createElement('a');
      prevLink.className = 'docs-footer-link prev';
      prevLink.href = prev.href;
      prevLink.innerHTML =
        '<span class=\"docs-footer-label\">Previous</span>' +
        '<span class=\"docs-footer-title\"></span>';
      prevLink.querySelector('.docs-footer-title').textContent = prev.text;
      nav.appendChild(prevLink);
    } else {
      nav.appendChild(document.createElement('span'));
    }

    if (index < links.length - 1) {
      var next = links[index + 1];
      var nextLink = document.createElement('a');
      nextLink.className = 'docs-footer-link next';
      nextLink.href = next.href;
      nextLink.innerHTML =
        '<span class=\"docs-footer-label\">Next</span>' +
        '<span class=\"docs-footer-title\"></span>';
      nextLink.querySelector('.docs-footer-title').textContent = next.text;
      nav.appendChild(nextLink);
    }

    if (nav.children.length) section.appendChild(nav);
  }

  window.HBDocsFooterNav = {
    init: addFooterNav,
    refresh: addFooterNav
  };
})();
">>.

docs_mobile_nav_js() ->
    <<"
(function () {
  var chevronSvg =
    '<svg class=\"nav-megamenu-chevron\" viewBox=\"0 0 12 12\" fill=\"none\" ' +
    'stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" ' +
    'stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M4.5 2.5 8 6 4.5 9.5\"/></svg>';

  function normalizePath(path) {
    return String(path || '/')
      .split('?')[0]
      .split('#')[0]
      .replace(/\\/$/, '') || '/';
  }

  function isMobileNavHomeDuplicate(href, label) {
    var home = document.querySelector('.mobile-nav-home');
    if (!home) return false;
    var homeHref = normalizePath(home.getAttribute('href') || '');
    var homeLabel = (home.textContent || '').trim();
    return normalizePath(href) === homeHref || (!!label && label === homeLabel);
  }

  function closeMobileNav() {
    var drawer = document.getElementById('mobile-nav-drawer');
    var toggle = document.getElementById('mobile-menu-toggle');
    if (!drawer) return;
    drawer.classList.remove('open');
    drawer.setAttribute('aria-hidden', 'true');
    if (toggle) toggle.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('mobile-nav-open');
    var searchInput = document.getElementById('mobile-nav-search-input');
    if (searchInput) {
      searchInput.value = '';
      filterMobileNav('');
    }
  }

  function openMobileNav() {
    var drawer = document.getElementById('mobile-nav-drawer');
    var toggle = document.getElementById('mobile-menu-toggle');
    if (!drawer) return;
    drawer.classList.add('open');
    drawer.setAttribute('aria-hidden', 'false');
    if (toggle) toggle.setAttribute('aria-expanded', 'true');
    document.body.classList.add('mobile-nav-open');
    drawer.querySelectorAll('.mobile-nav-section.active').forEach(function (sectionEl) {
      sectionEl.classList.add('open');
      var trigger = sectionEl.querySelector('.mobile-nav-section-trigger');
      if (trigger) trigger.setAttribute('aria-expanded', 'true');
    });
  }

  function syncLayoutForViewport() {
    if (window.matchMedia('(max-width: 1000px)').matches) {
      document.body.classList.add('close');
    } else {
      document.body.classList.remove('close');
      closeMobileNav();
    }
  }

  function setActiveNav(path) {
    var normalized = normalizePath(path);
    var home = document.querySelector('.mobile-nav-home');
    if (home) {
      home.classList.toggle('active', normalized === '/docs');
    }
    document.querySelectorAll('.mobile-nav-tab').forEach(function (tab) {
      var href = tab.getAttribute('href') || '';
      tab.classList.toggle('active', normalizePath(href) === normalized);
    });
    document.querySelectorAll('.mobile-nav-section').forEach(function (sectionEl) {
      var active = false;
      sectionEl.querySelectorAll('a[href]').forEach(function (link) {
        if (normalizePath(link.getAttribute('href')) === normalized) active = true;
      });
      sectionEl.classList.toggle('active', active);
    });
    document.querySelectorAll('.sidebar-nav a[href]').forEach(function (link) {
      var li = link.parentElement;
      if (!li || li.classList.contains('sidebar-viewing-context')) return;
      li.classList.toggle('active', normalizePath(link.getAttribute('href')) === normalized);
    });
  }

  function textMatchesQuery(text, query) {
    return String(text || '').trim().toLowerCase().indexOf(query) !== -1;
  }

  function filterMobileNav(query) {
    var q = String(query || '').trim().toLowerCase();
    var mobileNavList = document.getElementById('mobile-nav-list');
    var mobileNavTabs = document.getElementById('mobile-nav-tabs');
    if (!mobileNavList) return;

    function setHidden(el, hidden) {
      if (!el) return;
      el.classList.toggle('mobile-nav-filter-hidden', hidden);
    }

    if (mobileNavTabs) {
      mobileNavTabs.querySelectorAll('.mobile-nav-tab').forEach(function (tab) {
        var label = (tab.textContent || '').trim();
        setHidden(tab, q && !textMatchesQuery(label, q));
      });
      setHidden(
        mobileNavTabs.querySelector('.mobile-nav-home'),
        q && !textMatchesQuery((mobileNavTabs.querySelector('.mobile-nav-home')?.textContent || ''), q)
      );
    }

    mobileNavList.querySelectorAll('.mobile-nav-section').forEach(function (sectionEl) {
      var sectionLabel = (
        sectionEl.querySelector('.mobile-nav-section-trigger span')?.textContent || ''
      ).trim();
      var sectionMatches = q && textMatchesQuery(sectionLabel, q);
      var sectionVisible = !q;

      sectionEl.querySelectorAll('.mobile-nav-link').forEach(function (link) {
        var linkMatches = !q || sectionMatches || textMatchesQuery(link.textContent, q);
        var sublinks = link.nextElementSibling;
        var hasVisibleSublink = false;

        if (sublinks && sublinks.classList.contains('mobile-nav-sublinks')) {
          sublinks.querySelectorAll('.mobile-nav-sublink').forEach(function (sublink) {
            var sublinkMatches = !q || sectionMatches || textMatchesQuery(sublink.textContent, q);
            setHidden(sublink, !sublinkMatches);
            if (sublinkMatches) hasVisibleSublink = true;
          });
          setHidden(sublinks, q && !sectionMatches && !hasVisibleSublink && !linkMatches);
        }

        var visible = linkMatches || hasVisibleSublink;
        setHidden(link, q && !visible);
        if (visible) sectionVisible = true;
      });

      setHidden(sectionEl, q && !sectionVisible);

      if (q && sectionVisible) {
        sectionEl.classList.add('open');
        var trigger = sectionEl.querySelector('.mobile-nav-section-trigger');
        if (trigger) trigger.setAttribute('aria-expanded', 'true');
      } else if (!q) {
        var isActive = sectionEl.classList.contains('active');
        sectionEl.classList.toggle('open', isActive);
        var sectionTrigger = sectionEl.querySelector('.mobile-nav-section-trigger');
        if (sectionTrigger) sectionTrigger.setAttribute('aria-expanded', String(isActive));
      }
    });
  }

  function buildMobileNavFromSidebar() {
    var sidebarNav = document.querySelector('.sidebar-nav > ul');
    var mobileNavList = document.getElementById('mobile-nav-list');
    var mobileNavTabs = document.getElementById('mobile-nav-tabs');
    if (!sidebarNav || !mobileNavList || !mobileNavTabs) return;

    mobileNavList.innerHTML = '';
    mobileNavTabs.querySelectorAll('.mobile-nav-tab').forEach(function (el) {
      el.remove();
    });

    Array.prototype.forEach.call(sidebarNav.children, function (li, index) {
      if (li.tagName !== 'LI') return;
      if (li.classList.contains('sidebar-viewing-context')) {
        var deviceLink = li.querySelector('.sidebar-viewing-device');
        if (deviceLink) {
          var deviceHref = deviceLink.getAttribute('href') || '#';
          var deviceLabel = (deviceLink.textContent || '').trim();
          var deviceTab = document.createElement('a');
          deviceTab.className = 'mobile-nav-tab';
          deviceTab.href = deviceHref;
          deviceTab.setAttribute('data-section', 'viewing-context');
          deviceTab.textContent = deviceLabel;
          deviceTab.addEventListener('click', closeMobileNav);
          mobileNavTabs.appendChild(deviceTab);
        }
        return;
      }
      var sectionLabelEl = li.querySelector(':scope > p');
      var directLink = li.querySelector(':scope > a');
      var subUl = li.querySelector(':scope > ul');

      if (sectionLabelEl && subUl) {
        var label = (sectionLabelEl.textContent || '').trim();
        var sectionId = label.toLowerCase().replace(/[^a-z0-9]+/g, '-');
        var firstLink = subUl.querySelector('a[href]');
        var sectionHome = firstLink ? firstLink.getAttribute('href') : '/docs';

        if (!isMobileNavHomeDuplicate(sectionHome, label)) {
          var tab = document.createElement('a');
          tab.className = 'mobile-nav-tab';
          tab.href = sectionHome;
          tab.setAttribute('data-section', sectionId);
          tab.textContent = label;
          tab.addEventListener('click', closeMobileNav);
          mobileNavTabs.appendChild(tab);
        }

        var block = document.createElement('div');
        block.className = 'mobile-nav-section';
        if (li.classList.contains('sidebar-flat-links')) {
          block.classList.add('mobile-nav-flat-links');
        }
        block.setAttribute('data-section', sectionId);

        var trigger = document.createElement('button');
        trigger.type = 'button';
        trigger.className = 'mobile-nav-section-trigger';
        trigger.setAttribute('aria-expanded', 'false');
        trigger.innerHTML = '<span>' + label + '</span>' + chevronSvg;

        var panel = document.createElement('div');
        panel.className = 'mobile-nav-section-panel';

        subUl.querySelectorAll(':scope > li').forEach(function (item, itemIndex) {
          var link = item.querySelector(':scope > a');
          if (!link) return;
          var mobileLink = document.createElement('a');
          mobileLink.className = (itemIndex === 0 || li.classList.contains('sidebar-flat-links'))
            ? 'mobile-nav-link'
            : 'mobile-nav-link mobile-nav-link-nested';
          mobileLink.href = link.getAttribute('href') || '#';
          mobileLink.textContent = (link.textContent || '').trim();
          mobileLink.addEventListener('click', closeMobileNav);
          panel.appendChild(mobileLink);

          var nested = item.querySelector(':scope > ul');
          if (nested) {
            var sublinks = document.createElement('div');
            sublinks.className = 'mobile-nav-sublinks';
            nested.querySelectorAll('a[href]').forEach(function (childLink) {
              var child = document.createElement('a');
              child.className = 'mobile-nav-sublink';
              child.href = childLink.getAttribute('href') || '#';
              child.textContent = (childLink.textContent || '').trim();
              child.addEventListener('click', closeMobileNav);
              sublinks.appendChild(child);
            });
            panel.appendChild(sublinks);
          }
        });

        trigger.addEventListener('click', function () {
          var isOpen = block.classList.contains('open');
          mobileNavList.querySelectorAll('.mobile-nav-section.open').forEach(function (other) {
            if (other !== block) {
              other.classList.remove('open');
              var otherTrigger = other.querySelector('.mobile-nav-section-trigger');
              if (otherTrigger) otherTrigger.setAttribute('aria-expanded', 'false');
            }
          });
          block.classList.toggle('open', !isOpen);
          trigger.setAttribute('aria-expanded', String(!isOpen));
        });

        block.appendChild(trigger);
        block.appendChild(panel);
        mobileNavList.appendChild(block);
        return;
      }

      if (directLink) {
        var linkHref = directLink.getAttribute('href') || '#';
        var linkLabel = (directLink.textContent || '').trim();
        if (!isMobileNavHomeDuplicate(linkHref, linkLabel)) {
          var tabLink = document.createElement('a');
          tabLink.className = 'mobile-nav-tab';
          tabLink.href = linkHref;
          tabLink.setAttribute('data-section', 'link-' + index);
          tabLink.textContent = linkLabel;
          tabLink.addEventListener('click', closeMobileNav);
          mobileNavTabs.appendChild(tabLink);
        }
      }
    });
    var searchInput = document.getElementById('mobile-nav-search-input');
    filterMobileNav(searchInput ? searchInput.value : '');
  }

  function bindMobileNavSearch() {
    var searchInput = document.getElementById('mobile-nav-search-input');
    if (!searchInput || searchInput.__bound) return;
    searchInput.__bound = true;
    searchInput.addEventListener('input', function () {
      filterMobileNav(searchInput.value);
    });
  }

  function bindMobileChrome() {
    var mobileMenuToggle = document.getElementById('mobile-menu-toggle');
    var mobileNavDrawer = document.getElementById('mobile-nav-drawer');
    var navMedia = window.matchMedia('(max-width: 1000px)');

    mobileMenuToggle?.addEventListener('click', function () {
      if (mobileNavDrawer?.classList.contains('open')) closeMobileNav();
      else openMobileNav();
    });

    mobileNavDrawer?.querySelectorAll('[data-mobile-nav-close]').forEach(function (el) {
      el.addEventListener('click', closeMobileNav);
    });

    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      closeMobileNav();
    });

    navMedia.addEventListener('change', syncLayoutForViewport);
    window.addEventListener('resize', syncLayoutForViewport, { passive: true });
  }

  window.HBDocsMobileNav = {
    init: function () {
      buildMobileNavFromSidebar();
      bindMobileNavSearch();
      bindMobileChrome();
      syncLayoutForViewport();
      setActiveNav(document.body.getAttribute('data-active-path') || window.location.pathname);
      document.querySelector('.mobile-nav-home')?.addEventListener('click', closeMobileNav);
      document.querySelector('.site-header-home')?.addEventListener('click', closeMobileNav);
    }
  };
})();
">>.

docs_asset_response(Parts) ->
    case valid_asset_parts(Parts) of
        true ->
            case read_docs_asset(Parts) of
                {ok, Body0} ->
                    Body = docs_asset_body(Parts, Body0),
                    {ok, #{
                        <<"status">> => 200,
                        <<"content-type">> => docs_asset_content_type(Parts),
                        <<"body">> => Body
                    }};
                {error, _Reason} ->
                    {ok, not_found_response()}
            end;
        false ->
            {ok, not_found_response()}
    end.

valid_asset_parts([]) ->
    false;
valid_asset_parts(Parts) ->
    lists:all(fun valid_asset_part/1, Parts).

valid_asset_part(Part) when is_binary(Part) ->
    Part =/= <<>> andalso
        binary:match(Part, <<"/">>) =:= nomatch andalso
        binary:match(Part, <<"..">>) =:= nomatch;
valid_asset_part(_) ->
    false.

read_docs_asset(Parts) ->
    read_docs_asset(Parts, docs_asset_paths(Parts)).

read_docs_asset(Parts, [Path | Rest]) ->
    case file:read_file(Path) of
        {ok, Body} -> {ok, Body};
        {error, _Reason} -> read_docs_asset(Parts, Rest)
    end;
read_docs_asset(_Parts, []) ->
    {error, not_found}.

docs_asset_paths(Parts) ->
    RelParts = [binary_to_list(Part) || Part <- Parts],
    [
        filename:join([device_docs_root(), "site", "assets" | RelParts]),
        filename:join([device_docs_root(), "docs", "assets" | RelParts])
    ].

docs_asset_body([<<"example-runner.js">>], Body) ->
    binary:replace(
        Body,
        <<"const DEFAULT_NODE = 'http://localhost:8734';">>,
        <<"const DEFAULT_NODE = window.location.origin;">>
    );
docs_asset_body(_Parts, Body) ->
    Body.

docs_asset_content_type(Parts) ->
    Name = lists:last(Parts),
    case filename:extension(binary_to_list(Name)) of
        ".css" -> <<"text/css; charset=utf-8">>;
        ".js" -> <<"text/javascript; charset=utf-8">>;
        ".json" -> <<"application/json">>;
        ".woff2" -> <<"font/woff2">>;
        ".png" -> <<"image/png">>;
        ".svg" -> <<"image/svg+xml">>;
        ".ico" -> <<"image/x-icon">>;
        ".mp4" -> <<"video/mp4">>;
        _ -> <<"application/octet-stream">>
    end.

render_markdown(Markdown) ->
    render_markdown(Markdown, #{}).

render_markdown(Markdown, Opts) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    iolist_to_binary(render_markdown_lines(Lines, [], [], false, #{}, Opts)).

render_markdown_with_heading_ids(Markdown, Opts) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    iolist_to_binary(render_markdown_lines(Lines, [], [], true, #{}, Opts)).

render_markdown_lines([], Para, Acc, _AddHeadingIds, _UsedIds, Opts) ->
    lists:reverse([flush_paragraph(Para, Opts) | Acc]);
render_markdown_lines([Line | Rest], Para, Acc, AddHeadingIds, UsedIds, Opts) ->
    Trim = trim(Line),
    case fence_language(Trim) of
        {ok, Lang} ->
            {CodeLines, After} = take_code_block(Rest, []),
            Block = render_code_block(Lang, lists:reverse(CodeLines)),
            render_markdown_lines(After, [], [Block, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
        false ->
            case table_block(Trim, Rest, Opts) of
                {ok, Table, AfterTable} ->
                    render_markdown_lines(AfterTable, [], [Table, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                false ->
                    case {Trim, blockquote_text(Trim), raw_html_line(Trim), heading(Trim), bullet_text(Trim), numbered_text(Trim)} of
                        {<<>>, _, _, _, _, _} ->
                            render_markdown_lines(Rest, [], [flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, {ok, Text}, _, _, _, _} ->
                            {QuoteLines, AfterQuote} = take_blockquote(Rest, [Text]),
                            Quote = render_blockquote(lists:reverse(QuoteLines), Opts),
                            render_markdown_lines(AfterQuote, [], [Quote, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, _, {ok, Html}, _, _, _} ->
                            render_markdown_lines(Rest, [], [Html, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, _, _, {Level, Text}, _, _} ->
                            {H, NewUsedIds} = render_heading(Level, Text, AddHeadingIds, UsedIds, Opts),
                            render_markdown_lines(Rest, [], [H, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, NewUsedIds, Opts);
                        {_, _, _, _, {ok, Text}, _} ->
                            {Items, AfterList} = take_list_block(Rest, unordered, [Text], []),
                            List = render_list(<<"ul">>, Items, Opts),
                            render_markdown_lines(AfterList, [], [List, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        {_, _, _, _, _, {ok, Text}} ->
                            {Items, AfterList} = take_list_block(Rest, ordered, [Text], []),
                            List = render_list(<<"ol">>, Items, Opts),
                            render_markdown_lines(AfterList, [], [List, flush_paragraph(Para, Opts) | Acc], AddHeadingIds, UsedIds, Opts);
                        _ ->
                            render_markdown_lines(Rest, [Trim | Para], Acc, AddHeadingIds, UsedIds, Opts)
                    end
            end
    end.

take_code_block([], Acc) ->
    {Acc, []};
take_code_block([Line | Rest], Acc) ->
    case is_fence(Line) of
        true -> {Acc, Rest};
        false -> take_code_block(Rest, [Line | Acc])
    end.

flush_paragraph([], _Opts) ->
    [];
flush_paragraph(Lines, Opts) ->
    Text = iolist_to_binary(lists:join(<<" ">>, lists:reverse(Lines))),
    [<<"<p>">>, render_inline(Text, Opts), <<"</p>">>].

render_heading(Level0, Text, AddHeadingIds, UsedIds, Opts) ->
    Level = max(3, min(6, Level0 + 2)),
    Tag = integer_to_binary(Level),
    DisplayText = heading_display_text(Text, Opts),
    case AddHeadingIds =:= true andalso Level0 =:= 2 of
        true ->
            Plain = strip_inline_markdown(Text),
            {HeadingId, NewUsedIds} = unique_heading_slug(Plain, UsedIds),
            Heading = [
                <<"<h">>, Tag, <<" id=\"">>, esc(HeadingId), <<"\">">>,
                render_inline(DisplayText, Opts),
                <<"</h">>, Tag, <<">">>
            ],
            {Heading, NewUsedIds};
        false ->
            {[<<"<h">>, Tag, <<">">>, render_inline(DisplayText, Opts), <<"</h">>, Tag, <<">">>], UsedIds}
    end.

heading_display_text(Text, Opts) ->
    case maps:get(<<"strip-numbered-headings">>, Opts, false) of
        true ->
            spec_section_nav_label(strip_inline_markdown(Text));
        false ->
            Text
    end.

unique_heading_slug(Text, UsedIds) ->
    unique_heading_slug(heading_slug_base(Text), UsedIds, 2).

unique_heading_slug(Base, UsedIds, _Suffix) when Base =:= <<>> ->
    {Base, UsedIds};
unique_heading_slug(Base, UsedIds, Suffix) ->
    Candidate =
        case Suffix of
            2 -> Base;
            N -> <<Base/binary, "-", (integer_to_binary(N))/binary>>
        end,
    case maps:is_key(Candidate, UsedIds) of
        true ->
            unique_heading_slug(Base, UsedIds, Suffix + 1);
        false ->
            {Candidate, maps:put(Candidate, true, UsedIds)}
    end.

heading_slug_base(Text) ->
    collapse_hyphens(
        slug_spaces_to_hyphens(
            list_to_binary(slug_keep_chars(unicode:characters_to_list(hb_util:to_lower(hb_util:bin(Text))), []))
        )
    ).

slug_keep_chars([], Acc) ->
    lists:reverse(Acc);
slug_keep_chars([C | Rest], Acc)
    when (C >= $a andalso C =< $z) orelse (C >= $0 andalso C =< $9) orelse
        C =:= $_ orelse C =:= $- orelse C =:= $\s ->
    slug_keep_chars(Rest, [C | Acc]);
slug_keep_chars([_ | Rest], Acc) ->
    slug_keep_chars(Rest, Acc).

slug_spaces_to_hyphens(Bin) ->
    slug_spaces_to_hyphens(Bin, <<>>).

slug_spaces_to_hyphens(<<>>, Acc) ->
    Acc;
slug_spaces_to_hyphens(<<" ", Rest/binary>>, Acc) ->
    slug_spaces_to_hyphens(Rest, <<Acc/binary, "-">>);
slug_spaces_to_hyphens(<<C, Rest/binary>>, Acc) ->
    slug_spaces_to_hyphens(Rest, <<Acc/binary, C>>).

collapse_hyphens(Bin) ->
    collapse_hyphen_runs(Bin).

collapse_hyphen_runs(Bin) ->
    case binary:match(Bin, <<"--">>) of
        nomatch -> Bin;
        _ -> collapse_hyphen_runs(binary:replace(Bin, <<"--">>, <<"-">>, [global]))
    end.

render_code_block(Lang, Lines) ->
    NormLang = normalize_lang(Lang),
    Text = join_lines(Lines),
    [
        <<"<pre class=\"language-">>, esc(NormLang), <<"\" data-lang=\"">>,
        esc(NormLang), <<"\"><code class=\"language-">>,
        esc(NormLang), <<"\">">>, esc(Text), <<"</code></pre>">>
    ].

table_block(Header, [Separator | Rest], Opts) ->
    TrimSeparator = trim(Separator),
    case is_table_row(Header) andalso is_table_separator(TrimSeparator) of
        true ->
            {Rows, After} = take_table_rows(Rest, []),
            {ok, render_table([Header | Rows], Opts), After};
        false ->
            false
    end;
table_block(_Header, _Rest, _Opts) ->
    false.

is_table_row(Line) ->
    Line =/= <<>> andalso binary:match(Line, <<"|">>) =/= nomatch.

is_table_separator(Line) ->
    Cells = parse_table_row(Line),
    Cells =/= [] andalso lists:all(fun is_table_separator_cell/1, Cells).

is_table_separator_cell(Cell) ->
    Trimmed = trim(Cell),
    HasDash = binary:match(Trimmed, <<"-">>) =/= nomatch,
    NoColons = binary:replace(Trimmed, <<":">>, <<>>, [global]),
    NoDashes = binary:replace(NoColons, <<"-">>, <<>>, [global]),
    HasDash andalso trim(NoDashes) =:= <<>>.

take_table_rows([Line | Rest], Acc) ->
    Trim = trim(Line),
    case is_table_row(Trim) andalso Trim =/= <<>> of
        true -> take_table_rows(Rest, [Trim | Acc]);
        false -> {lists:reverse(Acc), [Line | Rest]}
    end;
take_table_rows([], Acc) ->
    {lists:reverse(Acc), []}.

render_table([Header | Rows], Opts) ->
    HeaderCells = parse_table_row(Header),
    [
        <<"<table><thead>">>,
        render_table_row(<<"th">>, HeaderCells, Opts),
        <<"</thead><tbody>">>,
        [render_table_row(<<"td">>, parse_table_row(Row), Opts) || Row <- Rows],
        <<"</tbody></table>">>
    ].

render_table_row(Tag, Cells, Opts) ->
    [
        <<"<tr>">>,
        [[<<"<">>, Tag, <<">">>, render_inline(Cell, Opts), <<"</">>, Tag, <<">">>] || Cell <- Cells],
        <<"</tr>">>
    ].

parse_table_row(Row) ->
    Trimmed = trim(Row),
    WithoutLeading =
        case starts_with(Trimmed, <<"|">>) of
            true -> binary:part(Trimmed, 1, byte_size(Trimmed) - 1);
            false -> Trimmed
        end,
    WithoutOuter =
        case ends_with(WithoutLeading, <<"|">>) of
            true -> binary:part(WithoutLeading, 0, byte_size(WithoutLeading) - 1);
            false -> WithoutLeading
        end,
    [trim(Cell) || Cell <- binary:split(WithoutOuter, <<"|">>, [global])].

render_inline(Text, Opts) ->
    render_inline(Text, [], Opts).

render_inline(<<>>, Acc, _Opts) ->
    lists:reverse(Acc);
render_inline(Text, Acc, Opts) ->
    case inline_markers(Text) of
        [] ->
            lists:reverse([esc(Text) | Acc]);
        [{Pos, Kind, Payload} | _] ->
            Prefix = binary:part(Text, 0, Pos),
            case Kind of
                link ->
                    {Label, Url, TotalLen} = Payload,
                    RestPos = Pos + TotalLen,
                    Rest = binary:part(Text, RestPos, byte_size(Text) - RestPos),
                    Node = render_markdown_link(Label, Url, Opts),
                    render_inline(Rest, [Node, esc(Prefix) | Acc], Opts);
                code ->
                    Marker = Payload,
                    AfterStartPos = Pos + byte_size(Marker),
                    AfterStart = binary:part(Text, AfterStartPos, byte_size(Text) - AfterStartPos),
                    case binary:match(AfterStart, Marker) of
                        {EndPos, _Len} ->
                            Inner = binary:part(AfterStart, 0, EndPos),
                            RestPos = EndPos + byte_size(Marker),
                            Rest = binary:part(AfterStart, RestPos, byte_size(AfterStart) - RestPos),
                            Node = [<<"<code>">>, esc(Inner), <<"</code>">>],
                            render_inline(Rest, [Node, esc(Prefix) | Acc], Opts);
                        nomatch ->
                            render_inline(AfterStart, [esc(Marker), esc(Prefix) | Acc], Opts)
                    end;
                strong ->
                    Marker = Payload,
                    AfterStartPos = Pos + byte_size(Marker),
                    AfterStart = binary:part(Text, AfterStartPos, byte_size(Text) - AfterStartPos),
                    case binary:match(AfterStart, Marker) of
                        {EndPos, _Len} ->
                            Inner = binary:part(AfterStart, 0, EndPos),
                            RestPos = EndPos + byte_size(Marker),
                            Rest = binary:part(AfterStart, RestPos, byte_size(AfterStart) - RestPos),
                            Node = [<<"<strong>">>, render_inline(Inner, Opts), <<"</strong>">>],
                            render_inline(Rest, [Node, esc(Prefix) | Acc], Opts);
                        nomatch ->
                            render_inline(AfterStart, [esc(Marker), esc(Prefix) | Acc], Opts)
                    end
            end
    end.

render_markdown_link(Label, Url, Opts) ->
    case resolve_markdown_link(Label, Url, Opts) of
        {link, Href} ->
            [
                <<"<a href=\"">>, esc(Href), <<"\">">>,
                render_inline(Label, Opts),
                <<"</a>">>
            ];
        {code, Text} ->
            [<<"<code>">>, esc(Text), <<"</code>">>]
    end.

resolve_markdown_link(Label, Href, Opts) ->
    Trim = trim(hb_util:bin(Href)),
    case Trim of
        <<"#", _/binary>> ->
            {link, Trim};
        _ ->
            case is_external_href(Trim) of
                true ->
                    {link, Trim};
                false ->
                    case is_direct_docs_href(Trim) of
                        true ->
                            {link, Trim};
                        false ->
                            RelPath =
                                case maps:get(<<"source-relative">>, Opts, undefined) of
                                    undefined ->
                                        resolve_boilerplate_relpath_from_path(Trim);
                                    SourceRel ->
                                        resolve_doc_relpath(Trim, SourceRel)
                                end,
                            boilerplate_link_target(Label, RelPath)
                    end
            end
    end.

is_external_href(<<"http://", _/binary>>) ->
    true;
is_external_href(<<"https://", _/binary>>) ->
    true;
is_external_href(<<"mailto:", _/binary>>) ->
    true;
is_external_href(_) ->
    false.

is_direct_docs_href(<<"/~", _/binary>>) ->
    true;
is_direct_docs_href(<<"/docs", _/binary>>) ->
    true;
is_direct_docs_href(_) ->
    false.

resolve_boilerplate_relpath_from_path(<<"/", Rest/binary>>) ->
    normalize_doc_relpath(<<"docs/", Rest/binary>>);
resolve_boilerplate_relpath_from_path(Path) ->
    normalize_doc_relpath(<<"docs/", Path/binary>>).

boilerplate_link_target(Label, RelPathWithFragment) ->
    {RelPath, Fragment} = split_href_fragment(RelPathWithFragment),
    case device_id_from_doc_relpath(RelPath) of
        {ok, DeviceID} ->
            case dev_hyperbeam_docs_data:supported_device(DeviceID) of
                true -> {link, append_href_fragment(device_info_path(DeviceID), Fragment)};
                false -> {code, device_marked_id(DeviceID)}
            end;
        false ->
            case lists:keyfind(RelPath, 2, boilerplate_pages()) of
                false -> {code, link_code_label(Label)};
                _Page -> {link, append_href_fragment(boilerplate_href(RelPath), Fragment)}
            end
    end.

split_href_fragment(Href) ->
    case binary:split(Href, <<"#">>) of
        [Path, Fragment] -> {Path, <<"#", Fragment/binary>>};
        [Path] -> {Path, <<>>}
    end.

append_href_fragment(Href, <<>>) ->
    Href;
append_href_fragment(Href, Fragment) ->
    <<Href/binary, Fragment/binary>>.

device_id_from_doc_relpath(<<"docs/devices/", Rest/binary>>) ->
    File = lists:last(binary:split(Rest, <<"/">>, [global])),
    Slug = strip_suffix(File, <<".md">>),
    case binary:split(Slug, <<"-at-">>) of
        [Name, VersionSlug] when Name =/= <<>>, VersionSlug =/= <<>> ->
            Version = binary:replace(VersionSlug, <<"-">>, <<".">>, [global]),
            {ok, <<Name/binary, "@", Version/binary>>};
        _ ->
            false
    end;
device_id_from_doc_relpath(_) ->
    false.

link_code_label(Label) ->
    case trim(strip_inline_markdown(Label)) of
        <<>> -> <<"reference">>;
        Text -> Text
    end.

resolve_doc_relpath(Href, SourceRel) ->
    Trim = trim(hb_util:bin(Href)),
    case Trim of
        <<"/", Rest/binary>> ->
            normalize_doc_relpath(<<"docs/", Rest/binary>>);
        _ ->
            normalize_doc_relpath(join_doc_paths(doc_dirname(SourceRel), Trim))
    end.

doc_dirname(SourceRel) ->
    case binary:split(SourceRel, <<"/">>, [global]) of
        [<<"docs">>] ->
            <<"docs">>;
        [<<"docs">> | Parts] ->
            case Parts of
                [] ->
                    <<"docs">>;
                [_File] ->
                    <<"docs">>;
                _ ->
                    DirParts = lists:droplast(Parts),
                    iolist_to_binary([<<"docs/">>, lists:join(<<"/">>, DirParts)])
            end;
        _ ->
            <<"docs">>
    end.

join_doc_paths(Dir, Href) ->
    iolist_to_binary([Dir, <<"/">>, Href]).

normalize_doc_relpath(Path) ->
    Parts = binary:split(Path, <<"/">>, [global]),
    iolist_to_binary(lists:join(<<"/">>, normalize_doc_parts(Parts, []))).

normalize_doc_parts([], Acc) ->
    lists:reverse(Acc);
normalize_doc_parts([<<>> | Rest], Acc) ->
    normalize_doc_parts(Rest, Acc);
normalize_doc_parts([<<"..">> | Rest], [_ | Acc]) ->
    normalize_doc_parts(Rest, Acc);
normalize_doc_parts([<<"..">> | Rest], Acc) ->
    normalize_doc_parts(Rest, Acc);
normalize_doc_parts([Part | Rest], Acc) ->
    normalize_doc_parts(Rest, [Part | Acc]).

inline_markers(Text) ->
    lists:keysort(
        1,
        marker_matches(Text, <<"**">>, strong) ++
            marker_matches(Text, <<"`">>, code) ++
            link_marker_matches(Text)
    ).

link_marker_matches(Text) ->
    case parse_markdown_link(Text) of
        {ok, Pos, Label, Url, TotalLen} ->
            [{Pos, link, {Label, Url, TotalLen}}];
        error ->
            []
    end.

parse_markdown_link(Text) ->
    case binary:match(Text, <<"[">>) of
        {Pos, _} ->
            AfterOpen = binary:part(Text, Pos + 1, byte_size(Text) - Pos - 1),
            case binary:match(AfterOpen, <<"](">>) of
                {LabelEnd, _} ->
                    Label = binary:part(AfterOpen, 0, LabelEnd),
                    AfterParen = binary:part(AfterOpen, LabelEnd + 2, byte_size(AfterOpen) - LabelEnd - 2),
                    case binary:match(AfterParen, <<")">>) of
                        {UrlEnd, _} ->
                            Url = binary:part(AfterParen, 0, UrlEnd),
                            TotalLen = 1 + LabelEnd + 2 + UrlEnd + 1,
                            {ok, Pos, Label, Url, TotalLen};
                        nomatch ->
                            error
                    end;
                nomatch ->
                    error
            end;
        nomatch ->
            error
    end.

marker_matches(Text, Marker, Kind) ->
    case binary:match(Text, Marker) of
        {Pos, _Len} -> [{Pos, Kind, Marker}];
        nomatch -> []
    end.

drop_first_h1(Markdown) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    iolist_to_binary(lists:join(<<"\n">>, drop_first_h1_lines(Lines))).

drop_first_h1_lines([]) ->
    [];
drop_first_h1_lines([Line | Rest]) ->
    case heading(trim(Line)) of
        {1, _Text} -> Rest;
        _ -> [Line | Rest]
    end.

markdown_title(Markdown, Fallback) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    case [Text || Line <- Lines, {1, Text} <- [heading(trim(Line))]] of
        [Title | _] -> Title;
        [] -> Fallback
    end.

markdown_summary(Markdown) ->
    Lines = binary:split(drop_first_h1(Markdown), <<"\n">>, [global]),
    summary_from_lines(Lines).

-define(CARD_SUMMARY_MAX, 120).
-define(RECIPE_CARD_SUMMARY_MAX, 80).

card_summary(Summary) ->
    Text = trim(hb_util:bin(Summary)),
    truncate_card_summary(first_sentence(Text), ?CARD_SUMMARY_MAX).

recipe_card_summary(Recipe) ->
    Text =
        case maps:get(<<"tagline">>, Recipe, undefined) of
            undefined ->
                first_clause(trim(hb_util:bin(maps:get(<<"summary">>, Recipe, <<>>))));
            Tagline ->
                trim(hb_util:bin(Tagline))
        end,
    truncate_card_summary(Text, ?RECIPE_CARD_SUMMARY_MAX).

recipe_card_meta(Recipe) ->
    case maps:get(<<"runnable-block-count">>, Recipe, 0) of
        0 ->
            <<>>;
        Count ->
            [
                <<"<small class=\"hb-docs-recipe-card-meta\">">>,
                esc(hb_util:bin(Count)),
                <<" runnable</small>">>
            ]
    end.

first_clause(<<>>) ->
    <<>>;
first_clause(Text) ->
    case earliest_clause_split(Text) of
        undefined ->
            first_sentence(Text);
        Pos ->
            binary:part(Text, 0, Pos)
    end.

earliest_clause_split(Text) ->
    Splits = [
        clause_split(Text, <<". ">>),
        clause_split(Text, <<", ">>),
        clause_split(Text, <<" and ">>)
    ],
    case [Pos || Pos <- Splits, Pos =/= undefined] of
        [] -> undefined;
        Positions -> lists:min(Positions)
    end.

clause_split(Text, Sep) ->
    case binary:match(Text, Sep) of
        {Pos, _} when Pos > 0 -> Pos;
        _ -> undefined
    end.

first_sentence(<<>>) ->
    <<>>;
first_sentence(Text) ->
    case binary:match(Text, <<". ">>) of
        {Pos, _} ->
            binary:part(Text, 0, Pos + 1);
        nomatch ->
            Text
    end.

truncate_card_summary(Text, Max) when byte_size(Text) =< Max ->
    Text;
truncate_card_summary(Text, Max) ->
    <<(binary:part(Text, 0, Max))/binary, "...">>.

summary_from_lines([]) ->
    <<>>;
summary_from_lines([Line | Rest]) ->
    Trim = trim(Line),
    case summary_line_usable(Trim) of
        false ->
            summary_from_lines(Rest);
        true ->
            case fence_language(Trim) of
                {ok, _Lang} ->
                    {_CodeLines, AfterFence} = take_code_block(Rest, []),
                    summary_from_lines(AfterFence);
                false ->
                    case heading(Trim) of
                        false -> strip_inline_markdown(Trim);
                        _ -> summary_from_lines(Rest)
                    end
            end
    end.

summary_line_usable(<<>>) ->
    false;
summary_line_usable(<<"- **Device name", _/binary>>) ->
    false;
summary_line_usable(<<"- **Depends-on", _/binary>>) ->
    false;
summary_line_usable(<<"- **Status", _/binary>>) ->
    false;
summary_line_usable(<<"Source tests:", _/binary>>) ->
    false;
summary_line_usable(<<"Prerequisites:", _/binary>>) ->
    false;
summary_line_usable(<<">", _/binary>>) ->
    false;
summary_line_usable(<<"<", _/binary>>) ->
    false;
summary_line_usable(_) ->
    true.

strip_inline_markdown(Text) ->
    NoTicks = binary:replace(Text, <<"`">>, <<>>, [global]),
    NoTicks.

code_blocks(Markdown) ->
    Lines = binary:split(Markdown, <<"\n">>, [global]),
    code_blocks(Lines, outside, <<>>, [], [], 0).

code_blocks([], outside, _Lang, _Lines, Acc, _Index) ->
    lists:reverse(Acc);
code_blocks([], inside, Lang, Lines, Acc, Index) ->
    lists:reverse([code_block(Index, Lang, lists:reverse(Lines)) | Acc]);
code_blocks([Line | Rest], outside, _Lang, _Lines, Acc, Index) ->
    case fence_language(Line) of
        {ok, Lang} -> code_blocks(Rest, inside, Lang, [], Acc, Index);
        false -> code_blocks(Rest, outside, <<>>, [], Acc, Index)
    end;
code_blocks([Line | Rest], inside, Lang, Lines, Acc, Index) ->
    case is_fence(Line) of
        true ->
            Block = code_block(Index, Lang, lists:reverse(Lines)),
            code_blocks(Rest, outside, <<>>, [], [Block | Acc], Index + 1);
        false ->
            code_blocks(Rest, inside, Lang, [Line | Lines], Acc, Index)
    end.

code_block(Index, Lang, Lines) ->
    Text = join_lines(Lines),
    NormLang = normalize_lang(Lang),
    #{
        <<"index">> => Index,
        <<"language">> => NormLang,
        <<"text">> => Text,
        <<"runnable">> => is_runnable_block(NormLang, Text),
        <<"command-count">> => command_count(Text)
    }.

command_count(Text) ->
    Lines = binary:split(Text, <<"\n">>, [global]),
    length([Line || Line <- Lines, is_command_line(trim(Line))]).

is_runnable_block(<<"http">>, Text) ->
    not inspect_only_block(Text) andalso command_count(Text) > 0;
is_runnable_block(<<"bash">>, Text) ->
    not inspect_only_block(Text) andalso binary:match(Text, <<"curl">>) =/= nomatch;
is_runnable_block(<<"sh">>, Text) ->
    not inspect_only_block(Text) andalso binary:match(Text, <<"curl">>) =/= nomatch;
is_runnable_block(_Lang, _Text) ->
    false.

inspect_only_block(Text) ->
    has_angle_placeholder(Text) orelse
        lists:any(
            fun(Pattern) -> binary:match(Text, Pattern) =/= nomatch end,
            [
                <<"PROCESS_ID">>,
                <<"/path/to/">>,
                <<"BAD_MESSAGE_ID">>,
                <<"$(">>,
                <<"`">>
            ]
        ).

has_angle_placeholder(Text) ->
    binary:match(Text, <<"<">>) =/= nomatch andalso
        binary:match(Text, <<">">>) =/= nomatch.

is_command_line(<<"curl">>) -> true;
is_command_line(<<"curl ", _/binary>>) -> true;
is_command_line(<<"GET ", _/binary>>) -> true;
is_command_line(<<"POST ", _/binary>>) -> true;
is_command_line(<<"PUT ", _/binary>>) -> true;
is_command_line(<<"PATCH ", _/binary>>) -> true;
is_command_line(<<"DELETE ", _/binary>>) -> true;
is_command_line(<<"HEAD ", _/binary>>) -> true;
is_command_line(_Line) -> false.

heading(<<"# ", Text/binary>>) -> {1, Text};
heading(<<"## ", Text/binary>>) -> {2, Text};
heading(<<"### ", Text/binary>>) -> {3, Text};
heading(<<"#### ", Text/binary>>) -> {4, Text};
heading(<<"##### ", Text/binary>>) -> {5, Text};
heading(_Line) -> false.

blockquote_text(<<"> ", Text/binary>>) -> {ok, Text};
blockquote_text(<<">", Text/binary>>) -> {ok, Text};
blockquote_text(_Line) -> false.

take_blockquote([Line | Rest], Acc) ->
    case blockquote_text(trim(Line)) of
        {ok, Text} -> take_blockquote(Rest, [Text | Acc]);
        false -> {Acc, [Line | Rest]}
    end;
take_blockquote([], Acc) ->
    {Acc, []}.

render_blockquote(Lines, Opts) ->
    [
        <<"<blockquote>">>,
        render_markdown(iolist_to_binary(lists:join(<<"\n">>, Lines)), Opts),
        <<"</blockquote>">>
    ].

raw_html_line(<<"<video class=\"theme-invert-video\" src=\"https://arweave.net/pc73dj9tZtj7AOeIKBGiiOm5ta13FYXzgsqWSePAxiM\" style=\"width: 100%; height: auto; display: block;\" autoplay=\"\" muted=\"\" playsinline=\"\" loop=\"\" controlslist=\"nodownload nofullscreen noremoteplayback\" disablepictureinpicture=\"\" preload=\"auto\"></video>">> = Line) ->
    {ok, Line};
raw_html_line(<<"<div class=\"core-concepts-flex\">">> = Line) ->
    {ok, Line};
raw_html_line(<<"<div class=\"core-concepts-column\">">> = Line) ->
    {ok, Line};
raw_html_line(<<"</div>">> = Line) ->
    {ok, Line};
raw_html_line(<<"<img class=\"core-concepts-fig ", Rest/binary>> = Line) ->
    case allowed_core_concepts_img(Rest) of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(<<"<p class=\"core-concept-header-", Rest/binary>> = Line) ->
    case allowed_core_concept_header(Rest) of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(<<"<span class=\"core-concept-subtitle\">", Rest/binary>> = Line) ->
    case ends_with(Rest, <<"</span>">>) of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(<<"<p class=\"core-concept-copy\">", Rest/binary>> = Line) ->
    case ends_with(Rest, <<"</p>">>) andalso binary:match(Rest, <<"<script">>) =:= nomatch of
        true -> {ok, Line};
        false -> false
    end;
raw_html_line(_Line) ->
    false.

allowed_core_concepts_img(Rest) ->
    (starts_with(Rest, <<"messages\" src=\"/docs/assets/images/aosvg1.svg\"">>) orelse
        starts_with(Rest, <<"devices\" src=\"/docs/assets/images/aosvg2.svg\"">>) orelse
        starts_with(Rest, <<"paths\" src=\"/docs/assets/images/aosvg3.svg\"">>)) andalso
        ends_with(Rest, <<" alt=\"\" loading=\"lazy\">">>).

allowed_core_concept_header(Rest) ->
    (starts_with(Rest, <<"messages\"><b>Messages</b></p>">>) orelse
        starts_with(Rest, <<"devices\"><b>Devices</b></p>">>) orelse
        starts_with(Rest, <<"paths\"><b>Paths</b></p>">>)).

bullet_text(<<"- ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(<<"-   ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(<<"* ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(<<"*   ", Text/binary>>) -> {ok, trim(Text)};
bullet_text(_Line) -> false.

numbered_text(Line) ->
    case binary:split(Line, <<". ">>) of
        [Num, Text] when byte_size(Num) > 0 ->
            case is_digits(Num) of
                true -> {ok, Text};
                false -> false
            end;
        _ -> false
    end.

take_list_block([], _Kind, Current, Items) ->
    {lists:reverse([finish_list_item(Current) | Items]), []};
take_list_block([Line | Rest] = All, Kind, Current, Items) ->
    Trim = trim(Line),
    case Trim of
        <<>> ->
            {lists:reverse([finish_list_item(Current) | Items]), Rest};
        _ ->
            case list_marker(Kind, Trim) of
                {ok, Text} ->
                    take_list_block(Rest, Kind, [Text], [finish_list_item(Current) | Items]);
                false ->
                    case is_list_continuation(Line, Trim) of
                        true ->
                            take_list_block(Rest, Kind, [Trim | Current], Items);
                        false ->
                            {lists:reverse([finish_list_item(Current) | Items]), All}
                    end
            end
    end.

list_marker(unordered, Line) ->
    bullet_text(Line);
list_marker(ordered, Line) ->
    numbered_text(Line).

is_list_continuation(Line, Trim) ->
    is_indented(Line) andalso not is_block_start(Trim).

is_indented(<<" ", _/binary>>) -> true;
is_indented(<<"\t", _/binary>>) -> true;
is_indented(_Line) -> false.

is_block_start(Trim) ->
    heading(Trim) =/= false orelse
        fence_language(Trim) =/= false orelse
        bullet_text(Trim) =/= false orelse
        numbered_text(Trim) =/= false.

finish_list_item(Lines) ->
    iolist_to_binary(lists:join(<<" ">>, lists:reverse(Lines))).

render_list(Tag, Items, Opts) ->
    [
        <<"<">>, Tag, <<">">>,
        [[<<"<li>">>, render_inline(Item, Opts), <<"</li>">>] || Item <- Items],
        <<"</">>, Tag, <<">">>
    ].

is_digits(<<>>) ->
    false;
is_digits(Bin) ->
    lists:all(fun(Char) -> Char >= $0 andalso Char =< $9 end, binary_to_list(Bin)).

fence_language(Line) ->
    Trim = trim(Line),
    case starts_with(Trim, <<"```">>) of
        true ->
            Size = byte_size(Trim),
            Lang =
                case Size of
                    3 -> <<"text">>;
                    _ -> trim(binary:part(Trim, 3, Size - 3))
                end,
            {ok, normalize_lang(Lang)};
        false ->
            false
    end.

is_fence(Line) ->
    fence_language(Line) =/= false.

normalize_lang(<<"">>) -> <<"text">>;
normalize_lang(<<"sh">>) -> <<"bash">>;
normalize_lang(<<"shell">>) -> <<"bash">>;
normalize_lang(Lang) -> hb_util:to_lower(Lang).

join_lines([]) ->
    <<>>;
join_lines(Lines) ->
    iolist_to_binary(lists:join(<<"\n">>, Lines)).

trim(Bin) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Bin))).

starts_with(Bin, Prefix) when byte_size(Bin) >= byte_size(Prefix) ->
    binary:part(Bin, 0, byte_size(Prefix)) =:= Prefix;
starts_with(_Bin, _Prefix) ->
    false.

ends_with(Bin, Suffix) when byte_size(Bin) >= byte_size(Suffix) ->
    Offset = byte_size(Bin) - byte_size(Suffix),
    binary:part(Bin, Offset, byte_size(Suffix)) =:= Suffix;
ends_with(_Bin, _Suffix) ->
    false.

esc(Value) ->
    B0 = hb_util:bin(Value),
    B1 = binary:replace(B0, <<"&">>, <<"&amp;">>, [global]),
    B2 = binary:replace(B1, <<"<">>, <<"&lt;">>, [global]),
    B3 = binary:replace(B2, <<">">>, <<"&gt;">>, [global]),
    B4 = binary:replace(B3, <<"\"">>, <<"&quot;">>, [global]),
    binary:replace(B4, <<"'">>, <<"&#39;">>, [global]).

not_found_response() ->
    #{
        <<"status">> => 404,
        <<"content-type">> => <<"application/json">>,
        <<"body">> => <<"{\"error\":\"not found\"}">>
    }.


is_arweave_txid(TXID) when byte_size(TXID) =:= 43 ->
    lists:all(
        fun(Char) ->
            (Char >= $A andalso Char =< $Z) orelse
                (Char >= $a andalso Char =< $z) orelse
                (Char >= $0 andalso Char =< $9) orelse
                Char =:= $_ orelse Char =:= $-
        end,
        binary_to_list(TXID)
    );
is_arweave_txid(_TXID) ->
    false.
