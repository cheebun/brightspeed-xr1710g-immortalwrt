# 本地构建

在 Linux 主机安装 OpenWrt 所需的编译工具，包括 C/C++ 编译器、GNU make、GNU sed、GNU awk、Python、Perl、Git、rsync、解压工具及下载工具。构建环境要求：GNU/Linux 系统（Debian 11+ 推荐），AMD64 架构，至少 4GB RAM 和 60GB 可用磁盘空间，并需要联网获取外部 feeds、工具链和软件包源码。详细依赖请参考 [ImmortalWrt 官方文档](https://openwrt.org/docs/guide-developer/build-system/install-buildsystem)。

```sh
git clone https://github.com/cheebun/brightspeed-xr1710g-immortalwrt.git
cd brightspeed-xr1710g-immortalwrt
```

以下命令全部在**仓库根目录**执行。

## 1. 更新 feeds 并应用补丁

feeds 不锁定提交，每次更新都会拉取各分支最新代码。`patches/feeds/` 中的补丁会在 feed 工作区留下改动，导致下次更新失败，所以先清理再更新、再重新应用。[`feeds.conf.default`](../feeds.conf.default) 中已注释停用的来源（如 mosdns、EasyTier、UniWRT、pon 相关）不会被拉取，下面的循环只处理已获取的 feed 目录，当前的补丁也只涉及 luci 和 packages 两个启用的 feed。

```sh
for d in feeds/*/; do
	[ -d "$d/.git" ] || continue
	git -C "$d" reset -q --hard
	git -C "$d" clean -qfd
done

./scripts/feeds update -a
./scripts/feeds install -a

bash scripts/fix-stale-golang-host.sh
FEED_PATCHES_STRICT=1 bash scripts/apply-feed-patches.sh
```

`apply-feed-patches.sh` 是幂等的：它以 feed 的 `HEAD` 为起点，按顺序叠加该 feed 的全部补丁，算出每个文件应有的内容，只改写内容不一致的文件；已经是正确内容的文件不会被改动，也不会触发重新编译。补丁涉及的文件由脚本接管，在 `feeds/` 里对这些文件的手工修改会被覆盖。若上游变化导致补丁不匹配（或两个补丁重复修改同一处），构建会停止；先核对本次 feeds 提交，再调整补丁，不应静默跳过。需要长期维护的 feed 改动请保存为 `patches/feeds/` 下的补丁，不要只改下载目录。修改脚本后运行 `bash scripts/test-apply-feed-patches.sh`。

## 2. 生成配置

以源码中的 [`1710.config`](../1710.config) 为种子，覆盖下列包与内核选项。做法是：先写出选项清单，再从种子中删掉这些键的原有取值，最后把清单追加到末尾，保证每个键只保留这里的设定。

```sh
cat > /tmp/xr1710g-options.conf <<'EOF'
CONFIG_KERNEL_DEBUG_INFO=y
# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_NETKIT=y
# CONFIG_PACKAGE_luci-app-vlmcsd is not set
# CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn is not set
# CONFIG_PACKAGE_vlmcsd is not set
# CONFIG_PACKAGE_luci-app-ddns-go is not set
# CONFIG_PACKAGE_luci-i18n-ddns-go-zh-cn is not set
# CONFIG_PACKAGE_ddns-go is not set
# CONFIG_PACKAGE_luci-app-ddns is not set
# CONFIG_PACKAGE_luci-i18n-ddns-zh-cn is not set
# CONFIG_PACKAGE_ddns-scripts is not set
# CONFIG_PACKAGE_ddns-scripts-aliyun is not set
# CONFIG_PACKAGE_ddns-scripts-cloudflare is not set
# CONFIG_PACKAGE_ddns-scripts-dnspod is not set
# CONFIG_PACKAGE_ddns-scripts-services is not set
# CONFIG_PACKAGE_luci-app-lucky is not set
# CONFIG_PACKAGE_luci-i18n-lucky-zh-cn is not set
# CONFIG_PACKAGE_lucky is not set
# CONFIG_PACKAGE_luci-app-zerotier is not set
# CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn is not set
# CONFIG_PACKAGE_zerotier is not set
# CONFIG_PACKAGE_luci-app-wechatpush is not set
# CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn is not set
# CONFIG_PACKAGE_luci-app-pushbot is not set
# CONFIG_PACKAGE_luci-i18n-pushbot-zh-cn is not set
CONFIG_PACKAGE_kmod-nft-queue=y
CONFIG_PACKAGE_kmod-nfnetlink-queue=y
CONFIG_PACKAGE_airoha-an7581-mt7996-board=y
# CONFIG_FEED_pon_drivers is not set
# CONFIG_FEED_onu_config is not set
# CONFIG_FEED_pon_userspace is not set
# CONFIG_FEED_pushbot is not set
# CONFIG_FEED_uniwrt is not set
# CONFIG_FEED_easytier is not set
# CONFIG_PACKAGE_luci-theme-uniwrt is not set
# CONFIG_PACKAGE_oxidns is not set
# CONFIG_PACKAGE_luci-app-oxidns is not set
# CONFIG_PACKAGE_luci-i18n-oxidns-zh-cn is not set
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_yq=y
CONFIG_PACKAGE_jq=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_kmod-inet-diag=y
CONFIG_PACKAGE_kmod-nft-socket=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-dummy=y
CONFIG_PACKAGE_luci-app-smartdns=y
CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y
# CONFIG_FEED_mosdns is not set
# CONFIG_PACKAGE_mosdns is not set
# CONFIG_PACKAGE_luci-app-mosdns is not set
# CONFIG_PACKAGE_luci-i18n-mosdns-zh-cn is not set
# CONFIG_PACKAGE_geo2txt is not set
CONFIG_PACKAGE_bridger=y
CONFIG_PACKAGE_kmod-crypto-hw-eip93=y
CONFIG_PACKAGE_kmod-cryptodev=y
CONFIG_PACKAGE_kmod-crypto-user=y
CONFIG_PACKAGE_luci-app-clients=y
CONFIG_PACKAGE_luci-i18n-clients-zh-cn=y
CONFIG_PACKAGE_nlbwmon=y
CONFIG_PACKAGE_arp-scan=y
CONFIG_PACKAGE_arp-scan-database=y
CONFIG_PACKAGE_flock=y
CONFIG_PACKAGE_mount-utils=y
CONFIG_PACKAGE_pppoe-discovery=y
# CONFIG_PACKAGE_luci-app-airoha-factory is not set
# CONFIG_PACKAGE_luci-i18n-airoha-factory-zh-cn is not set
# CONFIG_PACKAGE_luci-app-airoha-recovery is not set
# CONFIG_PACKAGE_luci-i18n-airoha-recovery-zh-cn is not set
# CONFIG_PACKAGE_usteer is not set
# CONFIG_PACKAGE_luci-app-usteer is not set
# CONFIG_PACKAGE_luci-i18n-usteer-zh-cn is not set
# CONFIG_PACKAGE_xray-core is not set
# CONFIG_PACKAGE_udpxy is not set
# CONFIG_PACKAGE_luci-app-udpxy is not set
# CONFIG_PACKAGE_luci-i18n-udpxy-zh-cn is not set
# CONFIG_PACKAGE_msd_lite is not set
# CONFIG_PACKAGE_luci-app-msd_lite is not set
# CONFIG_PACKAGE_luci-i18n-msd_lite-zh-cn is not set
# CONFIG_PACKAGE_rtp2httpd is not set
# CONFIG_PACKAGE_luci-app-rtp2httpd is not set
# CONFIG_PACKAGE_luci-i18n-rtp2httpd-zh-cn is not set
# CONFIG_PACKAGE_luci-app-mesh-conf is not set
# CONFIG_PACKAGE_luci-i18n-mesh-conf-zh-cn is not set
# CONFIG_PACKAGE_luci-app-wifihistory is not set
# CONFIG_PACKAGE_luci-i18n-wifihistory-zh-cn is not set
# CONFIG_PACKAGE_luci-proto-wireguard is not set
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_socat=y
CONFIG_OPENSSL_ENGINE=y
CONFIG_OPENSSL_ENGINE_BUILTIN=y
CONFIG_OPENSSL_ENGINE_BUILTIN_DEVCRYPTO=y
CONFIG_PREINITOPT=y
CONFIG_PACKAGE_relayd=y
CONFIG_PACKAGE_luci-proto-relay=y
# CONFIG_BUSYBOX_CONFIG_NTPD is not set
# CONFIG_BUSYBOX_CONFIG_FEATURE_NTPD_SERVER is not set
CONFIG_PACKAGE_chrony=y
CONFIG_PACKAGE_luci-app-chrony=y
CONFIG_PACKAGE_luci-i18n-chrony-zh-cn=y
EOF

cp 1710.config .config

awk '
  NR==FNR { k=$0; sub(/^# /,"",k); sub(/( is not set|=y)$/,"",k); drop[k]=1; next }
  { k=$0; sub(/^# /,"",k); sub(/(=.*| is not set)$/,"",k); if (k in drop) next; print }
' /tmp/xr1710g-options.conf .config > .config.new && mv .config.new .config

cat /tmp/xr1710g-options.conf >> .config

make defconfig
```

`make defconfig` 会按依赖补全其余选项。注意 `PREINITOPT` 必须开启，否则 `TARGET_PREINIT_*` 字符串没有提示项，`defconfig` 会把管理地址重置为 `192.168.1.1`。生成后请核对 `.config` 与最终镜像清单，不要仅凭选项断言某项已内置。

## 3. 下载与编译

```sh
make download -j"$(nproc)"
make -j"$(nproc)" world
```

固件、manifest、校验值和构建信息位于 `bin/targets/airoha/an7581/`，两个 profile 的镜像文件名分别形如 `*gemtek_xr1710g-squashfs-sysupgrade.itb` 和 `*gemtek_xr1710g-ubi-squashfs-sysupgrade.itb`。实际使用的 feeds 提交以本次 `feeds.buildinfo` 为准；由于 feeds 浮动，这不是严格可复现构建。

编译期间不要并行修改配置或应用上游补丁。无线客户端、中继接口、用户密码、SSH 密钥等属于设备设置，不从旧设备导入源码；全新固件中的上游默认无线口令应在部署时修改。
