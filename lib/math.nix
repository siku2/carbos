{ lib }:
rec {
  # Integer exponents only, by squaring.
  pow =
    base: exponent:
    if exponent < 0 then
      1.0 / pow base (-exponent)
    else if exponent == 0 then
      1
    else
      let
        half = pow base (exponent / 2);
      in
      half * half * (if lib.mod exponent 2 == 1 then base else 1);

  # A short series on x / 1024, raised back up with pow.
  exp =
    x:
    let
      y = x / 1024.0;
    in
    pow (1.0 + y * (1.0 + y / 2 * (1.0 + y / 3 * (1.0 + y / 4 * (1.0 + y / 5 * (1.0 + y / 6)))))) 1024;
}
