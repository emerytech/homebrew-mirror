cask "mirror" do
  version "1.2.0"
  sha256 "9bb9e51915cb1d52eb1f88be2f01bcb65008f9ef6fc7676e3c71ffb9df605fe3"

  url "https://github.com/emerytech/homebrew-mirror/releases/download/v#{version}/Mirror.zip"
  name "Mirror"
  desc "Continuous security-camera recorder with live mirror preview"
  homepage "https://github.com/emerytech/homebrew-mirror"

  depends_on :macos
  depends_on formula: "ffmpeg"

  app "Mirror.app"

  caveats <<~EOS
    Mirror.app records from your built-in camera and mic to ~/Documents/SecurityCam.
    macOS will prompt for camera and microphone access on first use.

    Note: the green camera light is hardware-controlled and cannot be turned off.
  EOS
end
