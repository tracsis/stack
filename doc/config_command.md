<div class="hidden-warning"><a href="https://docs.haskellstack.org/"><img src="https://cdn.jsdelivr.net/gh/commercialhaskell/stack/doc/img/hidden-warning.svg"></a></div>

# The `stack config` commands

~~~text
stack config COMMAND

Available commands:
  env                      Print environment variables for use in a shell
  set                      Sets a key in YAML configuration file to value
~~~

The `stack config` commands provide assistance with accessing or modifying
Stack's configuration. See `stack config` for the available commands.

## The `stack config env` command

~~~text
stack config env [--[no-]locals] [--[no-]ghc-package-path] [--[no-]stack-exe]
                 [--[no-]locale-utf8] [--[no-]keep-ghc-rts]
~~~

`stack config env` outputs a script that sets or unsets environment variables
for a Stack environment. Flags modify the script that is output:

* `--[no-]locals` (enabled by default) include/exclude project package
  information
* `--[no-]ghc-package-path` (enabled by default) set `GHC_PACKAGE_PATH`
  environment variable or not
* `--[no-]stack-exe` (enabled by default) set `STACK_EXE` environment variable
  or not
* `--[no-]locale-utf8` (disabled by default) set the `GHC_CHARENC`
  environment variable to `UTF-8` or not
* `--[no-]keep-ghc-rts` (disabled by default) keep/discard any `GHCRTS`
  environment variable

The command also accepts flags and options of the
[`stack build`](build_command.md#flags-affecting-ghcs-behaviour) command that
affect the location of the local project installation directory, such as
`--profile` and `--no-strip`. For further information, see the documentation of
the [project Stack work directory](stack_work.md#project-stack-work-directory).

## The `stack config set` commands

~~~text
stack config set COMMAND

Available commands:
  install-ghc              Configure whether Stack should automatically install
                           GHC when necessary.
  package-index            Configure Stack's package index
  resolver                 Change the resolver key of the current project.
  snapshot                 Change the snapshot of the current project.
  system-ghc               Configure whether Stack should use a system GHC
                           installation or not.
~~~

The `stack config set` commands allow the values of keys in YAML configuration
files to be set. See `stack config set` for the available keys.

!!! note

    The `config set` commands support an existing key only in the form
    `key: value` on a single line.

## The `stack config set install-ghc` command

~~~text
stack config set install-ghc [--global] true|false
~~~

`stack config set install-ghc true` or `false` sets the `install-ghc` key in a
YAML configuration file, accordingly. By default, the project-level
configuration file (`stack.yaml`, by default) is altered. The `--global` flag
specifies the user-specific global configuration file (`config.yaml`).

## The `stack config set package-index download-prefix` command

[:octicons-tag-24: 2.9.3](https://github.com/commercialhaskell/stack/releases/tag/v2.9.3)

~~~text
stack config set package-index download-prefix [--global] [URL]
~~~

`stack config set package-index download-prefix <url>` sets the
`download-prefix` key of the `package-index` key in a YAML configuration file,
accordingly. By default, the project-level configuration file (`stack.yaml`, by
default) is altered. The `--global` flag specifies the user-specific global
configuration file (`config.yaml`).

## The `stack config set resolver` command

~~~text
stack config set resolver SNAPSHOT
~~~

`stack config set resolver <snapshot>` sets the `resolver` key in the
project-level configuration file (`stack.yaml`, by default).

A snapshot of `lts` or `nightly` will be translated into the most recent
available. A snapshot of `lts-22` will be translated into the most recent
available in the `lts-22` sequence.

Known bug:

* The command does not respect the presence of a `snapshot` key.

## The `stack config set snapshot` command

[:octicons-tag-24: 2.15.1](https://github.com/commercialhaskell/stack/releases/tag/v2.15.1)

~~~text
stack config set snapshot SNAPSHOT
~~~

`stack config set snapshot <snapshot>` sets the `snapshot` key in the
project-level configuration file (`stack.yaml`, by default).

A snapshot of `lts` or `nightly` will be translated into the most recent
available. A snapshot of `lts-22` will be translated into the most recent
available in the `lts-22` sequence.

Known bug:

* The command does not respect the presence of a `resolver` key.

## The `stack config set system-ghc` command

~~~text
stack config set system-ghc [--global] true|false
~~~

`stack config set system-ghc true` or `false` sets the `system-ghc` key in a
YAML configuration file, accordingly. By default, the project-level
configuration file (`stack.yaml`, by default) is altered. The `--global` flag
specifies the user-specific global configuration file (`config.yaml`).
