{
  stdenvNoCC,
  lib,
  makeWrapper,
  bash,
  jq,
}:
stdenvNoCC.mkDerivation {
  pname = "hypr-wayvnc-virtual-display";
  version = "0.1.0";

  src = ../.;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    make install PREFIX="$out" BINDIR="$out/bin" SYSTEMD_USER_DIR="$out/lib/systemd/user"
    runHook postInstall
  '';

  postFixup = ''
    for f in $out/bin/*; do
      wrapProgram "$f" \
        --prefix PATH : ${lib.makeBinPath [ bash jq ]}
    done
  '';

  meta = with lib; {
    description = "On-demand Hyprland headless output for wayvnc, lifecycled by client connect/disconnect";
    homepage = "https://github.com/sauyon/hypr-wayvnc-virtual-display";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "wayvnc-on-demand";
  };
}
