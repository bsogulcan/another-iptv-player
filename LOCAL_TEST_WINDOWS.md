# Windows Lokal Test Rehberi

Windows bilgisayarınızda installer'ı lokal olarak test etmek için bu adımları izleyin.

## 📋 Gereksinimler

- Windows 10/11
- Flutter SDK kurulu
- NSIS (Nullsoft Scriptable Install System)
- Git

## 🚀 Adım Adım Kurulum ve Test

### 1. NSIS Kurulumu

1. **NSIS'i indirin:**
   - https://nsis.sourceforge.io/Download adresine gidin
   - En son sürümü indirin (örnek: `nsis-3.09-setup.exe`)

2. **NSIS'i kurun:**
   - İndirdiğiniz setup dosyasını çalıştırın
   - Kurulum sihirbazını takip edin
   - Varsayılan ayarlarla kurun (genellikle `C:\Program Files (x86)\NSIS`)

3. **PATH'e ekleyin (genellikle otomatik eklenir):**
   - Eğer `makensis` komutu çalışmazsa:
   - Windows Ayarlar > Sistem > Hakkında > Gelişmiş sistem ayarları
   - Ortam Değişkenleri > Sistem değişkenleri > Path > Düzenle
   - `C:\Program Files (x86)\NSIS` ekleyin

### 2. Projeyi Windows'a Aktarın

**Seçenek A: Git ile Clone**
```powershell
git clone https://github.com/[kullanıcı-adı]/another-iptv-player.git
cd another-iptv-player
```

**Seçenek B: USB ile Kopyala**
- macOS'tan projeyi USB'ye kopyalayın
- Windows'ta USB'den projeyi kopyalayın

### 3. Flutter Bağımlılıklarını Kurun

```powershell
cd another-iptv-player
flutter pub get
```

### 4. Build Runner'ı Çalıştırın

```powershell
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### 5. Windows Uygulamasını Build Edin

```powershell
flutter build windows
```

Bu işlem birkaç dakika sürebilir. Build tamamlandığında `build\windows\x64\runner\Release` klasöründe uygulama dosyaları oluşacak.

### 6. Installer'ı Oluşturun

```powershell
cd windows
makensis installer.nsi
```

Eğer `makensis` komutu bulunamazsa:
```powershell
& "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
```

### 7. Installer Dosyasını Bulun

Installer oluşturulduktan sonra:
- `windows\another-iptv-player-windows-setup.exe` dosyasını bulacaksınız
- Bu dosyayı Windows'ta çalıştırarak kurulumu test edebilirsiniz

### 8. Installer'ı Test Edin

1. **Installer'ı çalıştırın:**
   - `another-iptv-player-windows-setup.exe` dosyasına çift tıklayın
   - Kurulum sihirbazını takip edin

2. **Kurulumu kontrol edin:**
   - Program Files'a kurulduğunu kontrol edin: `C:\Program Files\Another IPTV Player`
   - Başlat menüsünde kısayol olduğunu kontrol edin
   - Uygulamayı çalıştırın ve düzgün çalıştığını kontrol edin

3. **Uninstaller'ı test edin:**
   - Windows Ayarlar > Uygulamalar > Another IPTV Player'ı bulun
   - Kaldır butonuna tıklayın
   - Tüm dosyaların silindiğini kontrol edin

## 🔧 Sorun Giderme

### NSIS Bulunamadı Hatası

```powershell
# NSIS'in kurulu olup olmadığını kontrol edin
Test-Path "C:\Program Files (x86)\NSIS\makensis.exe"

# Eğer kuruluysa tam yol ile çalıştırın
& "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
```

### Flutter Build Hatası

```powershell
# Flutter'ı güncelleyin
flutter upgrade

# Clean build yapın
flutter clean
flutter pub get
flutter build windows
```

### Build Klasörü Bulunamadı

Installer script'i `..\build\windows\x64\runner\Release` klasörünü arar. Eğer build klasörü farklı bir yerdeyse, `installer.nsi` dosyasındaki yolunu kontrol edin.

## 📝 Hızlı Test Script'i

Windows PowerShell için hızlı test script'i:

```powershell
# test-installer.ps1
Write-Host "🚀 Windows Installer Test Script" -ForegroundColor Green
Write-Host ""

# Flutter build
Write-Host "📦 Building Flutter app..." -ForegroundColor Yellow
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs
flutter build windows

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

# NSIS installer
Write-Host "🔨 Creating installer..." -ForegroundColor Yellow
cd windows
if (Test-Path "C:\Program Files (x86)\NSIS\makensis.exe") {
    & "C:\Program Files (x86)\NSIS\makensis.exe" installer.nsi
} else {
    makensis installer.nsi
}

if (Test-Path "another-iptv-player-windows-setup.exe") {
    Write-Host "✅ Installer created successfully!" -ForegroundColor Green
    Write-Host "📁 Location: windows\another-iptv-player-windows-setup.exe" -ForegroundColor Cyan
} else {
    Write-Host "❌ Installer creation failed!" -ForegroundColor Red
    exit 1
}
```

Bu script'i `test-installer.ps1` olarak kaydedip çalıştırabilirsiniz:

```powershell
.\test-installer.ps1
```

## ✅ Test Checklist

Kurulumu test ederken şunları kontrol edin:

- [ ] Installer başarıyla çalışıyor mu?
- [ ] Program Files'a doğru kuruluyor mu? (`C:\Program Files\Another IPTV Player`)
- [ ] Başlat menüsünde kısayol oluşuyor mu?
- [ ] Masaüstü kısayolu oluşuyor mu (seçildiyse)?
- [ ] Uygulama başarıyla çalışıyor mu?
- [ ] Windows "Programs and Features" listesinde görünüyor mu?
- [ ] Uninstaller çalışıyor mu?
- [ ] Kaldırma işlemi tüm dosyaları temizliyor mu?
- [ ] Kurulumdan sonra installer dosyası silinebiliyor mu?

## 💡 İpuçları

- İlk build biraz uzun sürebilir (5-10 dakika)
- NSIS kurulumu genellikle PATH'e otomatik eklenir
- Build klasörü büyük olabilir, disk alanınızı kontrol edin
- Installer'ı test ederken farklı Windows sürümlerinde deneyin (10/11)

