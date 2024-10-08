# Check administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

function Console
{
    param ([Switch]$Show,[Switch]$Hide)
    if (-not ("Console.Window" -as [type])) { 

        Add-Type -Name Window -Namespace Console -MemberDefinition '
        [DllImport("Kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
        '
    }

    if ($Show)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()

        $null = [Console.Window]::ShowWindow($consolePtr, 5)
    }

    if ($Hide)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()
        #0 hide
        $null = [Console.Window]::ShowWindow($consolePtr, 0)
    }
}

# Obtener RTCores
function GetRTCores {
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $value = (Get-ItemProperty -Path $keyPath -Name "ReservedCpuSets" -ErrorAction SilentlyContinue)."ReservedCpuSets"
    if ($null -eq $value) {
        return "0" * [Environment]::ProcessorCount
    } else {
        # Convertir el valor a un entero sin signo de 64 bits, convertir a una cadena binaria
        $bytes = [System.BitConverter]::ToUInt64($value, 0)
        $bitmask = [Convert]::ToString($bytes, 2).PadLeft([Environment]::ProcessorCount, '0')

        # Convertir de little-endian a big-endian
        $reversedBitmask = -join ($bitmask.ToCharArray() | Sort-Object -Descending)
        
        return $reversedBitmask
    }
}

# actualizar o remover RTCores
function SaveRTCores {
    param (
        [string]$bitmask
    )
    $keyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"

    if ($bitmask -eq "0") {
        Remove-ItemProperty -Path $keyPath -Name "ReservedCpuSets" -ErrorAction SilentlyContinue
    } else {
        $littleEndianBitmask = $bitmask.ToCharArray()
        [array]::Reverse($littleEndianBitmask)
        $bitString = -join $littleEndianBitmask
        $intValue = [Convert]::ToInt64($bitString, 2)
        $bytes = [System.BitConverter]::GetBytes($intValue)
        Set-ItemProperty -Path $keyPath -Name "ReservedCpuSets" -Value $bytes -Type Binary
    }
    [System.Windows.Forms.MessageBox]::Show("Updated settings", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}


Console -Hide
[System.Windows.Forms.Application]::EnableVisualStyles();
$form = New-Object System.Windows.Forms.Form
$form.Text = "Set-RTCores"
$form.ClientSize = New-Object System.Drawing.Size(170, 240)
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.KeyPreview = $true
$form.Add_KeyDown({
    $bitmask = GetRTCores
    for ($i = 0; $i -lt [Environment]::ProcessorCount; $i++) {
        $cpuListBox.SetItemChecked($i, $bitmask[$i] -eq "1")
    }
})

$form.Add_Paint({
    param (
        [object]$sender,
        [System.Windows.Forms.PaintEventArgs]$e
    )
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(44, 44, 44),   # Color negro
        [System.Drawing.Color]::FromArgb(99, 99, 99),# Color gris oscuro
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $e.Graphics.FillRectangle($brush, $rect)
})

$cpuListBox = New-Object System.Windows.Forms.CheckedListBox
$cpuListBox.Location = New-Object System.Drawing.Point(10, 10)
$cpuListBox.Size = New-Object System.Drawing.Size(150, 200)
$cpuListBox.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$cpuListBox.ForeColor = [System.Drawing.Color]::White
$cpuListBox.BorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
for ($i = 0; $i -lt [Environment]::ProcessorCount; $i++) {
    [void]$cpuListBox.Items.Add("CPU $i")
}
$form.Controls.Add($cpuListBox)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Size = New-Object System.Drawing.Size(75, 20)
$btnSave.Location = New-Object System.Drawing.Point(50, 215)
$btnSave.Text = "Save"
$btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnSave)

# cargar configuración actual
$bitmask = GetRTCores
for ($i = 0; $i -lt [Environment]::ProcessorCount; $i++) {
    $cpuListBox.SetItemChecked($i, $bitmask[$i] -eq "1")
}

# aplicar todo los cambios
$btnSave.Add_Click({
    if ($cpuListBox.CheckedItems.Count -eq 0) {
        SaveRTCores -bitmask "0"
        return
    }
    $bitmask = ""
    for ($i = 0; $i -lt [Environment]::ProcessorCount; $i++) {
        if ($cpuListBox.GetItemChecked($i)) {
            $bitmask += "1"
        } else {
            $bitmask += "0"
        }
    }
    SaveRTCores -bitmask $bitmask
    })

[void]$form.ShowDialog()
