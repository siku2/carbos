{ papers }:
papers.overrideAttrs (old: {
  passthru = old.passthru or { } // {
    desktopEntries = {
      "org.gnome.Papers" = [
        "application/vnd.comicbook-rar"
        "application/vnd.comicbook+zip"
        "application/x-cb7"
        "application/x-cbr"
        "application/x-cbt"
        "application/x-cbz"
        "application/x-ext-cb7"
        "application/x-ext-cbr"
        "application/x-ext-cbt"
        "application/x-ext-cbz"
        "application/x-ext-djv"
        "application/x-ext-djvu"
        "image/vnd.djvu"
        "image/vnd.djvu+multipage"
        "application/pdf"
        "application/x-bzpdf"
        "application/x-ext-pdf"
        "application/x-gzpdf"
        "application/x-xzpdf"
        "application/illustrator"
        "image/tiff"
      ];
      "org.gnome.Papers-previewer" = [ ];
    };
  };
})
