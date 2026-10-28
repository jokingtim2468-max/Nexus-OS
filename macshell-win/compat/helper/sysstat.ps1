# sysstat.ps1 — CPU / RAM / GPU load for desktop widgets (Widget Studio), one JSON line every 2 s:
#   {"cpu":12,"ram":48,"ramUsed":7.6,"ramTotal":15.9,"gpu":3}
# Uses the language-independent performance classes (Get-Counter's names are translated).
$ErrorActionPreference = 'SilentlyContinue'
while ($true) {
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [double]$os.TotalVisibleMemorySize; $free = [double]$os.FreePhysicalMemory
    $gpu = 0
    $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine | Where-Object { $_.Name -like '*engtype_3D' }
    if ($eng) { $gpu = [Math]::Min(100, ($eng | Measure-Object UtilizationPercentage -Sum).Sum) }
    $o = @{ cpu = [int]$cpu; gpu = [int]$gpu }
    if ($total -gt 0) { $o.ram = [int](100 * ($total - $free) / $total); $o.ramUsed = [Math]::Round(($total - $free) / 1MB, 1); $o.ramTotal = [Math]::Round($total / 1MB, 1) }
    [Console]::Out.WriteLine(($o | ConvertTo-Json -Compress)); [Console]::Out.Flush()
    Start-Sleep -Seconds 2
}
