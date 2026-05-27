cask "foil" do
  version "1.12.2"
  sha256 "39180396a7d29bd43c03165167823f91f4b7358a3937198f155a7eaae30574ad"

  url "https://github.com/mean-weasel/foil/releases/download/v#{version}/Foil-#{version}-macos.dmg"
  name "Foil"
  desc "Menu bar speech-to-text transcription with cloud and local providers"
  homepage "https://github.com/mean-weasel/foil"

  auto_updates true
  depends_on macos: :sonoma

  app "Foil.app"

  zap trash: [
    "~/Library/Application Support/com.neonwatty.Foil",
    "~/Library/Caches/com.neonwatty.Foil",
    "~/Library/Preferences/com.neonwatty.Foil.plist",
  ]
end
