{ ... }:

{
  # Plain text dotfiles at $HOME root, declarative via home.file.
  # (~/.vimrc is just 5 lines; .nanorc 2 lines; .latexmkrc 32 lines —
  # attrset translation buys nothing.)

  home.file.".vimrc".source = ../../../common/vim/.vimrc;
  home.file.".nanorc".source = ../../../common/vim/.nanorc;
  home.file.".latexmkrc".source = ../../../common/vim/.latexmkrc;
}
