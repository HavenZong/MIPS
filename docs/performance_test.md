# 性能测试说明

本测试用于验证 32 位 MIPS CPU 在基础监控程序和高负载测试程序下的功能正确性。相对三级评测，性能测试新增 `mul` 指令要求。

## 指令要求

性能测试要求支持 MIPS-C3 的 22 条指令：

- `and`
- `andi`
- `lui`
- `or`
- `ori`
- `xor`
- `xori`
- `sll`
- `srl`
- `addu`
- `addiu`
- `beq`
- `bgtz`
- `bne`
- `j`
- `jal`
- `jr`
- `lb`
- `sb`
- `lw`
- `sw`
- `mul`

其中 `mul` 编码为：

```text
opcode = 011100
funct  = 000010
格式   = mul rd, rs, rt
结果   = signed(rs) * signed(rt) 的低 32 位写入 rd
```

当前 `src/soc/mips_core.v` 已实现该指令：ID 阶段将 `opcode=011100` 识别为写回 `rd` 的 R 型运算，EX 阶段执行有符号乘法并写回低 32 位。

## CPU 与外设要求

- 虚拟内存空间为 `0x80000000` 到 `0x807FFFFF`，共 8MB。
- `0x80000000` 到 `0x803FFFFF` 映射到 BaseRAM。
- `0x80400000` 到 `0x807FFFFF` 映射到 ExtRAM。
- CPU 使用小端序。
- CPU 复位后从 `0x80000000` 开始取指执行。
- `reset_btn` 高电平时 CPU 复位，松开后解除复位。
- 当前设计使用 `clk_50M`。
- 串口为 9600 波特率，8 数据位，1 停止位，无校验。
- 串口 MMIO 地址与基础监控程序一致：

| 地址 | 位 | 说明 |
| --- | --- | --- |
| `0xBFD003F8` | `[7:0]` | 串口数据口，读表示接收一个字节，写表示发送一个字节 |
| `0xBFD003FC` | `[0]` | 只读，为 1 表示串口空闲，可发送 |
| `0xBFD003FC` | `[1]` | 只读，为 1 表示串口收到数据 |

## 官方测试流程

1. 将拨码开关设置为 0。
2. 将 `kernel.bin` 下载到 BaseRAM 起始位置，即物理地址 `0x00000000`。
3. 打开串口终端，参数为 9600、8N1。
4. 单击复位按钮。
5. 等待 Kernel 输出欢迎信息。
6. 使用 `G` 命令执行测试程序。
7. 使用 `R` 和 `D` 命令读取用户程序执行后的寄存器和内存，由测试器检查结果。

性能测试发布包：

```text
/home/luoshuang/下载/kernel.bin
/home/luoshuang/下载/supervisor_mips.zip
```

重复下载得到的另一个 Kernel 文件与 `kernel.bin` 内容完全一致，大小均为 12852 字节，SHA256 均为：

```text
05d4a1f5d57839a5aeedc1457a61759cb8e0e915e2f3d50d9c5c1a3fd9767e87
```

重复下载得到的另一个监控程序源码包与 `supervisor_mips.zip` 内容完全一致，大小均为 131655 字节，SHA256 均为：

```text
9a35afaf1ae910fe25c41c2fc5a80e74c81dc41f27589a8efda91c44828272e4
```

## Kernel 内置高负载程序

`supervisor_mips.zip` 中的 `kernel/kern/test.S` 包含以下内置测试入口：

| 符号 | 地址 | 说明 |
| --- | --- | --- |
| `UTEST_SIMPLE` | `0x80003000` | 简单寄存器返回测试 |
| `UTEST_STREAM` | `0x8000300C` | 连续内存读写 |
| `UTEST_MATRIX` | `0x8000303C` | 矩阵乘法，包含 `mul` |
| `UTEST_CRYPTONIGHT` | `0x800030C4` | 内存高负载循环，包含 `mul` |
| `UTEST_1PTB` | `0x8000315C` | 性能标定程序 |
| `UTEST_2DCT` | `0x80003190` | 运算数据冲突效率测试 |
| `UTEST_3CCT` | `0x800031D8` | 控制冲突测试 |
| `UTEST_4MDCT` | `0x80003204` | 访存相关数据冲突测试 |

这些地址来自发布包内的 `kernel.elf` 符号表。

## 本地测试

核心指令回归：

```sh
make -C sim all
```

其中 `isa-directed` 用例已经覆盖 `mul`：

```asm
addiu $t5, $zero, -3
ori   $t6, $zero, 7
mul   $t7, $t5, $t6
addiu $t8, $zero, -21
beq   $t7, $t8, mul_ok
```

MATRIX 高负载数据回归：

```sh
make -C sim perf-matrix
```

该目标会从 `supervisor_mips.zip` 中提取 `matrix.in` 和 `matrix.out`，将输入矩阵加载到 `0x80400000`，执行与远程日志相同的 MATRIX 程序，并比较 `0x80420000` 开始的 C 矩阵输出。

使用性能测试包的 Kernel 跑监控程序交互回归：

```sh
make -C sim kernel-perf
make -C sim soc-system-perf
```

如果需要覆盖真实 9600 串口路径，运行：

```sh
make -C sim soc-system-real-uart
```

## 远程平台操作要点

- bitstream 使用最新生成的 `run_vivado/project/thinpad_top.runs/impl_1/thinpad_top.bit`。
- Flash/RAM 写入时选择 BaseRAM，起始地址填 `00000000`，文件选择 `/home/luoshuang/下载/kernel.bin`。
- 拨码开关全部拨到 0。
- 串口终端必须在复位前打开，波特率选择 9600。
- 复位后应看到 `MONITOR for MIPS32 - initialized.`。
- 若复位后无串口输出，先读 ExtRAM `003e0000` 长度 `0100`，检查 UART 诊断 marker 是否出现。
