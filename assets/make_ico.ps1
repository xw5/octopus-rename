$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$src = "D:\code\ahk_pro\octopus-file\assets\icon.png"
$dst = "D:\code\ahk_pro\octopus-file\assets\icon.ico"
$sizes = @(16, 24, 32, 48, 64, 128, 256)

$srcImg = [System.Drawing.Image]::FromFile($src)

# For each size: 32bpp bottom-up BGRA pixels + BITMAPINFOHEADER + zero AND mask
$entries = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($srcImg, 0, 0, $s, $s)
    $g.Dispose()

    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $pixels = New-Object 'byte[]' ($s * $s * 4)
    for ($y = 0; $y -lt $s; $y++) {
        $srcRow = $data.Scan0.ToInt64() + ($s - 1 - $y) * $stride
        [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]$srcRow, $pixels, $y * $s * 4, $s * 4)
    }
    $bmp.UnlockBits($data)
    $bmp.Dispose()

    # BITMAPINFOHEADER (biHeight = height x2 for XOR+AND planes)
    $hdr = New-Object 'byte[]' 40
    [BitConverter]::GetBytes([UInt32]40).CopyTo($hdr, 0)
    [BitConverter]::GetBytes([Int32]$s).CopyTo($hdr, 4)
    [BitConverter]::GetBytes([Int32]($s * 2)).CopyTo($hdr, 8)
    [BitConverter]::GetBytes([UInt16]1).CopyTo($hdr, 12)
    [BitConverter]::GetBytes([UInt16]32).CopyTo($hdr, 14)

    $maskRow = [Math]::Ceiling($s / 32.0) * 4
    $mask = New-Object 'byte[]' ($maskRow * $s)

    $img = New-Object 'byte[]' ($hdr.Length + $pixels.Length + $mask.Length)
    [Array]::Copy($hdr, 0, $img, 0, $hdr.Length)
    [Array]::Copy($pixels, 0, $img, $hdr.Length, $pixels.Length)
    [Array]::Copy($mask, 0, $img, $hdr.Length + $pixels.Length, $mask.Length)

    $entries += @{ Size = $s; Data = $img }
}
$srcImg.Dispose()

# ICO header + directory entries + image data
$count = $entries.Count
$ms = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($ms)
$w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$count)

$offset = 6 + 16 * $count
foreach ($e in $entries) {
    $s = $e.Size
    if ($s -ge 256) { $b = 0 } else { $b = $s }
    $w.Write([Byte]$b); $w.Write([Byte]$b)
    $w.Write([Byte]0); $w.Write([Byte]0)
    $w.Write([UInt16]1); $w.Write([UInt16]32)
    $w.Write([UInt32]$e.Data.Length)
    $w.Write([UInt32]$offset)
    $offset += $e.Data.Length
}
foreach ($e in $entries) { $w.Write($e.Data) }
$w.Flush()
[System.IO.File]::WriteAllBytes($dst, $ms.ToArray())
$w.Dispose(); $ms.Dispose()
Write-Output "ICO written: $dst"
