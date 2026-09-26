cask "clipvault" do
  version "1.0.1"
  sha256 "d885ef56ae13c506699253626efcb96776cd3fe575e68ef53678ea4ca27e14ff"

  url "https://github.com/kennethjohnbalgos/clipvault-app/releases/download/v#{version}/Clipvault-#{version}.zip"
  name "Clipvault"
  desc "Private local clipboard history for macOS"
  homepage "https://github.com/kennethjohnbalgos/clipvault-app"

  depends_on macos: :sonoma

  app "Clipvault.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Clipvault.app"]
  end

  zap trash: [
    "~/Library/Application Support/Clipboard Vault",
    "~/Library/Preferences/local.clipvault.plist",
  ]
end
