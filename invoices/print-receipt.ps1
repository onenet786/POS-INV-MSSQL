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
$script:receiptFont = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)
$doc = New-Object System.Drawing.Printing.PrintDocument
$doc.DocumentName = "POS Receipt"
if (-not [string]::IsNullOrWhiteSpace($PrinterName)) {
  $doc.PrinterSettings.PrinterName = $PrinterName
}
$paperHeight = [Math]::Max(500, [Math]::Min(3200, 90 + ($script:receiptLines.Length * 18)))
$doc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("3 inch thermal receipt", 300, $paperHeight)
$doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
$doc.OriginAtMargins = $false
$script:index = 0
$doc.add_PrintPage({
  param($sender, $eventArgs)
  $eventArgs.Graphics.PageUnit = [System.Drawing.GraphicsUnit]::Display
  $x = $eventArgs.PageSettings.HardMarginX + 4
  $y = $eventArgs.PageSettings.HardMarginY + 4
  $lineHeight = $script:receiptFont.GetHeight($eventArgs.Graphics) + 5
  while ($script:index -lt $script:receiptLines.Length) {
    $eventArgs.Graphics.DrawString($script:receiptLines[$script:index], $script:receiptFont, [System.Drawing.Brushes]::Black, $x, $y)
    $y += $lineHeight
    $script:index++
    if ($y + $lineHeight -gt ($eventArgs.PageBounds.Height - 10)) {
      $eventArgs.HasMorePages = $true
      return
    }
  }
  $eventArgs.HasMorePages = $false
})
$doc.Print()
