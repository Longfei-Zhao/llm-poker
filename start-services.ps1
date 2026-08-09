# 大模型德州扑克服务启动脚本
# 启动 AI 服务 (:8000) 与后端 (:3000)；前端需另开终端运行: cd frontend; flutter run -d chrome

Write-Host "正在启动德州扑克游戏服务..." -ForegroundColor Green

# 只清理占用本项目端口的进程，不影响其他 Node 应用
Write-Host "检查端口占用..." -ForegroundColor Yellow
foreach ($port in 3000, 8000) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $conns) {
        try {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction Stop
            Write-Host "  已停止占用端口 $port 的进程 (PID: $($conn.OwningProcess))" -ForegroundColor Yellow
        } catch {
            Write-Host "  无法停止占用端口 $port 的进程: $_" -ForegroundColor Red
        }
    }
}

# 检查 AI 服务虚拟环境
$venvPython = Join-Path $PWD "ai_service\venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "未找到 ai_service\venv，请先创建虚拟环境:" -ForegroundColor Red
    Write-Host "  cd ai_service; python -m venv venv; venv\Scripts\pip install -r requirements.txt" -ForegroundColor Red
    exit 1
}

# 启动AI服务
Write-Host "`n启动AI服务..." -ForegroundColor Cyan
$aiServiceJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD\ai_service
    & $using:venvPython -m uvicorn src.main:app --host 0.0.0.0 --port 8000
}
Write-Host "  AI服务启动中 (Job ID: $($aiServiceJob.Id))" -ForegroundColor Cyan
Start-Sleep -Seconds 5

# 启动后端服务
Write-Host "`n启动后端服务..." -ForegroundColor Cyan
$backendJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD\backend
    node src/index.js
}
Write-Host "  后端服务启动中 (Job ID: $($backendJob.Id))" -ForegroundColor Cyan
Start-Sleep -Seconds 3

# 检查服务是否正常运行
Write-Host "`n检查服务状态..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "http://localhost:3000/api/health" -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  后端服务状态: 正常运行" -ForegroundColor Green
} catch {
    Write-Host "  后端服务状态: 无法连接 ($_)" -ForegroundColor Red
}
try {
    Invoke-RestMethod -Uri "http://localhost:8000/api/health" -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  AI服务状态: 正常运行" -ForegroundColor Green
} catch {
    Write-Host "  AI服务状态: 无法连接 ($_)" -ForegroundColor Red
}

Write-Host "`n后端与AI服务已启动。前端请另开终端运行:" -ForegroundColor Green
Write-Host "  cd frontend; flutter run -d chrome" -ForegroundColor Green
Write-Host "按Ctrl+C停止所有服务`n" -ForegroundColor Red

# 显示服务日志
try {
    while ($true) {
        $aiServiceOutput = Receive-Job -Job $aiServiceJob
        if ($aiServiceOutput) {
            Write-Host "AI服务: $aiServiceOutput" -ForegroundColor Magenta
        }
        $backendOutput = Receive-Job -Job $backendJob
        if ($backendOutput) {
            Write-Host "后端服务: $backendOutput" -ForegroundColor Cyan
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    Stop-Job -Job $aiServiceJob, $backendJob -ErrorAction SilentlyContinue
    Remove-Job -Job $aiServiceJob, $backendJob -Force
    Write-Host "`n服务已停止" -ForegroundColor Red
}
