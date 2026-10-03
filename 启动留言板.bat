@echo off
chcp 65001 >nul
title Mira 留言板
"F:\vscode\minicode\python.exe" "%~dp0adapter\board_web.py"
if errorlevel 1 pause
