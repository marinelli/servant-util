rec {
  sources = import ./nix/sources.nix;
  haskellNix = import sources."haskell.nix" {
    sourcesOverride = { hackage = sources."hackage.nix"; stackage = sources."stackage.nix"; };
  };
  pkgs = import sources.nixpkgs haskellNix.nixpkgsArgs;

  local-packages = [
    { name = "servant-util";         subdirectory = "servant-util"; }
    { name = "servant-util-beam-pg"; subdirectory = "servant-util-beam-pg"; }
  ];

  # names of all local packages
  local-packages-names = map (p: p.name) local-packages;

  # a set mapping package name to package subdirectory
  subdirectories = pkgs.lib.listToAttrs (map ({ name, subdirectory }:
    { inherit name; value = subdirectory; }
  ) local-packages);

  # source with gitignored files filtered out
  projectSrc = pkgs.haskell-nix.haskellLib.cleanGit {
    name = "servant-util";
    src = ./.;
  };

  # haskell.nix does not support 'include' in package.yaml, we have to generate .cabal ourselves
  cabalFiles = pkgs.runCommand "servant-util-cabal-files" {} ''
    mkdir -p $out
    ${pkgs.lib.concatMapStrings ({ name, subdirectory }: ''
      ${pkgs.haskellPackages.hpack}/bin/hpack ${projectSrc}/${subdirectory} - > $out/${name}.cabal
    '') local-packages}
  '';

  hs-pkgs = pkgs.haskell-nix.stackProject {
    # project src with .cabal files added
    src = pkgs.runCommand "src-with-cabal" {} ''
      cp -r --no-preserve=mode ${projectSrc} $out
      ${pkgs.lib.concatMapStrings ({ name, subdirectory }: ''
        cp ${cabalFiles}/${name}.cabal $out/${subdirectory}
      '') local-packages}
    '';

    ignorePackageYaml = true;

    modules = [{
      # configuration for local packages
      packages = pkgs.lib.genAttrs local-packages-names (packageName: {
        # disable optimizations, error on warning
        ghcOptions = [ "-O0" "-Werror" ];

        # run haddock for local packages
        doHaddock = true;
      });

      # don't haddock dependencies
      doHaddock = false;
    }];
  };

  # component set for each local package
  packages = pkgs.lib.genAttrs local-packages-names (pkg: hs-pkgs.${pkg}.components);

  # returns a list of all components for a package
  get-package-components = pkg: with pkg.components; with pkgs.lib;
    optionals (pkg ? library) [ library library.haddock ]
    ++ attrValues exes
    ++ attrValues tests;

  # a list of all components from all local packages
  all-components = pkgs.lib.concatMap (pkg: get-package-components hs-pkgs.${pkg}) local-packages-names;
}
