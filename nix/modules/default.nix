# nix/modules/default.nix
#
# aweb NixOS module entrypoint.
{ ... }:

{
  imports = [
    ./aweb.nix
  ];
}
