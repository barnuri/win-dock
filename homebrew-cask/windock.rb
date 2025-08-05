cask "windock" do
  version "1.0.20"
  sha256 :no_check

  url "https://github.com/barnuri/win-dock/releases/download/v#{version}/WinDock.zip"
  name "WinDock"
  desc "Windows 11-style taskbar for macOS"
  homepage "https://github.com/barnuri/win-dock"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "WinDock.app"

  uninstall quit: "barnuri.WinDock"

  zap trash: [
    "~/Library/Application Support/WinDock",
    "~/Library/Caches/barnuri.WinDock",
    "~/Library/Preferences/barnuri.WinDock.plist",
    "~/Library/Saved Application State/barnuri.WinDock.savedState",
    "~/Library/HTTPStorages/barnuri.WinDock",
    "~/Library/WebKit/barnuri.WinDock",
  ]
end
