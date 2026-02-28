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

  preflight do
    if File.exist?("#{staged_path}/data.tar.xz")
      system "tar", "-xf", "#{staged_path}/data.tar.xz", "-C", staged_path.to_s
    end

    if File.exist?("#{staged_path}/opt/Bitwarden/chrome-sandbox")
      system "chmod", "4755", "#{staged_path}/opt/Bitwarden/chrome-sandbox"
    end

    FileUtils.mkdir_p "#{Dir.home}/.local/share/applications"
    FileUtils.mkdir_p "#{Dir.home}/.local/share/icons"

    desktop_file = "#{staged_path}/usr/share/applications/bitwarden.desktop"
    if File.exist?(desktop_file)
      text = File.read(desktop_file)
      text = text.gsub(%r{^Exec=.*}, "Exec=#{HOMEBREW_PREFIX}/bin/bitwarden %U")
      text = text.gsub(%r{^Icon=.*}, "Icon=#{Dir.home}/.local/share/icons/bitwarden.png")
      File.write(desktop_file, text)
    end
  end

  binary "opt/Bitwarden/bitwarden"

  artifact "usr/share/applications/bitwarden.desktop",
           target: "#{Dir.home}/.local/share/applications/bitwarden.desktop"
           
  artifact "usr/share/icons/hicolor/512x512/apps/bitwarden.png",
           target: "#{Dir.home}/.local/share/icons/bitwarden.png"

  zap trash: [
    "~/.config/Bitwarden",
  ]
end
