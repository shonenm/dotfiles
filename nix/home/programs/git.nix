{ config, lib, pkgs, ... }:

let
  preCommitHook = pkgs.writeShellScript "pre-commit" ''
    # Pre-commit hook: Detect merge conflict markers
    # Applied automatically to new repos via init.templateDir

    if git rev-parse --verify HEAD >/dev/null 2>&1; then
      against=HEAD
    else
      # Initial commit: diff against an empty tree
      against=$(git hash-object -t tree /dev/null)
    fi

    # Check for conflict markers in staged files
    if git diff-index --cached --diff-filter=ACM -z --name-only "$against" \
      | xargs -0 grep -lE '^(<{7}|>{7}|={7})' 2>/dev/null; then
      echo ""
      echo "ERROR: Merge conflict markers found in staged files."
      echo "Please resolve conflicts before committing."
      exit 1
    fi
  '';

  gitTemplateDir = pkgs.runCommand "git-template-dir" { } ''
    mkdir -p $out/hooks
    cp ${preCommitHook} $out/hooks/pre-commit
    chmod +x $out/hooks/pre-commit
  '';
in
{
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      dark = true;
      side-by-side = true;
      line-numbers = true;
      syntax-theme = "Visual Studio Dark+";
    };
  };

  programs.git = {
    enable = true;

    includes = [
      { path = "~/.gitconfig.local"; }
    ];

    ignores = [
      ".DS_Store"
      "**/.claude/settings.local.json"
    ];

    settings = {
      alias = {
        secrets = "!gitleaks detect --verbose";
        absorb = "!git-absorb --and-rebase";
      };

      core = {
        editor = "nvim";
      };
      init = {
        defaultBranch = "main";
        templateDir = "${gitTemplateDir}";
      };
      diff = {
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
        renames = true;
      };
      merge = {
        # `diff3` (not `zdiff3`) for portability: Ubuntu 22.04 ships git 2.34
        # which rejects `zdiff3` as unknown.
        conflictstyle = "diff3";
      };
      "merge \"conflict-driver\"" = {
        name = "Claude-powered conflict resolver";
        driver = "conflict-driver %O %A %B %L %P";
      };
      push = {
        default = "simple";
        autoSetupRemote = true;
        followTags = true;
      };
      fetch = {
        prune = true;
        pruneTags = true;
      };
      pull = {
        rebase = true;
      };
      rebase = {
        autoSquash = true;
        autoStash = true;
        updateRefs = true;
      };
      rerere = {
        enabled = true;
        autoupdate = true;
      };
      column = {
        ui = "auto";
      };
      branch = {
        sort = "-committerdate";
      };
      tag = {
        sort = "version:refname";
      };
      help = {
        autocorrect = 10;
      };
      commit = {
        verbose = true;
      };
      ghq = {
        root = "~/ghq";
      };
      "credential \"https://github.com\"" = {
        helper = [ "" "!gh auth git-credential" ];
      };
      "credential \"https://gist.github.com\"" = {
        helper = [ "" "!gh auth git-credential" ];
      };
    };
  };
}
