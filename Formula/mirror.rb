class Mirror < Formula
  desc "Continuous security-camera recorder for macOS (menu bar app + scripts)"
  homepage "https://github.com/emerytech/homebrew-mirror"
  url "https://github.com/emerytech/homebrew-mirror/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "a293ad90bb7b9d7748a357cbf116391515f08eaa92499001953d26c7bea75e6b"
  license "MIT"

  depends_on "ffmpeg"
  depends_on :macos

  def install
    # Build Mirror.app (compiles the Swift menu bar app + generates the icon).
    system "bash", "menubar/build.sh"
    prefix.install "menubar/Mirror.app"

    # The underlying scripts, exposed on PATH. The app and the launchd
    # service both look for `mirror-record` in the Homebrew bin.
    bin.install "record.sh" => "mirror-record"
    bin.install "prune.sh"  => "mirror-prune"
    bin.install "status.sh" => "mirror-status"
  end

  service do
    run [opt_bin/"mirror-record"]
    keep_alive true
    run_type :immediate
    log_path var/"log/mirror.log"
    error_log_path var/"log/mirror.log"
  end

  def caveats
    <<~EOS
      Mirror.app was installed to:
        #{opt_prefix}/Mirror.app

      Open the menu bar app with:
        open #{opt_prefix}/Mirror.app

      To run it headlessly (record at login, no UI):
        brew services start mirror

      Recordings default to ~/Documents/SecurityCam. macOS will prompt for
      camera and microphone access on first record.

      Note: the green camera light is hardware-controlled and cannot be
      turned off while recording.
    EOS
  end

  test do
    assert_predicate bin/"mirror-record", :executable?
    assert_predicate prefix/"Mirror.app/Contents/MacOS/Mirror", :executable?
  end
end
