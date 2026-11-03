{
  system.defaults = {
    dock = {
      autohide = true;
      # Never show on hover. Cmd-Opt-D still toggles it.
      autohide-delay = 1000.0;
      show-recents = false;
      mru-spaces = false;
    };

    # Finder's "Remove items from the Trash after 30 days".
    finder.FXRemoveOldTrashItems = true;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  documentation.enable = false;
}
