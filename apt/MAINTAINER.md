# Maintainer Guide (How to Update Packages)

This guide documents how to add new package versions and update the repository metadata indices.

## Steps to Update

1.  **Copy the newly compiled packages** into the repository.
    *   Example: `cp ../trance/target/debian/*.deb pool/main/`

2.  **Run the update indexer script** from the repository root to regenerate the database indices and cryptographically sign the Release files:
    ```bash
    ./update.sh
    ```

3.  **Commit and push the changes** to GitHub to make them available to clients:
    ```bash
    git add .
    git commit -m "Add packages and update index"
    git push origin main
    ```

## Guidelines
*   **Aesthetics**: The Gentoo/systemd-style TUI progress formatting is great. Preserve this clean, text-based interactive styling for installer and setup scripts.
