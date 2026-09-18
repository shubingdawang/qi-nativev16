@echo off
cd /d "%~dp0"
title Claude Code 新桥（关掉这个窗口桥就断了）

rem NOTE: this file is saved as GBK (the default code page of Chinese Windows),
rem   NOT UTF-8, and it must keep CRLF line endings.
rem   UTF-8 + chcp 65001 makes cmd.exe cut multibyte lines apart
rem   ("... is not recognized as an internal or external command"),
rem   and LF-only line endings make "call :ask" fail, so the window flashes and closes.
rem   Keep labels, file names and variable names in plain English.

if not exist "bridge-token.txt" call :ask
set /p BRIDGE_TOKEN=<bridge-token.txt

if "%BRIDGE_TOKEN%"=="" (
  echo.
  echo 密钥是空的。删掉这个文件夹里的 bridge-token.txt 再跑一次就会重新问。
  echo.
  pause
  exit /b
)

echo.
echo 密钥已读到。手机上「Code - 接法 - 密钥」要填一模一样的。
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo 这台电脑上找不到 node。桥是 node 写的，得先装 Node.js。
  echo.
  pause
  exit /b
)

node bridge.js

echo.
echo 桥停了。按任意键关掉这个窗口。
pause >nul
exit /b

:ask
echo.
echo ========================================
echo  第一次跑，要先定一个密钥。
echo.
echo  这一串是用来拦住别人的：手机能通过这座桥在
echo  这台电脑上改文件、跑命令，所以没有密钥
echo  什么口子都不开。
echo.
echo  自己编一串，字母数字都行，别用空格和中文。
echo  例：qi7788abc
echo ========================================
echo.
set /p KEY="密钥："
>"bridge-token.txt" echo %KEY%
echo.
echo 记下来了，存在这个文件夹的 bridge-token.txt 里。
echo 这个文件不会进仓库（仓库是公开的）。
exit /b
