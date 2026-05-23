{ ... }:

{
  programs.bat = {
    enable = true;
    config = {
      theme = "Visual Studio Dark+";
      style = "numbers,changes,header";
      italic-text = "always";
      map-syntax = [
        "*.env:DotENV"
        ".envrc:Bash"
      ];
    };
  };
}
