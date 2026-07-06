#!/usr/bin/env bash
set -e

# 1. Install rpm-sign if missing
if ! command -v rpmsign &>/dev/null; then
    echo "Installing rpm-sign utility..."
    sudo dnf install -y rpm-sign
fi

# 2. Write RPM macros configuration
echo "Configuring ~/.rpmmacros..."
cat <<'_EOF' > ~/.rpmmacros
%_signature gpg
%_gpg_name jerydleuck@gmail.com
%_gpg_path /home/jeryd/.gnupg
%_gpgbin /usr/bin/gpg
_EOF

# 3. Check for GPG key
if ! gpg --list-secret-keys jerydleuck@gmail.com &>/dev/null; then
    echo "=========================================================="
    echo "❌ ERROR: No GPG private key found for jerydleuck@gmail.com"
    echo "Please import your GPG private key first:"
    echo "  gpg --import /path/to/your-private-key.asc"
    echo "=========================================================="
    exit 1
fi

# 4. Sign the RPMs
echo "Signing all RPM packages in rpm/pool/..."
rpmsign --resign rpm/pool/*.rpm

# 5. Run the repository update script to rebuild and sign metadata
echo "Running repository metadata update..."
./update.sh

echo "=========================================================="
echo "🎉 Successfully signed packages and updated repository metadata!"
echo "Now commit and push these changes to GitHub, then run:"
echo "  sudo dnf clean all && sudo dnf install trance"
echo "=========================================================="
