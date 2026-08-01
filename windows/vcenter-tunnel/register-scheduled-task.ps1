#Requires -RunAsAdministrator
# Register only the scheduled task (if scripts already installed)

$TaskName = "vCenter SSH Tunnel"
$Action = New-ScheduledTaskAction -Execute "C:\Tools\vcenter-tunnel\start-tunnel.bat"
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "SSH tunnel to vc01.vmalpha.com via ac01"
Write-Host "Scheduled task '$TaskName' registered."
