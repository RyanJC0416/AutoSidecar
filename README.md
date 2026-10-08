# 自动随航

菜单栏工具。Mac 单独带走、随航却还挂在 iPad 上时，按你记下的电源、硬盘、设备、网络或随航连接方式，自动打开或关闭某一台设备的随航。

菜单栏图标一直在。打开设置窗口时，程序会出现在 Dock 里；关掉窗口后 Dock 图标消失，菜单栏还留着。登录时启动只留菜单栏。窗口换到另一块屏幕时保持原来的大小。

## 规则怎么写

每条规则是一个场景加一个行为。

场景只能从**当前已经检测到的对象**里选，不能手填名字：

- 连接电源 / 断开电源：当前这只电源适配器
- 连接移动硬盘 / 断开移动硬盘：当前这一块磁盘
- 连接设备 / 断开设备：当前这一台 USB 设备，例如扩展坞
- 连接网络 / 断开网络：当前这个 Wi-Fi、这条网线所在的网关，或 iPad 的 USB 网络接口
- 随航切换到 Wi-Fi / 有线：当前这一台 iPad

行为同样要指定设备：对这一台 iPad 启用随航，或关闭随航。

连接类场景在对象从「没有」变成「有」时触发一次。断开类场景在它从「有」变成「没有」时触发一次。对象已经处于目标状态时保存规则，不会马上执行。

iPad 插上扩展坞后，USB 网络接口会先出现，随航的有线通道往往还要再等一会儿。规则如果绑的是这个接口，程序会等到 iPad 报出 USB 通道再按有线方式连接，不会在网卡刚出现时走无线、然后马上失败。

单独去开会可以这样配：场景选「断开电源」或「断开设备」，对象选工位上这只适配器或扩展坞，行为选「关闭随航」，随航设备选这台 iPad。拔掉电脑后，这条规则会把随航关掉。回到工位、iPad 的 USB 网络接口出现时，用「连接网络」启用这台 iPad 的随航。

程序会记住上一次看到的连接。关机后再打开，如果和上次相比已经变了，对应规则仍会执行。第一次打开只记录现状，不执行。

## 安装

需要 Apple 芯片的 macOS 15 或更高版本。

从 [Releases](https://github.com/RyanJC0416/AutoSidecar/releases) 下载 `AutoSidecar.app.zip`，解压后把 `AutoSidecar.app` 放进「应用程序」，再从那里打开。

开机自启、自动更新、手动检查更新都在设置窗口底部。更新包就是 GitHub Release 里的 `AutoSidecar.app.zip`。自动更新打开后，启动时如果有新版本会自己下载并替换。

## 开发

```bash
./build.sh
open AutoSidecar.app
```

发布新版本时改 `VERSION`，提交后执行：

```bash
./release.sh "这次改了什么"
```

这会重新打包，并在 GitHub 上创建带 `AutoSidecar.app.zip` 的 Release。

诊断当前能看到哪些对象：

```bash
./AutoSidecar.app/Contents/MacOS/AutoSidecar --dump
```

## 说明

随航没有公开接口，开关随航走系统私有的 SidecarCore。系统大版本更新后，这个接口可能变化。

读取 Wi-Fi 名称需要定位权限。不授权时，网络对象改用网关地址区分。

---

# AutoSidecar

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
