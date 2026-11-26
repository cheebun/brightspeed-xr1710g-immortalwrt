# 固件发布

固件由本仓库的 `Build Firmware` 工作流构建，在 Actions 页面手动触发；构建产物（artifacts）保留 30 天。触发时若把 Release Type 选为 release 或 prerelease，固件会同时发布到本仓库的 Releases 页面。也可以按[本地构建说明](build.md)自行构建。作者的官方构建请见 [Releases 页面](https://github.com/naoki66/ImmortalWrt-for-Gemtek-brightspeed/releases)。

## 升级注意事项

> [!WARNING]
> LuCI 中的“保留配置”不会保留额外安装的软件包。升级前请备份配置并记录已安装的软件包；升级后需要
> 重新安装 OpenClash、PassWall、AdGuard Home 等非预装组件。请使用与新固件匹配的软件包，不要恢复
> 旧固件的 `kmod-*` 内核模块。

### XR1710G 布局与旧版板型名

当前的两个 XR1710G 镜像使用不同的引导、NAND 和 `factory` 数据布局，不能互刷：

| 布局 | 当前镜像 profile | 设备树中的分区特征 |
|------|------------------|--------------------|
| 原版 U-Boot / 旧布局 | `gemtek_xr1710g` | `vendor` 从 `0x00000000` 开始、大小 `0x00600000`；`chainloader` 从 `0x00600000` 开始；`ubi` 从 `0x00700000` 开始 |
| OpenWrt U-Boot / UBI 布局 | `gemtek_xr1710g-ubi` | `bl2` 从 `0x00000000` 开始、大小 `0x00020000`；`ubi` 从 `0x00020000` 开始；`factory` 是完整的 2 MiB DSD 主数据 |

Actions 构建产物和 Releases 中的镜像文件名为：

| 布局 | 镜像文件名 |
|------|------------|
| 原版 U-Boot 布局（`gemtek_xr1710g`） | `immortalwrt-<owner>-xr1710g-<YYYYMMDD>-<HHmm>-<commit8>-squashfs-sysupgrade.itb` |
| OpenWrt U-Boot UBI 布局（`gemtek_xr1710g-ubi`） | `immortalwrt-<owner>-xr1710g-<YYYYMMDD>-<HHmm>-<commit8>-ubi-squashfs-sysupgrade.itb` |

即不带 `-ubi` 的是原版 U-Boot 布局，带 `-ubi` 的是 OpenWrt U-Boot UBI 布局；日期和时间为北京时间（Asia/Shanghai），
`<commit8>` 是本仓库提交的 8 位缩写，`sha256sums` 中的文件名与之对应。本地构建不做重命名，仍为原始文件名
`*-gemtek_xr1710g-squashfs-sysupgrade.itb` 和 `*-gemtek_xr1710g-ubi-squashfs-sysupgrade.itb`。

部分较早的旧布局固件报告的板型名是 `gemtek,xr1710g-ubi`，与当前 **新 UBI 布局**的板型名相同。
因此不能仅凭板型名、镜像文件名中的 `-ubi` 或校验通过就判断布局。可先在路由器上只读查看板型和
MTD 分区（`offset`、`size` 为十进制字节数）：

```sh
cat /tmp/sysinfo/board_name
cat /proc/mtd
for mtd in /sys/class/mtd/mtd[0-9]*; do
    [ -r "$mtd/name" ] || continue
    printf '%s offset=%s size=%s\n' "$(cat "$mtd/name")" \
        "$(cat "$mtd/offset")" "$(cat "$mtd/size")"
done
```

这些信息反映当前内核识别的布局，还需与设备的实际引导方式和已验证备份相互核对；如果结果不明确，
不要刷写。备份配置及引导、环境和校准数据，并按具体布局选择对应的镜像。
刷写前用 `sysupgrade -T <镜像文件>` 检查；该检查由**当前运行的固件**执行，不能代替布局核验。
如果旧布局设备的旧板型名被当前原版分区镜像拒绝，不要用 `-F` 强制升级或改刷新 UBI 布局镜像；
应等待针对该旧版板型和布局提供的明确迁移方案。
