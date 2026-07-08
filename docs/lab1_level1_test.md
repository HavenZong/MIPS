# 一级评测测试说明

本测试用于验证 32 位 MIPS CPU 对 MIPS-C1 指令集最小子集的支持情况。

## 指令要求

一级评测要求支持以下 6 条指令：

- `ori`
- `lui`
- `addu`
- `bne`
- `lw`
- `sw`

## CPU 与内存要求

- 虚拟内存空间为 `0x80000000` 到 `0x807FFFFF`，共 8MB。
- 整个 8MB 空间均要求可读、可写、可执行。
- `0x80000000` 到 `0x803FFFFF` 映射到 BaseRAM。
- `0x80400000` 到 `0x807FFFFF` 映射到 ExtRAM。
- CPU 使用小端序。
- CPU 时钟使用外部时钟输入，本项目当前使用 `clk_50M`。
- `reset_btn` 高电平时 CPU 复位，松开后解除复位。
- CPU 复位后从 `0x80000000` 开始取指执行。

## 自动化测试流程

1. 清空 BaseRAM 和 ExtRAM。
2. 将测试程序汇编为机器码后写入 BaseRAM 起始地址。
3. 单击复位按钮。
4. CPU 从 `0x80000000` 开始执行测试程序。
5. 程序循环计算 64 次斐波那契数列，并写入 ExtRAM 的 `0x80400000` 到 `0x804000FC`。
6. 每次写入后立即用 `lw` 读回，并用 `bne` 校验写入值。
7. 等待约 1 秒。
8. 测试脚本读取 ExtRAM 偏移 `0x0` 到 `0x100` 范围内的数据并检查结果。

## 本地测试程序

本仓库中的一级评测汇编程序为：

```text
asm/lab1.s
```

默认构建会将 `.text` 链接到 `0x80000000`：

```sh
make -C asm
```

本地 Verilator 测试命令：

```sh
make -C sim lab1
```

完整本地回归命令：

```sh
make -C sim all
```

## 当前实现对应关系

- 顶层 CPU 复位入口：`src/soc/thinpad_top.v` 中 `RESET_PC = 32'h8000_0000`。
- CPU 默认复位入口：`src/soc/mips_core.v` 中 `RESET_PC = 32'h8000_0000`。
- 本地仿真加载入口：`sim/mips_core_sim.cpp` 中 `kResetPc = 0x80000000`。
- SRAM 地址映射：`src/soc/soc_bus.v` 使用 CPU 地址低 23 位访问 8MB 空间，其中 bit 22 选择 BaseRAM/ExtRAM。
