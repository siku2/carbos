{ git-credential-manager }:
git-credential-manager.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # Backport of git-ecosystem/git-credential-manager#1837. Forgejo access
    # tokens expire after an hour, and without this the first push after that
    # fails before the refresh token is used.
    ./refresh-expired-jwt.patch
  ];
})
