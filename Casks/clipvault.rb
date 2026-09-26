cask "clipvault" do
  version "1.0.0"
  sha256 "4d12b3bea11e8cac0172641af8663ea5438d730884d2d2bbb38d8eeba5fe0ac4"

  url "https://github.com/kennethjohnbalgos/clipvault-app/releases/download/v#{version}/Clipvault-#{version}.zip"
  name "Clipvault"
  desc "Private local clipboard history for macOS"
  homepage "https://github.com/kennethjohnbalgos/clipvault-app"

  depends_on macos: :ventura

  app "Clipvault.app"

  zap trash: [
    "~/Library/Application Support/Clipboard Vault",
    "~/Library/Preferences/local.clipvault.plist",
  ]
end
