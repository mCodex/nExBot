#Requires -Version 5.1
#Requires -Modules ScheduledTasks
# Exercise the native ScheduledTasks definitions without registering a login job on the CI host.
param([Parameter(Mandatory)][string] $Engine)
$ErrorActionPreference = 'Stop'
$fixture = @{ Task = $null; Starts = 0; Stops = 0 }
function Get-ScheduledTask {
    param($TaskName, $TaskPath)
    $fixture.Task
}
function Register-ScheduledTask {
    param($TaskName, $TaskPath, $Action, $Trigger, $Principal, $Settings, [switch]$Force)
    $fixture.Task = [pscustomobject]@{
        TaskName = $TaskName; Actions = $Action; Triggers = $Trigger
        Principal = $Principal; Settings = $Settings; State = 'Ready'
    }
}
function Start-ScheduledTask {
    param($TaskName, $TaskPath)
    $fixture.Starts++
    $fixture.Task.State = 'Running'
}
function Stop-ScheduledTask {
    param($TaskName, $TaskPath, $InputObject)
    $fixture.Stops++
    $fixture.Task.State = 'Ready'
}
function Unregister-ScheduledTask {
    param($InputObject, [switch]$Confirm)
    $fixture.Task = $null
}

$profileDir = Join-Path ([IO.Path]::GetTempPath()) ("nExBot profile " + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $profileDir
try {
    $install = Join-Path $PSScriptRoot 'autostart.ps1'
    & $install -Engine $Engine -ProfileDir $profileDir
    $task = $fixture.Task
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $expectedPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    if ($task.Actions.Execute -ne (Get-Item -LiteralPath $Engine).FullName -or
        $task.Actions.Arguments -ne ('serve "{0}"' -f $profileDir) -or
        $task.Triggers.UserId -ne $identity.Name -or
        $task.Principal.UserId -ne $identity.Name -or
        $task.Principal.LogonType -ne $expectedPrincipal.LogonType -or
        $task.Principal.RunLevel -ne $expectedPrincipal.RunLevel) { throw 'Unexpected task definition' }
    & $install -Engine $Engine -ProfileDir $profileDir
    if ($fixture.Starts -ne 2 -or $fixture.Stops -ne 0) { throw 'Reinstall interrupted the active engine' }
    & $install -Uninstall
    & $install -Uninstall
    if ($fixture.Task -or $fixture.Stops -ne 1) { throw 'Uninstall failed' }
} finally {
    [IO.Directory]::Delete($profileDir)
}
