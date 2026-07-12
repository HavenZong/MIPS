# MIPS CPU 项目交接文档

本文档用于新开对话时快速接续当前项目状态。项目路径：

```text
/home/luoshuang/mips
```

## 当前稳定状态

当前分支是 `main`，远程是 `origin https://github.com/HavenZong/MIPS.git`。

当前 HEAD：

```text
245db82 Revert "Optimize icache metadata storage"
```

这个提交回滚了上一版导致远程 0 分的 I-cache 元数据 BRAM 化尝试。当前代码不是七级流水整体重构，而是在原五级流水基础上叠加了性能部件：

- I-cache
- 静态 backward-taken 分支预测
- 同步读 D-cache
- 两词 D-cache line
- write-back D-cache
- store queue + forwarding
- `mul` 指令和乘法写回流水
- 监控程序 UART 兼容
- CPU 时钟提升到 56.25MHz

最新可提交 bitstream：

```text
/home/luoshuang/mips/run_vivado/project/thinpad_top.runs/impl_1/thinpad_top.bit
```

这版本地 Vivado 实现通过，WNS：

```text
+0.028 ns
```

已经 push：

```text
git push origin main
```

## 本地验证命令

回滚后的稳定版已跑过以下本地验证：

```sh
python3 run_vivado/flow/lint_hdl.py run_vivado/project/thinpad_top.xpr
make -C sim kernel-perf
make -C sim cryptonight
make -C sim soc-system-perf
python3 run_vivado/flow/check_timing.py run_vivado/project/thinpad_top.runs/impl_1/timing_summary.rpt
vivado -mode batch -source run_vivado/flow/generate_bitstream.tcl
```

其中 `kernel-perf`、`cryptonight`、`soc-system-perf` 都通过；bitstream 生成成功。

注意：当前工作区有一些未跟踪的临时文件/诊断目录，不属于提交内容，除非明确需要，不要清理或提交：

```text
.codegraph/
clockInfo.txt
diag/
image copy.png
image.png
run_vivado/clockInfo.txt
run_vivado/ext_ram_magic/
run_vivado/hs_err_pid43.log
run_vivado/tight_setup_hold_pins.txt
run_vivado/uart_selftest/
sim/obj_dir_real_uart/
```

## 评测阶段与重要问题

### 一级评测

要求实现：

```text
ori lui addu bne lw sw
```

内存映射：

```text
0x80000000-0x803FFFFF -> BaseRAM
0x80400000-0x807FFFFF -> ExtRAM
```

复位 PC 是 `0x80000000`，小端序。一级斐波那契程序通过后，说明基础取指、load/store、分支和 ExtRAM 写入基本可用。

### 三级评测

要求实现 MIPS-C3 21 条指令：

```text
and andi lui or ori xor xori sll srl addu addiu
beq bgtz bne j jal jr lb sb lw sw
```

测试器用基础监控程序验证，必须支持 UART：

```text
9600 baud, 8N1
0xBFD003F8 数据口
0xBFD003FC 状态口
```

三级阶段遇到的关键问题：

- 远程复位后无串口输出，最初需要确认 kernel 是否加载到 BaseRAM 地址 `0x00000000`。
- UART 状态位、发送时序、RX 缓冲和复位行为都踩过坑。
- 最关键 CPU bug 是分支/跳转延迟槽被错误清掉。一级程序延迟槽多是 NOP，所以能过；监控程序延迟槽里有实际指令，例如 `jr $ra` 后的栈恢复，跳过后会跑飞。
- 修复延迟槽重定向后，三级远程通过。

### 性能评测

性能评测新增 `mul`，共 22 条指令。当前统一使用：

```text
/home/luoshuang/下载/kernel.bin
/home/luoshuang/下载/supervisor_mips.zip
```

重复下载的 `kernel (1).bin` 与 `kernel.bin` 相同；重复下载的 `supervisor_mips (1).zip` 与 `supervisor_mips.zip` 相同，项目里统一只引用不带 `(1)` 的路径。

性能测试远程主要包括：

```text
Test STREAM
Test MATRIX
Test CRYPTONIGHT
```

历史性能节点中，稳定优化后用户曾报告约：

```text
0.280s, 0.498s, 1.100s
```

后来尝试 I-cache metadata BRAM 化后远程 0 分，已回滚。因此当前应先以 `245db82` 生成的 bitstream 恢复 100 分，再继续优化。

## 优化尝试历史

主要提交链如下：

```text
14ed695 Implement five-stage MIPS CPU
cab9f76 Add level3 monitor evaluation test
b317926 Fix monitor UART status bits
a8532ee Buffer UART RX commands
7665e28 Use deterministic UART transmitter
009e0d0 Fix UART bus read handshake
8907e75 Stabilize remote UART startup
a079da9 Add matrix perf regression and SRAM margin
0c6eaae Fix matrix pipeline hazards
556b625 Fix taken branch delay slot redirect
15978da Optimize memory fetch overlap
4ea7e18 Overlap fetch and memory pipeline progress
1d3c90c Add instruction cache
5fbf091 Add static backward branch prediction
96442e3 Add synchronous data cache
60d29e1 Pipeline multiply writeback
4d47e15 Add two-word data cache line
ecc4727 Fix data cache prefetch valid merge
79719e0 Add store buffer
229a14e Fix store buffer cache coherency
b3d56d5 Revert store buffer
267ac0c Add store queue forwarding
520291a Expand store queue to two entries
b26a26a Disable D-cache prefetch
cb988f4 Increase I-cache capacity
dd21f20 Expand I-cache and predict direct jumps
a975068 Tune cache capacities
b16da01 Refine icache invalidation
a3f024f Implement write-back dcache
9288941 Bypass dcache store conflicts
fd35113 Register icache invalidation
f99e2c0 Run CPU at 55MHz
e2a7eaa Run CPU at 56.25MHz
19480fd Optimize icache metadata storage
245db82 Revert "Optimize icache metadata storage"
```

### 成功方向

- I-cache：明显降低 MATRIX/CRYPTONIGHT 时间。
- backward-taken 静态预测：有小幅收益。
- D-cache 改为同步读结构：降低资源/时序压力。
- two-word D-cache line：提升连续访存。
- write-back D-cache：带来较大收益，尤其 STREAM/MATRIX。
- store queue + forwarding：有效，但实现需要完整处理 load forwarding 和冲突。
- 提升时钟到 55MHz/56.25MHz：有效，但 WNS 余量很小。

### 失败或高风险方向

- 简单 store buffer 曾导致 50 分，后来回滚；原因是与 cache coherency/forwarding 不完整。
- 扩大 user I-cache 曾尝试后回滚。
- D-cache prefetch 曾出现有效位合并问题，最终关闭 prefetch。
- `19480fd Optimize icache metadata storage` 将 I-cache tag/valid 元数据改为 BRAM/同步 lookup，本地仿真通过且 Vivado WNS 为正，但远程 0 分。判断是远程监控交互路径或取指 refill/flush 边界被破坏。该提交已由 `245db82` 回滚。

## 参考项目结论

用户给过参考项目：

```text
https://github.com/fluctlight001/cpu_for_nscscc2022_single
```

本地 `/tmp/cpu_for_nscscc2022_single_submit7` 有 `submit7` 分支副本。该参考项目确实实现了 7 级流水，顶层阶段为：

```text
IF -> IC -> ID -> EX -> DC -> MEM -> WB
```

其中：

- `IC` 是 instruction capture，承接取指 SRAM 返回。
- `DC` 是 data capture，承接数据 SRAM 访问路径。
- `MEM` 做 load 数据选择和写回数据生成。

参考项目的流水总线包括：

```text
if_to_ic_bus
ic_to_id_bus
id_to_ex_bus
ex_to_dc_bus
dc_to_mem_bus
mem_to_wb_bus
```

结论：参考项目不是五级流水小修，它是明确的 7 级流水。但不能照搬源码。若要借鉴，应借鉴阶段边界，把我们当前的取指返回路径、D-cache 命中返回路径和 load 数据选择路径拆级。

## 当前没有做完整七级流水的原因

当前设计不是完整七级流水重构。之前的优化主要是围绕稳定 100 分逐步推进，原因：

- 监控程序、UART、SRAM、I/D cache、write-back D-cache、store queue、延迟槽、`mul` 已经强耦合。
- 七级流水需要重写 hazard、stall、flush、bypass、load-use、store-load forwarding、分支延迟槽处理。
- 中间态往往无法远程通过，不能像小优化一样每一步稳定验收。
- 远程平台本地仿真覆盖不完全，曾经出现本地过但远程 0 分的情况。

如果新开对话要继续大重构，建议先新建分支，不要直接在 `main` 上冒险。

## 后续建议

### 第一优先级：恢复确认

先用当前 bitstream 上传远程，确认分数恢复到 100：

```text
/home/luoshuang/mips/run_vivado/project/thinpad_top.runs/impl_1/thinpad_top.bit
```

若恢复 100，再继续优化。

### 第二优先级：七级流水重构分支

建议从当前稳定版创建新分支：

```sh
git checkout -b pipeline7-experiment
```

推荐拆级顺序：

1. 先只拆 IF 前端：形成 `IF1/IF2/ID/EX/MEM/WB` 或 `IF/IC/ID/EX/MEM/WB`，保持 D-cache 不动。
2. 重写 PC redirect、延迟槽和预测失败 flush，必须保证三级监控程序先过。
3. 再拆 D-cache/load 后端：形成 `IF/IC/ID/EX/DC/MEM/WB`。
4. 重新整理 forwarding：
   - EX 结果旁路
   - DC/MEM load 结果旁路
   - WB 结果旁路
   - store queue forwarding
5. 最后再提升频率。

七级重构的目标不是先加功能，而是缩短当前关键路径：

- I-cache/tag/PC/fetch redirect 路径
- D-cache hit/load data select/writeback 路径
- store queue conflict/forwarding 路径
- `mul` DSP 输出路径

### 第三优先级：继续小步优化

如果不做七级重构，比较稳的方向是：

- 优化 `mul` DSP pipeline。Vivado bitgen DRC 明确提示 DSP 的 MREG/PREG 不完整。
- 对 I-cache tag 元数据重新设计，但不能重复 `19480fd` 的同步 lookup 方式，必须增加远程交互相关仿真。
- 针对 CRYPTONIGHT 分析 cache miss 与 store queue 命中率，避免盲目扩大 cache。

## 新对话注意事项

新 agent 接手时请先做：

```sh
git status --short
git log --oneline -5
python3 run_vivado/flow/lint_hdl.py run_vivado/project/thinpad_top.xpr
make -C sim kernel-perf
make -C sim cryptonight
make -C sim soc-system-perf
```

不要重复做的事：

- 不要重新引入 `19480fd` 的 I-cache metadata BRAM 化实现。
- 不要假设本地仿真通过就能远程通过。
- 不要清理未跟踪文件，除非用户明确要求。
- 不要声称当前是七级流水。
- 不要直接照抄参考项目代码。

如果要做会影响远程通过率的大改，必须每一步都：

1. 本地 lint。
2. 本地 kernel/perf/cryptonight/soc-system 仿真。
3. Vivado 实现。
4. 生成 bitstream。
5. 用户远程确认。

