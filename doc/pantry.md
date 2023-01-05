<div class="hidden-warning"><a href="https://docs.haskellstack.org/"><img src="https://rawgit.com/commercialhaskell/stack/master/doc/img/hidden-warning.svg"></a></div>

# Snapshot and package location

[:octicons-tag-24: 2.1.1](https://github.com/commercialhaskell/stack/releases/tag/v2.1.1)

This document describes:

* the specification of a snapshot location (in the `resolver` key)
* the specification of a package location (in the `extra-deps` key and in a
  snapshot)

!!! info

    Stack uses the [Pantry](https://hackage.haskell.org/package/pantry) to
    specify the location of snapshots and packages. Pantry is geared towards
    reproducible build plans with cryptographically secure specification of
    snapshots and packages.

## Snapshot location

There are essentially four different ways of specifying a snapshot location:

1.  Via a compiler version, which is a "compiler only" snapshot. This could be,
    for example:

    ~~~yaml
    resolver: ghc-8.6.5`
    ~~~

2.  Via a URL pointing to a snapshot configuration file, for example:

    ~~~yaml
    resolver: https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/nightly/2018/8/21.yaml`
    ~~~

3.  Via a local file path pointing to a snapshot configuration file, for
    example:

    ~~~yaml
    resolver: my-local-snapshot.yaml
    ~~~

4.  Via a _convenience synonym_, which provides a short form for some common
    URLs. These are:

    * GitHub: `github:user/repo:path` is treated as:

        ~~~text
        https://raw.githubusercontent.com/user/repo/master/path
        ~~~

    * LTS Haskell: `lts-X.Y` is treated (by default) as:

        ~~~text
        github:commercialhaskell/stackage-snapshots:lts/X/Y.yaml
        ~~~

    * Stackage Nightly: `nightly-YYYY-MM-DD` is treated (by default) as:

        ~~~text
        github:commercialhaskell/stackage-snapshots:nightly/YYYY/M/D.yaml
        ~~~

!!! info

    By default, LTS Haskell and Stackage Nightly snapshot configurations are
    retrieved from the `stackage-snapshots` GitHub repository of user
    `commercialhaskell`. The
    [snapshot-location-base](yaml_configuration.md#snapshot-location-base)
    option allows a custom location to be set.

For safer, more reproducible builds, you can optionally specify a URL
together with a cryptographic hash of its content. For example:

~~~yaml
resolver:
  url: https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/12/0.yaml
  size: 499143
  sha256: 781ea577595dff08b9c8794761ba1321020e3e1ec3297fb833fe951cce1bee11
~~~

`size` is the number of bytes in the file and `sha256` is the file's SHA256
hash. If not provided, the information will automatically be generated and
stored in a [lock file](lock_files.md).

## Package location

There are three types of package locations:

1.  Hackage packages
2.  Git and Mecurial repositories
3.  Local or remote archives

All three types support optional tree metadata to be added, which can be used
for reproducibility and faster downloads. This information can automatically be
generated in a [lock file](lock_files.md).

### Hackage packages

Packages can be stated by a name-version combination. The basic syntax for this
is:

~~~yaml
extra-deps:
- acme-missiles-0.3
~~~

Using this syntax, the most recent Cabal file revision available will
be used.

You can specify a specific revision number, with `0` being the original file,
like this:

~~~yaml
extra-deps:
- acme-missiles-0.3@rev:0
~~~

For safer, more reproducible builds, you can optionally specify the SHA256 hash
of the Cabal file's contents, like this:

~~~yaml
extra-deps:
- acme-missiles-0.3@sha256:2ba66a092a32593880a87fb00f3213762d7bca65a687d45965778deb8694c5d1
~~~

You can optionally also specify the size of the Cabal file in bytes, like this:

~~~yaml
extra-deps:
- acme-missiles-0.3@sha256:2ba66a092a32593880a87fb00f3213762d7bca65a687d45965778deb8694c5d1,631
~~~

!!! note

    Specifying package using SHA256 is slightly more resilient in that it does
    not rely on correct ordering in the package index, while revision number is
    likely simpler to use. In practice, both should guarantee equally
    reproducible build plans.

You can also include the Pantry tree information. The following would be
generated and stored in the lock file:

~~~yaml
- hackage: acme-missiles-0.3@sha256:2ba66a092a32593880a87fb00f3213762d7bca65a687d45965778deb8694c5d1,613
  pantry-tree:
    size: 226
    sha256: 614bc0cca76937507ea0a5ccc17a504c997ce458d7f2f9e43b15a10c8eaeb033
~~~

### Git and Mercurial repositories

You can give a Git or Mercurial repository at a specific commit, and Stack will
clone that repository. For example:

~~~yaml
extra-deps:
- git: git@github.com:commercialhaskell/stack.git
  commit: 6a86ee32e5b869a877151f74064572225e1a0398
- git: git@github.com:snoyberg/http-client.git
  commit: "a5f4f3"
- hg: https://example.com/hg/repo
  commit: da39a3ee5e6b4b0d3255bfef95601890afd80709
~~~

!!! note

    It is highly recommended that you only use SHA1 values for a Git or
    Mercurial commit. Other values may work, but they are not officially
    supported, and may result in unexpected behavior (namely, Stack will not
    automatically pull to update to new versions). Another problem with this is
    that your build will not be deterministic, because when someone else tries
    to build the project they can get a different checkout of the package.

A common practice in the Haskell world is to use "megarepos", or repositories
with multiple packages in various subdirectories. Some common examples include
[wai](https://github.com/yesodweb/wai/) and
[digestive-functors](https://github.com/jaspervdj/digestive-functors). To
support this, you may also specify `subdirs` for repositories. For example:

~~~yaml
extra-deps:
- git: git@github.com:yesodweb/wai
  commit: 2f8a8e1b771829f4a8a77c0111352ce45a14c30f
  subdirs:
  - auto-update
  - wai
~~~

If unspecified, `subdirs` defaults to `['.']` meaning looking for a package in
the root of the repository. If you specify a value of `subdirs`, then `'.'` is
_not_ included by default and needs to be explicitly specified if a required
package is found in the top-level directory of the repository.

#### GitHub

[:octicons-tag-24: 1.7.1](https://github.com/commercialhaskell/stack/releases/tag/v1.7.1)

You can specify packages from GitHub repository name using `github`. For
example:

~~~yaml
extra-deps:
- github: snoyberg/http-client
  commit: a5f4f30f01366738f913968163d856366d7e0342
~~~

#### git-annex

[git-annex](https://git-annex.branchable.com) is not supported. This is because
`git archive` does not handle symbolic links outside the work tree. It is still
possible to use repositories which use git-annex but do not require the annex
files for the package to be built.

To do so, ensure that any files or directories stored by git-annex are marked
[export-ignore](https://git-scm.com/docs/git-archive#Documentation/git-archive.txt-export-ignore)
in the `.gitattributes` file in the repository. For further information, see
issue [#4579](https://github.com/commercialhaskell/stack/issues/4579).

For example, if the directory `fonts/` is controlled by git-annex, use the
following line:

~~~gitattributes
fonts export-ignore
~~~

### Local or remote archives

You can use filepaths referring to local archive files or HTTP or HTTPS URLs
referring to remote archive files, either tarballs or ZIP files.

!!! note

    Stack assumes that these archive files never change after downloading to
    avoid needing to make an HTTP request on each build.

For safer, more reproducible builds, you can optionally specify a cryptographic
hash of the archive file.

For example:

~~~yaml
extra-deps:
- https://example.com/foo/bar/baz-0.0.2.tar.gz
- archive: http://github.com/yesodweb/wai/archive/2f8a8e1b771829f4a8a77c0111352ce45a14c30f.zip
  subdirs:
  - wai
  - warp
- archive: ../acme-missiles-0.3.tar.gz
  sha256: e563d8b524017a06b32768c4db8eff1f822f3fb22a90320b7e414402647b735b
~~~
