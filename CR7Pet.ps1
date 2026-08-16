param(
    [switch]$SelfTest,
    [switch]$DebugWindow,
    [switch]$Demo
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:LogPath = Join-Path $script:AppRoot 'logs\cr7-pet.log'
$script:StatePath = Join-Path $script:AppRoot 'state.json'
$configPath = Join-Path $script:AppRoot 'config.json'
$skinsPath = Join-Path $script:AppRoot 'assets\skins'

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogPath) | Out-Null

function Write-PetLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $script:LogPath -Value ('{0:u} {1}' -f (Get-Date), $Message) -Encoding UTF8
    }
    catch {
    }
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Management
Add-Type -AssemblyName System.Drawing

$nativeCode = @'
using System;
using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading;

namespace CR7PetNative
{
    public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, int stateMask, IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig]
        int Activate(ref Guid interfaceId, int classContext, IntPtr activationParameters,
            [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport]
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float level, IntPtr eventContext);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, IntPtr eventContext);
        [PreserveSig] int GetMasterVolumeLevel(out float level);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float level, IntPtr eventContext);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, IntPtr eventContext);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float level);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool muted, IntPtr eventContext);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool muted);
        [PreserveSig] int GetVolumeStepInfo(out uint step, out uint stepCount);
        [PreserveSig] int VolumeStepUp(IntPtr eventContext);
        [PreserveSig] int VolumeStepDown(IntPtr eventContext);
        [PreserveSig] int QueryHardwareSupport(out uint hardwareSupportMask);
        [PreserveSig] int GetVolumeRange(out float minDb, out float maxDb, out float incrementDb);
    }

    public sealed class AudioSnapshot
    {
        public float Volume { get; set; }
        public bool Muted { get; set; }
    }

    public static class Sensors
    {
        private const int CLSCTX_ALL = 23;

        public static AudioSnapshot ReadAudio()
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IAudioEndpointVolume endpoint = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
                Marshal.ThrowExceptionForHR(
                    enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eConsole, out device));
                Guid interfaceId = typeof(IAudioEndpointVolume).GUID;
                object activated;
                Marshal.ThrowExceptionForHR(
                    device.Activate(ref interfaceId, CLSCTX_ALL, IntPtr.Zero, out activated));
                endpoint = (IAudioEndpointVolume)activated;
                float volume;
                bool muted;
                Marshal.ThrowExceptionForHR(endpoint.GetMasterVolumeLevelScalar(out volume));
                Marshal.ThrowExceptionForHR(endpoint.GetMute(out muted));
                return new AudioSnapshot { Volume = volume, Muted = muted };
            }
            finally
            {
                if (endpoint != null && Marshal.IsComObject(endpoint)) Marshal.FinalReleaseComObject(endpoint);
                if (device != null && Marshal.IsComObject(device)) Marshal.FinalReleaseComObject(device);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.FinalReleaseComObject(enumerator);
            }
        }

        public static int ReadBrightness()
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                    @"root\WMI", "SELECT Active, CurrentBrightness FROM WmiMonitorBrightness"))
                {
                    foreach (ManagementObject monitor in searcher.Get())
                    {
                        bool active = monitor["Active"] == null || Convert.ToBoolean(monitor["Active"]);
                        if (active && monitor["CurrentBrightness"] != null)
                            return Convert.ToInt32(monitor["CurrentBrightness"]);
                    }
                }
            }
            catch { return -1; }
            return -1;
        }
    }

    public static class KeyboardHook
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int VK_BACK = 0x08;
        private const int VK_RETURN = 0x0D;
        private const int VK_7 = 0x37;
        private const int VK_NUMPAD7 = 0x67;
        private static LowLevelKeyboardProc callback = HookCallback;
        private static IntPtr hook = IntPtr.Zero;
        private static int switchCounter = 0;
        private static int siuCounter = 0;
        private static int bicycleCounter = 0;
        private static long lastSwitchMilliseconds = 0;
        private static long lastSiuMilliseconds = 0;
        private static long lastBicycleMilliseconds = 0;

        public static int SwitchCounter { get { return Volatile.Read(ref switchCounter); } }
        public static int SiuCounter { get { return Volatile.Read(ref siuCounter); } }
        public static int BicycleCounter { get { return Volatile.Read(ref bicycleCounter); } }
        public static bool IsInstalled { get { return hook != IntPtr.Zero; } }

        public static bool Install()
        {
            if (hook != IntPtr.Zero) return true;
            using (Process process = Process.GetCurrentProcess())
            using (ProcessModule module = process.MainModule)
            {
                hook = SetWindowsHookEx(WH_KEYBOARD_LL, callback, GetModuleHandle(module.ModuleName), 0);
            }
            return hook != IntPtr.Zero;
        }

        public static void Uninstall()
        {
            if (hook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(hook);
                hook = IntPtr.Zero;
            }
        }

        private static IntPtr HookCallback(int code, IntPtr message, IntPtr data)
        {
            if (code >= 0 && (message == (IntPtr)WM_KEYDOWN || message == (IntPtr)WM_SYSKEYDOWN))
            {
                int key = Marshal.ReadInt32(data);
                if (key == VK_7 || key == VK_NUMPAD7)
                {
                    long now = DateTime.UtcNow.Ticks / TimeSpan.TicksPerMillisecond;
                    long previous = Interlocked.Read(ref lastSwitchMilliseconds);
                    if (now - previous > 320)
                    {
                        Interlocked.Exchange(ref lastSwitchMilliseconds, now);
                        Interlocked.Increment(ref switchCounter);
                    }
                }
                else if (key == VK_RETURN)
                {
                    long now = DateTime.UtcNow.Ticks / TimeSpan.TicksPerMillisecond;
                    long previous = Interlocked.Read(ref lastSiuMilliseconds);
                    if (now - previous > 420)
                    {
                        Interlocked.Exchange(ref lastSiuMilliseconds, now);
                        Interlocked.Increment(ref siuCounter);
                    }
                }
                else if (key == VK_BACK)
                {
                    long now = DateTime.UtcNow.Ticks / TimeSpan.TicksPerMillisecond;
                    long previous = Interlocked.Read(ref lastBicycleMilliseconds);
                    if (now - previous > 420)
                    {
                        Interlocked.Exchange(ref lastBicycleMilliseconds, now);
                        Interlocked.Increment(ref bicycleCounter);
                    }
                }
            }
            return CallNextHookEx(hook, code, message, data);
        }

        private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr message, IntPtr data);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc callback, IntPtr module, uint threadId);
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string moduleName);
    }
}
'@

Add-Type -TypeDefinition $nativeCode -ReferencedAssemblies @(
    'System.dll',
    'System.Core.dll',
    'System.Management.dll'
)

$script:SkinSlugs = @(
    'purple-noodle',
    'young-ronaldo',
    'juventus-half',
    'portugal-euro',
    'white-gold'
)
$script:SkinNames = @(
    'Purple Noodle',
    'Young Ronaldo',
    'Juventus Half & Half',
    'Portugal Euro Red',
    'White & Gold'
)

$missingAssets = New-Object System.Collections.Generic.List[string]
foreach ($slug in $script:SkinSlugs) {
    $frameDir = Join-Path $skinsPath (Join-Path $slug 'frames')
    for ($index = 1; $index -le 25; $index++) {
        $pattern = '{0:D2}_*.png' -f $index
        if (@(Get-ChildItem -LiteralPath $frameDir -Filter $pattern -File -ErrorAction SilentlyContinue).Count -ne 1) {
            $missingAssets.Add((Join-Path $frameDir $pattern))
        }
    }
}

if ($SelfTest) {
    $alphaErrors = New-Object System.Collections.Generic.List[string]
    foreach ($slug in $script:SkinSlugs) {
        $frameDir = Join-Path $skinsPath (Join-Path $slug 'frames')
        foreach ($file in @(Get-ChildItem -LiteralPath $frameDir -Filter '*.png' -File | Sort-Object Name)) {
            try {
                $bitmap = [System.Drawing.Bitmap]::FromFile($file.FullName)
                if ($bitmap.GetPixel(0, 0).A -ne 0 -or $bitmap.GetPixel(($bitmap.Width - 1), 0).A -ne 0) {
                    $alphaErrors.Add($file.FullName)
                }
                $bitmap.Dispose()
            }
            catch {
                $alphaErrors.Add($file.FullName)
            }
        }
    }

    $audio = $null
    $audioError = $null
    try { $audio = [CR7PetNative.Sensors]::ReadAudio() }
    catch { $audioError = $_.Exception.Message }
    $brightness = [CR7PetNative.Sensors]::ReadBrightness()
    $hookInstalled = [CR7PetNative.KeyboardHook]::Install()
    [CR7PetNative.KeyboardHook]::Uninstall()

    [pscustomobject]@{
        engine = 'WPF per-pixel alpha'
        language = 'English'
        skinsFound = $script:SkinSlugs.Count
        framesFound = (125 - $missingAssets.Count)
        framesMissing = @($missingAssets)
        alphaCornerErrors = @($alphaErrors)
        globalSevenHook = $hookInstalled
        globalEnterSiu = $hookInstalled
        globalBackspaceBicycle = $hookInstalled
        globalHotkeysPassThrough = $true
        audioVolumePercent = if ($audio) { [math]::Round($audio.Volume * 100) } else { $null }
        audioMuted = if ($audio) { $audio.Muted } else { $null }
        audioError = $audioError
        brightnessPercent = $brightness
        brightnessSupported = ($brightness -ge 0)
    } | ConvertTo-Json -Depth 4
    $passed = $missingAssets.Count -eq 0 -and $alphaErrors.Count -eq 0 -and $hookInstalled -and -not $audioError
    exit $(if ($passed) { 0 } else { 1 })
}

if ($missingAssets.Count -gt 0) {
    [System.Windows.MessageBox]::Show(
        ('Animation assets are missing.' + [Environment]::NewLine + ($missingAssets -join [Environment]::NewLine)),
        'CR7 Codex Pet',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\CR7CodexPet.WPF.SingleInstance', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Import-WpfBitmap {
    param([string]$Path)
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat
    $bitmap.UriSource = New-Object System.Uri($Path, [System.UriKind]::Absolute)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

$script:Frames = @{}
foreach ($slug in $script:SkinSlugs) {
    $frameDir = Join-Path $skinsPath (Join-Path $slug 'frames')
    $frameList = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $frameDir -Filter '*.png' -File | Sort-Object Name)) {
        $frameList += Import-WpfBitmap -Path $file.FullName
    }
    $script:Frames[$slug] = $frameList
}

$script:SkinIndex = 0
$script:SavedState = $null
if (Test-Path -LiteralPath $script:StatePath -PathType Leaf) {
    try {
        $script:SavedState = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        if ($null -ne $script:SavedState.skinIndex) {
            $script:SkinIndex = [math]::Max(0, [math]::Min($script:SkinSlugs.Count - 1, [int]$script:SavedState.skinIndex))
        }
    }
    catch { Write-PetLog ('State load: ' + $_.Exception.Message) }
}

$window = New-Object System.Windows.Window
$window.Title = 'CR7 Codex Pet'
$window.Width = [double]$config.windowWidth
$window.Height = [double]$config.windowHeight
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = [bool]$config.alwaysOnTop
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.SizeToContent = [System.Windows.SizeToContent]::Manual

$root = New-Object System.Windows.Controls.Grid
$root.Background = [System.Windows.Media.Brushes]::Transparent
$root.Cursor = [System.Windows.Input.Cursors]::Hand
$window.Content = $root

$petImage = New-Object System.Windows.Controls.Image
$petImage.Width = [double]$config.windowWidth
$petImage.Height = 420
$petImage.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$petImage.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom
$petImage.Stretch = [System.Windows.Media.Stretch]::Uniform
$petImage.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.84)
$root.Children.Add($petImage) | Out-Null

$scaleTransform = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
$rotateTransform = New-Object System.Windows.Media.RotateTransform(0.0)
$translateTransform = New-Object System.Windows.Media.TranslateTransform(0.0, 0.0)
$transformGroup = New-Object System.Windows.Media.TransformGroup
$transformGroup.Children.Add($scaleTransform)
$transformGroup.Children.Add($rotateTransform)
$transformGroup.Children.Add($translateTransform)
$petImage.RenderTransform = $transformGroup

$bubble = New-Object System.Windows.Controls.Border
$bubble.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(242, 15, 18, 26))
$bubble.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(239, 184, 64))
$bubble.BorderThickness = New-Object System.Windows.Thickness(1.5)
$bubble.CornerRadius = New-Object System.Windows.CornerRadius(14)
$bubble.Padding = New-Object System.Windows.Thickness(14, 7, 14, 7)
$bubble.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
$bubble.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
$bubble.Margin = New-Object System.Windows.Thickness(12, 5, 12, 0)
$bubble.Visibility = [System.Windows.Visibility]::Collapsed

$bubbleText = New-Object System.Windows.Controls.TextBlock
$bubbleText.Foreground = [System.Windows.Media.Brushes]::White
$bubbleText.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI Semibold')
$bubbleText.FontSize = 13
$bubbleText.TextAlignment = [System.Windows.TextAlignment]::Center
$bubbleText.TextWrapping = [System.Windows.TextWrapping]::Wrap
$bubble.Child = $bubbleText
$root.Children.Add($bubble) | Out-Null

$bubbleTimer = New-Object System.Windows.Threading.DispatcherTimer
$bubbleTimer.Add_Tick({
    $bubbleTimer.Stop()
    $bubble.Visibility = [System.Windows.Visibility]::Collapsed
})

function Show-PetMessage {
    param([string]$Text, [int]$Milliseconds = 1300)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $bubbleText.Text = $Text
    $bubble.Visibility = [System.Windows.Visibility]::Visible
    $bubbleTimer.Stop()
    $bubbleTimer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
    $bubbleTimer.Start()
}

$script:Animations = @{
    rest = @{
        Frames = @(0)
        Durations = @(60000)
        Priority = 0
        Loop = $true
        Message = ''
    }
    idle = @{
        Frames = @(0, 0, 0, 0, 0)
        Durations = @(260, 260, 260, 260, 340)
        Priority = 0
        Loop = $false
        Message = ''
    }
    bicycle = @{
        Frames = @(5, 6, 7, 8, 9)
        Durations = @(190, 150, 180, 230, 350)
        Priority = 10
        Loop = $false
        Message = 'OVERHEAD!'
    }
    siu = @{
        Frames = @(10, 11, 12, 13, 14)
        Durations = @(300, 170, 330, 190, 520)
        Priority = 10
        Loop = $false
        Message = 'ME. HERE. SIUUU!'
    }
    calma = @{
        Frames = @(15, 16, 15, 16, 16)
        Durations = @(230, 260, 230, 300, 420)
        Priority = 7
        Loop = $false
        Message = 'CALMA.'
    }
    meditate = @{
        Frames = @(17, 18, 19, 18, 19)
        Durations = @(220, 300, 440, 300, 520)
        Priority = 7
        Loop = $false
        Message = 'FOCUS.'
    }
    shirt = @{
        Frames = @(20, 21, 22, 23, 24)
        Durations = @(190, 190, 230, 520, 500)
        Priority = 9
        Loop = $false
        Message = 'MAXIMUM!'
    }
}

$script:Motion = @{
    rest = @(
        @{ ScaleX = 1.000; ScaleY = 1.000; X = 0; Y = 0; Rotation = 0.0 }
    )
    idle = @(
        @{ ScaleX = 1.000; ScaleY = 1.000; X = -1.5; Y = 0; Rotation = -0.35 },
        @{ ScaleX = 1.003; ScaleY = 1.004; X = 1.5; Y = -0.5; Rotation = 0.35 },
        @{ ScaleX = 1.000; ScaleY = 1.000; X = -1.0; Y = 0; Rotation = -0.25 },
        @{ ScaleX = 1.002; ScaleY = 1.003; X = 1.0; Y = -0.4; Rotation = 0.25 },
        @{ ScaleX = 1.000; ScaleY = 1.000; X = 0; Y = 0; Rotation = 0.0 }
    )
    bicycle = @(
        @{ ScaleX = 0.97; ScaleY = 1.03; Y = 3; Rotation = 0 },
        @{ ScaleX = 1.04; ScaleY = 0.96; Y = -12; Rotation = -5 },
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = -30; Rotation = -10 },
        @{ ScaleX = 1.05; ScaleY = 0.96; Y = -36; Rotation = 7 },
        @{ ScaleX = 1.03; ScaleY = 0.93; Y = 4; Rotation = 0 }
    )
    siu = @(
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = -1 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = 1; Rotation = 1 },
        @{ ScaleX = 0.98; ScaleY = 1.02; Y = 0; Rotation = 0 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = -38; Rotation = 6 },
        @{ ScaleX = 1.06; ScaleY = 0.92; Y = 3; Rotation = 0 }
    )
    calma = @(
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = -1 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = 1; Rotation = 1 },
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = -1 },
        @{ ScaleX = 1.02; ScaleY = 0.98; Y = 1; Rotation = 1 },
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = 0 }
    )
    meditate = @(
        @{ ScaleX = 1.00; ScaleY = 1.00; Y = 0; Rotation = 0 },
        @{ ScaleX = 1.01; ScaleY = 1.01; Y = -1; Rotation = -0.5 },
        @{ ScaleX = 1.00; ScaleY = 1.015; Y = -2; Rotation = 0.5 },
        @{ ScaleX = 1.01; ScaleY = 1.01; Y = -1; Rotation = -0.4 },
        @{ ScaleX = 1.00; ScaleY = 1.015; Y = -2; Rotation = 0.3 }
    )
    shirt = @(
        @{ ScaleX = 0.98; ScaleY = 1.03; Y = 2; Rotation = 0 },
        @{ ScaleX = 1.02; ScaleY = 1.00; Y = -2; Rotation = -1 },
        @{ ScaleX = 1.04; ScaleY = 0.98; Y = -5; Rotation = 1 },
        @{ ScaleX = 1.08; ScaleY = 0.94; Y = 2; Rotation = 0 },
        @{ ScaleX = 1.02; ScaleY = 1.00; Y = 0; Rotation = 0 }
    )
}

$script:CurrentAnimation = 'rest'
$script:AnimationStep = -1
$script:CurrentPriority = 0
$script:FrameDeadline = [DateTime]::MinValue

function Start-PropertyAnimation {
    param(
        [System.Windows.Media.Animation.IAnimatable]$Target,
        [System.Windows.DependencyProperty]$Property,
        [double]$To,
        [int]$Milliseconds
    )
    $animation = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animation.To = $To
    $animation.Duration = [TimeSpan]::FromMilliseconds([math]::Max(45, [math]::Min(120, $Milliseconds * 0.62)))
    $ease = New-Object System.Windows.Media.Animation.QuadraticEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $animation.EasingFunction = $ease
    $Target.BeginAnimation($Property, $animation)
}

function Set-PetFrame {
    param([int]$FrameIndex, [int]$StepDuration)
    $slug = $script:SkinSlugs[$script:SkinIndex]
    $petImage.Source = $script:Frames[$slug][$FrameIndex]
    $motion = $script:Motion[$script:CurrentAnimation][$script:AnimationStep]
    $motionX = 0.0
    if ($motion.ContainsKey('X')) { $motionX = [double]$motion.X }
    Start-PropertyAnimation $scaleTransform ([System.Windows.Media.ScaleTransform]::ScaleXProperty) ([double]$motion.ScaleX) $StepDuration
    Start-PropertyAnimation $scaleTransform ([System.Windows.Media.ScaleTransform]::ScaleYProperty) ([double]$motion.ScaleY) $StepDuration
    Start-PropertyAnimation $rotateTransform ([System.Windows.Media.RotateTransform]::AngleProperty) ([double]$motion.Rotation) $StepDuration
    Start-PropertyAnimation $translateTransform ([System.Windows.Media.TranslateTransform]::XProperty) $motionX $StepDuration
    Start-PropertyAnimation $translateTransform ([System.Windows.Media.TranslateTransform]::YProperty) ([double]$motion.Y) $StepDuration
}

function Start-PetAnimation {
    param([string]$Name, [switch]$Force)
    $spec = $script:Animations[$Name]
    if (-not $Force -and $script:CurrentPriority -gt [int]$spec.Priority) { return }
    $script:CurrentAnimation = $Name
    $script:AnimationStep = -1
    $script:CurrentPriority = [int]$spec.Priority
    $script:FrameDeadline = [DateTime]::MinValue
    if (-not [string]::IsNullOrWhiteSpace([string]$spec.Message)) {
        Show-PetMessage -Text ([string]$spec.Message) -Milliseconds 1250
    }
}

function Update-PetAnimation {
    if ((Get-Date) -lt $script:FrameDeadline) { return }
    $spec = $script:Animations[$script:CurrentAnimation]
    $script:AnimationStep++
    if ($script:AnimationStep -ge $spec.Frames.Count) {
        if ([bool]$spec.Loop) {
            $script:AnimationStep = 0
        }
        else {
            Start-PetAnimation -Name 'rest' -Force
            $spec = $script:Animations['rest']
            $script:AnimationStep = 0
        }
    }
    $duration = [int]$spec.Durations[$script:AnimationStep]
    Set-PetFrame -FrameIndex ([int]$spec.Frames[$script:AnimationStep]) -StepDuration $duration
    $script:FrameDeadline = (Get-Date).AddMilliseconds($duration)
}

function Switch-PetSkin {
    $script:SkinIndex = ($script:SkinIndex + 1) % $script:SkinSlugs.Count
    $spec = $script:Animations[$script:CurrentAnimation]
    $safeStep = [math]::Max(0, [math]::Min($script:AnimationStep, $spec.Frames.Count - 1))
    $slug = $script:SkinSlugs[$script:SkinIndex]
    $petImage.Source = $script:Frames[$slug][[int]$spec.Frames[$safeStep]]
    Show-PetMessage -Text ($script:SkinNames[$script:SkinIndex] + '  |  7') -Milliseconds 1500
    Write-PetLog ('Skin switched: ' + $script:SkinNames[$script:SkinIndex])
}

$animationTimer = New-Object System.Windows.Threading.DispatcherTimer
$animationTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.animationTickMs)
$animationTimer.Add_Tick({ Update-PetAnimation })

$script:LastHookCounter = 0
$script:LastSiuCounter = 0
$script:LastBicycleCounter = 0
$hookTimer = New-Object System.Windows.Threading.DispatcherTimer
$hookTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$hookTimer.Add_Tick({
    $counter = [CR7PetNative.KeyboardHook]::SwitchCounter
    if ($counter -ne $script:LastHookCounter) {
        $script:LastHookCounter = $counter
        Switch-PetSkin
    }
    $siuCounter = [CR7PetNative.KeyboardHook]::SiuCounter
    if ($siuCounter -ne $script:LastSiuCounter) {
        $script:LastSiuCounter = $siuCounter
        Start-PetAnimation -Name 'siu' -Force
        Write-PetLog 'Shortcut Enter: SIU'
    }
    $bicycleCounter = [CR7PetNative.KeyboardHook]::BicycleCounter
    if ($bicycleCounter -ne $script:LastBicycleCounter) {
        $script:LastBicycleCounter = $bicycleCounter
        Start-PetAnimation -Name 'bicycle' -Force
        Write-PetLog 'Shortcut Backspace: bicycle'
    }
})

$script:LastVolume = $null
$script:LastMuted = $null
$volumeTimer = New-Object System.Windows.Threading.DispatcherTimer
$volumeTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.volumePollMs)
$volumeTimer.Add_Tick({
    try {
        $snapshot = [CR7PetNative.Sensors]::ReadAudio()
        if ($null -ne $script:LastVolume) {
            $delta = $snapshot.Volume - $script:LastVolume
            if ($snapshot.Muted -and -not $script:LastMuted) {
                Start-PetAnimation -Name 'bicycle'
            }
            elseif (-not $snapshot.Muted -and $delta -le -0.006) {
                Start-PetAnimation -Name 'calma'
            }
            elseif (-not $snapshot.Muted -and $delta -ge 0.006) {
                Start-PetAnimation -Name 'meditate'
            }
        }
        $script:LastVolume = $snapshot.Volume
        $script:LastMuted = $snapshot.Muted
    }
    catch { Write-PetLog ('Audio sensor: ' + $_.Exception.Message) }
})

$script:LastBrightness = $null
$brightnessTimer = New-Object System.Windows.Threading.DispatcherTimer
$brightnessTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.brightnessPollMs)
$brightnessTimer.Add_Tick({
    try {
        $brightness = [CR7PetNative.Sensors]::ReadBrightness()
        if ($brightness -ge 0) {
            if ($null -ne $script:LastBrightness -and $brightness -eq 100 -and $script:LastBrightness -lt 100) {
                Start-PetAnimation -Name 'shirt'
            }
            $script:LastBrightness = $brightness
        }
    }
    catch { Write-PetLog ('Brightness sensor: ' + $_.Exception.Message) }
})

$script:CodexWasRunning = $false
$codexTimer = New-Object System.Windows.Threading.DispatcherTimer
$codexTimer.Interval = [TimeSpan]::FromMilliseconds([int]$config.codexPollMs)
$codexTimer.Add_Tick({
    if (-not [bool]$config.triggerOnCodexOpen) { return }
    try {
        $running = @(Get-Process -Name 'ChatGPT', 'codex' -ErrorAction SilentlyContinue).Count -gt 0
        if ($running -and -not $script:CodexWasRunning) {
            Start-PetAnimation -Name 'bicycle'
        }
        $script:CodexWasRunning = $running
    }
    catch { Write-PetLog ('Codex sensor: ' + $_.Exception.Message) }
})

function Open-VSCodeAndCelebrate {
    Start-PetAnimation -Name 'shirt' -Force
    $existingVSCode = @(Get-Process -Name 'Code' -ErrorAction SilentlyContinue).Count -gt 0
    if ($existingVSCode) {
        Show-PetMessage -Text 'VS CODE IS OPEN' -Milliseconds 1500
        Write-PetLog 'Double-click: VS Code was already running; no new launch.'
        return
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
        'C:\Program Files\Microsoft VS Code\Code.exe',
        'C:\Program Files (x86)\Microsoft VS Code\Code.exe'
    )
    $codePath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $codePath) {
        $codeCommand = Get-Command code -ErrorAction SilentlyContinue
        if ($codeCommand) { $codePath = $codeCommand.Source }
    }
    if ($codePath) {
        Show-PetMessage -Text 'OPENING VS CODE' -Milliseconds 1500
        Start-Process -FilePath $codePath
        Write-PetLog ('Double-click: opened VS Code from ' + $codePath)
    }
    else {
        Show-PetMessage -Text 'VS CODE NOT FOUND' -Milliseconds 1800
        Write-PetLog 'Double-click: VS Code was not found.'
    }
}

$menu = New-Object System.Windows.Controls.ContextMenu
$menuSpecs = @(
    @{ Header = 'Open VS Code + Shirt-Rip'; Action = { Open-VSCodeAndCelebrate } },
    @{ Header = 'Bicycle Kick'; Action = { Start-PetAnimation -Name 'bicycle' -Force } },
    @{ Header = 'Point > Ground > SIU'; Action = { Start-PetAnimation -Name 'siu' -Force } },
    @{ Header = 'Calma'; Action = { Start-PetAnimation -Name 'calma' -Force } },
    @{ Header = 'Sleeping Meditation'; Action = { Start-PetAnimation -Name 'meditate' -Force } },
    @{ Header = 'Shirt-Rip Power'; Action = { Start-PetAnimation -Name 'shirt' -Force } },
    @{ Header = 'Next Skin    7'; Action = { Switch-PetSkin } }
)
foreach ($menuSpec in $menuSpecs) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $menuSpec.Header
    $item.Add_Click($menuSpec.Action)
    $menu.Items.Add($item) | Out-Null
}
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
$topItem = New-Object System.Windows.Controls.MenuItem
$topItem.Header = 'Always on Top'
$topItem.IsCheckable = $true
$topItem.IsChecked = $window.Topmost
$topItem.Add_Click({ $window.Topmost = $topItem.IsChecked })
$menu.Items.Add($topItem) | Out-Null
$resetItem = New-Object System.Windows.Controls.MenuItem
$resetItem.Header = 'Reset Position'
$resetItem.Add_Click({
    $area = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $area.Right - $window.Width - 22
    $window.Top = $area.Bottom - $window.Height - 12
})
$menu.Items.Add($resetItem) | Out-Null
$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Header = 'Exit CR7 Pet'
$exitItem.Add_Click({ $window.Close() })
$menu.Items.Add($exitItem) | Out-Null
$root.ContextMenu = $menu

$singleClickTimer = New-Object System.Windows.Threading.DispatcherTimer
$singleClickTimer.Interval = [TimeSpan]::FromMilliseconds(280)
$singleClickTimer.Add_Tick({
    $singleClickTimer.Stop()
    Start-PetAnimation -Name 'siu' -Force
})

$petImage.Add_MouseEnter({
    if ($script:CurrentPriority -eq 0 -and $script:CurrentAnimation -eq 'rest') {
        Start-PetAnimation -Name 'idle'
    }
})
$petImage.Add_MouseLeave({
    if ($script:CurrentPriority -eq 0) {
        Start-PetAnimation -Name 'rest' -Force
    }
})

$window.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ClickCount -ge 2) {
        $singleClickTimer.Stop()
        Open-VSCodeAndCelebrate
        return
    }
    $beforeX = $window.Left
    $beforeY = $window.Top
    try { $window.DragMove() }
    catch { }
    $distance = [math]::Abs($window.Left - $beforeX) + [math]::Abs($window.Top - $beforeY)
    if ($distance -lt 4) {
        $singleClickTimer.Stop()
        $singleClickTimer.Start()
    }
})

$area = [System.Windows.SystemParameters]::WorkArea
$window.Left = $area.Right - $window.Width - 22
$window.Top = $area.Bottom - $window.Height - 12
if ($null -ne $script:SavedState) {
    try {
        $x = [double]$script:SavedState.x
        $y = [double]$script:SavedState.y
        if ($x -ge $area.Left -and $x -le ($area.Right - 80) -and $y -ge $area.Top -and $y -le ($area.Bottom - 80)) {
            $window.Left = $x
            $window.Top = $y
        }
    }
    catch { Write-PetLog ('Position restore: ' + $_.Exception.Message) }
}

$script:DemoIndex = 0
$demoTimer = New-Object System.Windows.Threading.DispatcherTimer
$demoTimer.Interval = [TimeSpan]::FromMilliseconds(2300)
$demoActions = @('siu', 'calma', 'meditate', 'shirt', 'bicycle')
$demoTimer.Add_Tick({
    Switch-PetSkin
    Start-PetAnimation -Name $demoActions[$script:DemoIndex] -Force
    $script:DemoIndex = ($script:DemoIndex + 1) % $demoActions.Count
})

$window.Add_ContentRendered({
    try {
        if (-not [CR7PetNative.KeyboardHook]::Install()) {
            Write-PetLog 'Global shortcut hook could not be installed.'
        }
        $script:LastHookCounter = [CR7PetNative.KeyboardHook]::SwitchCounter
        $script:LastSiuCounter = [CR7PetNative.KeyboardHook]::SiuCounter
        $script:LastBicycleCounter = [CR7PetNative.KeyboardHook]::BicycleCounter
        try {
            $snapshot = [CR7PetNative.Sensors]::ReadAudio()
            $script:LastVolume = $snapshot.Volume
            $script:LastMuted = $snapshot.Muted
        }
        catch { Write-PetLog ('Initial audio: ' + $_.Exception.Message) }
        $initialBrightness = [CR7PetNative.Sensors]::ReadBrightness()
        if ($initialBrightness -ge 0) { $script:LastBrightness = $initialBrightness }
        $script:CodexWasRunning = @(Get-Process -Name 'ChatGPT', 'codex' -ErrorAction SilentlyContinue).Count -gt 0

        foreach ($timer in @($animationTimer, $hookTimer, $volumeTimer, $brightnessTimer, $codexTimer)) {
            $timer.Start()
        }
        Start-PetAnimation -Name 'bicycle' -Force
        if ($Demo) { $demoTimer.Start() }
        Write-PetLog ('Shown WPF handle-ready location={0},{1} skin={2} debug={3}' -f $window.Left, $window.Top, $script:SkinNames[$script:SkinIndex], $DebugWindow)
    }
    catch {
        Write-PetLog ('Startup: ' + $_.Exception.ToString())
        throw
    }
})

if ($DebugWindow) {
    $window.ShowInTaskbar = $true
    $root.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(180, 28, 31, 40))
}

$window.Add_Closed({
    foreach ($timer in @($animationTimer, $hookTimer, $volumeTimer, $brightnessTimer, $codexTimer, $bubbleTimer, $singleClickTimer, $demoTimer)) {
        $timer.Stop()
    }
    [CR7PetNative.KeyboardHook]::Uninstall()
    try {
        [pscustomobject]@{
            x = [math]::Round($window.Left)
            y = [math]::Round($window.Top)
            skinIndex = $script:SkinIndex
        } | ConvertTo-Json | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
    }
    catch { Write-PetLog ('State save: ' + $_.Exception.Message) }
    if ($createdNew) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
})

try {
    $application = New-Object System.Windows.Application
    $application.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    $application.Run($window) | Out-Null
}
catch {
    Write-PetLog ('Fatal: ' + $_.Exception.ToString())
    [CR7PetNative.KeyboardHook]::Uninstall()
    throw
}
