# luci-app-turboacc

一个适用于官方Official OpenWrt(24.10/snapshot) firewall3/firewall4的turboacc  
包括以下功能：快速转发引擎、全锥形 NAT1、TCP 拥塞控制算法

目前仅测试了2025-11-20的x86平台的snapshot版本OpenWrt，fw3(iptables)和fw4(nftables)均可用

## 使用方法

+ 在openwrt源代码所在目录执行：

    ```bash
    curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh
    ```

+ 之后执行

```bash
make menuconfig
```

+ 在 > LuCI > 3. Applications中选中luci-app-turboacc

## 注意

1. 软件流量分载默认使用`flow offloading`，可根据需要自行更换为`fast classifier`或`shortcut-fe`。
2. 因OpenWrt现在使用`firewall4`作为默认防火墙，如果切换为`firewall3`的话，请把所有与nft相关的包手动取消掉，并替换为相应的ipt包(例如: `iptables-nft`替换为`iptables-zz-legacy`)。

## 插件预览

![fw3预览](https://raw.githubusercontent.com/mufeng05/turboacc/main/img/fw3.png)
![fw4预览](https://raw.githubusercontent.com/mufeng05/turboacc/main/img/fw4.png)

## 关于

此仓库的luci-app-turboacc是基于lede的[luci-app-turboacc](https://github.com/coolsnowwolf/luci/tree/openwrt-23.05/applications/luci-app-turboacc)和chenmozhijin的[turboacc](https://github.com/chenmozhijin/turboacc)修改而来的，保留了lede版luci-app-turboacc的所有功能。

## 感谢

 感谢以下项目：

+ [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)
+ [coolsnowwolf/luci](https://github.com/coolsnowwolf/luci)
+ [chenmozhijin/turboacc](https://github.com/chenmozhijin/turboacc)
