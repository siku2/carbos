{ lib, ... }:
{
  options.carbos.user = {
    fullName = lib.mkOption {
      type = lib.types.str;
    };

    email = lib.mkOption {
      type = lib.types.str;
    };
  };
}
