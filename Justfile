build:
    swift build --jobs 4

test:
    swift test --jobs 4
    python3 -m unittest discover -s scripts/tests -v

bundle *flags:
    scripts/bundle.sh {{flags}}

# Debug bundle, replace any running Splay, and run attached so logs stream here.
run: kill
    scripts/bundle.sh --debug
    ./build/Splay.app/Contents/MacOS/splay

# Only Splay's own executable: an installed upstream dinky.app never matches. SIGTERM, so windows are restored.
kill:
    pkill -f 'Splay\.app/Contents/MacOS/splay' || true

# Symlink the bundled CLI into ~/.local/bin so `splay <command>` works from any shell.
install: bundle
    mkdir -p ~/.local/bin
    ln -sf "$PWD/build/Splay.app/Contents/MacOS/splay" ~/.local/bin/splay
    ls -l ~/.local/bin/splay

# Build, sign, notarize and zip a release into dist/ without publishing. Needs NOTARYTOOL_PROFILE.
package version:
    scripts/package-release.sh {{quote(version)}}

# Prepare, test, package, tag and publish a GitHub release from a clean, pushed main. The version defaults
# to the latest tag plus 0.1. Needs NOTARYTOOL_PROFILE.
release version="":
    scripts/release.sh {{quote(version)}}

# Serve the site and manual at http://127.0.0.1:4000/splay/, to this Mac only, and rebuild it as docs/
# changes. It builds into build/site, outside docs/. Needs Jekyll: gem install jekyll jekyll-relative-links
docs:
    jekyll serve --source docs --destination build/site --disable-disk-cache --livereload --host 127.0.0.1
