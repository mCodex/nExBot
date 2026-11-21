#Requires -Version 5.1
#Requires -Modules ScheduledTasks
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [string] $Engine,
    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [string] $ProfileDir,
    [Parameter(Mandatory, ParameterSetName = 'Remove')]
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$taskName = "nExBot Engine - $($identity.User.Value)"
$prior = Get-ScheduledTask -TaskPath '\' | Where-Object TaskName -eq $taskName

if ($Uninstall) {
    if ($prior) {
        if ($prior.State -eq 'Running') { Stop-ScheduledTask -InputObject $prior }
        Unregister-ScheduledTask -InputObject $prior -Confirm:$false
    }
    return
}

$binary = Get-Item -LiteralPath $Engine
$profile = Get-Item -LiteralPath $ProfileDir
if ($binary -isnot [IO.FileInfo] -or $binary.Extension -ne '.exe' -or $profile -isnot [IO.DirectoryInfo]) {
    throw 'Supply an installed engine executable and a bot profile directory.'
}
# Task Scheduler expands percent-delimited environment variables in executable paths and arguments.
if ($binary.FullName.Contains('%') -or $profile.FullName.Contains('%')) {
    throw 'Task Scheduler paths must be free of percent signs.'
}
$profilePath = $profile.FullName
if ($profilePath.EndsWith('\')) { $profilePath += '.' }
$action = New-ScheduledTaskAction -Execute $binary.FullName -Argument ('serve "{0}"' -f $profilePath)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
if ($prior -and $prior.State -eq 'Running' -and
    ($prior.Actions.Execute -ne $action.Execute -or $prior.Actions.Arguments -ne $action.Arguments)) {
    Stop-ScheduledTask -TaskPath '\' -TaskName $taskName
}
Start-ScheduledTask -TaskPath '\' -TaskName $taskName

$deadline = (Get-Date).AddSeconds(15)
do {
    Start-Sleep -Milliseconds 500
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    if ($task.State -eq 'Running') {
        Write-Output "Running: $taskName"
        return
    }
} while ((Get-Date) -lt $deadline)
$result = (Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\').LastTaskResult
throw "Engine task did not stay running (Task Scheduler result $result)."
