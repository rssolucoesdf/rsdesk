@echo off
rem Abre o instalar-rsdesk.ps1 como administrador.
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0instalar-rsdesk.ps1\"'"
