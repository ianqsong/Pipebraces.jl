# Pipebraces `|> {}` 
A small extension to the surface syntax of `Julia Base`, which provides a convenient piping tool for prototyping.
---

## With this extension you can do ...
- `last(first(["hello", "world"]))` could be piping with braces as below.
```jl
julia> ["hello", "world"] |> {
       first;
       last
       }
'o': ASCII/Unicode U+006F (category Ll: Letter, lowercase)
```
- `(first(["hello", "world"]), last(["hello", "world"]))` could be keyed in as below.
```jl
julia> ["hello", "world"] |> {
       first last
       }
("hello", "world")
```
- Please note that `{f;g}` is like a column while `{f g}` is like a row. 
In fact it has been deprecated matrix syntax in Julia. Aslo, you could use comma, `{f,g}`, when there were no "row", i.e., `{f g}` involved.

- Also, you could `println` intermiate results. Eg. the output of the step 1 in the following example, is printed with three dots "...".  
```jl
julia> ["hello", "world"] |> {
       join(_, ", ") * '!', println,
       uppercasefirst
       }
... hello, world!
"Hello, world!"
```

## Usage
- When loading the package, a binary choice question shows up.
```jl
julia> using Pipebraces
Piping directly (y) or using the macro `@pb` (otherwise) ? [y] : 
```
The former choice is the default, i.e., when you hit enter key or input nothing in about 4 seconds, you could pipe without calling the macro in an REPL where users can set `Base.active_repl_backend.ast_transforms`.

- In Pluto notebooks, where `Base.active_repl_backend.ast_transforms` is not defined, you might just use the macro by `using Pipebraces: @pb` and ignore the question.

### Let's see the usage through a typical example.
```jl
julia> using DataFrames

julia> abspath(DEPOT_PATH[3], "base") |> {
        # use `_` to specify the position of the argument
        Cmd(["grep", "-r", "braces", _]);
        # by default it piped into the first argument when there are no `_` or `__` (Cf. next section for anonymous functions)
        read(String);
        # however you need specify the position of the argument 
        # when it's not a simple function call
        split(_, '\n', keepempty=false)[1:min(20, end)];
        # in dot syntax you also need specify the position of the argument
        split.(_, r"(?<=\.jl):");
        # multiple functions with space(s) in one line would output a tuple
        # also can't use either one or two `@.` for the two functions in the row, i.e., `basename` and `string`
        basename.(getindex.(_,1)) string.(getindex.(_,2));
        DataFrame(file=_[1], line=_[2])
        }
```

## Shortcut for anonymous functions
- In pipe braces you could write `_1 * 100 + _2` for the anonymous function `(x, y) -> x *100 + y`. The variables one can name in the shortcut of anonymous functions should be in the pattern `r"^_\d*$"`. (one can't use variables `_` and `_00` simultaneously as this package would internally treat `_` as `_00`.)
```jl
julia> using DataFrames

julia> df = DataFrame(x = [1, 3, 2, 1], y = 1:4);
julia> df |> {
           filter([:x, :y] => _1 > _2, __), 
           transform([:x, :y] => _1 *100 + _2 => :z)
       }
1×3 DataFrame
 Row │ x      y      z     
     │ Int64  Int64  Int64 
─────┼─────────────────────
   1 │     3      2    302
```
- Use `__` instead of `_` to reprensent the piping argument here.
Eg. the row of `filter` in the example above. However, when `_` is not used for anonymous function, you can **NOT** use `__` (as no need to do it).
- Only one anonymous function can be abbreviated this way per function call in the pipe.

## The last but not least
- It is recommended to use `;` instead of `,`. If a row `{f g}` was involved, or a macro `{@m f}` is used, `;` is the only option, i.e., `{...; f g; ...}` and `{...; @m f; ...}`.
- Multi-line function calls are not supported, like `map` with `do` block. 
- This package adopts the idea of using curly braces in the [proposal](https://discourse.julialang.org/t/fixing-the-piping-chaining-issue-rev-3/90836), which is in favor of `.{}` syntax.