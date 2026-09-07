# 功能与性能测试记录

测试日期：2026-09-08。结果：70 项自动化测试通过，0 失败、0 测试错误；StyLua 与 `git diff --check` 通过。

**比较基线**

本轮开始时的工作区快照，已经包含上一轮 ShaDa 批量读取、避免复制后额外读取剪贴板，以及 Lua API 迁移。表格中的收益是本轮新增收益，不是与最初上游版本比较。

**功能覆盖**

| 测试文件 | 数量 | 覆盖内容 |
| --- | ---: | --- |
| `spec/yanky_spec.lua` | 16 | 字符、行、块、可视粘贴，次数、命名寄存器、表达式寄存器、点重复与撤销 |
| `spec/yanky_cycle_spec.lua` | 4 | 字符、行、可视、可视块模式的历史轮换与边界 |
| `spec/yanky/special_put_spec.lua` | 2 | 格式化粘贴及光标位置 |
| `spec/yanky/utils_spec.lua` | 10 | OSC 52 检测和寄存器选择 |
| `spec/yanky/performance_spec.lua` | 9 | 模拟剪贴板 provider 调用次数、内容转换、寄存器追加、ShaDa 容量与副本隔离 |
| `spec/yanky/lifecycle_spec.lua` | 12 | 重复初始化、焦点定时器取消、高亮清理、临时寄存器异常恢复、无效映射、游标边界、监听数量 |
| `spec/yanky/storage_spec.lua` | 12 | memory/ShaDa/SQLite 的去重、容量、读取、轮换、删除、清空；SQLite 重开、限量查询、失败回滚、内存回退 |
| `spec/yanky/system_clipboard_spec.lua` | 5 | 剪贴板改变与未改变、读取失败恢复、快速焦点切换、持续失焦后的同步 |

本轮补充回归测试时，修复前首先复现了 9 个失败断言。另一个延迟注册问题会在 Neovim 调度回调中报错，测试现已直接捕获并检查该回调，避免只看测试进程退出码。

**修复与实现调整**

- 高亮 autocmd 使用独立分组，重复 `setup()` 不再累积回调；重新配置时关闭旧定时器。
- 高亮清理绑定原缓冲区；切换缓冲区、关闭高亮时不再遗留标记。过期定时回调不会清除新的高亮。
- 关闭剪贴板同步时清除旧 autocmd、定时器及快照；快速焦点切换取消待执行读取，重新配置后的过期回调失效。
- 临时寄存器在 callback 抛错后恢复原内容和类型，再传播错误；读取失败时避免覆盖无法恢复的寄存器。
- picker 的无效特殊映射会报告错误，不再因为拼接 Lua 内置 `type` 函数而异常；按实际模式检查映射并复用回调。
- 历史游标不再递减到负数；读取首条、下一条直接读取记录，省去前置长度查询。
- SQLite 初始化失败正确回退并初始化 memory 后端；支持没有目录部分的数据库路径。
- SQLite 插入与历史裁剪在一个事务内提交；模拟裁剪失败后验证插入被回滚、后续写入仍可成功。
- 同一缓冲区的光标保留监听仅注册一次；历史边界的重复操作不再叠加 ring 监听。
- ring 清理或重新配置后，待调度的移动事件注册不再访问空状态；旧缓冲区的回调不会清理新的 ring。
- 保留上一轮 Lua 迁移；实现与测试代码中已无 `vim.cmd`、`nvim_command` 或内嵌 Ex 脚本字符串。原生编辑操作通过结构化 `nvim_cmd` 执行。

**性能测量方法**

环境：WSL2，内核 `6.18.33.2-microsoft-standard-WSL2`，Neovim 0.12.5，LuaJIT 2.1.1787165859。
每个场景预填充 100 条历史，开启数字寄存器同步；分别使用约 1 KiB 和 64 KiB 的条目。每组执行五轮，表格为总耗时中位数，单位 ms；正百分比表示耗时减少。

SQLite 数据库位于插件目录下的 `.spec/benchmark/`，在 WSL Linux 文件系统上，`stat -f` 显示 `ext2/ext3`。未关闭 SQLite 的默认同步保障。临时数据库在每个场景结束时删除。早期 `/tmp`（tmpfs）测量不纳入下表。

| 场景 | 每轮次数 | 本轮前 ms | 本轮后 ms | 耗时变化 |
| --- | ---: | ---: | ---: | ---: |
| memory push+sync 1024B | 500 | 3.265 | 3.639 | -11.5% |
| memory push+sync 65536B | 100 | 27.872 | 29.117 | -4.5% |
| shada push+sync 1024B | 500 | 52.038 | 52.100 | -0.1% |
| shada first 1024B | 500 | 14.553 | 6.986 | +52.0% |
| shada next 1024B | 500 | 14.873 | 6.863 | +53.9% |
| shada push+sync 65536B | 100 | 114.459 | 105.109 | +8.2% |
| shada first 65536B | 100 | 32.357 | 16.581 | +48.8% |
| shada next 65536B | 100 | 32.044 | 15.978 | +50.1% |
| sqlite push+sync 1024B | 500 | 3067.272 | 1709.449 | +44.3% |
| sqlite first 1024B | 500 | 128.514 | 44.217 | +65.6% |
| sqlite next 1024B | 500 | 114.557 | 50.095 | +56.3% |
| sqlite push+sync 65536B | 100 | 709.984 | 475.986 | +33.0% |
| sqlite first 65536B | 100 | 24.077 | 11.630 | +51.7% |
| sqlite next 65536B | 100 | 26.463 | 13.675 | +48.3% |

| 累积场景 | 本轮前 | 本轮后 |
| --- | ---: | ---: |
| 再执行 20 次 setup 后的 TextYankPost 回调数 | 22 | 2 |
| 连续 1000 次 yank 注册的光标保留监听数 | 1000 | 1 |

memory 的首条/下一条读取在此循环中受 LuaJIT 优化影响，计时接近分辨率下限，因此不报告加速倍数。memory 写入本轮未改热路径，测量略慢；这组结果不支持声称 memory 写入提速。ShaDa 写入小条目基本持平；主要收益来自历史读取和 SQLite 事务。

这些数据是内部路径微基准，不等于完整编辑操作延迟。剪贴板测试使用模拟 provider 验证正确性及调用次数，未测量 Windows `win32yank.exe` 或 PowerShell 的真实耗时；也未测试 `/mnt/c` 上的数据库、交互式 Telescope/Snacks UI 或其他 Neovim 版本。

**复跑**

```sh
make test
YANKY_SQLITE_RTP="/path/to/sqlite.lua" make benchmark
```

`make test` 会准备 Plenary 与 sqlite.lua 测试依赖，需要系统可加载 SQLite 库。`make benchmark` 不加载个人 Neovim 配置，不修改用户剪贴板；未提供可用 sqlite.lua 时会明确跳过 SQLite 场景。

可用 `YANKY_BENCH_DIR` 指定数据库所在文件系统。当前本地保留了被 git 忽略的 `.spec/baseline` 快照，可这样复测基线：

```sh
YANKY_BENCH_RTP="$PWD/.spec/baseline" \
YANKY_SQLITE_RTP="/path/to/sqlite.lua" make benchmark
```
