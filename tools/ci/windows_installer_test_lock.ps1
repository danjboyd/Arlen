# Both installer fixtures temporarily change the same persisted user PATH.
# Hold this mutex before taking a snapshot and until restoration is complete,
# including when the fixtures run from different checkouts or runner sessions.
function Enter-ArlenInstallerTestLock {
  param([int]$TimeoutSeconds = 1800)
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = New-Object Threading.Mutex($false, "Global\ArlenInstallerTests-$sid")
  $acquired = $false
  try {
    try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)) }
    catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw 'another Windows installer fixture holds the user PATH lock' }
    return $mutex
  } catch {
    $mutex.Dispose()
    throw
  }
}
