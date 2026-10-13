# Draft formula for a danjboyd/homebrew-arlen tap. The tap does not exist yet.
# At release time, set `version` and `sha256` from the release's SHA256SUMS
# entry for arlen-<version>-macos-arm64.tar.gz.
class Arlen < Formula
  desc "GNUstep-native Objective-C web framework (Apple runtime build)"
  homepage "https://github.com/danjboyd/Arlen"
  version "0.2.0"
  url "https://github.com/danjboyd/Arlen/releases/download/v#{version}/arlen-#{version}-macos-arm64.tar.gz"
  sha256 "REPLACE_WITH_SHA256_FROM_SHA256SUMS"
  license "LGPL-2.1-or-later"

  depends_on arch: :arm64
  depends_on "libpq"
  depends_on macos: :sonoma
  depends_on "openssl@3"

  def install
    # The archive is a framework root: prebuilt tools under build/apple plus
    # the sources and headers that apps compile against.
    libexec.install Dir["*"], ".arlen-dist"
    (bin/"arlen").write <<~SH
      #!/bin/bash
      export ARLEN_FRAMEWORK_ROOT="${ARLEN_FRAMEWORK_ROOT:-#{opt_libexec}}"
      exec "#{opt_libexec}/bin/arlen" "$@"
    SH
  end

  def caveats
    <<~EOS
      Apps are compiled on this Mac, so the Xcode Command Line Tools are
      required. Full Xcode is needed only for `arlen test`.
    EOS
  end

  test do
    assert_match "using prebuilt release artifacts", shell_output("#{opt_libexec}/bin/build-apple")
    system bin/"arlen", "new", "TestApp"
    assert_path_exists testpath/"TestApp/config/app.plist"
  end
end
