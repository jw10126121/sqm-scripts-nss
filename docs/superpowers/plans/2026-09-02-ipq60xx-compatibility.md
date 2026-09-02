# IPQ60xx NSS 兼容性适配实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 让 `nss-zk.qos` 在 IPQ6010、IPQ6018、IPQ807x 以及兼容的未知 NSS 平台上运行，并在 NSS 能力不足时明确失败和清理。

**架构：** 脚本读取 device-tree compatible 生成诊断用平台名，但不按 SoC 修改整形参数。模块准备和正式 qdisc/filter 创建共同构成能力检查；启动任一方向失败时调用幂等的停止流程回滚部分配置。

**技术栈：** POSIX `sh`、OpenWrt `sqm-scripts` helpers、BusyBox `tr`、`tc` NSS qdisc、Markdown。

---

### 任务 1：加入可注入的平台识别

**文件：**
- 修改：`sqm-scripts-nss/files/nss-zk.qos:46-75`（常量与工具函数区域）
- 测试：`tests/test_nss_platform.sh`

- [x] **步骤 1：编写失败测试**

创建测试脚本，生成 null 分隔的 compatible 临时文件，从 `nss-zk.qos` 提取 `nss_platform_detect` 函数并断言 IPQ6010、IPQ6018、IPQ807x、未知值分别映射为预期名称。测试通过 `NSS_COMPATIBLE_FILE` 注入文件路径，不触碰真实 `/proc`。

```sh
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../sqm-scripts-nss/files" && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

extract_platform_fn() {
    sed -n '/^nss_platform_detect()/,/^}/p' "$SCRIPT_DIR/nss-zk.qos"
}

assert_platform() {
    name=$1
    printf '%s\\000%s\\000' "$2" > "$TEST_ROOT/compatible"
    NSS_COMPATIBLE_FILE="$TEST_ROOT/compatible"
    export NSS_COMPATIBLE_FILE
    result=$(sh -c "$(extract_platform_fn); nss_platform_detect")
    [ "$result" = "$name" ]
}

assert_platform ipq6010 'qcom,ipq6010-router'
assert_platform ipq6018 'qcom,ipq6018-router'
assert_platform ipq807x 'qcom,ipq8074'
assert_platform unknown 'vendor,custom-router'
```

- [x] **步骤 2：运行测试确认失败**

运行：`sh tests/test_nss_platform.sh`

预期：FAIL，因为 `nss_platform_detect` 尚未定义。

- [x] **步骤 3：实现最小平台识别函数**

在常量之后加入：

```sh
nss_platform_detect() {
    local compatible_file="${NSS_COMPATIBLE_FILE:-/proc/device-tree/compatible}"
    local compatible

    [ -r "$compatible_file" ] || {
        echo unknown
        return 0
    }
    compatible=$(tr '\\000' '\\n' < "$compatible_file" 2>/dev/null) || compatible=
    case "$compatible" in
        *ipq6010*) echo ipq6010 ;;
        *ipq6018*) echo ipq6018 ;;
        *ipq60*) echo ipq60xx ;;
        *ipq807*|*ipq8074*) echo ipq807x ;;
        *) echo unknown ;;
    esac
}
```

- [x] **步骤 4：运行测试确认通过**

运行：`sh tests/test_nss_platform.sh`

预期：无输出且退出码为 0。

### 任务 2：接入能力日志与启动失败回滚

**文件：**
- 修改：`sqm-scripts-nss/files/nss-zk.qos:316-384`（生命周期函数）
- 测试：`tests/test_nss_zk_syntax.sh`

- [x] **步骤 1：增加 shell 语法回归测试**

```sh
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../sqm-scripts-nss/files" && pwd)
sh -n "$SCRIPT_DIR/nss-zk.qos"
```

- [x] **步骤 2：运行语法测试确认当前基线**

运行：`sh tests/test_nss_zk_syntax.sh`

预期：当前脚本语法检查通过。

- [x] **步骤 3：在 `sqm_start` 中记录平台并聚合失败状态**

在 `network_get_protocol` 后执行 `platform=$(nss_platform_detect)` 并记录 `sqm_log "sqm_start: NSS platform=${platform}"`。增加 `local status=0`；egress 或 ingress 返回失败时设置 `status=1`。两个方向处理完成后，若 `status` 非 0，记录警告、调用 `sqm_stop` 清理并 `return 1`，否则记录成功。

- [x] **步骤 4：补充 qdisc 状态诊断**

新增 `nss_log_qdisc_state()`，对启用的真实设备执行 `$TC qdisc show dev ...`，通过 `sqm_debug` 输出结果；该函数只读，不执行独立探测命令。egress/ingress 成功后调用它，便于确认输出中的 `accel_mode 0`。

- [x] **步骤 5：运行语法测试和静态检查**

运行：`sh tests/test_nss_zk_syntax.sh && rtk git diff --check`

预期：全部通过，且 diff 无空白错误。

### 任务 3：更新包元数据与用户文档

**文件：**
- 修改：`sqm-scripts-nss/files/nss-zk.qos:4-15`
- 修改：`sqm-scripts-nss/files/nss-zk.qos.help:1-2`
- 修改：`sqm-scripts-nss/Makefile:16-19`
- 修改：`README.md` 中平台、依赖、验证和限制说明

- [x] **步骤 1：更新脚本头和帮助文本**

将平台描述统一为“IPQ60xx（IPQ6010/IPQ6018）及 IPQ807x NSS-enabled 平台”，并说明需要 qdisc、IGS redirect 模块和对应 `tc` 支持；不声称普通无 NSS 固件可用。

- [x] **步骤 2：更新 Makefile 描述**

把包标题/描述改为 Qualcomm IPQ60xx/IPQ807x NSS 硬件加速 SQM，保持现有依赖名称和安装路径不变。

- [x] **步骤 3：更新 README 的平台范围**

替换仅指向 IPQ807x 的要求、标题和限制文字，加入 IPQ6010/IPQ6018；在验证章节增加平台日志和 `accel_mode 0` 检查方法，并说明最终兼容性取决于运行时 NSS 驱动/固件能力。

- [x] **步骤 4：运行 Markdown 与差异检查**

运行：`rtk rg -n 'IPQ807x|IPQ8074|IPQ60xx|IPQ6010|IPQ6018' README.md sqm-scripts-nss && rtk git diff --check`

预期：文档不再把 IPQ807x 描述为唯一支持平台，且没有空白错误。

### 任务 4：端到端主机侧验证

**文件：**
- 修改：无
- 测试：`tests/test_nss_platform.sh`、`tests/test_nss_zk_syntax.sh`

- [x] **步骤 1：运行全部测试**

运行：`sh tests/test_nss_platform.sh && sh tests/test_nss_zk_syntax.sh`

预期：两个脚本均以退出码 0 完成。

- [x] **步骤 2：检查工作区范围**

运行：`rtk git status --short` 和 `rtk git diff --stat`

预期：只包含本规格、实现脚本、包元数据、README 和测试文件；不修改用户已有文件。

- [x] **步骤 3：记录设备侧验证命令**

在交付说明中给出设备侧命令：`logread | grep 'NSS platform'`、`tc -s qdisc show dev <wan>`、`tc -s qdisc show dev ifb@<wan>`，并说明应看到 `nsstbl`、`nssfq_codel` 和 `accel_mode 0`。本地环境不具备 IPQ 设备时，不宣称已完成硬件实测。
