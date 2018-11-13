#Generic Logging function --
Function Log($message, $color) {
   if ($color) {
      Write-Host -ForegroundColor $color "$(Get-Date -Format u) | $message"
   }
   else {
      "$(Get-Date -Format u) | $message"
   }
}
Export-ModuleMember Log
