# Helpers to isolate preprocessor state across tests
saved_pps() = copy(X.FRANKLIN_ENV[:preprocessors])
restore_pps!(saved) = (X.FRANKLIN_ENV[:preprocessors] = saved; nothing)
clear_pps!() = empty!(X.FRANKLIN_ENV[:preprocessors])


@testset "register_preprocessor!" begin
    saved = saved_pps()
    clear_pps!()
    try
        fn1 = (c, r) -> c
        X.register_preprocessor!(fn1; key=:pp_t1, extensions=[".md"])
        @test length(X.FRANKLIN_ENV[:preprocessors]) == 1
        @test X.FRANKLIN_ENV[:preprocessors][1].second === fn1

        # same key + same extensions → replaces
        fn2 = (c, r) -> c * " extra"
        X.register_preprocessor!(fn2; key=:pp_t1, extensions=[".md"])
        @test length(X.FRANKLIN_ENV[:preprocessors]) == 1
        @test X.FRANKLIN_ENV[:preprocessors][1].second === fn2

        # different key → both stored
        fn3 = (c, r) -> reverse(c)
        X.register_preprocessor!(fn3; key=:pp_t2, extensions=[".md"])
        @test length(X.FRANKLIN_ENV[:preprocessors]) == 2

        # default key is :anonymous
        fn4 = (c, r) -> c
        X.register_preprocessor!(fn4)
        keys_stored = [p.first[1] for p in X.FRANKLIN_ENV[:preprocessors]]
        @test :anonymous in keys_stored

        # re-registering :anonymous replaces previous :anonymous
        n_before = length(X.FRANKLIN_ENV[:preprocessors])
        X.register_preprocessor!((c, r) -> c)
        @test length(X.FRANKLIN_ENV[:preprocessors]) == n_before

        # same key, different extensions → separate entries (different key tuples)
        X.register_preprocessor!((c, r) -> c; key=:pp_t1, extensions=[".txt"])
        n_md  = count(p -> p.first == (:pp_t1, [".md"]),  X.FRANKLIN_ENV[:preprocessors])
        n_txt = count(p -> p.first == (:pp_t1, [".txt"]), X.FRANKLIN_ENV[:preprocessors])
        @test n_md == 1
        @test n_txt == 1
    finally
        restore_pps!(saved)
    end
end


@testset "_get_preprocessors" begin
    saved = saved_pps()
    clear_pps!()
    try
        fn_md  = (c, r) -> c
        fn_txt = (c, r) -> c * "!"
        fn_both = (c, r) -> strip(c)

        X.register_preprocessor!(fn_md;   key=:pp_md,   extensions=[".md"])
        X.register_preprocessor!(fn_txt;  key=:pp_txt,  extensions=[".txt"])
        X.register_preprocessor!(fn_both; key=:pp_both, extensions=[".md", ".txt"])

        pps_md = X._get_preprocessors(".md")
        @test length(pps_md) == 2
        @test fn_md  in pps_md
        @test fn_both in pps_md

        pps_txt = X._get_preprocessors(".txt")
        @test length(pps_txt) == 2
        @test fn_txt  in pps_txt
        @test fn_both in pps_txt

        @test isempty(X._get_preprocessors(".html"))
        @test isempty(X._get_preprocessors(".jl"))
    finally
        restore_pps!(saved)
    end
end


@testset "pass_1 — preprocessor transforms content" begin
    saved = saved_pps()
    d, gc = testdir(tag=false)
    X.set_current_global_context(gc)
    clear_pps!()
    try
        X.register_preprocessor!(
            (c, r) -> replace(c, "hello" => "goodbye");
            key=:pp_transform
        )

        write(d/"pp_transform.md", "hello world")
        X.process_md_file(gc, "pp_transform.md")

        out = read(X.path(gc, :site)/"pp_transform"/"index.html", String)
        @test contains(out, "goodbye")
        @test !contains(out, "hello")
    finally
        restore_pps!(saved)
    end
end


@testset "pass_1 — preprocessor returning nothing skips file" begin
    saved = saved_pps()
    d, gc = testdir(tag=false)
    X.set_current_global_context(gc)
    clear_pps!()
    try
        X.register_preprocessor!((c, r) -> nothing; key=:pp_skip)

        write(d/"pp_skip.md", "should not render")
        X.process_md_file(gc, "pp_skip.md")

        ofile = X.path(gc, :site)/"pp_skip"/"index.html"
        @test !isfile(ofile)
    finally
        restore_pps!(saved)
    end
end


@testset "pass_1 — extension filtering" begin
    saved = saved_pps()
    d, gc = testdir(tag=false)
    X.set_current_global_context(gc)
    clear_pps!()
    try
        # Register a skip preprocessor for .txt only — should not affect .md
        X.register_preprocessor!((c, r) -> nothing; key=:pp_ext, extensions=[".txt"])

        write(d/"ext_test.md", "visible content")
        X.process_md_file(gc, "ext_test.md")

        out = read(X.path(gc, :site)/"ext_test"/"index.html", String)
        @test contains(out, "visible content")
    finally
        restore_pps!(saved)
    end
end


@testset "pass_1 — invokelatest: newer-world closure works" begin
    saved = saved_pps()
    d, gc = testdir(tag=false)
    X.set_current_global_context(gc)
    clear_pps!()
    try
        # Simulate a preprocessor closure created in a different world age by
        # defining a function via eval (increments world age) and wrapping it.
        eval(:(newer_world_fn(c) = replace(c, "old" => "new")))
        X.register_preprocessor!((c, r) -> newer_world_fn(c); key=:pp_world)

        write(d/"world_test.md", "old content")
        # Would throw MethodError without Base.invokelatest in pass_1
        X.process_md_file(gc, "world_test.md")

        out = read(X.path(gc, :site)/"world_test"/"index.html", String)
        @test contains(out, "new content")
        @test !contains(out, "old content")
    finally
        restore_pps!(saved)
    end
end


@testset "pass_1 — multiple preprocessors run in order" begin
    saved = saved_pps()
    d, gc = testdir(tag=false)
    X.set_current_global_context(gc)
    clear_pps!()
    try
        # first: "alpha" → "beta", second: "beta" → "gamma"
        X.register_preprocessor!((c, r) -> replace(c, "alpha" => "beta");  key=:pp_chain1)
        X.register_preprocessor!((c, r) -> replace(c, "beta"  => "gamma"); key=:pp_chain2)

        write(d/"chain_test.md", "alpha word")
        X.process_md_file(gc, "chain_test.md")

        out = read(X.path(gc, :site)/"chain_test"/"index.html", String)
        @test contains(out, "gamma")
        @test !contains(out, "alpha")
        @test !contains(out, "beta")
    finally
        restore_pps!(saved)
    end
end
