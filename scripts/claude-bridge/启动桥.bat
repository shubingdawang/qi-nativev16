@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Claude Code 桥（关掉这个窗口桥就断了）

rem ⚠️⚠️ 这个文件里，**代码部分一律用英文**：
rem 标签名（:ask）、文件名（bridge-token.txt）、变量名都不许出现中文。
rem
rem 上一版我把标签写成 `:问一次`、密钥文件写成 `密钥.txt`，
rem 结果她双击之后**窗口一闪就没了**。原因是 cmd.exe 解析标签和路径
rem 不走 `chcp 65001`，中文按 GBK 读、按 UTF-8 存，两头对不上就找不到标签。
rem
rem 中文只能待在 `echo` 后面的那句话里——那部分是 chcp 之后才输出的，没事。

rem 顺手把老版本留下的中文名密钥文件搬过来，免得她要重填一次
if exist "密钥.txt" if not exist "bridge-token.txt" ren "密钥.txt" "bridge-token.txt"

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
echo 密钥已读到。手机那边「设置 - 供应商 - 密钥」要填一模一样的。
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
echo  这一串是用来拦住别人的：手机能通过桥在这台
echo  电脑上跑命令，所以没有密钥就不开那个口子。
echo.
echo  自己编一串，字母数字都行，别用空格和中文。
echo  例：qi7788abc
echo ========================================
echo.
set /p KEY="密钥："
>"bridge-token.txt" echo %KEY%
echo.
echo 记下来了，存在这个文件夹的 bridge-token.txt 里。
echo 以后再启动就不问了；忘了的话打开那个文件就能看。
exit /b
