# App Lifecycle

## Prerequisites

* OS: Fedora 39
* Packages:
    * skopeo
    * podman
* Root privileges

Then link one of the [Podman search directories](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) to `/var/quadlets/`.

## Run

Make sure to update all references to container images in `apps/**/*.container` files to a valid digest. Then run:

```bash
./demo.sh
```
