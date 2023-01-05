<div class="hidden-warning"><a href="https://docs.haskellstack.org/"><img src="https://cdn.jsdelivr.net/gh/commercialhaskell/stack/doc/img/hidden-warning.svg"></a></div>

# Editor integration

## Visual Studio Code

For further information, see the [Stack and Visual Code](Stack_and_VS_Code.md)
documentation.

## The `intero` project

For editor integration, Stack has a related project called
[intero](https://github.com/commercialhaskell/intero). It is particularly well
supported by Emacs, but some other editors have integration for it as well.

## Shell auto-completion

Love tab-completion of commands? You're not alone. If you're on bash, just run
the following command (or add it to `.bashrc`):

~~~text
eval "$(stack --bash-completion-script stack)"
~~~

For more information and other shells, see the
[Shell auto-completion wiki page](https://docs.haskellstack.org/en/stable/shell_autocompletion)
