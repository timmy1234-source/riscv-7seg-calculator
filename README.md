# riscv-7seg-calculator
本專題以 FGMT_RiscV 作為系統基礎，簡單設計一個C語言程式，實現計算機與七段顯示器介面。
基本上是以 FGMT_RiscV 為基礎開發，搭配他的系統能夠一鍵編譯更改後的main.c非常方便。我們僅需專注於設計C語言程式，就能他配他的GPIO成功實現簡單的計算機系統。

本專題實作了一套基於 **軟硬體協同設計 (Hardware/Software Co-design)** 的輕量級計算機系統。以開源核心 `FGMT_RiscV` (RV32I) 為運算核心，全面透過 C 語言韌體進行動態 I/O 輪詢、去彈跳防呆與算術邏輯運算，並透過硬體到位址解碼優化，完美整合於 FPGA 開發板上。

---

## 1. 使用開發板

* **核心平台**：Digilent Basys 3 FPGA 開發板
* **核心晶片**：Xilinx Artix-7 FPGA (型號：`XC7A35T-1CPG236C`)
* **硬體周邊應用**：
  * 板載 4 位數共陰極七段顯示器（用於顯示運算結果與狀態碼）
  * 滑動開關 (Switches) 與實體按鍵 (Push Buttons)（用於資料輸入與功能控制）

---

## 2. 使用工具版本 

本專案之軟硬體整合開發環境完全採用高獨立性、免安裝的可攜式（Portable）架構建置，各工具精確版本如下：
* **注意這些工具都必須安裝，建議打包成一個tool資料夾，後續需要設定路徑對應**

* **硬體開發與邏輯合成工具**：
  * **Xilinx Vivado Design Suite v2020.2**：負責系統電路合成（Synthesis）、佈局繞線（Implementation）與生成硬體位元流（Bitstream）。
* **韌體整合開發環境 (IDE)**：
  * **Eclipse IDE for C/C++ Developers (Version 2024-12-R)**：負責 C 語言專案架構管理、程式碼高亮編輯與 Makefile 編譯腳本調用。
* **RISC-V 跨平台編譯器 (Cross-Compiler Toolchain)**：
  * **xPack RISC-V None ELF GCC (Version 12.2.0-3)**：依據 `-march=rv32i` 與 `-mabi=ilp32` 參數，將 C 原始碼編譯為純淨的裸機（Bare-Metal）RV32I 機器碼。
* **Windows 原生構建工具 (Build Tools)**：
  * **xPack Windows Build Tools (Version 4.2.1-2)**：於 Windows 環境下提供 GNU `make` 輔助指令，供 Eclipse 執行自動化專案構建。

---
## 3. 工作區環境建置
* **我們透過建立這個工作區，將工具整合，便能使用 Eclipse IDE 快速且方便的編譯`main.c`**

* **前面工具安裝完後，會有tool資料夾將工具都放裡面**
  <img width="650" height="117" alt="image" src="https://github.com/user-attachments/assets/ef124024-b61e-48a1-9485-1a799ad7cfec" />

* **接著在路徑"FGMT_RiscV-main\Software\Eclipse.bat"中我們必須修改這個檔案讓他對應到我們剛剛tool資料夾的位置**
**如下圖 將內容修改為電腦中tool資料夾各個內容的相對位置**
  <img width="777" height="260" alt="image" src="https://github.com/user-attachments/assets/80b33dd5-6c67-4b78-91ba-5fbce79b97d5" />

* **接著點擊"Eclipse.bat"他就會自動開啟**
* **這時要注意Eclipse的設定是否正確如PDF**
  [Setup_Debug_Configuration.pdf](https://github.com/user-attachments/files/29289072/Setup_Debug_Configuration.pdf)


---
## 4. VIVADO 燒入步驟
* **開啟Hardware Manager 點選Auto Connect**
  
  <img width="507" height="309" alt="image" src="https://github.com/user-attachments/assets/e6f30003-12ec-4b66-b6ed-4699a4d2c693" />

* **點選program device 燒入 bit**
  
  <img width="507" height="307" alt="image" src="https://github.com/user-attachments/assets/874c2772-a17a-4a7b-9c0a-4e35b4e4333f" />


---
## 5. Eclipse IDE使用。	
* **搭配前面的工作環境，他其實可以做到只要修改main.c他都能幫你一鍵編譯成RISC-V需要的檔案**
* **點選左上槌子圖示就會自動編譯**
* **Console 會顯示是否有error。以及是否編譯成功。**
  
  <img width="507" height="360" alt="image" src="https://github.com/user-attachments/assets/634a34eb-10c7-41a6-bbea-12c697d32013" />

* **點選debug圖式。將編好的檔案編進板子裡跑。**
* **開始為暫停狀態，點擊resume讓他繼續跑就好。**
* **這時檔案就已經完整編寫進basys3裡面了。**
  
  <img width="450" height="209" alt="image" src="https://github.com/user-attachments/assets/510d4897-abda-49a5-929c-5eb7ccc0f9b9" />

---
## 6. Basys3操作

<img width="677" height="427" alt="image" src="https://github.com/user-attachments/assets/5ba050d9-77d0-442d-88d1-2d3a70ba39f7" />
**1)	7段顯示器(紅色框):用來顯示A、B、A+B、A-B的數值。**
**2)	按鈕(黃色框):總共5顆，只有上、中、左、右有功能。**
**功能如下:**
* 上:控制A的數值，按一次數值加1。當按按鈕   時7段顯示器自動切換至A數值。
* 中: 控制B的數值，按一次數值加1。當按按鈕時7段顯示器自動切換至B數值。
* 左:用於切換加法、減法模式。按下會同步切換即顯示計算結果。
* 右:把A、B的值歸零。

  
















