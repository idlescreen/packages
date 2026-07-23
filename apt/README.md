# IdleScreen APT repository

Signed Debian packages for IdleScreen, served from
[idlescreen.github.io/packages/apt](https://idlescreen.github.io/packages/apt).

Shipped package names remain `trance` / `trance-*` for install stability.
Keyring filename on the host may still be `crateria-keyring.gpg`.

## Add the repository

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://idlescreen.github.io/packages/apt/crateria-keyring.gpg \
  -o /etc/apt/keyrings/idlescreen.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/idlescreen.gpg] https://idlescreen.github.io/packages/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/idlescreen.list
sudo apt update
sudo apt install trance
```

See the [packages README](../README.md) for the full pipeline.
