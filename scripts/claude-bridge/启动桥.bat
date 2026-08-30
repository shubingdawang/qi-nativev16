@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Claude Code 桥（关掉这个窗口桥就断了）

rem 密钥存在旁边的「密钥.txt」里，没有就问一次。
rem
rem ⚠️ 不写进这个 .bat 本身：这个文件是跟着代码进 git 的，
rem 密钥进了 git 就等于贴在公开的地方了。密钥.txt 已经加进 .gitignore。
if not exist "密钥.txt" call :问一次
set /p BRIDGE_TOKEN=<密钥.txt

echo.
echo 密钥已读到。手机那边「设置 → 供应商 → 密钥」要填一模一样的。
echo.
node bridge.js

echo.
echo 桥停了。按任意键关掉这个窗口。
pause >nul
exit /b

:问一次
echo.
echo ════════════════════════════════════════
echo  第一次跑，要先定一个密钥。
echo.
echo  这一串是用来拦住别人的：手机能通过桥在这台
echo  电脑上跑命令，所以没有密钥就不开那个口子。
echo.
echo  自己编一串，字母数字都行，别用空格和中文。
echo  例：qi7788abc
echo ════════════════════════════════════════
echo.
set /p KEY="密钥："
>"密钥.txt" echo %KEY%
echo.
echo 记下来了，存在这个文件夹的「密钥.txt」里。
echo 以后再启动就不问了；忘了的话打开那个文件就能看。
exit /b
