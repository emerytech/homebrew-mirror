cask "mirror" do
  version "1.3.0"
  sha256 "85cdc04a3c9ed1722c6c4e291df256d5feea5b4123385e292618a9690833be07"

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
