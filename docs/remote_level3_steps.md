# 三级评测远程平台操作步骤

本文档记录在线实验平台上复现三级评测需要执行的操作。当前设计对应的 bitstream 为：

```text
/home/luoshuang/mips/run_vivado/project/thinpad_top.runs/impl_1/thinpad_top.bit
```

该文件最后生成时间应为 `2026-07-08 22:45:29 +0800` 或更新。

## 1. 上传 bitstream

1. 进入在线实验平台的 FPGA/ThinPad 实验页面。
2. 上传本项目生成的 `thinpad_top.bit`。
3. 等待平台提示 bitstream 上传或配置完成。

注意不要上传 Vivado 工程里的其他文件，也不要上传旧的 `.bit` 文件。

## 2. 设置拨码开关

1. 将拨码开关全部设置为 `0`。
2. 三级评测说明要求拨码开关为 0；当前 CPU 设计不依赖拨码开关，但远程平台流程仍按要求设置。

## 3. 下载 Kernel 到 BaseRAM

1. 在平台的内存/程序加载区域选择 BaseRAM。
2. 将官方 `kernel.bin` 下载到 BaseRAM 起始位置。
3. 起始地址对应 CPU 虚拟地址 `0x80000000`，也就是 BaseRAM 偏移 `0x00000000`。

本地官方 Kernel 文件路径：

```text
/home/luoshuang/下载/kernel.bin
```

## 4. 连接串口

1. 串口接口选择 `txd/rxd`。
2. 参数设置为：
   - 波特率：`9600`
   - 数据位：`8`
   - 停止位：`1`
   - 校验：无
3. 打开 Term 或平台提供的模拟终端。

## 5. 复位启动 CPU

1. 单击复位按钮，使 `reset_btn` 拉高。
2. 松开复位按钮，CPU 开始从 `0x80000000` 取指。
3. 正常情况下，串口终端应输出：

```text
MONITOR for MIPS32 - initialized.
```

看到这行欢迎信息后，说明 bitstream、Kernel 加载、复位、BaseRAM 取指和串口发送路径基本正常。

## 6. 执行三级测试流程

远程测试器会自动执行以下流程；手动复现时按同样顺序操作：

1. 使用 `A` 命令将用户程序加载到 `0x80100000`。
2. 使用 `D` 命令读出 `0x80100000` 处的用户程序，确认加载内容正确。
3. 使用 `G` 命令跳转执行 `0x80100000` 处的用户程序。
4. 使用 `R` 命令读取寄存器，检查用户程序执行结果。
5. 使用 `D` 命令读取数据内存，检查 ExtRAM 中的结果。

本地自检使用的用户程序会把结果写到 `0x80400000`，失败计数为 `0` 表示通过。

## 7. 0 分时优先排查

如果远程平台仍然显示 0 分，按以下顺序确认：

1. 上传的是否是最新 bitstream：

```text
/home/luoshuang/mips/run_vivado/project/thinpad_top.runs/impl_1/thinpad_top.bit
```

2. `kernel.bin` 是否下载到了 BaseRAM 起始位置，而不是 ExtRAM 或其他偏移。
3. 拨码开关是否全部为 0。
4. 串口是否选择 `txd/rxd`，参数是否为 `9600 8N1`。
5. 复位释放后终端是否出现 `MONITOR for MIPS32 - initialized.`。
6. 如果没有欢迎信息，优先怀疑 bitstream 上传错误、Kernel 未加载到 BaseRAM 起始位置、复位流程错误或串口接口选择错误。
7. 如果有欢迎信息但仍 0 分，说明启动路径正常，应继续检查远程测试器发送 `A/D/G/R/D` 命令后的响应。

## 8. 本地对应验证

远程提交前，本地已经通过以下验证：

```sh
make -C sim all kernel-c3 soc-system soc-system-real-uart
python3 run_vivado/flow/check_timing.py run_vivado/project/thinpad_top.runs/impl_1/timing_summary.rpt
```

关键通过信息：

```text
kernel-c3 monitor check passed
soc-system real UART command check passed
WNS: 5.079 ns
```
