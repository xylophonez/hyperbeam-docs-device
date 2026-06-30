%%% @doc Docs-owned schema extraction helpers.
%%%
%%% This mirrors the public shape of the WIP `hb_types' extractor closely
%%% enough for docs rendering, but reads BEAM binaries directly from packaged
%%% implementation archives. HyperBEAM's runtime loader keeps those binaries
%%% out of `code:get_object_code/1', so docs cannot rely only on the code
%%% server for packaged devices.
-module(dev_hyperbeam_docs_schema).
-export([extract_archive/1, normalize_extract/1]).

extract_archive(Archive) when is_binary(Archive) ->
    maybe
        {ok, Modules, _Resources} ?= hb_device_archive:contents(Archive),
        Extracted = [extract_module(Mod, Beam) || {Mod, _File, Beam} <- root_modules(Modules)],
        Good = [{Mod, Keys} || {ok, Mod, Keys} <- Extracted],
        case Good of
            [] ->
                {error, {no_abstract_schema, Extracted}};
            _ ->
                {ok,
                    #{
                        <<"module">> => join_modules([Mod || {Mod, _Keys} <- Good]),
                        <<"keys">> => merge_key_maps([Keys || {_Mod, Keys} <- Good])
                    }}
        end
    end;
extract_archive(Other) ->
    {error, {archive_not_binary, Other}}.

normalize_extract(#{ <<"keys">> := Keys } = Extracted) ->
    case normalize_keys(Keys) of
        {ok, Normalized} ->
            {ok,
                Normalized,
                maps:with([<<"module">>, <<"types">>], Extracted)};
        {error, _Reason} = Error ->
            Error
    end;
normalize_extract(Other) ->
    {error, {unexpected_schema_shape, Other}}.

root_modules(Modules) ->
    Roots =
        [
            Module
        ||  Module = {Mod, _File, _Beam} <- Modules,
            not generated_helper_module(Mod)
        ],
    case Roots of
        [] -> Modules;
        _ -> Roots
    end.

generated_helper_module(Mod) ->
    binary:match(atom_to_binary(Mod, utf8), <<"__">>) =/= nomatch.

extract_module(Mod, Beam) ->
    case beam_lib:chunks(Beam, [abstract_code]) of
        {ok, {_, [{abstract_code, {_, Forms}}]}} ->
            TypeEnv = build_type_env(Forms),
            Keys =
                lists:foldl(
                    fun(Form, Acc) ->
                        case spec_to_schema(Form, TypeEnv) of
                            false -> Acc;
                            {Key, Schema} -> merge_key_schema(Key, Schema, Acc)
                        end
                    end,
                    #{},
                    Forms
                ),
            {ok, module_label(Mod), Keys};
        {ok, {_, [{abstract_code, no_abstract_code}]}} ->
            {error, {abstract_code_unavailable, Mod, no_abstract_code}};
        Error ->
            {error, {abstract_code_unavailable, Mod, Error}}
    end.

build_type_env(Forms) ->
    lists:foldl(
        fun
            ({attribute, _, Tag, {Name, Ast, Vars}}, Acc)
                    when Tag =:= type; Tag =:= opaque ->
                Acc#{
                    Name =>
                        #{
                            vars => [var_name(Var) || Var <- Vars],
                            ast => Ast
                        }
                };
            (_, Acc) ->
                Acc
        end,
        #{},
        Forms
    ).

spec_to_schema({attribute, _, spec, {{Name, _Arity}, Heads}}, TypeEnv)
        when is_list(Heads) ->
    {normalize_name(Name), heads_to_key_schema([fun_schema(Head, TypeEnv) || Head <- Heads])};
spec_to_schema(_, _) ->
    false.

fun_schema(Spec, TypeEnv) ->
    {Args, Return} = parse_fun_spec(Spec, TypeEnv),
    #{
        <<"args">> => Args,
        <<"return">> => Return
    }.

parse_fun_spec({type, _, bounded_fun, [FunSpec, _Constraints]}, TypeEnv) ->
    parse_fun_spec(FunSpec, TypeEnv);
parse_fun_spec({type, _, 'fun', [{type, _, product, Args}, Return]}, TypeEnv) ->
    {
        [parse_type(Arg, TypeEnv, #{}, []) || Arg <- Args],
        parse_type(Return, TypeEnv, #{}, [])
    };
parse_fun_spec(Other, _TypeEnv) ->
    {[unknown_type(Other)], any_type()}.

normalize_keys(Keys) when is_map(Keys) ->
    {ok,
        maps:fold(
            fun(Key, Value, Acc) ->
                case normalize_key_schema(Value) of
                    {ok, Schema} ->
                        merge_key_schema(normalize_name(Key), Schema, Acc);
                    {error, _Reason} ->
                        Acc
                end
            end,
            #{},
            Keys
        )};
normalize_keys(Keys) when is_list(Keys) ->
    {ok,
        lists:foldl(
            fun(Entry, Acc) ->
                case normalize_key_entry(Entry) of
                    {ok, Key, Schema} -> merge_key_schema(Key, Schema, Acc);
                    {error, _Reason} -> Acc
                end
            end,
            #{},
            Keys
        )};
normalize_keys(Keys) ->
    {error, {unexpected_keys_shape, Keys}}.

normalize_key_entry({Name, Heads}) ->
    case normalize_heads(Heads) of
        {ok, NormalizedHeads} ->
            {ok, normalize_name(Name), heads_to_key_schema(NormalizedHeads)};
        {error, _Reason} = Error ->
            Error
    end;
normalize_key_entry(Other) ->
    {error, {unexpected_key_entry, Other}}.

normalize_key_schema(#{ <<"request">> := _Request } = Schema) ->
    {ok, normalize_schema_maps(Schema)};
normalize_key_schema(#{ <<"base">> := _Base } = Schema) ->
    {ok, normalize_schema_maps(Schema)};
normalize_key_schema(#{ <<"args">> := _Args } = Head) ->
    heads_to_key_schema_result([normalize_head(Head)]);
normalize_key_schema(Heads) when is_list(Heads) ->
    case normalize_heads(Heads) of
        {ok, NormalizedHeads} -> heads_to_key_schema_result(NormalizedHeads);
        {error, _Reason} = Error -> Error
    end;
normalize_key_schema(Other) ->
    {error, {unexpected_key_schema, Other}}.

normalize_heads(Heads) when is_list(Heads) ->
    Normalized = [normalize_head(Head) || Head <- Heads, is_map(Head)],
    case Normalized of
        [] -> {error, no_heads};
        _ -> {ok, Normalized}
    end;
normalize_heads(Head) when is_map(Head) ->
    {ok, [normalize_head(Head)]};
normalize_heads(Other) ->
    {error, {unexpected_heads, Other}}.

normalize_head(#{ <<"args">> := Args } = Head) when is_list(Args) ->
    #{
        <<"args">> => [normalize_type_schema(Arg) || Arg <- Args],
        <<"return">> => normalize_type_schema(maps:get(<<"return">>, Head, any_type()))
    };
normalize_head(Head) ->
    Head.

heads_to_key_schema_result(Heads) ->
    {ok, heads_to_key_schema(Heads)}.

heads_to_key_schema([]) ->
    #{
        <<"arity">> => 0,
        <<"base">> => any_type(),
        <<"request">> => any_type(),
        <<"opts">> => any_type(),
        <<"return">> => any_type(),
        <<"heads">> => []
    };
heads_to_key_schema([Head | _] = Heads) ->
    Args = maps:get(<<"args">>, Head, []),
    #{
        <<"arity">> => length(Args),
        <<"base">> => nth_or(1, Args, any_type()),
        <<"request">> => nth_or(2, Args, any_type()),
        <<"opts">> => nth_or(3, Args, any_type()),
        <<"return">> => maps:get(<<"return">>, Head, any_type()),
        <<"heads">> => Heads
    }.

nth_or(N, List, _Default) when is_list(List), length(List) >= N ->
    lists:nth(N, List);
nth_or(_N, _List, Default) ->
    Default.

merge_key_maps(Maps) ->
    lists:foldl(
        fun(Keys, Acc) ->
            maps:fold(fun merge_key_schema/3, Acc, Keys)
        end,
        #{},
        Maps
    ).

merge_key_schema(Key, Schema, Acc) ->
    maps:update_with(
        Key,
        fun(Existing) ->
            OldHeads = maps:get(<<"heads">>, Existing, [schema_to_head(Existing)]),
            NewHeads = maps:get(<<"heads">>, Schema, [schema_to_head(Schema)]),
            heads_to_key_schema(OldHeads ++ NewHeads)
        end,
        Schema,
        Acc
    ).

schema_to_head(Schema) ->
    #{
        <<"args">> =>
            [
                maps:get(<<"base">>, Schema, any_type()),
                maps:get(<<"request">>, Schema, any_type()),
                maps:get(<<"opts">>, Schema, any_type())
            ],
        <<"return">> => maps:get(<<"return">>, Schema, any_type())
    }.

normalize_schema_maps(Schema) ->
    maps:map(
        fun
            (<<"base">>, Value) -> normalize_type_schema(Value);
            (<<"request">>, Value) -> normalize_type_schema(Value);
            (<<"opts">>, Value) -> normalize_type_schema(Value);
            (<<"return">>, Value) -> normalize_type_schema(Value);
            (<<"heads">>, Heads) when is_list(Heads) -> [normalize_head(Head) || Head <- Heads];
            (_Key, Value) -> Value
        end,
        Schema
    ).

normalize_type_schema(#{ <<"kind">> := <<"map">>, <<"keys">> := Keys } = Schema)
        when is_map(Keys) ->
    normalize_type_schema(
        maps:merge(
            Schema#{ <<"kind">> => <<"message">> },
            #{ <<"keys">> => normalize_message_keys(Keys) }
        )
    );
normalize_type_schema(#{ <<"kind">> := <<"message">>, <<"keys">> := Keys } = Schema)
        when is_map(Keys) ->
    Schema#{ <<"keys">> => normalize_message_keys(Keys) };
normalize_type_schema(#{ <<"kind">> := <<"list">>, <<"item">> := Item } = Schema) ->
    Schema#{ <<"item">> => normalize_type_schema(Item) };
normalize_type_schema(#{ <<"kind">> := <<"tuple">>, <<"items">> := Items } = Schema)
        when is_list(Items) ->
    Schema#{ <<"items">> => [normalize_type_schema(Item) || Item <- Items] };
normalize_type_schema(#{ <<"kind">> := <<"union">>, <<"members">> := Members } = Schema)
        when is_list(Members) ->
    Schema#{ <<"members">> => [normalize_type_schema(Member) || Member <- Members] };
normalize_type_schema(Other) ->
    Other.

normalize_message_keys(Keys) ->
    maps:from_list(
        [
            {
                normalize_name(Key),
                Field#{ <<"type">> => normalize_type_schema(maps:get(<<"type">>, Field, any_type())) }
            }
        || {Key, Field} <- maps:to_list(Keys),
            is_map(Field)
        ]
    ).

parse_type({ann_type, _, [_Var, Type]}, TypeEnv, VarEnv, Seen) ->
    parse_type(Type, TypeEnv, VarEnv, Seen);
parse_type({var, _, '_'}, _TypeEnv, _VarEnv, _Seen) ->
    empty_type();
parse_type({var, _, Name}, TypeEnv, VarEnv, Seen) ->
    case maps:get(Name, VarEnv, undefined) of
        undefined -> variable_type(Name);
        Bound -> parse_type(Bound, TypeEnv, VarEnv, Seen)
    end;
parse_type({user_type, _, Name, Args}, TypeEnv, VarEnv, Seen) ->
    case lists:member(Name, Seen) of
        true ->
            alias_type(Name);
        false ->
            case maps:get(Name, TypeEnv, undefined) of
                undefined ->
                    alias_type(Name);
                #{ vars := Vars, ast := Ast } ->
                    parse_type(
                        Ast,
                        TypeEnv,
                        maps:merge(VarEnv, maps:from_list(lists:zip(Vars, Args))),
                        [Name | Seen]
                    )
            end
    end;
parse_type({remote_type, _, [{atom, _, Mod}, {atom, _, Name}, Args]},
        TypeEnv,
        VarEnv,
        Seen) ->
    #{
        <<"kind">> => <<"remote">>,
        <<"module">> => normalize_name(Mod),
        <<"name">> => normalize_name(Name),
        <<"args">> => [parse_type(Arg, TypeEnv, VarEnv, Seen) || Arg <- Args]
    };
parse_type({type, _, map, any}, _TypeEnv, _VarEnv, _Seen) ->
    any_type();
parse_type({type, _, map, Fields}, TypeEnv, VarEnv, Seen) ->
    message_type(parse_fields(Fields, TypeEnv, VarEnv, Seen));
parse_type({type, _, ListType, [Item]}, TypeEnv, VarEnv, Seen)
        when ListType =:= list; ListType =:= nonempty_list ->
    #{ <<"kind">> => <<"list">>, <<"item">> => parse_type(Item, TypeEnv, VarEnv, Seen) };
parse_type({type, _, ListType, []}, _TypeEnv, _VarEnv, _Seen)
        when ListType =:= list; ListType =:= nonempty_list ->
    #{ <<"kind">> => <<"list">>, <<"item">> => any_type() };
parse_type({type, _, tuple, Items}, TypeEnv, VarEnv, Seen) ->
    #{ <<"kind">> => <<"tuple">>, <<"items">> =>
        [parse_type(Item, TypeEnv, VarEnv, Seen) || Item <- Items] };
parse_type({type, _, union, Members}, TypeEnv, VarEnv, Seen) ->
    #{ <<"kind">> => <<"union">>, <<"members">> =>
        [parse_type(Member, TypeEnv, VarEnv, Seen) || Member <- Members] };
parse_type({type, _, range, [Min, Max]}, TypeEnv, VarEnv, Seen) ->
    #{
        <<"kind">> => <<"range">>,
        <<"min">> => literal_value(parse_type(Min, TypeEnv, VarEnv, Seen)),
        <<"max">> => literal_value(parse_type(Max, TypeEnv, VarEnv, Seen))
    };
parse_type({type, _, integer, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"integer">>);
parse_type({type, _, non_neg_integer, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"non-neg-integer">>);
parse_type({type, _, pos_integer, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"pos-integer">>);
parse_type({type, _, neg_integer, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"neg-integer">>);
parse_type({type, _, float, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"float">>);
parse_type({type, _, number, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"number">>);
parse_type({type, _, binary, _}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"binary">>);
parse_type({type, _, bitstring, _}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"bitstring">>);
parse_type({type, _, boolean, []}, _TypeEnv, _VarEnv, _Seen) -> boolean_type();
parse_type({type, _, atom, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"atom">>);
parse_type({type, _, pid, []}, _TypeEnv, _VarEnv, _Seen) -> scalar_type(<<"pid">>);
parse_type({type, _, any, []}, _TypeEnv, _VarEnv, _Seen) -> any_type();
parse_type({atom, _, Atom}, _TypeEnv, _VarEnv, _Seen) -> literal_type(hb_util:bin(Atom));
parse_type({integer, _, Int}, _TypeEnv, _VarEnv, _Seen) -> literal_type(Int);
parse_type({char, _, Char}, _TypeEnv, _VarEnv, _Seen) -> literal_type(<<Char/utf8>>);
parse_type({string, _, String}, _TypeEnv, _VarEnv, _Seen) -> literal_type(hb_util:bin(String));
parse_type({nil, _}, _TypeEnv, _VarEnv, _Seen) -> literal_type([]);
parse_type(Other, _TypeEnv, _VarEnv, _Seen) ->
    unknown_type(Other).

parse_fields(Fields, TypeEnv, VarEnv, Seen) ->
    lists:foldl(
        fun({type, _, Assoc, [KeyAst, ValueAst]}, {Keys, Wildcard}) ->
            Field =
                #{
                    <<"presence">> => field_presence(Assoc),
                    <<"type">> => parse_type(ValueAst, TypeEnv, VarEnv, Seen)
                },
            case key_name(KeyAst, TypeEnv, VarEnv, Seen) of
                <<"_">> -> {Keys, Field};
                Key -> {Keys#{ Key => Field }, Wildcard}
            end
        end,
        {#{}, none},
        Fields
    ).

field_presence(map_field_exact) -> required;
field_presence(map_field_assoc) -> optional;
field_presence(Other) -> normalize_name(Other).

key_name({atom, _, Atom}, _TypeEnv, _VarEnv, _Seen) ->
    normalize_name(Atom);
key_name({string, _, String}, _TypeEnv, _VarEnv, _Seen) ->
    hb_util:bin(String);
key_name({var, _, '_'}, _TypeEnv, _VarEnv, _Seen) ->
    <<"_">>;
key_name(Other, TypeEnv, VarEnv, Seen) ->
    case parse_type(Other, TypeEnv, VarEnv, Seen) of
        #{ <<"kind">> := <<"literal">>, <<"value">> := Value } when is_binary(Value) ->
            Value;
        #{ <<"kind">> := <<"literal">>, <<"value">> := Value } ->
            hb_util:bin(io_lib:format("~tp", [Value]));
        _ ->
            hb_util:bin(io_lib:format("~tp", [Other]))
    end.

normalize_name('_') ->
    <<"_">>;
normalize_name(Name) when is_atom(Name) ->
    binary:replace(atom_to_binary(Name, utf8), <<"_">>, <<"-">>, [global]);
normalize_name(Name) when is_binary(Name) ->
    Name;
normalize_name(Name) ->
    hb_util:bin(Name).

module_label(Name) when is_atom(Name) ->
    atom_to_binary(Name, utf8);
module_label(Name) ->
    hb_util:bin(Name).

join_modules(Modules) ->
    iolist_to_binary(lists:join(<<",">>, Modules)).

literal_value(#{ <<"kind">> := <<"literal">>, <<"value">> := Value }) -> Value;
literal_value(Type) -> Type.

var_name({var, _, Name}) -> Name;
var_name(Name) -> Name.

message_type({Keys, Wildcard}) ->
    #{
        <<"kind">> => <<"message">>,
        <<"keys">> => Keys,
        <<"wildcard">> => Wildcard
    }.

any_type() -> #{ <<"kind">> => <<"any">> }.
empty_type() -> #{ <<"kind">> => <<"empty">> }.
scalar_type(Name) -> #{ <<"kind">> => Name }.
literal_type(Value) -> #{ <<"kind">> => <<"literal">>, <<"value">> => Value }.
alias_type(Name) -> #{ <<"kind">> => <<"alias">>, <<"name">> => normalize_name(Name) }.
variable_type(Name) -> #{ <<"kind">> => <<"variable">>, <<"name">> => normalize_name(Name) }.
unknown_type(Other) ->
    #{ <<"kind">> => <<"unknown">>, <<"ast">> => hb_util:bin(io_lib:format("~tp", [Other])) }.
boolean_type() ->
    #{
        <<"kind">> => <<"union">>,
        <<"members">> => [literal_type(true), literal_type(false)]
    }.
