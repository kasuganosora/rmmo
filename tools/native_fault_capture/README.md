# Windows 原生异常取证（仅诊断）

普通游戏和编辑器不注册此扩展。仅在独立测试子进程中显式加载。正常运行
只安装 VEH、记录初始模块表；没有定时采样、线程挂起、调试器或优先级修改。
首个 access violation / illegal instruction 写入寄存器、原始栈与最多 64 个
展开地址，随后返回 `EXCEPTION_CONTINUE_SEARCH`，不吞掉异常。

这是 **first-chance** 证据，必须与同一 PID / 创建时间的退出结果一起判断。
若程序自己处理并恢复了首个异常，本工具不会记录后续异常。模块表只含扩展
加载时的模块，后载 DLL 可能无法定位；损坏的栈可能无法完全展开。它不等同
于 dump，也不证明捕获异常来自项目代码。输出原始地址，离线解析匹配符号。

Windows API 合同参见 [VEH](https://learn.microsoft.com/en-us/windows/win32/debug/vectored-exception-handling)、
[RtlLookupFunctionEntry](https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-rtllookupfunctionentry)、
[RtlVirtualUnwind](https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-rtlvirtualunwind)。

## 构建与真实地图

`build.py --compiler <g++.exe> --engine-source <当前带生成头的引擎源码> --output <全新外部目录>`

当前 ABI 针对 4.7 的 `GDExtensionClassCreationInfo6`。构建记录源、生成头、
DLL 的 SHA 与完整命令；不得把 DLL 或测试输出放进 Godot 项目自动扫描目录。

`tools/run_axel_texture_phase.py --engine <engine.exe> --output <新外部样本路径> --fault-capture-extension <capture.gdextension> [--traverse]`

该入口使用既有独立桌面，launch 清单记录实际参数及 DLL SHA，明确标记
diagnostic。加载前强制关闭故障注入，确认 `NativeFaultProbe` 不存在。只在
这一子进程设置环境变量。原始文件使用 CREATE_NEW，不覆盖既有证据。

`decode.py <sample.fault.raw> --addr2line <addr2line.exe> --output <新文件.json>`

也可用 `--gdb <gdb.exe>` 替代 `--addr2line`。GDB 在此只离线读取符号，
不会启动或附加目标；本机该 2.2GB 符号构建的 addr2line 曾超过 120s，
GDB 单次符号核对约 10.8s。解码必须放在性能测量之后，避免抢占内存和 IO。

离线 decoder 根据每次 ASLR 模块地址和 PE 首选地址换算，非首帧 return PC
减 1，优先使用同名 `.exe.debugsymbols`，保留无法解码的地址。符号与引擎
必须保持同一构建；Windows 系统 DLL 没有 MinGW 符号时出现 `??` 是正常限制。

## 受控复现

先验证采集器再抓真实问题。使用单独 headless Godot 子进程执行 `fixture.gd`，
在该进程环境设置：

- `RMMO_FAULT_EXTENSION`：外部扩展绝对路径。
- `RMMO_FAULT_CAPTURE_FILE`：全新外部 `.raw` 路径。
- `RMMO_FAULT_CAPTURE_TEST=1`：唯一开放故障方法的开关。
- `RMMO_FAULT_MODE=noop|main_read|worker_read|worker_execute`。
- `RMMO_FAULT_CAPTURE_DISABLED=0|1`：1 禁用 handler，保留模块表供对照。

noop 应 exit 0；后三者故意崩溃，应 exit `0xC0000005`，不能算游戏回归。
worker 使用真正的 Godot Thread。解码检查对应故障方法、worker 的
`Thread::callback` 和主线程/故障线程身份；execute 另检查 fault PC=0、
access=8。具体原始样本和证据边界见道路 paint 专项记录中的后续引用。
