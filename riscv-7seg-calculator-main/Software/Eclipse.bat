@echo off


PATH E:\tool\xpack-windows-build-tools-4.2.1-2\bin

PATH E:\tool\xpack-riscv-none-elf-gcc-12.2.0-3\bin;%PATH%


set ECLIPSE_PATH=E:\tool\eclipse-cpp-2024-12-R-win32-x86_64\eclipse

set WORKSPACE=%CD%
%ECLIPSE_PATH%\eclipse.exe -data %WORKSPACE%
