# `brew cook`

## "Cook" a system by installing/uninstalling everything from a manifest.

Takes a Brewfile as defined by the `brew bundle` cask. Unlike `brew
bundle`, `brew cook` will install and _uninstall_ any needed or
no-longer needed formulae. The manifest provided by the Brewfile is
absolute and what should be installed at any given time.

Also, unlike `brew bundle`, `brew cook` only needs you to specify
the packages you want. All dependencies are handled automatically.
This lets you list all the things you're interested in having,
commenting them so you have a record as to why, and everything else
is incidental to that manifest.
