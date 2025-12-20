# Windows Installer Test Script
# Bu script Flutter uygulamasını build edip installer oluşturur

Write-Host "🚀 Windows Installer Test Script" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Proje dizinini kontrol et
if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "❌ Hata: pubspec.yaml bulunamadı. Proje dizininde olduğunuzdan emin olun." -ForegroundColor Red
    exit 1
}

# Flutter kurulumunu kontrol et
Write-Host "🔍 Flutter kurulumunu kontrol ediliyor..." -ForegroundColor Yellow
$flutterVersion = flutter --version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Hata: Flutter bulunamadı. Flutter SDK'nın kurulu olduğundan ve PATH'te olduğundan emin olun." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Flutter bulundu: $flutterVersion" -ForegroundColor Green
Write-Host ""

# NSIS kurulumunu kontrol et
Write-Host "🔍 NSIS kurulumunu kontrol ediliyor..." -ForegroundColor Yellow
$nsisPath = "C:\Program Files (x86)\NSIS\makensis.exe"
if (-not (Test-Path $nsisPath)) {
    Write-Host "⚠️  Uyarı: NSIS bulunamadı. PATH'te olabilir, devam ediliyor..." -ForegroundColor Yellow
    $nsisCmd = "makensis"
} else {
    Write-Host "✅ NSIS bulundu: $nsisPath" -ForegroundColor Green
    $nsisCmd = "& `"$nsisPath`""
}
Write-Host ""

# Flutter dependencies
Write-Host "📦 Flutter bağımlılıkları kuruluyor..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Hata: flutter pub get başarısız oldu!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Bağımlılıklar kuruldu" -ForegroundColor Green
Write-Host ""

# Build runner
Write-Host "🔨 Build runner çalıştırılıyor..." -ForegroundColor Yellow
flutter packages pub run build_runner build --delete-conflicting-outputs
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Hata: build_runner başarısız oldu!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Build runner tamamlandı" -ForegroundColor Green
Write-Host ""

# Flutter build windows
Write-Host "🏗️  Windows uygulaması build ediliyor..." -ForegroundColor Yellow
Write-Host "   Bu işlem birkaç dakika sürebilir..." -ForegroundColor Gray
flutter build windows
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Hata: Windows build başarısız oldu!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Windows build tamamlandı" -ForegroundColor Green
Write-Host ""

# Build klasörünü kontrol et
$buildPath = "build\windows\x64\runner\Release"
if (-not (Test-Path $buildPath)) {
    Write-Host "❌ Hata: Build klasörü bulunamadı: $buildPath" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Build klasörü bulundu: $buildPath" -ForegroundColor Green
Write-Host ""

# NSIS installer oluştur
Write-Host "📦 Installer oluşturuluyor..." -ForegroundColor Yellow
Push-Location windows

if ($nsisCmd -eq "makensis") {
    makensis installer.nsi
} else {
    & "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Hata: Installer oluşturma başarısız oldu!" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location

# Installer dosyasını kontrol et
$installerPath = "windows\another-iptv-player-windows-setup.exe"
if (Test-Path $installerPath) {
    $fileSize = (Get-Item $installerPath).Length / 1MB
    Write-Host ""
    Write-Host "✅ Installer başarıyla oluşturuldu!" -ForegroundColor Green
    Write-Host "📁 Konum: $installerPath" -ForegroundColor Cyan
    Write-Host "📊 Boyut: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🎉 Test için installer'ı çalıştırabilirsiniz!" -ForegroundColor Green
} else {
    Write-Host "❌ Hata: Installer dosyası bulunamadı: $installerPath" -ForegroundColor Red
    exit 1
}

