cask "clipvault" do
  version "1.0.2"
  sha256 "b5e92c3c9b362fa387a2c0ce096c83ae0248ab7314ddbf154f04c5f877c3164b"

  url "https://github.com/kennethjohnbalgos/clipvault-app/releases/download/v#{version}/Clipvault-#{version}.zip"
  name "Clipvault"
  desc "Private local clipboard history for macOS"
  homepage "https://github.com/kennethjohnbalgos/clipvault-app"

  depends_on macos: :sonoma

  app "Clipvault.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Clipvault.app"]
  end

  zap trash: [
    "~/Library/Application Support/Clipboard Vault",
    "~/Library/Preferences/local.clipvault.plist",
  ]
end
