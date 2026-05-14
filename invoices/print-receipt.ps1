param(
  [Parameter(Mandatory = $true)]
  [string]$ReceiptPath,
  [string]$PrinterName = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ReceiptPath) -or -not [System.IO.File]::Exists($ReceiptPath)) {
  throw "Receipt file was not found: $ReceiptPath"
}
Add-Type -AssemblyName System.Drawing
$script:receiptLines = [System.IO.File]::ReadAllLines($ReceiptPath)
$script:receiptFont = New-Object System.Drawing.Font("Consolas", 11.5, [System.Drawing.FontStyle]::Regular)
$doc = New-Object System.Drawing.Printing.PrintDocument
$doc.DocumentName = "POS Receipt"
if (-not [string]::IsNullOrWhiteSpace($PrinterName)) {
  $doc.PrinterSettings.PrinterName = $PrinterName
}
$script:index = 0
$doc.add_PrintPage({
  param($sender, $eventArgs)
  $x = $eventArgs.MarginBounds.Left
  $y = $eventArgs.MarginBounds.Top
  $lineHeight = $script:receiptFont.GetHeight($eventArgs.Graphics) + 5
  while ($script:index -lt $script:receiptLines.Length) {
    $eventArgs.Graphics.DrawString($script:receiptLines[$script:index], $script:receiptFont, [System.Drawing.Brushes]::Black, $x, $y)
    $y += $lineHeight
    $script:index++
    if ($y + $lineHeight -gt $eventArgs.MarginBounds.Bottom) {
      $eventArgs.HasMorePages = $true
      return
    }
  }
  $eventArgs.HasMorePages = $false
})
$doc.Print()
