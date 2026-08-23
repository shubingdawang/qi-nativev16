@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Claude Code 桥（关掉这个窗口桥就断了）
node bridge.js
echo.
echo 桥停了。按任意键关掉这个窗口。
pause >nul
