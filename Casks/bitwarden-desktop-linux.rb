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

    # 7. Write the polkit policy content.
    # Taken verbatim from Bitwarden source:
    # apps/desktop/src/key-management/biometrics/os-biometrics-linux.service.ts
    # This is identical to what Bitwarden's own runSetup() installs via pkexec.
    polkit_policy = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE policyconfig PUBLIC
       "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
       "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">

      <policyconfig>
          <action id="com.bitwarden.Bitwarden.unlock">
            <description>Unlock Bitwarden</description>
            <message>Authenticate to unlock Bitwarden</message>
            <defaults>
              <allow_any>no</allow_any>
              <allow_inactive>no</allow_inactive>
              <allow_active>auth_self</allow_active>
            </defaults>
          </action>
      </policyconfig>
    XML

    File.write("#{staged_path}/com.bitwarden.Bitwarden.policy", polkit_policy)

    # 8. Write helper scripts for polkit policy management.
    # We mirror exactly what Bitwarden's runSetup() does:
    #   - install policy to /usr/share/polkit-1/actions/
    #   - chcon for SELinux context (Fedora/Bluefin/Bazzite)
    # pkexec is used instead of sudo, matching Bitwarden's own implementation.
    File.write("#{staged_path}/bitwarden-polkit-setup", <<~BASH)
      #!/bin/bash
      set -e

      POLICY_SRC="#{staged_path}/com.bitwarden.Bitwarden.policy"
      POLICY_DST="/usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy"

      echo "Installing Bitwarden polkit policy (requires authentication)..."
      pkexec bash -c "
        cp -f '$POLICY_SRC' '$POLICY_DST' &&
        chown root:root '$POLICY_DST' &&
        if command -v chcon &>/dev/null; then
          chcon system_u:object_r:usr_t:s0 '$POLICY_DST' 2>/dev/null || true
        fi
      "
      echo "Done! You can now enable 'Unlock with system authentication' in Bitwarden settings."
    BASH

    File.write("#{staged_path}/bitwarden-polkit-remove", <<~BASH)
      #!/bin/bash
      set -e

      POLICY_DST="/usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy"

      if [ ! -f "$POLICY_DST" ]; then
        echo "Polkit policy not found at $POLICY_DST, nothing to do."
        exit 0
      fi

      echo "Removing Bitwarden polkit policy (requires authentication)..."
      pkexec rm -f "$POLICY_DST"
      echo "Done."
    BASH

    system "chmod", "+x", "#{staged_path}/bitwarden-polkit-setup"
    system "chmod", "+x", "#{staged_path}/bitwarden-polkit-remove"
  end

  postflight do
    # Symlink helper scripts into PATH
    FileUtils.ln_sf "#{staged_path}/bitwarden-polkit-setup",
                    "#{HOMEBREW_PREFIX}/bin/bitwarden-polkit-setup"
    FileUtils.ln_sf "#{staged_path}/bitwarden-polkit-remove",
                    "#{HOMEBREW_PREFIX}/bin/bitwarden-polkit-remove"
  end

  caveats do
    puts <<~EOS
      To enable "Unlock with system authentication" in Bitwarden settings,
      run the following command once after installation:

        bitwarden-polkit-setup

      This installs the polkit policy and will prompt for authentication via pkexec.
      Works on both SELinux (Fedora/Bluefin/Bazzite) and AppArmor (Ubuntu) systems.

      To clean up the policy before uninstalling, run:

        bitwarden-polkit-remove
    EOS
  end

  uninstall_preflight do
    # Remove the polkit policy before cask files are deleted,
    # while staged_path and the remove script are still available.
    if File.exist?("#{staged_path}/bitwarden-polkit-remove")
      system "#{staged_path}/bitwarden-polkit-remove"
    end
  end

  uninstall_postflight do
    FileUtils.rm_f "#{Dir.home}/.local/share/applications/bitwarden.desktop"
    FileUtils.rm_f "#{Dir.home}/.local/share/icons/bitwarden.png"
    FileUtils.rm_f "#{HOMEBREW_PREFIX}/bin/bitwarden-polkit-setup"
    FileUtils.rm_f "#{HOMEBREW_PREFIX}/bin/bitwarden-polkit-remove"
  end

  zap trash: [
    "~/.config/Bitwarden",
  ]
end
