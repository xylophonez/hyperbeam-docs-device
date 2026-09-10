# HyperBEAM Docs Device

Standalone HyperBEAM Forge device for serving HyperBEAM documentation without
adding the docs implementation to HyperBEAM core.

The public device name is `hyperbeam-docs@1.0`.

## Purpose

This repository packages the docs UI, static guide content, and on-weave device
documentation renderer as a normal HyperBEAM device. Operators can load it by
preloading, pinning, or trusting the packaged device, then mount it through a
node request hook.

The main goal is to keep the docs surface independently deployable:

- no docs modules need to be committed into HyperBEAM core
- the docs device can be rebuilt and redeployed on a live edge node
- public device docs can resolve canonical on-weave `Device-Specification`
  messages while runtime devices still load from the node's normal device policy

## Scope

This device serves:

- `/docs` node documentation index
- `/docs/assets/...` static UI assets
- `/docs/introduction/...`, `/docs/forge/...`, and `/docs/processes/...`
  bundled guide pages
- `/~device@version/docs` device documentation pages
- `/~device@version/docs/spec` canonical Device-Specification Markdown
- `/~device@version/docs/schema` implementation-derived schema where available
- `/~device@version/docs/recipes` recipe pages discovered from on-weave metadata
- JSON or HTML responses based on the incoming `Accept` header

This device does not:

- replace HyperBEAM's device loader
- publish or bless canonical specs
- require HyperBEAM core source edits
- guarantee that a historical implementation archive can run on a newer
  runtime; spec documentation can still be displayed when schema extraction is
  unavailable

## Repository Layout

```text
src/dev_hyperbeam_docs.erl
  Request hook and public device entrypoints.

src/dev_hyperbeam_docs_data.erl
  Data discovery: node docs, canonical spec lookup, schema, recipes, metadata.

src/dev_hyperbeam_docs_render.erl
  HTML/JSON response construction.

src/dev_hyperbeam_docs_ui.erl
  HTML, CSS, and Markdown rendering helpers.

src/priv/dev_hyperbeam_docs/device-docs/
  Bundled guide Markdown and static docs UI assets.
```

Runtime private files are packaged into the Forge archive under
`priv/device-docs/`. The device locates them at runtime through
`hb_device_archive:implementation_dir(?MODULE)`.

## Build

Requirements:

- Erlang/OTP compatible with the pinned HyperBEAM commit
- `rebar3`
- network access to fetch `https://github.com/permaweb/HyperBEAM.git`

Compile:

```sh
rebar3 compile
```

Check the bundled docs assets:

```sh
cd src/priv/dev_hyperbeam_docs/device-docs
npm run docs:build
```

The docs asset check does not emit a `dist/` tree. HyperBEAM serves the checked
in `site/assets` and `docs/assets` files directly.

## Package And Verify

Build the Forge device archive:

```sh
rebar3 device package
```

Verify the generated archive:

```sh
rebar3 device verify
```

Build a local preloaded store containing HyperBEAM core devices plus this docs
device:

```sh
rebar3 device preload
```

Run the packaged-device smoke test:

```sh
rebar3 device test
```

`rebar3 device test` is the most useful local check because it packages the
device, builds a temporary preloaded store, loads `hyperbeam-docs@1.0` from that
store, and starts a node against the packaged form.

## Integration Model

The docs device is mounted through HyperBEAM's `on/request` hook. The hook
recognizes:

- `/docs`
- `/docs/...`
- `/~device@version/docs`
- `/~device@version/docs/...`

and rewrites those requests to this device's `route` key.

Minimal node option shape:

```erlang
#{
    <<"on">> => #{
        <<"request">> => #{
            <<"device">> => <<"hyperbeam-docs@1.0">>,
            <<"path">> => <<"request">>
        }
    }
}
```

The device must also be loadable through normal HyperBEAM device policy. Common
options are:

- include the package in the node's `preloaded-store`
- pin the docs device implementation in `trusted-devices`
- trust the signer that publishes the docs package

## Canonical Specs Vs Runtime Preload

Public docs should usually show canonical on-weave device specifications, not
the generated specifications produced while packaging a local preloaded store.

This device supports a docs-only resolver option:

```erlang
#{
    <<"docs-name-resolvers">> => [CanonicalDocsResolver],
    <<"name-resolvers">> => [
        CanonicalDocsResolver,
        RuntimePreloadedResolver
    ]
}
```

Use `docs-name-resolvers` when the node needs a runtime preloaded resolver for
codecs and local packages, but the public docs index must enumerate only a
curated canonical device map.

Important operator guidance:

- Keep the canonical resolver before generated preload resolvers for public docs.
- Do not let generated package specs become the docs source for public core
  devices.
- Keep runtime preload available for devices such as `httpsig@1.0`, `json@1.0`,
  `structured@1.0`, and `meta@1.0`.
- Avoid pinning runtime device names to historical implementation IDs on a newer
  runtime. If you need canonical trust pins for docs, pin canonical spec IDs to
  implementation IDs and let device names load through the runtime preload.

## Example Launcher Policy

The following sketch shows the separation used by a docs edge node:

```erlang
CanonicalDeviceResolver =
    #{
        <<"message@1.0">> =>
            <<"SmKKa51azSM3KjsNL4A6wAz2Nap3p4RH_PhLJYsDqac">>,
        <<"meta@1.0">> =>
            <<"eTTrhnCa2ZqJJWMLANlQcWEAy8AUjhAq1F7d2tHqd2k">>
    },

PreloadedDeviceResolver =
    %% Read from the node's preloaded-devices-index.
    RuntimeGeneratedResolver,

Opts =
    Base#{
        <<"load-remote-devices">> => true,
        <<"name-resolvers">> =>
            [CanonicalDeviceResolver, PreloadedDeviceResolver],
        <<"docs-name-resolvers">> =>
            [CanonicalDeviceResolver],
        <<"on">> => maps:merge(hb_opts:get(<<"on">>, #{}, Base), #{
            <<"request">> => #{
                <<"device">> => <<"hyperbeam-docs@1.0">>,
                <<"path">> => <<"request">>
            }
        })
    }.
```

The full canonical resolver should include every device you want listed on
`/docs`.

## Request Contract

The request hook rewrites docs routes to `hyperbeam-docs@1.0/route` with these
fields:

- `docs-kind`: `node` or `device`
- `docs-device`: target device name for device docs, or empty binary for node
  docs
- `docs-tail`: remaining path segments after `docs`
- `request`: original request metadata used for HTML/JSON negotiation

You can also call renderer entrypoints directly:

```text
/~hyperbeam-docs@1.0/index
/~hyperbeam-docs@1.0/device?for=message@1.0
/~message@1.0/docs/schema
/~hyperbeam-docs@1.0/spec?for=message@1.0
/~hyperbeam-docs@1.0/recipes?for=message@1.0
```

## Data Sources

For a device docs page, the device resolves the target device name through
`docs-name-resolvers` when present, otherwise through `name-resolvers`.

Spec Markdown is loaded in this order:

1. local preloaded store, when the requested spec ID is present there
2. local HyperBEAM cache
3. configured Arweave gateway/cache path

For public canonical docs deployments, ensure `docs-name-resolvers` points at
canonical on-weave spec IDs. That keeps the displayed docs rooted in the weave
even when the node uses generated preloaded packages for runtime mechanics.

Schema comes from the target device's public `schema` key. The runtime's
`message@1.0/schema` implementation returns the loaded device's `hb_types`
metadata; devices may export their own schema. The docs device inherits this
key too, so `/~hyperbeam-docs@1.0/schema` describes the docs device itself.

The raw schema maps function names to arities, then to `args` and `return`.
The cookbook displays the arity selected by normal dispatch for each directly
callable key, and reads request parameters from the second argument. Internal
functions and catch-all handlers are not presented as callable key inventories.
`/~device@version/schema` retains the complete runtime schema.

If the implementation or schema is unavailable, `/~device@version/docs/schema`
reports that status while the spec and recipes remain available. The docs device
does not extract BEAM metadata, discover archive files, or infer schemas from
an export list.

## Publishing

Publish a packaged device with a wallet:

```sh
rebar3 device publish --key wallet.json
```

Do not commit wallet files. `.gitignore` excludes `hyperbeam-key.json`,
`wallet.json`, build artifacts, cache directories, and logs.

## Development Notes

This repo pins HyperBEAM at:

```text
f253d77cf510b7ef07c5ded789d3bd7f32177db2
```

Update the `hb` dependency and Forge plugin ref together in `rebar.config` when
moving to a new HyperBEAM commit.

This is the AO-Core `vary` implementation in HyperBEAM PR #1124. Schema display
also requires the shared `message@1.0/schema` key and handler inheritance in the
runtime. Apply that companion change in a local HyperBEAM checkout for testing.

For local HyperBEAM development, use a rebar checkout override instead of
committing machine-local `file://` paths:

```sh
mkdir -p _checkouts
ln -s /path/to/HyperBEAM _checkouts/hb
```

Then run the normal `rebar3 compile` and `rebar3 device ...` commands.

Alternatively, with sibling `HyperBEAM` and `hyperbeam_docs` checkouts, run the
packaged integration tests from HyperBEAM:

```sh
HB_PORT=0 rebar3 device test \
  --device-src src/preloaded,../hyperbeam_docs/src \
  --module dev_hyperbeam_docs
```

These tests exercise schema inheritance, the request hook, HTML/JSON rendering,
and packaged assets on a disposable local HyperBEAM node.
