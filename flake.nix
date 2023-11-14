{
  description = "kuberay-example";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    let
      overlays = [
        (final: prev: {
          # No overlays for now...
        })
      ];
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system overlays; config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
        };
      in
      rec {
        devShell = pkgs.mkShell rec {
          name = "kuberay-example";

          buildInputs = with pkgs; [
            gnumake
            findutils
            tmux
            google-cloud-sdk
            (google-cloud-sdk.withExtraComponents [
              pkgs.google-cloud-sdk.components.kubectl
              pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
            ])
            terraform
            tfsec
            tflint
          ];
        };
      }
    );
}
