cask "bitwarden-desktop-linux" do
  version "2026.1.0"
  sha256 "6db36b2ed691901483a1c2355bdef5ca102a1f53a26cf4be2173b9e1a4b252e5"

  url "https://github.com/bitwarden/clients/releases/download/desktop-v#{version}/Bitwarden-#{version}-amd64.deb"
  name "Bitwarden"
  desc "Secure and free password manager for all of your devices"
  homepage "https://bitwarden.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  binary "opt/Bitwarden/bitwarden"

  artifact "usr/share/applications/bitwarden.desktop",
           target: "#{Dir.home}/.local/share/applications/bitwarden.desktop"
  artifact "usr/share/pixmaps/bitwarden.png",
           target: "#{Dir.home}/.local/share/icons/bitwarden.png"

  preflight do
    desktop_file = "#{staged_path}/usr/share/applications/bitwarden.desktop"
    if File.exist?(desktop_file)
      text = File.read(desktop_file)
      new_contents = text.gsub(%r{^Exec=.*}, "Exec=#{HOMEBREW_PREFIX}/bin/bitwarden %U")
      new_contents = new_contents.gsub(%r{^Icon=.*}, "Icon=#{Dir.home}/.local/share/icons/bitwarden.png")
      File.write(desktop_file, new_contents)
    end
  end

  zap trash: [
    "~/.config/Bitwarden",
  ]
end
