cask "mirror" do
  version "1.1.0"
  sha256 "b053d036ee147e4def0c6dec0cad6073b3f1201a47bf8da5cc5b4804688fce5a"

  url "https://github.com/emerytech/homebrew-mirror/releases/download/v#{version}/Mirror.zip"
  name "Mirror"
  desc "Continuous security-camera recorder with live mirror preview"
  homepage "https://github.com/emerytech/homebrew-mirror"

  depends_on formula: "ffmpeg"

  app "Mirror.app"

  caveats <<~EOS
    Mirror.app records from your built-in camera and mic to ~/Documents/SecurityCam.
    macOS will prompt for camera and microphone access on first use.

    Note: the green camera light is hardware-controlled and cannot be turned off.
  EOS
end
