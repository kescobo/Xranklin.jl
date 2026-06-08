+++
showtoc = true
header = "Content preprocessors"
menu_title = "Preprocessors"
+++

## Overview

`register_preprocessor!` lets you transform or filter the raw content of source
files before Xranklin parses them. This is useful for plugins that need to
rewrite syntax or decide at build time which files to publish.

## Registering a preprocessor

Call `register_preprocessor!` from `utils.jl` with a function of the form
`(content::String, rpath::String) -> Union{String, Nothing}`:

```julia
# utils.jl

register_preprocessor!(
    function (content, rpath)
        # `content` is the raw text of the file
        # `rpath`   is the site-relative path, e.g. "notes/my-note.md"
        replace(content, "OLD" => "NEW")
    end;
    key        = :my_plugin,   # symbol identifying this preprocessor
    extensions = [".md"],      # file extensions to apply it to
)
```

The two return values have distinct meanings:

| Return value | Effect |
| ------------ | ------ |
| `String` | Xranklin parses this string instead of the file's raw content |
| `nothing` | Xranklin skips the file entirely — no HTML output is generated |

## Parameters

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| `key` | `:anonymous` | Symbol that identifies this preprocessor. Re-registering with the same key replaces the previous entry, so calling from `utils.jl` is safe across live-reload cycles. |
| `extensions` | `[".md"]` | List of file extensions (with leading dot) that this preprocessor applies to. Files with other extensions are passed through unchanged. |

## Chaining multiple preprocessors

Multiple preprocessors run in registration order. Each receives the output of
the previous one:

```julia
register_preprocessor!((c, r) -> replace(c, "foo" => "bar"); key=:step1)
register_preprocessor!((c, r) -> replace(c, "bar" => "baz"); key=:step2)
# files see "foo" → "bar" → "baz"
```

If any preprocessor in the chain returns `nothing`, processing stops and the
file is skipped.

## Filtering files by path

Use the `rpath` argument to apply transformation only to a subset of files:

```julia
register_preprocessor!(
    function (content, rpath)
        # only touch files under vault/
        startswith(rpath, "vault/") || return content
        process_vault_note(content, rpath)
    end;
    key = :vault,
)
```

## Idempotency across reloads

Each `key`/`extensions` pair is unique in the registry. Registering a
preprocessor with a key that is already in use replaces the old function — so
it is safe to call `register_preprocessor!` at the top level of `utils.jl`
without accumulating duplicates on each live-reload cycle.

## World age

Preprocessors registered in `utils.jl` are closures from a newer world age
than the Xranklin build loop. Xranklin calls them via `Base.invokelatest`, so
they work correctly without any special handling on the plugin side.

## Example: publishing filter

A plugin that controls which Markdown files are rendered can use `nothing` to
suppress output for files that should not be published:

```julia
function should_publish(content, rpath)
    # parse the YAML/TOML frontmatter
    fm = parse_frontmatter(content)
    get(fm, "publish", false)
end

register_preprocessor!(
    function (content, rpath)
        should_publish(content, rpath) ? content : nothing
    end;
    key        = :publish_filter,
    extensions = [".md"],
)
```

Xranklin will not create an output file for any note where the preprocessor
returns `nothing`.
Of course, this just duplicates the existing `ignore` functionality
that Xranklin has built-in, but you can get more complicated.

