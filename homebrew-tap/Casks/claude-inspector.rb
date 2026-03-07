cask "claude-inspector" do
  version "1.1.1"

  on_arm do
    url "https://github.com/kangraemin/claude-inspector/releases/download/v#{version}/Claude-Inspector-#{version}-arm64.dmg"
    sha256 "PLACEHOLDER_ARM64" # arm64
  end
  on_intel do
    url "https://github.com/kangraemin/claude-inspector/releases/download/v#{version}/Claude-Inspector-#{version}-x64.dmg"
    sha256 "PLACEHOLDER_X64" # x64
  end

  name "Claude Inspector"
  desc "Claude Code Prompt Mechanism Visualizer"
  homepage "https://github.com/kangraemin/claude-inspector"
  app "Claude Inspector.app"

  zap trash: [
    "~/Library/Application Support/Claude Inspector",
    "~/Library/Preferences/com.claudeinspector.app.plist",
    "~/Library/Caches/com.claudeinspector.app",
  ]
end
