# neanderthal → Iluvatar CoreX (ivcore11) 迁移记录

## 来源
- 仓库：https://github.com/uncomplicate/neanderthal.git
- 分支/commit：master @ e5ba39ec8537dcd7ad777f97d853c5778585ffa6 (2026-07-27)
- 性质：基于原生 BLAS/LAPACK 的 Clojure 高性能矩阵/线性代数库。多模块：neanderthal-base / -mkl / -openblas / -accelerate / -opencl / **-cuda**(CUDA 后端) / -test。构建用 Leiningen。

## CUDA 使用性质
- neanderthal-cuda(0.64.0) 的 GPU 后端 **不是** 用 nvcc 编译 .cu 产出二进制，而是一个 JVM/Clojure 运行时栈：
  - `uncomplicate/clojurecuda 0.31.0` 封装 CUDA driver API + NVRTC；
  - 通过 `org.bytedeco:cuda-platform:13.1-9.19-1.5.13`(JavaCPP **CUDA 13.1** 预设) 调 cuBLAS(`org.bytedeco.cuda.global.cublas`)；
  - `src/device/.../*.cu` 里的 kernel(vector/ge/uplo 运算、vect-math、random123)在运行时由 **NVRTC JIT** 编译(见 factory.clj 的 `compile!`/`program`/`module`)。
- 因此“让 CUDA 跑在 ivcore11 上”= 让 JavaCPP 的 CUDA JNI + NVRTC 绑定到 CoreX 的 cuBLAS/cudart/nvrtc(/usr/local/corex, CUDA 10.2)。

## 环境
- CoreX SDK：/usr/local/corex(SDK 4.5.0, IX-ML 4.4.0, **CUDA 10.2**, driver 4.5.0)；clang/clang++ 22.1.0；监控用 ixsmi。
- 硬件：2×Iluvatar BI-V150；本任务仅用 **GPU1**(`export CUDA_VISIBLE_DEVICES=1`)，未触碰 GPU0。
- 工具链：系统自带 JDK 21；无 lein/clojure，**用户态安装 Leiningen 2.12.0**(/usr/local/bin/lein)完成依赖解析与测试。
- 注：GPU 设备访问在沙箱内不可见(ixsmi 报 No supported GPUs)，需在非沙箱下运行——已按此执行。

## 适配内容
1. **依赖链定位**：clojurecuda 0.31.0 → clojure-cpp 0.10.0(锁 `javacpp 1.5.13`) → `org.bytedeco:cuda-platform 13.1`(CUDA 13.1 JNI)。这是本仓库能否在 CoreX 跑通的关键。
2. **neanderthal-cuda/project.clj**(改动见 corex_port/changes/project.clj.orig 对照)：
   - 移除 `:linux` 里的 `org.bytedeco/cuda-redist`、`org.bytedeco/cuda-redist-cublas`(NVIDIA CUDA 13.1 用户态 redist，多 GB，在 CoreX 上无用)，令 JavaCPP 回退到系统 CoreX 库；
   - `:dev` jvm-opts 追加 `-Dorg.bytedeco.javacpp.pathsFirst=true` 与 `-Djava.library.path=<corex-libs 垫片>:/usr/local/corex/lib64`，让 JavaCPP 优先加载 CoreX 库。
3. **SONAME 垫片**(corex_port/corex-libs/make_shims.sh)：把 CoreX 的 `libcudart.so.10.2.89`/`libcublas.so.10.2.3.254`/`libcublasLt`/`libnvrtc.so.10.2.89`/`libcusolver` 软链为 JNI 期望的 `.so.13`/`.so.12` 名，尝试满足动态连接。

## 结果
- **overall_status = blocked**；compile_status = not_applicable(无 host 侧 CUDA 编译步骤，kernel 为运行时 NVRTC JIT，未到达)；test_status = not_attempted；运行时用例 **0/0**。
- 端到端 `lein midje` 在加载 `uncomplicate.clojurecuda.core` / `...cuda.constants` 时即失败：
  - `UnsatisfiedLinkError: libjnicudart.so: /usr/local/corex-4.5.0/lib64/libcudart.so.10.2.89: version 'libcudart.so.13' not found`
  - → `NoClassDefFoundError: Could not initialize class org.bytedeco.cuda.global.cudart`
  - → 测试命名空间 `LOAD FAILURE`，无任何 midje fact 执行。
- 逐条日志：corex_port/test/test.log；ABI 探针：corex_port/build/abi_probe.log；依赖树：corex_port/build/deps_tree.log。

## Failure Gate（真实复现 + 分类 + 尝试）
- **Blocker 1(terminal)：JavaCPP CUDA 13.1 JNI vs CoreX CUDA 10.2 ABI 断层。**
  - 真实复现：
    1. `readelf -d` 证实 JNI 桩 NEEDED `libcudart.so.13/libcublas.so.13/libcublasLt.so.13/libnvrtc.so.13/libcusolver.so.12`。
    2. 符号级：JNI 引用的 798 个 cublas 符号全部带版本 `@libcublas.so.13`；CoreX 10.2 虽定义同名函数(995 个)但**无版本节点**，798 个全部不可解析。
    3. `dlopen` 探针(垫片就位)：`version 'libcudart.so.13' not found`、`undefined symbol: cublasZsyrk_v2_64, version libcublas.so.13`、`undefined symbol: nvrtcGetLTOIRSize, version libnvrtc.so.13`。
    4. 端到端 `lein midje`(pathsFirst 已优先 CoreX 库)复现同一 UnsatisfiedLinkError，0 用例运行。
  - 已尝试的 workaround：
    - (a) SONAME 垫片 + pathsFirst + java.library.path 指向 CoreX 库 → **失败**(版本节点缺失，不可解)。
    - (b) 把 bytedeco cuda 预设降到 CUDA 10.2 以匹配 CoreX → **结构性不可行**：clojure-cpp 0.10.0 锁 javacpp 1.5.13，而 javacpp 1.5.13 只发布 CUDA 13.1 预设；不存在兼容的 CUDA 10.2 预设，且 clojurecuda/neanderthal 字节码已按 13.1 API 编译，降版本等同 fork 整条 javacpp/clojurecuda 预设链(非对单仓库的可分离适配，红线1 禁改 SDK)。
  - 判定 **terminal**：不改 /usr/local/corex 且不 fork 整条预设链，CUDA 13.1 JNI 与 CoreX 10.2 无法调和。
- **Blocker 2(terminal，预判性登记)：ivcore11 无真 FP64。** neanderthal 默认大量用 double(cuda-double factory 跑整轮 BLAS/LAPACK/math)；ivcore11 double 静默退化 fp32、`<cmath>` double builtin 失效、cublas double 例程受限。按红线3/5 本应对 GPU 端 double 路径做平台守卫式降级(float)或如实记录为受限，但因 Blocker 1 使代码根本无法加载运行，**未实测到该层**，故不计入运行时失败计数，仅如实登记为已知平台限制。

## 结论
HEAD 版 neanderthal 的 CUDA 后端与 CoreX(ivcore11, CUDA 10.2) 存在根本性的 JavaCPP CUDA-13.1-vs-10.2 ABI 断层，属 terminal blocker，GPU 矩阵测试无法在本环境运行。已按契约完成真实复现、分类、workaround 尝试与证据落盘，并将 corex-port 分支推送到 fork。
