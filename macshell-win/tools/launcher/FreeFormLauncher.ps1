# FreeForm launcher window: what the Desktop / Start Menu shortcut opens.
#   Launch FreeForm      starts the shell (FreeForm.ps1) and closes this window
#   Configure settings   start at sign-in, taskbar / desktop icons, skip this window, automatic updates, uninstall
# Settings: %APPDATA%\FreeForm\launcher.json (FreeForm.ps1 reads hideTaskbar / hideIcons from it).
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$cfgDir = Join-Path $env:APPDATA 'FreeForm'
$cfgPath = Join-Path $cfgDir 'launcher.json'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$cfg = [ordered]@{ hideTaskbar = $true; hideIcons = $true; skipLauncher = $false; autoUpdate = $true }
if (Test-Path $cfgPath) {
    try { (Get-Content $cfgPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value } } catch {}
}
function Save-Config { New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null; $cfg | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8 }
function Start-FreeForm([switch]$Force) {
    $a = @{ FilePath = (Join-Path $root 'FreeForm.cmd'); WindowStyle = 'Hidden' }
    if ($Force) { $a.ArgumentList = '-Force' }
    Start-Process @a
}

# "Skip this window" (or -Launch): go straight to FreeForm. Hold Shift while opening to get the window anyway.
$shift = [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or
         [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift)
if (-not $env:FREEFORM_LAUNCHER_TEST -and (($cfg.skipLauncher -and -not $shift) -or $args -contains '-Launch')) { Start-FreeForm; exit 0 }
# FreeForm is still loaded in the background ("Switch to Windows"): bring it straight back
if (-not $env:FREEFORM_LAUNCHER_TEST -and -not $shift -and (Get-Process -Name qs -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root*" })) { Start-FreeForm; exit 0 }

$version = 'dev'
$vf = Join-Path $root 'version.txt'
if (Test-Path $vf) { $version = (Get-Content $vf -Raw).Trim() }
$logo = (Join-Path $root 'shell\assets\freeform-logo.png') -replace '\\', '/'

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FreeForm" Width="600" Height="340" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <Style x:Key="Card" TargetType="Button">
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Height" Value="56"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#2B2B2B" CornerRadius="6" BorderBrush="#363636" BorderThickness="1" Padding="18,0">
              <Grid>
                <ContentPresenter VerticalAlignment="Center"/>
                <TextBlock Text="&#xE76C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"
                           HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="#C8C8C8"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#323232"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="#272727"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Link" TargetType="Button">
      <Setter Property="Foreground" Value="#E6E6E6"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent" CornerRadius="4" Padding="8,4"><ContentPresenter/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#2A2A2A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6E6E6"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
  </Window.Resources>
  <Border Background="#202020" CornerRadius="8" BorderBrush="#3A3A3A" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition/></Grid.RowDefinitions>
      <!-- title bar -->
      <Grid x:Name="TitleBar" Background="Transparent">
        <StackPanel Orientation="Horizontal" Margin="12,0" VerticalAlignment="Center">
          <Image Source="$logo" Width="16" Height="16"/>
          <TextBlock Text="FreeForm" Foreground="#E6E6E6" FontSize="12" Margin="8,0,0,0"/>
        </StackPanel>
        <Button x:Name="CloseBtn" HorizontalAlignment="Right" Width="46" Background="Transparent" BorderThickness="0" Cursor="Hand">
          <TextBlock Text="&#xE8BB;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="10" Foreground="#E6E6E6"/>
        </Button>
      </Grid>
      <Grid Grid.Row="1" Margin="24,8,24,24">
        <Grid.ColumnDefinitions><ColumnDefinition Width="240"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <!-- left: logo, name, version, links -->
        <StackPanel VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
            <Border CornerRadius="14" Width="72" Height="72" ClipToBounds="True">
              <Image Source="$logo" Width="72" Height="72"/>
            </Border>
            <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
              <TextBlock Text="FreeForm" Foreground="White" FontSize="26" FontWeight="SemiBold"/>
              <TextBlock Text="Version $version" Foreground="#A0A0A0" FontSize="13"/>
            </StackPanel>
          </StackPanel>
          <Button x:Name="AboutBtn" Style="{StaticResource Link}" HorizontalAlignment="Center" Margin="0,26,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE946;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock Text="About FreeForm"/>
            </StackPanel>
          </Button>
          <Button x:Name="RestoreBtn" Style="{StaticResource Link}" HorizontalAlignment="Center" Margin="0,6,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE777;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock Text="Back to Windows"/>
            </StackPanel>
          </Button>
          <Button x:Name="DiagBtn" Style="{StaticResource Link}" HorizontalAlignment="Center" Margin="0,6,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE9D9;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock Text="Save diagnostics"/>
            </StackPanel>
          </Button>
        </StackPanel>
        <!-- right: main buttons -->
        <StackPanel x:Name="MainPage" Grid.Column="1" VerticalAlignment="Center" Margin="20,0,0,0">
          <Button x:Name="UpdateBtn" Style="{StaticResource Card}" Margin="0,0,0,12" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE896;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center" Margin="0,0,16,0"/>
              <TextBlock x:Name="UpdateText" Text="Update available" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button x:Name="LaunchBtn" Style="{StaticResource Card}" Margin="0,0,0,12">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72A;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center" Margin="0,0,16,0"/>
              <TextBlock Text="Launch FreeForm" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <Button x:Name="SettingsBtn" Style="{StaticResource Card}">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE713;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center" Margin="0,0,16,0"/>
              <TextBlock Text="Configure settings" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
          <TextBlock x:Name="Status" Foreground="#A0A0A0" FontSize="12" Margin="2,12,0,0" TextWrapping="Wrap"/>
        </StackPanel>
        <!-- right: settings -->
        <StackPanel x:Name="SettingsPage" Grid.Column="1" VerticalAlignment="Center" Margin="20,0,0,0" Visibility="Collapsed">
          <CheckBox x:Name="AutoStart" Content="Start FreeForm when I sign in"/>
          <CheckBox x:Name="HideTaskbar" Content="Hide the Windows taskbar"/>
          <CheckBox x:Name="HideIcons" Content="Hide Windows desktop icons"/>
          <CheckBox x:Name="SkipLauncher" Content="Skip this window (hold Shift to see it)"/>
          <CheckBox x:Name="AutoUpdate" Content="Update FreeForm automatically"/>
          <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
            <Button x:Name="BackBtn" Style="{StaticResource Link}" Content="&#x2190;  Back"/>
            <Button x:Name="UninstallBtn" Style="{StaticResource Link}" Content="Uninstall FreeForm" Foreground="#FF8A80" Margin="16,0,0,0"/>
          </StackPanel>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml'); $ui[$n] = $win.FindName($n) }

$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })
$ui.CloseBtn.Add_Click({ $win.Close() })
$ui.AboutBtn.Add_Click({ Start-Process 'https://github.com/jokingtim2468-max/Nexus-OS/tree/vibe-coded/sharp-noether-i8tg9c/macshell-win' })
$ui.RestoreBtn.Add_Click({
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'FreeForm.ps1') -Stop
    $ui.Status.Text = 'FreeForm is closed and the Windows taskbar and desktop are back.'
})
$ui.LaunchBtn.Add_Click({ Start-FreeForm -Force; $win.Close() })
$ui.SettingsBtn.Add_Click({ $ui.MainPage.Visibility = 'Collapsed'; $ui.SettingsPage.Visibility = 'Visible' })
$ui.BackBtn.Add_Click({ $ui.SettingsPage.Visibility = 'Collapsed'; $ui.MainPage.Visibility = 'Visible' })

$ui.AutoStart.IsChecked = [bool](Get-ItemProperty -Path $runKey -Name FreeForm -ErrorAction SilentlyContinue)
$ui.HideTaskbar.IsChecked = [bool]$cfg.hideTaskbar
$ui.HideIcons.IsChecked = [bool]$cfg.hideIcons
$ui.SkipLauncher.IsChecked = [bool]$cfg.skipLauncher
$ui.AutoUpdate.IsChecked = [bool]$cfg.autoUpdate
$ui.AutoUpdate.Add_Click({ $cfg.autoUpdate = [bool]$ui.AutoUpdate.IsChecked; Save-Config })
$ui.AutoStart.Add_Click({
    if ($ui.AutoStart.IsChecked) { Set-ItemProperty -Path $runKey -Name FreeForm -Value "`"$(Join-Path $root 'FreeForm.cmd')`"" }
    else { Remove-ItemProperty -Path $runKey -Name FreeForm -ErrorAction SilentlyContinue }
})
$ui.HideTaskbar.Add_Click({ $cfg.hideTaskbar = [bool]$ui.HideTaskbar.IsChecked; Save-Config })
$ui.HideIcons.Add_Click({ $cfg.hideIcons = [bool]$ui.HideIcons.IsChecked; Save-Config })
$ui.SkipLauncher.Add_Click({ $cfg.skipLauncher = [bool]$ui.SkipLauncher.IsChecked; Save-Config })
$ui.UninstallBtn.Add_Click({
    $r = [System.Windows.MessageBox]::Show('Remove FreeForm''s shortcuts, start-at-sign-in and the fetch command? The FreeForm folder is left for you to delete.', 'Uninstall FreeForm', 'YesNo', 'Question')
    if ($r -eq 'Yes') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'install.ps1') -Uninstall | Out-Null
        $win.Close()
    }
})

# ── system check: things that make FreeForm fail or look wrong, shown under the buttons ──
function Get-SystemNotes {
    $notes = @()
    try {
        $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
        if ($build -lt 19041) { $notes += 'Windows 10 version 2004 or newer is recommended.' }
        $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name })
        if (-not ($gpus | Where-Object { $_ -notmatch 'Basic Display|Basic Render|Remote Display' })) {
            $notes += 'No graphics driver found: install your GPU driver for smooth animations.'
        }
    } catch {}
    try {
        $c = @((Get-Content (Join-Path $cfgDir 'crashes.json') -Raw | ConvertFrom-Json).crashes) | Where-Object { $_ -and ([datetime]$_) -gt (Get-Date).AddHours(-1) }
        if ($c.Count) { $notes += "FreeForm crashed $($c.Count) time(s) in the last hour. Save diagnostics to see why." }
    } catch {}
    $notes -join "`n"
}

# ── updates: the freeform-latest release carries version.txt next to the zip ──
$versionUrl = 'https://github.com/jokingtim2468-max/Nexus-OS/releases/download/freeform-latest/version.txt'
$script:updateTask = $null
function Start-UpdateCheck {
    if ($version -eq 'dev') { return }
    try { $wc = New-Object System.Net.WebClient; $script:updateTask = $wc.DownloadStringTaskAsync($versionUrl) } catch {}
}
$updateTimer = New-Object System.Windows.Threading.DispatcherTimer
$updateTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$updateTimer.Add_Tick({
    if (-not $script:updateTask -or -not $script:updateTask.IsCompleted) { return }
    $updateTimer.Stop()
    if ($script:updateTask.Status -ne 'RanToCompletion') { return }
    $latest = $script:updateTask.Result.Trim()
    if ($latest -and $latest -ne $version) {
        $ui.UpdateText.Text = "Update to $latest"
        $ui.UpdateBtn.Visibility = 'Visible'
        # automatic updates (Configure settings): install it right away
        if ($cfg.autoUpdate) { $ui.Status.Text = "Updating to $latest..."; $ui.UpdateBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
    }
})
$ui.UpdateBtn.Add_Click({
    # get.ps1 stops FreeForm, installs the new build over this one and opens the launcher again
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'FreeForm.ps1') -Stop
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'get.ps1')`"")
    $win.Close()
})

# ── diagnostics: a zip on the Desktop with logs and setup info (no network details, no personal files) ──
$ui.DiagBtn.Add_Click({
    try {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $tmp = Join-Path $env:TEMP "FreeForm-diagnostics-$stamp"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $logs = Join-Path $env:LOCALAPPDATA 'FreeForm\logs'
        if (Test-Path $logs) { Get-ChildItem $logs -File | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | Copy-Item -Destination $tmp }
        foreach ($f in 'launcher.json', 'crashes.json') { $src = Join-Path $cfgDir $f; if (Test-Path $src) { Copy-Item $src $tmp } }
        $os = Get-CimInstance Win32_OperatingSystem
        @(
            "FreeForm $version"
            "Windows: $($os.Caption) build $($os.BuildNumber)"
            "GPU: $((Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) ($($_.DriverVersion))" }) -join '; ')"
            "Screens: $(([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)" }) -join ', ')"
            "PowerShell: $($PSVersionTable.PSVersion)"
            "Notes: $(Get-SystemNotes)"
        ) | Set-Content (Join-Path $tmp 'system.txt')
        $zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "FreeForm-diagnostics-$stamp.zip"
        Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -Force
        Remove-Item $tmp -Recurse -Force
        Start-Process explorer.exe -ArgumentList "/select,`"$zip`""
        $ui.Status.Text = "Saved $([IO.Path]::GetFileName($zip)) to your Desktop."
    } catch { $ui.Status.Text = "Couldn't save diagnostics: $($_.Exception.Message)" }
})

$win.Add_ContentRendered({
    $ui.Status.Text = Get-SystemNotes
    Start-UpdateCheck
    $updateTimer.Start()
})

if ($env:FREEFORM_LAUNCHER_TEST) { "notes: $(Get-SystemNotes)"; 'launcher window ok'; exit 0 }   # CI: the XAML loads and the buttons are wired
[void]$win.ShowDialog()
