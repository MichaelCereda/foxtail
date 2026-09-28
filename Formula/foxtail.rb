class Foxtail < Formula
  desc "Connect to several Tailscale tailnets at the same time on macOS"
  homepage "https://github.com/MichaelCereda/foxtail"
  url "https://github.com/MichaelCereda/foxtail/releases/download/v0.1.4/foxtail-0.1.4.tar.gz"
  sha256 "2331a1dfceb7ff8c77a051ba137b0e6d63ea2a762a1015c607b4a78ab9b2b8c4"
  license "MIT"
  head "https://github.com/MichaelCereda/foxtail.git", branch: "main"

  depends_on :macos
  depends_on "jq"
  depends_on "socat"
  depends_on "tailscale"

  def install
    bin.install "bin/foxtail"
  end

  def caveats
    <<~EOS
      foxtail runs extra tailnets alongside the Tailscale GUI app, which keeps
      one tailnet native. Install that separately if you have not already:

        brew install --cask tailscale-app

      Then check your setup with:

        foxtail doctor
    EOS
  end

  test do
    assert_match "foxtail", shell_output("#{bin}/foxtail --help")
    system bin/"foxtail", "selftest"
  end
end
