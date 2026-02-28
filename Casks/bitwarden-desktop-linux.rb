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

    # 7. Write the polkit policy file.
    # Policy XML taken verbatim from Bitwarden source:
    # apps/desktop/src/key-management/biometrics/os-biometrics-linux.service.ts
    File.write("#{staged_path}/com.bitwarden.Bitwarden.policy", <<~XML)
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

    # 8. Write helper scripts for polkit policy management.
    # Installing to /etc/polkit-1/actions/ requires root (sudo).
    # NOTE: On immutable ostree systems (Bluefin, Bazzite, Aurora) /usr is
    # read-only so we fall back to /etc/polkit-1/actions/ which polkitd also
    # reads. However /etc/polkit-1/actions/ does not exist by default and must
    # be created with sudo. This is a workaround — the proper solution on
    # immutable systems is to have the policy shipped in the base image.
    File.write("#{staged_path}/bitwarden-polkit-setup", <<~BASH)
      #!/bin/bash
      set -e

      POLICY_SRC="#{staged_path}/com.bitwarden.Bitwarden.policy"
      POLICY_DST="/etc/polkit-1/actions/com.bitwarden.Bitwarden.policy"

      if [ -f "$POLICY_DST" ]; then
        echo "Polkit policy already installed at $POLICY_DST"
        exit 0
      fi

      echo "Creating /etc/polkit-1/actions/ and installing Bitwarden polkit policy..."
      echo "This requires sudo."
      sudo mkdir -p /etc/polkit-1/actions
      sudo cp -f "$POLICY_SRC" "$POLICY_DST"
      sudo chown root:root "$POLICY_DST"
      sudo chmod 644 "$POLICY_DST"
      echo "Done! You can now enable 'Unlock with system authentication' in Bitwarden settings."
    BASH

    File.write("#{staged_path}/bitwarden-polkit-remove", <<~BASH)
      #!/bin/bash
      set -e

      POLICY_DST="/etc/polkit-1/actions/com.bitwarden.Bitwarden.policy"

      if [ ! -f "$POLICY_DST" ]; then
        echo "Polkit policy not found at $POLICY_DST, nothing to do."
        exit 0
      fi

      echo "Removing Bitwarden polkit policy (requires sudo)..."
      sudo rm -f "$POLICY_DST"
      echo "Done."
    BASH

    system "chmod", "+x", "#{staged_path}/bitwarden-polkit-setup"
    system "chmod", "+x", "#{staged_path}/bitwarden-polkit-remove"
  end

  postflight do
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

      This installs the polkit policy to /etc/polkit-1/actions/ and requires sudo.

      ⚠️  Workaround notice: on immutable ostree-based systems (Bluefin, Bazzite, Aurora)
      /usr/share/polkit-1/actions/ is read-only, so we install to /etc/polkit-1/actions/
      instead. This directory is created if it does not exist.

      To remove the policy on uninstall, run first:

        bitwarden-polkit-remove
    EOS
  end

  uninstall_preflight do
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
