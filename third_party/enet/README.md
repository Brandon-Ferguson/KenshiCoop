# ENet (vendored dependency)

KenshiCoop uses [ENet](http://enet.bespin.org/) for reliable and unreliable UDP
channels. Its external source is restored at a pinned revision and patched for
the plugin's VS2010 (v100) toolchain; do not substitute the latest release or
add a new submodule.

## Restore the pinned source

From the KenshiCoop repository root, on a fresh checkout:

```bat
git clone https://github.com/lsalzman/enet.git third_party/enet/enet
git -C third_party/enet/enet checkout 5a9c537fd464b3c6d3c55e1d3bd47588faf71b42
git apply third_party/enet/patches/0001-enet-c89-for-loops.patch
git apply third_party/enet/patches/0002-enet-socket-hooks.patch
```

Apply the patches in that order, once, to the pinned source. The resulting
headers live at `third_party/enet/enet/include/enet/enet.h`. The C89 patch and
socket-hook patch are tracked here; the fetched upstream source is not.

## Build

The existing plugin project already compiles the ENet C sources directly and
configures its includes and Windows `ws2_32.lib` / `winmm.lib` dependencies.
Do not add another ENet library or change project configuration to follow an
unrelated CMake/nettest recipe. Build the matching core/UI pair from the root:

```bat
scripts\build_plugin.cmd Release
```

Use `Harness` explicitly for diagnostics; it is also the script's default.
See [Build setup](../../docs/BUILD_SETUP.md) for the v100 / SDK 7.1 /
KB2519277 `/MD` ABI requirements and the other pinned dependencies.

## License and notices

ENet is MIT-licensed. Preserve the upstream `LICENSE` copyright and permission
notice with copies or substantial portions of ENet, including distributions
containing it. Keep the pinned upstream source and these local patches available
alongside the project's corresponding-source instructions; this README does
not replace ENet's license text or the project's AGPL/dependency obligations.
