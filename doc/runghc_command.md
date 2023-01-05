<div class="hidden-warning"><a href="https://docs.haskellstack.org/"><img src="https://cdn.jsdelivr.net/gh/commercialhaskell/stack/doc/img/hidden-warning.svg"></a></div>

# The `stack runghc` and `stack runhaskell` commands

~~~text
stack runghc [-- ARGUMENT(S) (e.g. stack runghc -- X.hs)]
             [--[no-]ghc-package-path] [--[no-]stack-exe] [--package PACKAGE]
             [--rts-options RTSFLAG] [--cwd DIR]
~~~

`stack runhaskell` has the same effect as `stack runghc`. `stack runghc` has the
same effect as, and is provided as a shorthand for,
[`stack exec runghc`](exec_command.md), with the exception of the `--package`
option.

Pass the option `--package <package>` to add the initial GHC argument
`-package-id=<unit_id>`, where `<unit_id>` is the unit ID of the specified
package in the installed package database. The option can be specified multiple
times.
