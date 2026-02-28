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

  # Link the main binary to the Homebrew prefix
  binary "opt/Bitwarden/bitwarden"

  preflight do
    # 1. Manually extract the data archive from the .deb container
    # Homebrew sometimes doesn't extract the inner data.tar.xz automatically on Linux
    if File.exist?("#{staged_path}/data.tar.xz")
      system "tar", "-xf", "#{staged_path}/data.tar.xz", "-C", staged_path.to_s
    end

    # 2. Set necessary SUID permissions for the Electron chrome-sandbox
    # This is required for the application to launch correctly on many Linux kernels
    if File.exist?("#{staged_path}/opt/Bitwarden/chrome-sandbox")
      system "chmod", "4755", "#{staged_path}/opt/Bitwarden/chrome-sandbox"
    end

    # 3. Ensure local user directories exist for desktop integration
    FileUtils.mkdir_p "#{Dir.home}/.local/share/applications"
    FileUtils.mkdir_p "#{Dir.home}/.local/share/icons"

    # 4. Patch and install the .desktop entry
    # We update the executable path to point to the Homebrew binary and fix the icon reference
    desktop_src = "#{staged_path}/usr/share/applications/bitwarden.desktop"
    desktop_dst = "#{Dir.home}/.local/share/applications/bitwarden.desktop"
    
    if File.exist?(desktop_src)
      text = File.read(desktop_src)
      text = text.gsub(%r{^Exec=.*}, "Exec=#{HOMEBREW_PREFIX}/bin/bitwarden %U")
      text = text.gsub(%r{^Icon=.*}, "Icon=bitwarden")
      File.write(desktop_src, text)
      FileUtils.cp(desktop_src, desktop_dst)
    end

    # 5. Install the application icon
    # We use the high-resolution 512x512 icon for better display quality
    icon_src = "#{staged_path}/usr/share/icons/hicolor/512x512/apps/bitwarden.png"
    icon_dst = "#{Dir.home}/.local/share/icons/bitwarden.png"
    if File.exist?(icon_src)
      FileUtils.cp(icon_src, icon_dst)
    end
  end

  # Manually clean up desktop integration files upon uninstallation
  uninstall_postflight do
    FileUtils.rm_f "#{Dir.home}/.local/share/applications/bitwarden.desktop"
    FileUtils.rm_f "#{Dir.home}/.local/share/icons/bitwarden.png"
  end

  zap trash: [
    "~/.config/Bitwarden",
  ]
end
