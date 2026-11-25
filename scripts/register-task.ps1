# Registers the "Practice Drill Server" scheduled task on the mini PC: the drill server (server/index.mjs) at logon,
# hidden (conhost --headless, like the HQ Widget task), restarted on failure, logging to logs\service.log.
# Run once: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\register-task.ps1
# Then start it now with: Start-ScheduledTask -TaskName "Practice Drill Server"
$repo = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $repo 'logs') | Out-Null
$user = "$env:USERDOMAIN\$env:USERNAME"
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><URI>\Practice Drill Server</URI><Description>Practice drill server: the drill catalog and run results for the Practice iPhone app, tailnet and loopback only (port 4700, addresses in config.local.json). Repo: $repo</Description></RegistrationInfo>
  <Principals><Principal id="Author"><UserId>$user</UserId><LogonType>InteractiveToken</LogonType></Principal></Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure><Count>3</Count><Interval>PT1M</Interval></RestartOnFailure>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Triggers><LogonTrigger><UserId>$user</UserId><Delay>PT30S</Delay></LogonTrigger></Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\System32\conhost.exe</Command>
      <Arguments>--headless cmd.exe /c "C:\Program Files\nodejs\node.exe" server\index.mjs &gt;&gt; logs\service.log 2&gt;&amp;1</Arguments>
      <WorkingDirectory>$repo</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
Register-ScheduledTask -TaskName 'Practice Drill Server' -Xml $xml -Force | Out-Null
Write-Output "Registered the Practice Drill Server task for $user in $repo."
