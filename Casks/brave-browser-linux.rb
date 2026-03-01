cask "brave-browser-linux" do
  version "1.87.191"

  if Hardware::CPU.intel?
    sha256 "0a0af1158663e6483acf76d81393414555bd590e9e216997863cd72afc69efa0"
    url "https://github.com/brave/brave-browser/releases/download/v#{version}/brave-browser-#{version}-linux-amd64.zip",
        verified: "github.com/brave/brave-browser/"
  else
    sha256 "1091bdfe0e3a69649dee44231c42a9f18de07799226835e770db895019b2a371"
    url "https://github.com/brave/brave-browser/releases/download/v#{version}/brave-browser-#{version}-linux-arm64.zip",
        verified: "github.com/brave/brave-browser/"
  end

  name "Brave Browser"
  desc "Web browser that blocks ads and trackers by default"
  homepage "https://brave.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Link the main binary to the Homebrew prefix
  binary "brave", target: "brave-browser"

  preflight do
    # Set necessary SUID permissions for the Electron chrome-sandbox
    if File.exist?("#{staged_path}/chrome-sandbox")
      system "chmod", "4755", "#{staged_path}/chrome-sandbox"
    end

    # Ensure local user directories exist for desktop integration
    FileUtils.mkdir_p "#{Dir.home}/.local/share/applications"
    FileUtils.mkdir_p "#{Dir.home}/.local/share/icons/hicolor"

    [16, 24, 32, 48, 64, 128, 256].each do |size|
      FileUtils.mkdir_p "#{Dir.home}/.local/share/icons/hicolor/#{size}x#{size}/apps"
    end

    # Install the application icon
    [16, 24, 32, 48, 64, 128, 256].each do |size|
      icon_src = "#{staged_path}/product_logo_#{size}.png"
      icon_dst = "#{Dir.home}/.local/share/icons/hicolor/#{size}x#{size}/apps/brave-desktop.png"
      if File.exist?(icon_src)
        FileUtils.cp(icon_src, icon_dst)
      end
    end

    # Generate and install the .desktop entry
    desktop_dst = "#{Dir.home}/.local/share/applications/brave-browser.desktop"
    desktop_content = <<~DESKTOP
      [Desktop Entry]
      Version=1.0
      Name=Brave Web Browser
      GenericName=Web Browser
      Comment=Access the Internet
      Exec=#{HOMEBREW_PREFIX}/bin/brave-browser %U
      StartupNotify=true
      Terminal=false
      Icon=brave-desktop
      Type=Application
      Categories=Network;WebBrowser;
      Actions=new-window;new-private-window;

      [Desktop Action new-window]
      Name=New Window
      Exec=#{HOMEBREW_PREFIX}/bin/brave-browser --new-window

      [Desktop Action new-private-window]
      Name=New Incognito Window
      Exec=#{HOMEBREW_PREFIX}/bin/brave-browser --incognito
    DESKTOP

    File.write(desktop_dst, desktop_content)
  end

  uninstall_postflight do
    FileUtils.rm_f "#{Dir.home}/.local/share/applications/brave-browser.desktop"
    [16, 24, 32, 48, 64, 128, 256].each do |size|
      FileUtils.rm_f "#{Dir.home}/.local/share/icons/hicolor/#{size}x#{size}/apps/brave-desktop.png"
    end
  end

  zap trash: [
    "~/.config/BraveSoftware",
    "~/.cache/BraveSoftware",
  ]
end
