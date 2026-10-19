param([Parameter(Mandatory=$true)][string]$ProbePath,
      [Parameter(Mandatory=$true)][string]$RootPath)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RootPath)
$workspace = [IO.Path]::GetFullPath((Get-Location).Path)
if (!$root.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'ACL test root must remain inside the worktree'
}
$storage = Join-Path $root 'state.plist'
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Assert-PrivateAcl([string]$Path) {
  $acl = Get-Acl -LiteralPath $Path
  if (!$acl.AreAccessRulesProtected) { throw "DACL inherits access: $Path" }
  $rules = $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])
  if ($rules.Count -ne 1) { throw "Unexpected ACL entries: $Path" }
  foreach ($rule in $rules) {
    if ($rule.IdentityReference.Value -ne $userSid -or
        $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
        $rule.IsInherited) { throw "Unexpected effective access: $Path" }
  }
}
try {
  & $ProbePath produce $storage | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Fresh storage failed' }
  Assert-PrivateAcl $root
  Assert-PrivateAcl $storage
  foreach ($path in @($root, $storage)) {
    $acl = Get-Acl -LiteralPath $path
    $acl.SetAccessRuleProtection($false, $true)
    $everyone = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    # Persist only the DACL. PowerShell Set-Acl may also request audit-policy
    # privileges from a descriptor returned by Get-Acl on this host.
    $sections = [Security.AccessControl.AccessControlSections]::Access
    if ([IO.Directory]::Exists($path)) {
      $accessOnly = New-Object Security.AccessControl.DirectorySecurity
      $accessOnly.SetSecurityDescriptorSddlForm($acl.GetSecurityDescriptorSddlForm($sections), $sections)
      [IO.Directory]::SetAccessControl($path, $accessOnly)
    } else {
      $accessOnly = New-Object Security.AccessControl.FileSecurity
      $accessOnly.SetSecurityDescriptorSddlForm($acl.GetSecurityDescriptorSddlForm($sections), $sections)
      [IO.File]::SetAccessControl($path, $accessOnly)
    }
  }
  & $ProbePath produce $storage | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Existing insecure storage could not be secured' }
  Assert-PrivateAcl $root
  Assert-PrivateAcl $storage
  Write-Output 'private-acl-passed: fresh and existing directory/file; protected current-user DACL only'
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
