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
    # 1. Extract the .deb container using ar (a .deb is an ar-archive)
    system "ar", "x", "#{staged_path}/Bitwarden-#{version}-amd64.deb", chdir: staged_path

    # 2. Extract the inner data archive (may be .zst, .xz, or .gz depending on deb version)
    data_archive = Dir.glob("#{staged_path}/data.tar.*").first
    if data_archive
      system "tar", "-xf", data_archive, "-C", staged_path.to_s
    else
      odie "Could not find data.tar.* inside the .deb archive"
    end

    # 3. Set necessary SUID permissions for the Electron chrome-sandbox
    # This is required for the application to launch correctly on many Linux kernels
    if File.exist?("#{staged_path}/opt/Bitwarden/chrome-sandbox")
      system "chmod", "4755", "#{staged_path}/opt/Bitwarden/chrome-sandbox"
    end

    # 4. Ensure local user directories exist for desktop integration
    FileUtils.mkdir_p "#{Dir.home}/.local/share/applications"
    FileUtils.mkdir_p "#{Dir.home}/.local/share/icons"

    # 5. Patch and install the .desktop entry
    desktop_src = "#{staged_path}/usr/share/applications/bitwarden.desktop"
    desktop_dst = "#{Dir.home}/.local/share/applications/bitwarden.desktop"

    if File.exist?(desktop_src)
      text = File.read(desktop_src)
      text = text.gsub(%r{^Exec=.*}, "Exec=#{HOMEBREW_PREFIX}/bin/bitwarden %U")
      text = text.gsub(%r{^Icon=.*}, "Icon=bitwarden")
      File.write(desktop_src, text)
      FileUtils.cp(desktop_src, desktop_dst)
    end

    # 6. Install the application icon
    icon_src = "#{staged_path}/usr/share/icons/hicolor/512x512/apps/bitwarden.png"
    icon_dst = "#{Dir.home}/.local/share/icons/bitwarden.png"
    if File.exist?(icon_src)
      FileUtils.cp(icon_src, icon_dst)
    end

    # 7. Write a helper script for AppArmor profile installation.
    # Installing the profile requires root, so we provide it as a post-install
    # step the user runs manually (see caveats). This mirrors the approach used
    # by linux-mcp-server in this tap.
    apparmor_profile_src = "#{staged_path}/opt/Bitwarden/resources/apparmor-profile"
    setup_script = "#{HOMEBREW_PREFIX}/bin/bitwarden-apparmor-setup"

    File.write(setup_script, <<~BASH)
      #!/bin/bash
      set -e

      PROFILE_SRC="#{staged_path}/opt/Bitwarden/resources/apparmor-profile"
      PROFILE_DST="/etc/apparmor.d/bitwarden"

      if ! apparmor_status --enabled > /dev/null 2>&1; then
        echo "AppArmor is not enabled on this system, nothing to do."
        exit 0
      fi

      if ! apparmor_parser --skip-kernel-load --debug "$PROFILE_SRC" > /dev/null 2>&1; then
        echo "This version of AppArmor does not support the bundled profile, skipping."
        exit 0
      fi

      echo "Installing AppArmor profile to $PROFILE_DST (requires sudo)..."
      sudo cp -f "$PROFILE_SRC" "$PROFILE_DST"
      sudo apparmor_parser --replace --write-cache --skip-read-cache "$PROFILE_DST"
      echo "Done! You can now enable 'Unlock with system authentication' in Bitwarden settings."
    BASH

    system "chmod", "+x", setup_script
  end

  # Remove desktop integration, AppArmor profile, and the setup script on uninstall
  uninstall_postflight do
    FileUtils.rm_f "#{Dir.home}/.local/share/applications/bitwarden.desktop"
    FileUtils.rm_f "#{Dir.home}/.local/share/icons/bitwarden.png"
    FileUtils.rm_f "#{HOMEBREW_PREFIX}/bin/bitwarden-apparmor-setup"

    if File.exist?("/etc/apparmor.d/bitwarden")
      system "sudo", "rm", "-f", "/etc/apparmor.d/bitwarden"
    end
  end

  def caveats
    <<~EOS
      To enable "Unlock with system authentication" in Bitwarden settings,
      run the following command after installation:

        bitwarden-apparmor-setup

      This installs the AppArmor profile and requires your sudo password.
    EOS
  end

  zap trash: [
    "~/.config/Bitwarden",
  ]
end
