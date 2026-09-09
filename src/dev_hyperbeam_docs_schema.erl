%%% @doc Adapt the loaded implementation's schemas to the docs contract.
%%%
%%% The runtime retains schemas when loading BEAM archives, including modules
%%% whose object code is unavailable from the code server. Resolve each public
%%% key to its actual function so handlers and delegated implementations use
%%% the same argument positions and schemas as AO-Core execution.
-module(dev_hyperbeam_docs_schema).
-export([extract/2]).

%% @doc Extract public key schemas without executing the documented functions.
extract(Device, Opts) ->
    try
        maybe
            {ok, Mod} ?= hb_device_load:reference(Device, Opts),
            Base = #{ <<"device">> => Device },
            Info = hb_device:info(Mod, Base, Opts),
            Keys = public_keys(Mod, Base, Info, Opts),
            Schemas = maps:from_list([
                {Key, key_schema(Base, Key, Opts)} || Key <- Keys
            ]),
            Typed = length([
                ok || #{ <<"status">> := <<"present">> } <- maps:values(Schemas)
            ]),
            {ok, #{
                <<"module">> => atom_to_binary(Mod),
                <<"keys">> => Schemas,
                <<"key-count">> => length(Keys),
                <<"typed-key-count">> => Typed
            }}
        end
    catch
        Class:Reason -> {error, {schema_extraction_failed, Class, Reason}}
    end.

%% @doc Enumerate explicit exports, or callable exports and named handlers.
public_keys(Mod, Base, Info, Opts) ->
    Candidates =
        case hb_maps:get(exports, Info, undefined, Opts) of
            Exports when is_list(Exports) -> Exports;
            _ ->
                [
                    Name
                ||
                    {Name, Arity} <- Mod:module_info(exports),
                    Name =/= module_info,
                    Arity >= 1, Arity =< 3,
                    Name =/= info orelse Arity =:= 3
                ] ++
                    handler_keys(hb_maps:get(handler, Info, undefined, Opts), Opts) ++
                    handler_keys(hb_maps:get(default, Info, undefined, Opts), Opts)
        end,
    lists:usort([
        Key
    ||
        Name <- Candidates,
        Key <- [normalize_name(Name)],
        hb_device:is_exported(Base, Mod, Key, Opts)
    ]).

%% @doc Include a named catch-all function even when it is not an Erlang export.
handler_keys(Fun, _Opts) when is_function(Fun) ->
    {name, Name} = erlang:fun_info(Fun, name),
    [Name];
handler_keys(Handler, Opts) when is_map(Handler) ->
    handler_keys(hb_maps:get(func, Handler, undefined, Opts), Opts);
handler_keys(_Handler, _Opts) ->
    [].

%% @doc Preserve missing specs explicitly instead of reporting invented types.
key_schema(Base, Key, Opts) ->
    try
        case resolved_schema(Base, Key, Opts) of
            {ok, Schema} -> Schema#{ <<"status">> => <<"present">> };
            {error, Reason} -> unavailable(Reason)
        end
    catch
        Class:Error -> unavailable({Class, Error})
    end.

%% @doc Use the runtime's function selection and archive-backed schema store.
resolved_schema(Base, Key, Opts) ->
    maybe
        {Mode, _DeviceMod, Fun} = hb_device:message_to_fun(Base, Key, Opts),
        {module, Mod} = erlang:fun_info(Fun, module),
        {name, Name} = erlang:fun_info(Fun, name),
        {arity, Arity} = erlang:fun_info(Fun, arity),
        {ok, Schemas} ?= hb_device_load:schema(Mod, Opts),
        {ok, Head} ?= function_schema(normalize_name(Name), Key, Arity, Schemas),
        {ok, (normalize_head(Head, Mode))#{
            <<"module">> => atom_to_binary(Mod),
            <<"function">> => normalize_name(Name),
            <<"arity">> => Arity,
            <<"handler">> => Mode =:= add_key
        }}
    end.

%% @doc Match the function name first, then the key, as hb_types:vary/6 does.
function_schema(Name, Key, Arity, Schemas) ->
    case maps:get(Name, Schemas, #{}) of
        #{ Arity := Schema } -> {ok, Schema};
        _ ->
            case maps:get(Key, Schemas, #{}) of
                #{ Arity := Schema } -> {ok, Schema};
                _ -> {error, no_extractable_spec}
            end
    end.

%% @doc Map argument positions to their AO-Core roles, accounting for handlers.
normalize_head(#{ <<"args">> := Args } = Head, Mode) ->
    Roles =
        case Mode of
            add_key -> [<<"key">>, <<"base">>, <<"request">>, <<"opts">>];
            ok -> [<<"base">>, <<"request">>, <<"opts">>]
        end,
    Arguments = lists:zip(lists:sublist(Roles, length(Args)), Args),
    (maps:from_list(Arguments))#{
        <<"return">> => maps:get(<<"return">>, Head),
        <<"arguments">> => [
            #{ <<"name">> => Role, <<"type-schema">> => Type }
        || {Role, Type} <- Arguments
        ]
    }.

%% @doc Normalize Erlang function names into callable HTTP keys.
normalize_name(Name) when is_atom(Name) -> hb_util:atom_to_dashed_binary(Name);
normalize_name(Name) -> hb_ao:normalize_key(Name).

%% @doc Explain why a public key has no typed schema.
unavailable(Reason) ->
    #{
        <<"status">> => <<"unavailable">>,
        <<"reason">> => hb_util:bin(io_lib:format("~tp", [Reason]))
    }.
