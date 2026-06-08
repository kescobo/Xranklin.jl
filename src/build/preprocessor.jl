"""
    register_preprocessor!(fn; key, extensions)

Register a content preprocessor with Xranklin. `fn` is called with
`(content::String, rpath::String) -> Union{String, Nothing}` before Xranklin
processes any file whose extension is in `extensions`.

- Returning a `String` replaces the file content fed to Xranklin's parser.
- Returning `nothing` tells Xranklin to skip the file entirely (no HTML output).

Multiple registrations with the same `key` replace each other, so calling this
from `utils.jl` is idempotent across reloads.
"""
function register_preprocessor!(
        fn;
        key::Symbol            = :anonymous,
        extensions::Vector{String} = [".md"]
    )::Nothing
    pps = FRANKLIN_ENV[:preprocessors]
    filter!(p -> p.first != (key, extensions), pps)
    push!(pps, (key, extensions) => fn)
    return
end

function _get_preprocessors(ext::String)
    [fn for ((_, exts), fn) in FRANKLIN_ENV[:preprocessors] if ext in exts]
end
