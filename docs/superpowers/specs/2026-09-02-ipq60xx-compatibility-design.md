# IPQ60xx NSS 兼容性适配设计

## 目标

在保留现有 IPQ807x 行为的前提下，使 `sqm-scripts-nss` 支持启用 NSS qdisc 的 IPQ60xx 固件，至少覆盖 IPQ6010 和 IPQ6018。适配不根据 SoC 型号猜测队列或整形参数；这些参数继续由链路配置和 NSS 驱动实际能力决定。

## 方案

采用平台识别与能力探测结合的方式：

- 从 `/proc/device-tree/compatible` 读取平台信息，仅用于日志和诊断。
- 支持 `ipq6010`、`ipq6018`、`ipq807x` 的归一化名称；无法识别的平台记为 `unknown`，不因名称未知而直接拒绝。
- 启动时加载 `qca_nss_qdisc` 和 `act_nssmirred`，以模块加载结果作为基础能力检查。
- 正式创建 `nsstbl`、`nssfq_codel` 和 ingress redirect 时检查 `$TC` 返回值。任何一步失败都记录清晰错误，并由生命周期清理逻辑删除已经创建的 qdisc/filter。
- 保留现有 ECN 参数回退：patched `tc` 不接受 ECN 时重试不带 ECN 的命令。

## 运行流程

1. `sqm_start` 记录归一化平台名称。
2. 执行现有地址检查和模块准备流程。
3. 按现有 egress/ingress 顺序创建 qdisc；每个创建步骤保留返回码。
4. egress 或 ingress 创建失败时，不继续伪装成成功启动；清理本次已建立的对象并返回失败状态。
5. `sqm_stop` 保持幂等，可清理部分启动留下的 root、ingress 和 IFB qdisc。

## 文档与包元数据

- `nss-zk.qos` 文件头、`.help` 和 Makefile 描述改为 IPQ60xx/IPQ807x NSS-enabled 平台。
- README 的支持平台、依赖和验证说明覆盖 IPQ6010、IPQ6018，同时明确要求对应固件提供 `qca_nss_qdisc`、`act_nssmirred` 及支持 `nsstbl`/`nssfq_codel` 的 `tc`。
- 文档说明：SoC 识别用于诊断，实际兼容性由运行时 NSS 能力决定。

## 验证

- 对脚本执行 `sh -n`，确保 POSIX shell 语法正确。
- 使用 stub 方式模拟 IPQ6010、IPQ6018、IPQ807x 和未知 compatible，确认平台日志不影响启动路径。
- 模拟模块加载失败、qdisc 创建失败和 ingress redirect 失败，确认返回失败并清理已建立对象。
- 检查 git diff，确保只涉及脚本、包元数据、README、规格及必要测试文件。

## 非目标

- 不为不同 SoC 引入不同的带宽、burst、quantum、overhead 或队列层级参数。
- 不承诺没有 NSS qdisc/firmware 支持的普通 IPQ60xx 固件可以使用该脚本。
- 不通过独立的破坏性 `tc` 试探命令改变线上接口；能力判断以正式创建流程的返回值为准。
