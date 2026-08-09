# 大模型德州扑克服务启动脚本

Write-Host "正在启动德州扑克游戏服务..." -ForegroundColor Green

# 停止可能已运行的Node进程
Write-Host "检查并清理现有进程..." -ForegroundColor Yellow
$nodeProcesses = Get-Process | Where-Object { $_.ProcessName -eq "node" }
if ($nodeProcesses) {
    Write-Host "  发现运行中的Node进程，尝试停止..." -ForegroundColor Yellow
    $nodeProcesses | ForEach-Object { 
        try {
            $_.Kill()
            Write-Host "  已停止进程: $($_.Id)" -ForegroundColor Yellow
        } catch {
            Write-Host "  无法停止进程 $($_.Id): $_" -ForegroundColor Red
        }
    }
}

# 启动AI服务
Write-Host "`n启动AI服务..." -ForegroundColor Cyan
$aiServiceJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD\ai_service
    & "$using:PWD\ai_service\venv\Scripts\python.exe" -m uvicorn src.main:app --host 0.0.0.0 --port 8000
}
Write-Host "  AI服务启动中 (Job ID: $($aiServiceJob.Id))" -ForegroundColor Cyan
Write-Host "  等待AI服务启动..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

# 启动后端服务
Write-Host "`n启动后端服务..." -ForegroundColor Cyan
$backendJob = Start-Job -ScriptBlock {
    Set-Location $using:PWD\backend
    node src/index.js
}
Write-Host "  后端服务启动中 (Job ID: $($backendJob.Id))" -ForegroundColor Cyan
Write-Host "  等待后端服务启动..." -ForegroundColor Cyan
Start-Sleep -Seconds 3

# 检查服务是否正常运行
Write-Host "`n检查服务状态..." -ForegroundColor Yellow
try {
    $backendHealth = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -Method Get -ErrorAction Stop
    Write-Host "  后端服务状态: " -NoNewline -ForegroundColor Yellow
    Write-Host "正常运行" -ForegroundColor Green
} catch {
    Write-Host "  后端服务状态: " -NoNewline -ForegroundColor Yellow
    Write-Host "无法连接" -ForegroundColor Red
    Write-Host "  错误: $_" -ForegroundColor Red
}

try {
    $aiHealth = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -Method Get -ErrorAction Stop
    Write-Host "  AI服务状态: " -NoNewline -ForegroundColor Yellow
    Write-Host "正常运行" -ForegroundColor Green
} catch {
    Write-Host "  AI服务状态: " -NoNewline -ForegroundColor Yellow
    Write-Host "无法连接" -ForegroundColor Red
    Write-Host "  错误: $_" -ForegroundColor Red
}

Write-Host "`n所有服务已启动，正在显示日志输出..." -ForegroundColor Green
Write-Host "按Ctrl+C停止所有服务`n" -ForegroundColor Red

# 显示服务日志
try {
    # 循环显示服务日志，直到用户按Ctrl+C
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
    # 清理作业
    Remove-Job -Job $aiServiceJob -Force
    Remove-Job -Job $backendJob -Force
    
    Write-Host "`n服务已停止" -ForegroundColor Red
} 