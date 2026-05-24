{ ... }:

{
  # Plain text dotfiles at $HOME root, declarative via home.file.
  # (~/.vimrc is just 5 lines; .nanorc 2 lines; .latexmkrc 32 lines —
  # attrset translation buys nothing.)

  home.file.".vimrc".source = ./vim/.vimrc;
  home.file.".nanorc".source = ./vim/.nanorc;
  home.file.".latexmkrc".source = ./vim/.latexmkrc;
}
