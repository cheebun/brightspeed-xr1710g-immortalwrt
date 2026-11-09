<img src="https://avatars.githubusercontent.com/u/53193414?s=200&v=4" alt="logo" width="200" height="200" align="right">

# ImmortalWrt for Brightspeed XR1710G

[![Upstream](https://img.shields.io/badge/upstream-immortalwrt%403e246256ce-blue)](https://github.com/immortalwrt/immortalwrt)
[![Kernel](https://img.shields.io/badge/kernel-6.18.44-red)](https://www.kernel.org/)
[![SoC](https://img.shields.io/badge/SoC-Airoha%20AN7581GT-orange)]()
[![License](https://img.shields.io/badge/license-GPL--2.0-green)](https://spdx.org/licenses/GPL-2.0-only.html)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 与 [naoki66 的移植](https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed)，为 Brightspeed/Gemtek XR1710G 定制的固件。

项目的重要功能、稳定性和补丁维护记录见 [更新日志](CHANGELOG.md)。

## 在 naoki66 / ImmortalWrt 基础上增加的内容

**新增应用**

SmartDNS、chrony 对时、relayd 无线中继。

**新增内核模块**

`kmod-veth`、`kmod-nft-queue`、`kmod-nfnetlink-queue`、`kmod-xdp-sockets-diag`。

**新增软件包**

`mount-utils`（完整版 `mount`、`umount`、`findmnt` 等挂载工具）。

**内核与编译选项**

- 内核 BTF 调试信息。
- 内核 netkit。
- OpenSSL 内置 devcrypto 引擎。

**相对 naoki66 移除的内容**

- 动态域名与内网穿透：DDNS、DDNS-Go、Lucky、ZeroTier。
- 推送与杂项：WeChatPush、PushBot、vlmcsd。
- 时间同步：busybox ntpd、sysntpd。

## 支持的分区布局

`1710.config` 一次编译出两个镜像，分别对应两种分区布局，不能互刷。刷写前请按[升级注意事项](docs/firmware-release.md#升级注意事项)确认设备当前的布局。

| 镜像 profile | 适用分区布局 | 设备树 |
|------|----------|------------|
| `gemtek_xr1710g` | 原厂 U-Boot 分区 | [`an7581-xr1710g.dts`](target/linux/airoha/dts/an7581-xr1710g.dts) |
| `gemtek_xr1710g-ubi` | OpenWrt U-Boot UBI 布局 | [`an7581-gemtek-xr1710g-ubi.dts`](target/linux/airoha/dts/an7581-gemtek-xr1710g-ubi.dts) |

## 设备参数

- 默认管理地址：http://192.168.50.1 或 http://XR1710G.lan
- 用户名：**root**
- 密码：*无*

首次启动的无线网络名称为 `OpenWRT`（2.4GHz、5GHz、6GHz 三个频段同名），初始密码为 `password`。

2.4GHz 使用 WPA2，5GHz 使用 WPA2/WPA3 混合模式，6GHz 使用 WPA3。

首次登录后请及时修改管理密码和无线密码。

| 项目 | 参数 |
|------|------|
| **SoC** | Airoha AN7581GT（1.3GHz 4 核 CPU + 8 核 NPU） |
| **内存** | 2GB |
| **闪存** | 512MB |
| **网口** | 2×10G RTL8261BE + 2×1G AN7581 |
| **无线** | MediaTek MT7996AV，2.4GHz/5GHz/6GHz 三频 Wi-Fi 7 |
| **PWM 风扇** | 新唐 NCT7802 |
| **电源规格** | 12V 5A |

### 无线局域网（MT7996AV BE19000）

| 频段 | 芯片 | 规格 | 最高速率 |
|------|------|------|----------|
| WLAN1 | MT7976GN | 2.4GHz 4×4 (Tx/Rx) 4096 QAM 40 MHz | 1376 Mbps |
| WLAN2 | MT7977BN | 5GHz 4×4 (Tx/Rx) 4096 QAM 160 MHz | 5.76 Gbps |
| WLAN3 | MT7977AN | 6GHz 4×5 (Tx/Rx) 4096 QAM 320 MHz (backhaul) | 10 Gbps |

## 固件特性

### 硬件适配

- 两种分区布局各用一份设备树：原厂 U-Boot 布局用 [an7581-xr1710g.dts](target/linux/airoha/dts/an7581-xr1710g.dts)，OpenWrt U-Boot UBI 布局用 [an7581-gemtek-xr1710g-ubi.dts](target/linux/airoha/dts/an7581-gemtek-xr1710g-ubi.dts)（参考 [pbs05/uboot-an758x](https://github.com/pbs05/uboot-an758x) 的引导方案）。
- UBI 布局首次启动前，需把原厂 `dsd` 分区去除 OOB 后的 2 MiB 主数据恢复到 UBI `factory` 卷；其中 `0x006c/0x0086` 为 WAN/LAN MAC，`0x5000` 起为 MT7996 校准数据。
- 内核补丁（[airoha](target/linux/airoha/patches-6.18/)、[generic](target/linux/generic/pending-6.18/)）：RTL8261BE SerDes/USXGMII 调优、PCIe 3.0 x2 链路修复、NPU 恢复与固件加载、PPE/flowtable 硬件卸载与 WLAN 流绑定、RX ring 扩容。
- 无线补丁：[mt76](package/kernel/mt76/patches/)（MT7996 MLO 稳定性、速率控制）、[mac80211](package/kernel/mac80211/patches/subsys/411-mac80211-export-link-sta-capability-limits.patch) 与 [hostapd](package/network/services/hostapd/patches/)（6GHz、EHT、多 VAP）。

### 默认设置

- 管理地址 `192.168.50.1`；IPv6 使用 SLAAC，关闭 DHCPv6 与 RA DNS。
- 默认开启软件与硬件 flow offload；VLAN、PPPoE 透传和 AP 模式卸载可在 NPU 页面按需启用。
- 三频默认启用：2.4GHz EHT20 信道 1，5GHz EHT80 信道 36，6GHz EHT160 信道 37。
- 默认主题 Argon；SmartDNS 默认关闭，端口 6053，不接管 dnsmasq；时间同步由 chrony 负责。

### 预装 LuCI 应用

| 分类 | 应用 |
|------|------|
| 设备 | NPU 状态与加速 `luci-app-airoha-npu`、风扇控制 `luci-app-airoha-fancontrol`、网络模式 `luci-app-netmode` |
| 网络 | 防火墙 `luci-app-firewall`、UPnP `luci-app-upnp`、IP/MAC 绑定 `luci-app-arpbind`、Wi-Fi 7 多链路 `luci-app-mlo`、在线客户端 `luci-app-clients`、SmartDNS `luci-app-smartdns`、无线中继 `luci-proto-relay` |
| 系统 | 包管理 `luci-app-package-manager`、Web 终端 `luci-app-ttyd`、定时重启 `luci-app-autoreboot`、网络唤醒 `luci-app-wol` / `luci-app-timewol`、Wi-Fi 定时开关 `luci-app-wifischedule`、网络看门狗 `luci-app-watchcat`、时间同步 `luci-app-chrony` |

### 主要系统包

**网络核心**
- `dnsmasq-full`（完整版 DNS/DHCP）
- `firewall4` + `nftables-json`（nftables 防火墙）
- `wpad-mesh-mbedtls`（WPA2/WPA3、EHT/MLO 与 Mesh 支持）
- `odhcp6c` / `odhcpd-ipv6only`（IPv6）
- `ppp` / `ppp-mod-pppoe` / `pppoe-discovery`（PPPoE）
- `smartdns` + `smartdns-ui`（DNS 加速/分流）
- `wireguard-tools` + `rpcd-mod-wireguard`（WireGuard；不预装 `luci-proto-wireguard`）
- `relayd`（无线中继）
- `chrony`（时间同步，取代 busybox ntpd/sysntpd）
- `bridger` / `nlbwmon`（桥接加速 / 流量统计）

**内核模块（kmod）**
- `kmod-mt7996-firmware` / `kmod-mt7996e`（MT7996 Wi-Fi 7 驱动）
- `airoha-en7581-mt7996-npu-firmware`（Airoha NPU 固件）
- `kmod-crypto-hw-eip93` / `kmod-cryptodev` / `kmod-crypto-user`（硬件加密加速与用户态接口）
- `kmod-nft-offload`（硬件流量卸载）
- `kmod-nft-queue` / `kmod-nfnetlink-queue`（nftables 用户态队列）
- `kmod-br-netfilter` / `kmod-tcp-bbr`（桥接 Netfilter / BBR 拥塞控制）
- `kmod-wireguard`（WireGuard 内核支持）
- `kmod-veth` / `kmod-tun` / `kmod-dummy`（虚拟网络设备）
- `kmod-sched-core` / `kmod-sched-bpf` / `kmod-xdp-sockets-diag`（流量调度与 BPF/XDP 诊断）
- `kmod-nft-tproxy` / `kmod-nft-socket` / `kmod-inet-diag`（透明代理与套接字诊断）
- `kmod-hwmon-nct7802`（NCT7802 温度传感器）
- `kmod-leds-gpio` / `kmod-gpio-button-hotplug`
- `kmod-phy-realtek` / `kmod-mt76-connac` / `kmod-mt76-core`
- `rtl826x-firmware`（RTL8261BE PHY 固件）

**系统工具**
- `bash` / `coreutils` / `curl` / `ip-full` / `jq` / `yq` / `flock` / `mount-utils`
- `ethtool-full` / `pciutils` / `uboot-envtools` / `arp-scan` / `socat`
- `iperf3`（内置测速服务端/客户端）
- `luci-theme-argon` + `luci-theme-bootstrap`
- `default-settings-chn`（中文默认设置）

**代理与网络核心**
- `simple-obfs-client` / `chinadns-ng` / `geoview`
- `dns2socks` / `microsocks` / `ipt2socks`

## 致谢

### 上游固件
- [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) - ImmortalWrt 主项目
- [immortalwrt/luci](https://github.com/immortalwrt/luci) - LuCI Web 界面
- [immortalwrt/packages](https://github.com/immortalwrt/packages) - 社区软件包仓库
- [openwrt/routing](https://github.com/openwrt/routing) - OpenWrt 路由相关包
- [openwrt/mt76](https://github.com/openwrt/mt76) - MediaTek WiFi 驱动

### 参考项目
- [naoki66/ImmortalWrt-for-Gemtek-brightspeed](https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed) - 本项目的直接上游移植
- [YYH2913/openwrt](https://github.com/YYH2913/openwrt) - XR1710G 6.18 内核集成参考（an7581-xr1710g.dts 基础结构）
- [hurrian/openwrt-w1700k](https://github.com/hurrian/openwrt-w1700k) - XR1710G PCIe 3.0 x2 补丁参考（912 Gen3 速度协商）
- [lvcdy/openwrt_xr1710g](https://github.com/lvcdy/openwrt_xr1710g) - XR1710G 早期移植参考（分区表、PHY 配置）

### LuCI 应用来源
- [naoki66/luci-app-airoha](https://github.com/naoki66/luci-app-airoha) - Airoha LuCI 应用 feed，包含 `luci-app-airoha-npu`
- [Gilly1970/Gemtek-W1700K](https://github.com/Gilly1970/Gemtek-W1700K) - Airoha 风扇控制与 FlowSense（commit db3f1c8）

## 许可证

[GPL-2.0-only](https://spdx.org/licenses/GPL-2.0-only.html)（继承 ImmortalWrt）
