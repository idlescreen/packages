# IdleScreen RPM repository

Signed RPM packages for IdleScreen, served from
[idlescreen.github.io/packages/rpm](https://idlescreen.github.io/packages/rpm).

Shipped package names remain `trance` / `trance-*` for install stability.
Repo drop-in filename on the host may still be `crateria.repo`.

## Add the repository

```bash
sudo curl -fsSL https://idlescreen.github.io/packages/rpm/crateria.repo \
  -o /etc/yum.repos.d/idlescreen.repo
sudo dnf install trance
```

See the [packages README](../README.md) for the full pipeline.
