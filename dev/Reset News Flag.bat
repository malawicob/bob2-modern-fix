@echo off
rem Makes the morning bulletin unread again so the dispersal news strip
rem can be tested more than once. Touches one field and backs up first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reset_news_flag.ps1"
