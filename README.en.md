# AutoSidecar

[中文](README.md)

A menu-bar app. When you take the Mac somewhere alone and Sidecar is still connected to an iPad, it turns Sidecar on or off for a specific device according to the power adapter, disk, device, network, or Sidecar link you recorded.

The menu-bar icon stays. Opening the settings window also shows the app in the Dock; closing the window removes the Dock icon and leaves the menu bar. A login launch stays in the menu bar only. Moving the window to another display keeps its size.

## Rules

Each rule is one scene plus one action.

A scene can only use an object the Mac can see right now. Names cannot be typed in:

- Power connected / disconnected: this power adapter
- Volume mounted / unmounted: this disk
- Device connected / disconnected: this USB device, such as a dock
- Network connected / disconnected: this Wi-Fi network, the gateway of this Ethernet connection, or the iPad’s USB network interface
- Sidecar switches to Wi-Fi / wired: this iPad

The action names a device too: enable Sidecar for this iPad, or disable it.

A connect scene fires once when its object appears. A disconnect scene fires once when that object disappears. Saving a rule while the object is already in the target state does not run it.

After an iPad is plugged into a dock, its USB network interface shows up before the wired Sidecar channel is ready. A rule bound to that interface waits until the iPad reports the USB channel, then connects over the wire. It does not try Wi-Fi the moment the interface appears and fail immediately.

For leaving the desk: choose “power disconnected” or “device disconnected”, pick the adapter or dock at the desk, choose “disable Sidecar”, and pick this iPad. Unplugging the Mac turns Sidecar off. When you come back and the iPad’s USB network interface appears, a “network connected” rule turns Sidecar on for that iPad.

The app remembers the last connections it saw. After a restart, a rule still runs if the state changed while the Mac was off. The first launch only records the current state.

## Install

Requires Apple silicon and macOS 15 or later.

Download `AutoSidecar.app.zip` from [Releases](https://github.com/RyanJC0416/AutoSidecar/releases), unzip it, move `AutoSidecar.app` into Applications, and open it from there.

Launch at login, automatic updates, and the manual update check are at the bottom of the settings window. The update package is the `AutoSidecar.app.zip` asset on the GitHub Release. With automatic updates on, a newer version is downloaded and replaced at launch.

## Development

```bash
./build.sh
open AutoSidecar.app
```

To publish, change `VERSION`, commit, then run:

```bash
./release.sh "what changed"
```

That rebuilds the app and creates a GitHub Release containing `AutoSidecar.app.zip`.

To list the objects the app can see:

```bash
./AutoSidecar.app/Contents/MacOS/AutoSidecar --dump
```

## Notes

Sidecar has no public API. Turning it on and off uses the private SidecarCore framework, which can change in a major macOS update.

Reading the Wi-Fi name needs Location permission. Without it, network objects are identified by the gateway address.
