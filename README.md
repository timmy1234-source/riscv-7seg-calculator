# -RISC-V-FPGA-
本專題以 FGMT_RiscV 作為系統基礎，簡單設計一個C語言程式，實現計算機與七段顯示器介面。

本專題實作了一套基於 **軟硬體協同設計 (Hardware/Software Co-design)** 的輕量級計算機系統。以開源核心 `FGMT_RiscV` (RV32I) 為運算核心，全面透過 C 語言韌體進行動態 I/O 輪詢、去彈跳防呆與算術邏輯運算，並透過硬體到位址解碼優化，完美整合於 FPGA 開發板上。

---

## 1. 使用開發板 (Development Board)

* **核心平台**：Digilent Basys 3 FPGA 開發板
* **核心晶片**：Xilinx Artix-7 FPGA (型號：`XC7A35T-1CPG236C`)
* **硬體周邊應用**：
  * 板載 4 位數共陰極七段顯示器（用於顯示運算結果與狀態碼）
  * 滑動開關 (Switches) 與實體按鍵 (Push Buttons)（用於資料輸入與功能控制）

---

## 2. 使用工具版本 (Toolchains & Software Versions)

本專案之軟硬體整合開發環境完全採用高獨立性、免安裝的可攜式（Portable）架構建置，各工具精確版本如下：
**注意這些工具都必須安裝，建議打包成一個tool資料夾，後續需要設定路徑對應**

* **硬體開發與邏輯合成工具**：
  * **Xilinx Vivado Design Suite v2020.2**：負責系統電路合成（Synthesis）、佈局繞線（Implementation）與生成硬體位元流（Bitstream）。
* **韌體整合開發環境 (IDE)**：
  * **Eclipse IDE for C/C++ Developers (Version 2024-12-R)**：負責 C 語言專案架構管理、程式碼高亮編輯與 Makefile 編譯腳本調用。
* **RISC-V 跨平台編譯器 (Cross-Compiler Toolchain)**：
  * **xPack RISC-V None ELF GCC (Version 12.2.0-3)**：依據 `-march=rv32i` 與 `-mabi=ilp32` 參數，將 C 原始碼編譯為純淨的裸機（Bare-Metal）RV32I 機器碼。
* **Windows 原生構建工具 (Build Tools)**：
  * **xPack Windows Build Tools (Version 4.2.1-2)**：於 Windows 環境下提供 GNU `make` 輔助指令，供 Eclipse 執行自動化專案構建。

---
