<div class="hidden-warning"><a href="https://docs.haskellstack.org/"><img src="https://cdn.jsdelivr.net/gh/commercialhaskell/stack/doc/img/hidden-warning.svg"></a></div>

# The `stack ide` commands

~~~text
stack ide COMMAND

Available commands:
  packages                 List all available local loadable packages
  targets                  List all available Stack targets
~~~

The `stack ide` commands provide information that may be of use in an
integrated development environment (IDE). See `stack ide` for the available
commands.

## The `stack ide packages` command

~~~text
stack ide packages [--stdout] [--cabal-files]
~~~

`stack ide packages` lists all available local packages that are loadable.

By default:

* its output is sent to the standard error channel. Pass the flag `--stdout` to
  change to the standard output channel; and
* the output is the package name (without its version). Pass the flag
  `--cabal-files` to change to the full path to the package's Cabal file.

## The `stack ide targets` command

~~~text
stack ide targets [--stdout]
~~~

`stack ide targets` lists all available Stack targets.

By default, its output is sent to the standard error channel. Pass the flag
`--stdout` to change to the standard output channel.

For example, for the Stack project itself, command:

~~~text
cd stack
stack ide targets
~~~

and the output from the second command is:

~~~text
stack:lib
stack:exe:stack
stack:exe:stack-integration-test
stack:test:stack-test
~~~
