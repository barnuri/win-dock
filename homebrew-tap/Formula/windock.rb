class Windock < Formula
  desc "Windows 11-style taskbar for macOS"
  homepage "https://github.com/barnuri/win-dock"
  url "https://github.com/barnuri/win-dock/releases/download/v1.0.25/WinDock.zip"
  version "1.0.25"
  sha256 :no_check

  depends_on macos: ">= :sonoma"

  def install
    prefix.install "WinDock.app"
  end

  def caveats
    <<~EOS
      WinDock has been installed to:
        #{prefix}/WinDock.app

      To run WinDock, you can either:
      1. Open it from Finder: #{prefix}/WinDock.app
      2. Use the open command: open "#{prefix}/WinDock.app"

      To add WinDock to your Applications folder, create a symlink:
        ln -sf "#{prefix}/WinDock.app" /Applications/WinDock.app
    EOS
  end

  test do
    assert_predicate prefix/"WinDock.app", :exist?
    assert_predicate prefix/"WinDock.app/Contents/Info.plist", :exist?
  end
end
